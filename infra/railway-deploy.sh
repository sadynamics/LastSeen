#!/usr/bin/env bash
# Bootstraps a fresh Railway project for LastSeen.
#
# This script handles the parts that are scriptable (project init, plugin
# adds, secret generation). Service creation for API/Worker still happens
# in the dashboard because Railway's CLI can't fully script "deploy this
# repo as two separate services from the same GitHub source" — but it's a
# 60-second click-through after this script finishes.
#
# Prereqs:
#   - Railway CLI installed:  brew install railway   (or: npm i -g @railway/cli)
#   - You ran:                 railway login
#   - You're in the LastSeen repo root
#
# Usage:
#   ./infra/railway-deploy.sh              # interactive; will prompt for project name
#   PROJECT_NAME=lastseen-prod ./infra/railway-deploy.sh

set -euo pipefail

cd "$(dirname "$0")/.."  # repo root

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_RED=$'\033[31m'

step() { echo -e "\n${C_BLUE}${C_BOLD}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { echo -e "${C_GREEN}  ok${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}  warn${C_RESET} $*"; }
fail() { echo -e "${C_RED}  error${C_RESET} $*" >&2; exit 1; }
hint() { echo -e "${C_DIM}    $*${C_RESET}"; }

step "Checking prerequisites"
command -v railway >/dev/null 2>&1 || fail "Railway CLI not found. Install: brew install railway  (or npm i -g @railway/cli)"
ok "railway CLI: $(railway --version 2>/dev/null | head -n1)"

if ! railway whoami >/dev/null 2>&1; then
  fail "You're not logged in. Run:  railway login"
fi
ok "logged in as: $(railway whoami 2>&1 | tail -n1)"

# ----------------------------------------------------------------------------
step "Linking or creating Railway project"
if [ -f ".railway/project.json" ] || railway status >/dev/null 2>&1; then
  ok "already linked to a Railway project"
  railway status || true
else
  if [ -z "${PROJECT_NAME:-}" ]; then
    read -r -p "Project name [lastseen-prod]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-lastseen-prod}
  fi
  railway init --name "$PROJECT_NAME"
  ok "created project: $PROJECT_NAME"
fi

# ----------------------------------------------------------------------------
step "Adding managed plugins (Postgres, Redis)"
hint "Railway's stock Postgres works — TimescaleDB is optional and our init"
hint "script will gracefully skip hypertable setup if the extension is absent."

# `railway add` syntax: --database <name> for managed dbs.
if railway add --database postgres 2>&1 | tee /tmp/lastseen-add-pg.log | grep -qiE "added|created|already"; then
  ok "postgres plugin added (or already present)"
else
  warn "could not auto-add postgres. Add it manually in the dashboard: New → Database → Postgres"
fi

if railway add --database redis 2>&1 | tee /tmp/lastseen-add-redis.log | grep -qiE "added|created|already"; then
  ok "redis plugin added (or already present)"
else
  warn "could not auto-add redis. Add it manually in the dashboard: New → Database → Redis"
fi

# ----------------------------------------------------------------------------
step "Generating production secrets"
gen_secret() { openssl rand -hex 32; }

if [ ! -f ".env.railway.generated" ]; then
  cat > .env.railway.generated <<EOF
# ----------------------------------------------------------------------------
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by infra/railway-deploy.sh
# Paste these into the API + Worker services in Railway dashboard
# (Service → Variables → Raw editor).
# Do NOT commit this file. It's gitignored.
# ----------------------------------------------------------------------------

NODE_ENV=production
LOG_LEVEL=info

# Wired automatically by Railway when Postgres/Redis plugins are attached:
DATABASE_URL=\${{Postgres.DATABASE_URL}}
REDIS_URL=\${{Redis.REDIS_URL}}

# JWT — server-side signing key for app sessions
JWT_SECRET=$(gen_secret)
JWT_ISSUER=lastseen.app
JWT_AUDIENCE=lastseen-ios

# Apple — fill these in from Apple Developer + App Store Connect
APPLE_BUNDLE_ID=com.lastseen.app
APPLE_TEAM_ID=REPLACE_ME
APPLE_INAPP_KEY_ID=REPLACE_ME
APPLE_INAPP_ISSUER_ID=REPLACE_ME
APPLE_INAPP_PRIVATE_KEY_BASE64=REPLACE_ME
APPLE_INAPP_ENVIRONMENT=Production

# APNs (push)
APNS_KEY_ID=REPLACE_ME
APNS_TEAM_ID=REPLACE_ME
APNS_PRIVATE_KEY_BASE64=REPLACE_ME
APNS_BUNDLE_ID=com.lastseen.app
APNS_ENVIRONMENT=production

# S3 / R2 for Baileys auth state — see docs/deploy-railway.md for R2 setup
S3_ENDPOINT=https://YOUR_R2_ACCOUNT.r2.cloudflarestorage.com
S3_REGION=auto
S3_ACCESS_KEY_ID=REPLACE_ME
S3_SECRET_ACCESS_KEY=REPLACE_ME
S3_BUCKET_BAILEYS=lastseen-baileys-prod
S3_FORCE_PATH_STYLE=true

# Admin (used to pair scraper accounts)
ADMIN_BASIC_USER=admin
ADMIN_BASIC_PASSWORD=$(gen_secret | cut -c1-24)

# Observability
SENTRY_DSN=
SENTRY_ENVIRONMENT=production

# Worker-only: tell Railway to load the worker config
# (Set this ONLY on the worker service, not the API.)
# RAILWAY_CONFIG_FILE=railway.worker.json
EOF
  ok "wrote .env.railway.generated (gitignored)"
else
  warn ".env.railway.generated already exists; not overwriting"
fi

# ----------------------------------------------------------------------------
step "Next steps (manual, ~3 minutes in the Railway dashboard)"
cat <<'EOF'

  1. Open the project:        railway open
  2. Connect your GitHub repo if you haven't already
     (Project Settings → GitHub → Connect repo)

  3. Create the API service:
     New → GitHub Repo → pick this repo
     Service Settings:
       - Root Directory:     backend
       - Builder:            Dockerfile (auto-detected via railway.json)
       - Public Networking:  Generate Domain
     Variables:               paste contents of .env.railway.generated

  4. Create the Worker service:
     New → GitHub Repo → pick the SAME repo
     Service Settings:
       - Root Directory:     backend
     Variables:               paste contents of .env.railway.generated AND
                              add: RAILWAY_CONFIG_FILE=railway.worker.json

  5. (Optional) Swap the stock Postgres for TimescaleDB:
     Add → Docker Image → timescale/timescaledb:latest-pg16
     Set volume to /var/lib/postgresql/data, copy DATABASE_URL into both
     API and Worker variables, delete the stock Postgres service.

  6. Trigger first deploy by pushing to main, or:
        cd backend && railway up

  7. Once API is healthy, pair the scraper:
        curl -u admin:$ADMIN_BASIC_PASSWORD https://YOUR_API/admin/scrapers/pair

EOF

ok "bootstrap complete"
