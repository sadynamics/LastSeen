#!/usr/bin/env node
// Idempotent TimescaleDB setup for the presence_events hypertable.
// Safe to run on every boot:
//   - If the timescaledb extension is unavailable (e.g. plain Postgres on
//     Railway), this script logs a warning and exits 0 instead of failing
//     the deploy. The app still works; you just lose the retention &
//     compression policies until you point DATABASE_URL at a Timescale image.
//   - If the extension is available, the SQL uses IF NOT EXISTS / if_not_exists
//     guards so re-runs are a no-op.

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { PrismaClient } from '@prisma/client';

const here = dirname(fileURLToPath(import.meta.url));
const sqlPath = resolve(here, '..', 'prisma', 'sql', 'timescale.sql');

const prisma = new PrismaClient();

async function hasTimescale() {
  const rows = await prisma.$queryRawUnsafe(
    `SELECT 1 AS ok FROM pg_available_extensions WHERE name = 'timescaledb'`,
  );
  return Array.isArray(rows) && rows.length > 0;
}

async function ensureExtension() {
  await prisma.$executeRawUnsafe(`CREATE EXTENSION IF NOT EXISTS timescaledb`);
}

async function tableExists(name) {
  const rows = await prisma.$queryRawUnsafe(
    `SELECT 1 AS ok FROM information_schema.tables WHERE table_name = $1`,
    name,
  );
  return Array.isArray(rows) && rows.length > 0;
}

async function main() {
  try {
    if (!(await hasTimescale())) {
      console.warn('[init-timescale] timescaledb extension not available on this database; skipping hypertable setup.');
      return;
    }
    await ensureExtension();

    if (!(await tableExists('presence_events'))) {
      console.warn('[init-timescale] presence_events table not present yet; run prisma migrate deploy first. Skipping.');
      return;
    }

    const sql = await readFile(sqlPath, 'utf8');
    // Run statement-by-statement so a benign error on one (e.g. compression
    // already configured) does not abort the rest. Statements are split on
    // semicolons followed by newline boundaries to keep dollar-quoted blocks
    // (we have none today, but be defensive) intact in the simple case.
    const statements = sql
      .split(/;\s*\n/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && !s.startsWith('--'));

    for (const stmt of statements) {
      try {
        await prisma.$executeRawUnsafe(stmt);
      } catch (err) {
        console.warn(`[init-timescale] statement failed (continuing): ${err.message}`);
      }
    }
    console.log('[init-timescale] done.');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error('[init-timescale] fatal:', err);
  // Do NOT exit 1 — we don't want a missing extension to block the API boot.
  // If the failure was something serious, the API will surface it on first query.
  process.exit(0);
});
