import * as tf from '@tensorflow/tfjs-node';
import * as faceapi from '@vladmandic/face-api';
import path from 'path';

/**
 * Compares a signup selfie against the photo printed on a submitted ID —
 * entirely local (face-api.js + tfjs-node), no vendor API/key. Detection,
 * landmark alignment, and the 128-d face descriptor all run once per
 * photo; two descriptors are then compared by euclidean distance, same as
 * the library's own reference implementation (see its
 * demo/node-face-compare.js), converted to a 0-100 score via `1 -
 * distance` — the exact formula that demo itself uses for "similarity".
 *
 * Score ≥ FACE_MATCH_AUTO_CLEAR_SCORE auto-clears a signup at POST
 * /signup (see commuter.ts) instead of queuing it for manual admin
 * review. That threshold is set well above the ~40% (distance ≈0.6) that
 * face-api's own community treats as "probably the same person" —
 * deliberately conservative since this is a brand-new, unvalidated-in-
 * production system auto-approving real accounts: it should only ever
 * catch the obvious, unambiguous matches, and let anything even slightly
 * uncertain fall through to a human. Tune down only after watching it
 * score a meaningful number of real signups correctly.
 */
export const FACE_MATCH_AUTO_CLEAR_SCORE = 70;

// face-api.js ships its own pretrained weights inside its npm package —
// resolved from wherever it's actually installed rather than a relative
// path, so this doesn't break between ts-node (src/) and the compiled
// build (dist/), which sit at different depths from node_modules.
const MODEL_PATH = path.join(path.dirname(require.resolve('@vladmandic/face-api/package.json')), 'model');

let modelsReady: Promise<void> | null = null;

function loadModels(): Promise<void> {
  if (!modelsReady) {
    modelsReady = (async () => {
      await tf.ready();
      await faceapi.nets.tinyFaceDetector.loadFromDisk(MODEL_PATH);
      await faceapi.nets.faceLandmark68Net.loadFromDisk(MODEL_PATH);
      await faceapi.nets.faceRecognitionNet.loadFromDisk(MODEL_PATH);
    })().catch((err) => {
      // Don't leave a rejected promise cached forever — a transient
      // failure (cold-start resource pressure, a slow disk read) should
      // get retried on the next signup, not permanently disable face
      // matching for the life of the process.
      modelsReady = null;
      throw err;
    });
  }
  return modelsReady;
}

// Phones routinely save a photo's pixels in the camera sensor's native
// (often landscape) orientation and record how to display it upright as
// an EXIF Orientation tag instead — browsers and <img> tags apply that
// tag automatically, which is why a captured selfie looks upright
// everywhere it's *displayed*, but tf.node.decodeImage only reads raw
// pixels and ignores EXIF entirely. Left uncorrected, this feeds the
// detector a sideways face and (confirmed against a real captured
// selfie) reliably fails detection even on an otherwise clear, well-lit
// photo — turning "auto face-match" into "always falls back to manual
// review" for a large share of real phone photos, silently.
//
// Only reads the one EXIF tag this needs (0x0112) rather than pulling in
// a full EXIF parsing dependency for it.
function readExifOrientation(buf: Buffer): number | null {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null; // not a JPEG
  let offset = 2;
  while (offset < buf.length - 4 && buf[offset] === 0xff) {
    const marker = buf[offset + 1];
    const size = buf.readUInt16BE(offset + 2);
    if (marker === 0xe1) {
      const exifStart = offset + 4;
      if (buf.toString('ascii', exifStart, exifStart + 4) !== 'Exif') break;
      const tiffStart = exifStart + 6;
      const little = buf.toString('ascii', tiffStart, tiffStart + 2) === 'II';
      const readU16 = (o: number) => (little ? buf.readUInt16LE(o) : buf.readUInt16BE(o));
      const readU32 = (o: number) => (little ? buf.readUInt32LE(o) : buf.readUInt32BE(o));
      const ifdOffset = tiffStart + readU32(tiffStart + 4);
      const numEntries = readU16(ifdOffset);
      for (let i = 0; i < numEntries; i++) {
        const entryOffset = ifdOffset + 2 + i * 12;
        if (readU16(entryOffset) === 0x0112) return readU16(entryOffset + 8);
      }
      return null;
    }
    offset += 2 + size;
  }
  return null;
}

// One 90-degree-clockwise rotation, done as transpose+reverse rather than
// tf.image.rotateWithOffset — that op isn't registered on tfjs-node's
// 'tensorflow' backend at all (throws "Kernel 'RotateWithOffset' not
// registered"), confirmed by hitting exactly that error against the real
// production backend. transpose+reverse only needs ops available
// everywhere.
function rotate90Cw(t: tf.Tensor3D): tf.Tensor3D {
  const transposed = tf.transpose(t, [1, 0, 2]);
  const rotated = tf.reverse(transposed, [1]) as tf.Tensor3D;
  transposed.dispose();
  return rotated;
}

// Only the values a real camera actually produces (1/3/6/8) are handled —
// the mirrored variants (2/4/5/7) come from flatbed scanners, never a
// phone camera, so they're left as a no-op same as a missing/unreadable
// tag rather than guessing.
function correctOrientation(tensor: tf.Tensor3D, exifOrientation: number | null): tf.Tensor3D {
  const cwTurns = exifOrientation === 6 ? 1 : exifOrientation === 3 ? 2 : exifOrientation === 8 ? 3 : 0;
  if (cwTurns === 0) return tensor;
  let result = tensor;
  for (let i = 0; i < cwTurns; i++) {
    const next = rotate90Cw(result);
    if (result !== tensor) result.dispose();
    result = next;
  }
  return result;
}

async function getFaceDescriptor(imageBuffer: Buffer): Promise<Float32Array | null> {
  const decoded = tf.node.decodeImage(imageBuffer, 3) as tf.Tensor3D;
  const tensor = correctOrientation(decoded, readExifOrientation(imageBuffer));
  try {
    const result = await faceapi
      .detectSingleFace(tensor, new faceapi.TinyFaceDetectorOptions())
      .withFaceLandmarks()
      .withFaceDescriptor();
    return result?.descriptor ?? null;
  } finally {
    if (tensor !== decoded) tf.dispose(decoded);
    tf.dispose(tensor);
  }
}

/** Downloads a Cloudinary-hosted photo (or any http(s) URL) as a Buffer. */
export async function fetchImageBuffer(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch image (${response.status}): ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

/**
 * Returns a 0-100 match score between the faces in [selfieBuffer] and
 * [idPhotoBuffer], or null if a face couldn't be confidently found in
 * either photo. Never throws — any model, decoding, or detection failure
 * degrades to `null`, which callers treat exactly like a below-threshold
 * score (falls back to manual admin review), never a blocked signup.
 */
export async function compareFaces(selfieBuffer: Buffer, idPhotoBuffer: Buffer): Promise<number | null> {
  try {
    await loadModels();
    const [selfieDescriptor, idDescriptor] = await Promise.all([
      getFaceDescriptor(selfieBuffer),
      getFaceDescriptor(idPhotoBuffer),
    ]);
    if (!selfieDescriptor || !idDescriptor) return null;

    const distance = faceapi.euclideanDistance(selfieDescriptor, idDescriptor);
    return Math.max(0, Math.min(100, Math.round((1 - distance) * 100)));
  } catch {
    return null;
  }
}
