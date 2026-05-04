-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('ACTIVE', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY', 'EXPIRED', 'REVOKED', 'REFUNDED', 'PAUSED');

-- CreateEnum
CREATE TYPE "AppleEnvironment" AS ENUM ('Sandbox', 'Production');

-- CreateEnum
CREATE TYPE "ScraperStatus" AS ENUM ('PAIRING', 'WARMING', 'HEALTHY', 'COOLING', 'BANNED', 'RETIRED');

-- CreateEnum
CREATE TYPE "PresenceStatus" AS ENUM ('AVAILABLE', 'UNAVAILABLE', 'COMPOSING', 'RECORDING', 'PAUSED');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "appleSub" TEXT NOT NULL,
    "email" TEXT,
    "locale" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "apnsToken" TEXT NOT NULL,
    "appVersion" TEXT,
    "osVersion" TEXT,
    "locale" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "originalTransactionId" TEXT NOT NULL,
    "latestTransactionId" TEXT,
    "webOrderLineItemId" TEXT,
    "status" "SubscriptionStatus" NOT NULL,
    "environment" "AppleEnvironment" NOT NULL,
    "purchaseDate" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "autoRenewEnabled" BOOLEAN NOT NULL DEFAULT true,
    "autoRenewProductId" TEXT,
    "cancellationDate" TIMESTAMP(3),
    "cancellationReason" TEXT,
    "rawJws" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "scraper_accounts" (
    "id" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "jid" TEXT,
    "phoneE164" TEXT,
    "status" "ScraperStatus" NOT NULL DEFAULT 'PAIRING',
    "authStateKey" TEXT NOT NULL,
    "warmupUntil" TIMESTAMP(3),
    "lastHeartbeat" TIMESTAMP(3),
    "banReason" TEXT,
    "capacity" INTEGER NOT NULL DEFAULT 50,
    "proxyUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "scraper_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tracked_numbers" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "e164" TEXT NOT NULL,
    "jid" TEXT,
    "displayName" TEXT,
    "countryCode" TEXT,
    "scraperAccountId" TEXT,
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tracked_numbers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "presence_events" (
    "id" TEXT NOT NULL,
    "trackedNumberId" TEXT NOT NULL,
    "scraperAccountId" TEXT,
    "ts" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "PresenceStatus" NOT NULL,

    CONSTRAINT "presence_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "daily_rollups" (
    "id" TEXT NOT NULL,
    "trackedNumberId" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "totalOnlineSeconds" INTEGER NOT NULL DEFAULT 0,
    "sessionCount" INTEGER NOT NULL DEFAULT 0,
    "firstOnline" TIMESTAMP(3),
    "lastOnline" TIMESTAMP(3),
    "peakHour" INTEGER,
    "hourly" JSONB NOT NULL,
    "finalized" BOOLEAN NOT NULL DEFAULT false,
    "computedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_rollups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_prefs" (
    "trackedNumberId" TEXT NOT NULL,
    "onlineEnabled" BOOLEAN NOT NULL DEFAULT true,
    "offlineEnabled" BOOLEAN NOT NULL DEFAULT false,
    "sessionEndedEnabled" BOOLEAN NOT NULL DEFAULT true,
    "dailySummaryEnabled" BOOLEAN NOT NULL DEFAULT true,
    "quietHoursStart" INTEGER,
    "quietHoursEnd" INTEGER,
    "timezone" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "notification_prefs_pkey" PRIMARY KEY ("trackedNumberId")
);

-- CreateTable
CREATE TABLE "apple_notifications" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "notificationType" TEXT NOT NULL,
    "subtype" TEXT,
    "payload" JSONB NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),
    "error" TEXT,

    CONSTRAINT "apple_notifications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_appleSub_key" ON "users"("appleSub");

-- CreateIndex
CREATE INDEX "users_deletedAt_idx" ON "users"("deletedAt");

-- CreateIndex
CREATE UNIQUE INDEX "devices_apnsToken_key" ON "devices"("apnsToken");

-- CreateIndex
CREATE INDEX "devices_userId_idx" ON "devices"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "subscriptions_originalTransactionId_key" ON "subscriptions"("originalTransactionId");

-- CreateIndex
CREATE INDEX "subscriptions_userId_idx" ON "subscriptions"("userId");

-- CreateIndex
CREATE INDEX "subscriptions_expiresAt_idx" ON "subscriptions"("expiresAt");

-- CreateIndex
CREATE INDEX "subscriptions_status_idx" ON "subscriptions"("status");

-- CreateIndex
CREATE UNIQUE INDEX "scraper_accounts_jid_key" ON "scraper_accounts"("jid");

-- CreateIndex
CREATE UNIQUE INDEX "scraper_accounts_phoneE164_key" ON "scraper_accounts"("phoneE164");

-- CreateIndex
CREATE UNIQUE INDEX "scraper_accounts_authStateKey_key" ON "scraper_accounts"("authStateKey");

-- CreateIndex
CREATE INDEX "scraper_accounts_status_idx" ON "scraper_accounts"("status");

-- CreateIndex
CREATE INDEX "tracked_numbers_userId_idx" ON "tracked_numbers"("userId");

-- CreateIndex
CREATE INDEX "tracked_numbers_scraperAccountId_idx" ON "tracked_numbers"("scraperAccountId");

-- CreateIndex
CREATE INDEX "tracked_numbers_jid_idx" ON "tracked_numbers"("jid");

-- CreateIndex
CREATE UNIQUE INDEX "tracked_numbers_userId_e164_key" ON "tracked_numbers"("userId", "e164");

-- CreateIndex
CREATE INDEX "presence_events_trackedNumberId_ts_idx" ON "presence_events"("trackedNumberId", "ts");

-- CreateIndex
CREATE INDEX "daily_rollups_day_idx" ON "daily_rollups"("day");

-- CreateIndex
CREATE UNIQUE INDEX "daily_rollups_trackedNumberId_day_key" ON "daily_rollups"("trackedNumberId", "day");

-- CreateIndex
CREATE UNIQUE INDEX "apple_notifications_notificationId_key" ON "apple_notifications"("notificationId");

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracked_numbers" ADD CONSTRAINT "tracked_numbers_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracked_numbers" ADD CONSTRAINT "tracked_numbers_scraperAccountId_fkey" FOREIGN KEY ("scraperAccountId") REFERENCES "scraper_accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "presence_events" ADD CONSTRAINT "presence_events_trackedNumberId_fkey" FOREIGN KEY ("trackedNumberId") REFERENCES "tracked_numbers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "presence_events" ADD CONSTRAINT "presence_events_scraperAccountId_fkey" FOREIGN KEY ("scraperAccountId") REFERENCES "scraper_accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "daily_rollups" ADD CONSTRAINT "daily_rollups_trackedNumberId_fkey" FOREIGN KEY ("trackedNumberId") REFERENCES "tracked_numbers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_prefs" ADD CONSTRAINT "notification_prefs_trackedNumberId_fkey" FOREIGN KEY ("trackedNumberId") REFERENCES "tracked_numbers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

