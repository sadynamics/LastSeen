-- AlterTable
ALTER TABLE "users" ADD COLUMN     "isReviewer" BOOLEAN NOT NULL DEFAULT false;

-- CreateIndex
CREATE INDEX "users_isReviewer_idx" ON "users"("isReviewer");
