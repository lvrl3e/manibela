import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import multer from 'multer';

const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads');

/** Which subdirectory of UPLOAD_DIR a file lands in, keyed by its
 * multipart field name — so profile photos, ID scans, and verification
 * selfies don't all pile up loose in the same folder. */
const SUBDIR_BY_FIELD: Record<string, string> = {
  photo: 'profile-photos',
  front: 'id-photos',
  back: 'id-photos',
  selfie: 'selfies',
};

for (const subdir of new Set(Object.values(SUBDIR_BY_FIELD))) {
  fs.mkdirSync(path.join(UPLOAD_DIR, subdir), { recursive: true });
}

const ALLOWED_EXTENSIONS: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

const storage = multer.diskStorage({
  destination: (_req, file, cb) => {
    const subdir = SUBDIR_BY_FIELD[file.fieldname] ?? '';
    cb(null, path.join(UPLOAD_DIR, subdir));
  },
  filename: (_req, file, cb) => {
    const ext = ALLOWED_EXTENSIONS[file.mimetype] ?? '';
    cb(null, `${randomBytes(16).toString('hex')}${ext}`);
  },
});

const imageFileFilter: multer.Options['fileFilter'] = (_req, file, cb) => {
  if (!(file.mimetype in ALLOWED_EXTENSIONS)) {
    cb(new Error('Only JPEG, PNG, or WEBP images are allowed.'));
    return;
  }
  cb(null, true);
};

const IMAGE_LIMITS = { fileSize: 5 * 1024 * 1024 }; // 5 MB

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

/** Deletes a previously-uploaded photo, keyed by its stored `/uploads/...`
 * path (e.g. `/uploads/profile-photos/xyz.jpg`) — silently no-ops if it's
 * missing or wasn't a local upload (e.g. null). */
export function deleteUploadedPhoto(photoUrl: string | null): void {
  if (!photoUrl || !photoUrl.startsWith('/uploads/')) return;
  const filePath = path.join(UPLOAD_DIR, photoUrl.slice('/uploads/'.length));
  // Never delete outside the upload dir, however photoUrl got constructed.
  if (!filePath.startsWith(UPLOAD_DIR)) return;
  fs.rm(filePath, { force: true }, () => {});
}
