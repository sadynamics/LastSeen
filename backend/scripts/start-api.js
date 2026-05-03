#!/usr/bin/env node
// Boots the API process on Railway:
//   1. Apply Prisma migrations (idempotent, advisory-locked)
//   2. Apply Timescale hypertable setup (graceful fallback when extension absent)
//   3. Start the Fastify server
//
// We spawn child processes instead of importing because prisma migrate
// expects to own its own process lifecycle, and any unhandled error there
// should fail the deploy fast.

import { spawn } from 'node:child_process';

function run(cmd, args, opts = {}) {
  return new Promise((resolveFn, rejectFn) => {
    const child = spawn(cmd, args, {
      stdio: 'inherit',
      env: process.env,
      ...opts,
    });
    child.on('exit', (code) => {
      if (code === 0) resolveFn();
      else rejectFn(new Error(`${cmd} ${args.join(' ')} exited with code ${code}`));
    });
    child.on('error', rejectFn);
  });
}

async function main() {
  console.log('[start-api] applying migrations...');
  await run('node_modules/.bin/prisma', ['migrate', 'deploy']);

  console.log('[start-api] configuring timescale (if available)...');
  await run(process.execPath, ['scripts/init-timescale.js']);

  console.log('[start-api] starting fastify...');
  // Replace this process so signal handling (SIGTERM from Railway) goes
  // straight to Node, not the wrapper.
  const server = spawn(process.execPath, ['dist/api/server.js'], {
    stdio: 'inherit',
    env: process.env,
  });

  const forward = (sig) => () => server.kill(sig);
  process.on('SIGTERM', forward('SIGTERM'));
  process.on('SIGINT', forward('SIGINT'));

  server.on('exit', (code) => process.exit(code ?? 0));
}

main().catch((err) => {
  console.error('[start-api] boot failed:', err);
  process.exit(1);
});
