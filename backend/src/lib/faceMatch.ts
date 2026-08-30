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
    })();
  }
  return modelsReady;
}

async function getFaceDescriptor(imageBuffer: Buffer): Promise<Float32Array | null> {
  const tensor = tf.node.decodeImage(imageBuffer, 3) as tf.Tensor3D;
  try {
    const result = await faceapi
      .detectSingleFace(tensor, new faceapi.TinyFaceDetectorOptions())
      .withFaceLandmarks()
      .withFaceDescriptor();
    return result?.descriptor ?? null;
  } finally {
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
