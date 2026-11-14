#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dump=${1:?Usage: scripts/restore.sh database.dump uploads.tar.gz CONFIRM_RESTORE}
uploads=${2:?Uploads archive required}
[ "${3:-}" = CONFIRM_RESTORE ] || { echo 'Restoration replaces the target database. Supply CONFIRM_RESTORE.'; exit 1; }
docker compose stop api
cat "$dump" | docker compose exec -T db pg_restore -U qazaqmetal -d qazaqmetal --clean --if-exists --no-owner
cat "$uploads" | docker compose run --rm -T --no-deps api tar -C /data -xzf -
docker compose up -d api
echo 'Check /api/health and test login, images and QR after restore.'
