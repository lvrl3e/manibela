CREATE TYPE "AdminRole" AS ENUM ('MAIN_ADMIN', 'ADMIN');

ALTER TABLE "Admin" ADD COLUMN "role" "AdminRole" NOT NULL DEFAULT 'ADMIN';
ALTER TABLE "Admin" ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Admin" ADD COLUMN "lastLoginAt" TIMESTAMP(3);

-- Every existing deployment needs exactly one Main Admin from the moment
-- this migration runs — designate whichever admin account is oldest.
-- No-op if the Admin table is empty (a fresh install bootstraps its first
-- Main Admin via scripts/create-admin.ts instead).
UPDATE "Admin"
SET "role" = 'MAIN_ADMIN'
WHERE "id" = (SELECT "id" FROM "Admin" ORDER BY "createdAt" ASC LIMIT 1);

-- Belt-and-suspenders: the application layer already refuses to create a
-- second Main Admin, but this makes it impossible at the database level
-- too, regardless of what code path ever writes to this table.
CREATE UNIQUE INDEX "Admin_single_main_admin" ON "Admin" ("role") WHERE "role" = 'MAIN_ADMIN';
