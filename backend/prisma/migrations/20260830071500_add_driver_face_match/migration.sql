-- "selfieUrl" already exists on Driver, orphaned from the earlier Didit
-- integration's own migration (reverted from the schema/git history, but
-- the live column was never dropped) — same shape (nullable TEXT) this
-- migration needs, so only faceMatchScore actually needs adding here.
ALTER TABLE "Driver" ADD COLUMN "faceMatchScore" INTEGER;
