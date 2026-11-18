#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
umask 077
destination=${1:?Usage: scripts/backup.sh /secure/backup-directory}
mkdir -p "$destination"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose exec -T db pg_dump -U qazaqmetal -d qazaqmetal -Fc > "$destination/database-$stamp.dump"
docker compose exec -T api tar -C /data -czf - uploads > "$destination/uploads-$stamp.tar.gz"
echo "Backup created in private destination. Copy both files to encrypted off-host storage."
