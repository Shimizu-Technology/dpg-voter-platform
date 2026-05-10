#!/usr/bin/env bash
# Deploy frontend to Netlify with production Clerk keys
# Usage: ./scripts/deploy-frontend.sh
set -euo pipefail

cd "$(dirname "$0")/../web"
source ../.env.deploy

: "${NETLIFY_SITE_ID:?Set NETLIFY_SITE_ID in .env.deploy to the DPG Netlify site ID}"
: "${NETLIFY_AUTH_TOKEN:?Set NETLIFY_AUTH_TOKEN in .env.deploy}"

# Temporarily hide dev env files so .env.production takes priority
trap '[ -f .env.bak ] && mv .env.bak .env; [ -f .env.local.bak ] && mv .env.local.bak .env.local' EXIT
[ -f .env.local ] && mv .env.local .env.local.bak
[ -f .env ] && mv .env .env.bak

npx vite build --mode production
npx netlify-cli deploy --prod --dir=dist --site="$NETLIFY_SITE_ID" --auth="$NETLIFY_AUTH_TOKEN"

echo "✅ Frontend deployed with production Clerk keys"
