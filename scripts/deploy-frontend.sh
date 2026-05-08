#!/usr/bin/env bash
# Deploy frontend to Netlify with production Clerk keys
# Usage: ./scripts/deploy-frontend.sh
set -euo pipefail

cd "$(dirname "$0")/../web"
source ../.env.deploy

# Temporarily hide dev env files so .env.production takes priority
[ -f .env.local ] && mv .env.local .env.local.bak
[ -f .env ] && mv .env .env.bak

trap '[ -f .env.bak ] && mv .env.bak .env; [ -f .env.local.bak ] && mv .env.local.bak .env.local' EXIT

npx vite build --mode production
npx netlify-cli deploy --prod --dir=dist --site=7ba53528-21bb-472a-94c2-d0f71721777e --auth="$NETLIFY_AUTH_TOKEN"

echo "✅ Frontend deployed with production Clerk keys"
