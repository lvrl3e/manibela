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
 * already pass through unchanged (see ApiClient.resolveUrl). */
export function uploadBufferToCloudinary(buffer: Buffer, folder: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream(
      { folder: `manibelapp/${folder}`, resource_type: 'image' },
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

export const uploadPhoto = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).single('photo');

/** Optional photo evidence attached to a complaint. */
export const uploadComplaintAttachment = multer({
  storage,
  limits: IMAGE_LIMITS,
  fileFilter: imageFileFilter,
}).single('attachment');

/** Deletes a previously-uploaded photo from Cloudinary, keyed by its
 * stored secure_url — silently no-ops if it's missing or wasn't a
 * Cloudinary URL (e.g. null, or a pre-Cloudinary local /uploads/... path
 * left over from before this migration, which no longer resolves to a
 * real file anyway). Best-effort, same as callers' fire-and-forget usage.
 */
export async function deleteUploadedPhoto(photoUrl: string | null): Promise<void> {
  if (!photoUrl || !photoUrl.includes('res.cloudinary.com')) return;
  const match = photoUrl.match(/\/upload\/(?:v\d+\/)?(.+)\.[a-zA-Z0-9]+$/);
  if (!match) return;
  try {
    await cloudinary.uploader.destroy(match[1]);
  } catch {
    // Best-effort — nothing else references this file either way.
  }
}
