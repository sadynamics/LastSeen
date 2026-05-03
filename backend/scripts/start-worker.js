#!/usr/bin/env node
// Boots the worker process on Railway. Prisma migrate deploy is safe to
// re-run (advisory lock); doing it here too means the worker can come up
// even if the API service is paused.

import { spawn } from 'node:child_process';

function run(cmd, args) {
  return new Promise((resolveFn, rejectFn) => {
    const child = spawn(cmd, args, { stdio: 'inherit', env: process.env });
    child.on('exit', (code) => (code === 0 ? resolveFn() : rejectFn(new Error(`${cmd} exited ${code}`))));
    child.on('error', rejectFn);
  });
}

async function main() {
  console.log('[start-worker] applying migrations...');
  await run('npx', ['--yes', 'prisma', 'migrate', 'deploy']);

  console.log('[start-worker] starting BullMQ worker...');
  const worker = spawn(process.execPath, ['dist/workers/index.js'], {
    stdio: 'inherit',
    env: process.env,
  });

  const forward = (sig) => () => worker.kill(sig);
  process.on('SIGTERM', forward('SIGTERM'));
  process.on('SIGINT', forward('SIGINT'));

  worker.on('exit', (code) => process.exit(code ?? 0));
}

main().catch((err) => {
  console.error('[start-worker] boot failed:', err);
  process.exit(1);
});
