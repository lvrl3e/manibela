import { Readable } from 'node:stream';
import multer from 'multer';
import { v2 as cloudinary } from 'cloudinary';

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

const ALLOWED_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

const storage = multer.memoryStorage();

const imageFileFilter: multer.Options['fileFilter'] = (_req, file, cb) => {
  if (!ALLOWED_MIME_TYPES.has(file.mimetype)) {
    cb(new Error('Only JPEG, PNG, or WEBP images are allowed.'));
    return;
  }
  cb(null, true);
};

const IMAGE_LIMITS = { fileSize: 5 * 1024 * 1024 }; // 5 MB

/** Pushes an in-memory upload straight to Cloudinary — nothing ever
 * touches local disk, so a file survives Render's ephemeral filesystem
 * being wiped on every restart/redeploy (the actual cause of photos that
 * showed as "Approved" but rendered as broken images). Returns the
 * https:// URL Cloudinary serves the image from, which both clients
 * already pass through unchanged (see ApiClient.resolveUrl).
 *
 * Pass `sensitive: true` for anything that shouldn't be a plain,
 * guessable-from-its-path public URL — government ID photos, license
 * photos, and the face-verification selfie, none of which are meant to
 * be viewable by anyone but an admin reviewing them (unlike a profile
 * picture, which the app shows to other users by design). These upload
 * with Cloudinary's `authenticated` delivery type instead of the
 * default `upload` type: the returned URL already carries a real
 * cryptographic signature computed from the account's private secret
 * (confirmed against Cloudinary's own docs and a live test — it's
 * usable immediately, not a placeholder needing a separate signing
 * step), so it can be stored and returned exactly like an ordinary
 * public URL — but unlike one, nobody can construct a working link to
 * it from just the folder/filename the way they could for a plain
 * `upload`-type asset. There's no built-in expiry on this (that needs
 * Cloudinary's token-auth feature, which requires enabling "strict
 * transformations" in the dashboard — not done here); the real
 * protection is that the link isn't derivable without the account's
 * own secret in the first place.
 */
export function uploadBufferToCloudinary(
  buffer: Buffer,
  folder: string,
  { sensitive = false }: { sensitive?: boolean } = {},
): Promise<string> {
  return new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream(
      {
        folder: `manibelapp/${folder}`,
        resource_type: 'image',
        type: sensitive ? 'authenticated' : 'upload',
      },
      (error, result) => {
        if (error || !result) {
          reject(error ?? new Error('Cloudinary upload failed'));
          return;
        }
        resolve(result.secure_url);
      },
    );
    Readable.from(buffer).pipe(uploadStream);
  });
}

// Cloudinary delivery URLs embed the access type right after the
// resource type — .../image/upload/v.../public_id.ext for a plain
// public asset, .../image/authenticated/s--SIGNATURE--/v.../public_id.ext
// for one uploaded with `sensitive: true` above (confirmed against a
// live upload — the authenticated form has that extra signature
// segment an `upload`-type URL never does). deleteUploadedPhoto needs
// both the real public_id (not the signature) and the type, since
// destroying an authenticated asset requires passing that type back.
const CLOUDINARY_URL_PATTERN = /\/(upload|authenticated)\/(?:s--[\w-]+--\/)?(?:v\d+\/)?(.+)\.[a-zA-Z0-9]+$/;

export const uploadPhoto = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).single('photo');

/** Front + back of a government ID, uploaded together during sign-up. */
export const uploadIdPhotos = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).fields([
  { name: 'front', maxCount: 1 },
  { name: 'back', maxCount: 1 },
]);

/** The identity-verification selfie captured at the end of sign-up. */
export const uploadSelfie = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).single('selfie');

/** Optional photo evidence attached to a complaint. */
export const uploadComplaintAttachment = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).single('attachment');

/** Front/back of a driver's license — uploaded by an admin from the
 * Driver Detail Panel (drivers have no self-serve doc upload, unlike a
 * commuter's KYC docs). Either field alone is accepted, so an admin can
 * add or replace just one side without re-uploading both. */
export const uploadLicensePhotos = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).fields([
  { name: 'licenseFront', maxCount: 1 },
  { name: 'licenseBack', maxCount: 1 },
]);

/** Deletes a previously-uploaded photo from Cloudinary, keyed by its
 * stored secure_url — silently no-ops if it's missing or wasn't a
 * Cloudinary URL (e.g. null, or a pre-Cloudinary local /uploads/... path
 * left over from before this migration, which no longer resolves to a
 * real file anyway). Best-effort, same as callers' fire-and-forget usage.
 */
export async function deleteUploadedPhoto(photoUrl: string | null): Promise<void> {
  if (!photoUrl || !photoUrl.includes('res.cloudinary.com')) return;
  const match = photoUrl.match(CLOUDINARY_URL_PATTERN);
  if (!match) return;
  try {
    await cloudinary.uploader.destroy(match[2], { type: match[1] === 'authenticated' ? 'authenticated' : 'upload' });
  } catch {
    // Best-effort — nothing else references this file either way.
  }
}
