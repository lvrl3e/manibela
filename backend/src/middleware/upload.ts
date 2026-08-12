import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import multer from 'multer';

const UPLOAD_DIR = path.join(__dirname, '..', '..', 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const ALLOWED_EXTENSIONS: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const ext = ALLOWED_EXTENSIONS[file.mimetype] ?? '';
    cb(null, `${randomBytes(16).toString('hex')}${ext}`);
  },
});

export const uploadPhoto = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (_req, file, cb) => {
    if (!(file.mimetype in ALLOWED_EXTENSIONS)) {
      cb(new Error('Only JPEG, PNG, or WEBP images are allowed.'));
      return;
    }
    cb(null, true);
  },
}).single('photo');

/** Deletes a previously-uploaded photo, keyed by its stored `/uploads/<file>` path. Silently no-ops if it's missing or wasn't a local upload (e.g. null). */
export function deleteUploadedPhoto(photoUrl: string | null): void {
  if (!photoUrl || !photoUrl.startsWith('/uploads/')) return;
  const filePath = path.join(UPLOAD_DIR, path.basename(photoUrl));
  fs.rm(filePath, { force: true }, () => {});
}
