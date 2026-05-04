ALTER TABLE "tracked_numbers" ADD COLUMN "lid" TEXT;
CREATE INDEX "tracked_numbers_lid_idx" ON "tracked_numbers"("lid");
