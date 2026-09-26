#!/usr/bin/env bash
#
# deploy.sh — deploy wacrm to Vercel
#
# Runs wacrm's local quality gate first (so a broken build never ships),
# then deploys via the Vercel CLI. Secrets are NOT handled here — they
# live in the Vercel project's Environment Variables (dashboard or
# `vercel env`). This script only reminds you which keys must exist.
#
# Usage:
#   ./scripts/deploy.sh                 # deploy a PREVIEW build
#   ./scripts/deploy.sh --prod          # deploy to PRODUCTION
#   ./scripts/deploy.sh --skip-gate     # skip local checks (Vercel builds anyway)
#
# Prereqs (one-time):
#   npm i -g vercel        # install the CLI
#   vercel login           # authenticate
#   vercel link            # link this folder to your Vercel project
#   # then set env vars in the Vercel dashboard (or `vercel env add ...`)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PROD=0
SKIP_GATE=0
for arg in "$@"; do
  case "$arg" in
    --prod) PROD=1 ;;
    --skip-gate) SKIP_GATE=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$1" >&2; exit 1; }

# --- Node + Vercel CLI ---------------------------------------------------
command -v node >/dev/null 2>&1 || die "node not found on PATH"
if ! command -v vercel >/dev/null 2>&1; then
  die "Vercel CLI not found. Install it: npm i -g vercel && vercel login && vercel link"
fi

# --- Linked to a project? ------------------------------------------------
[ -f .vercel/project.json ] || die "Not linked to a Vercel project. Run: vercel link"

# --- Required env keys (names only — values live in Vercel) --------------
# From wacrm's .env.local.example. Set these in the Vercel project before
# a production deploy or the app will fail at runtime.
REQUIRED_ENV=(
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  SUPABASE_SERVICE_ROLE_KEY
  ENCRYPTION_KEY
  META_APP_SECRET
)
log "Ensure these env vars are set in the Vercel project (Settings → Environment Variables):"
for k in "${REQUIRED_ENV[@]}"; do printf '      - %s\n' "$k"; done
warn "Generate FRESH production secrets (ENCRYPTION_KEY, etc.) — do not reuse local/dev values."

# --- Local quality gate (matches wacrm's package.json scripts) -----------
if [ "$SKIP_GATE" -eq 0 ]; then
  if [ ! -d node_modules ]; then
    log "Installing dependencies (npm ci)"
    if [ -f package-lock.json ]; then npm ci; else npm install; fi
  fi
  log "Type-checking";  npm run typecheck
  log "Format check";   npm run format:check || warn "prettier reported formatting issues"
  log "Linting";        npm run lint
  log "Tests";          npm run test
  log "Build";          npm run build
else
  warn "Skipping local gate (--skip-gate); Vercel will still build."
fi

# --- Deploy --------------------------------------------------------------
if [ "$PROD" -eq 1 ]; then
  log "Deploying wacrm to PRODUCTION..."
  vercel deploy --prod
else
  log "Deploying wacrm PREVIEW build..."
  vercel deploy
fi

log "Deploy command finished — check the URL Vercel printed above."
log "Reminder: apply wacrm's supabase/migrations to the target Supabase project,"
log "and (re)configure the Meta webhook to point at this deployment."
