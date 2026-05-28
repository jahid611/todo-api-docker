#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
COMPOSE_DIR="/opt/todo-stack"
LOG="/var/log/todo-deploy.log"
BACKUP_DIR="/var/backups/todo-api"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

cd "$COMPOSE_DIR"

GHCR_USER=$(grep '^GHCR_USER=' .env | cut -d= -f2)
CURRENT_VERSION=$(grep '^APP_VERSION=' .env | cut -d= -f2)

log "Deploy started: $CURRENT_VERSION -> $VERSION"

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
log "Backup SQLite -> $BACKUP_DIR/todos-${TIMESTAMP}.db"
docker run --rm \
    -v todo-stack_todo-data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine sh -c "[ -f /data/todos.db ] && cp /data/todos.db /backup/todos-${TIMESTAMP}.db || true" 2>>"$LOG"

log "Pulling ghcr.io/${GHCR_USER}/todo-api:${VERSION}"
if ! docker pull "ghcr.io/${GHCR_USER}/todo-api:${VERSION}" >>"$LOG" 2>&1; then
    log "ERROR: Pull failed for version $VERSION, aborting"
    exit 1
fi

sed -i "s/^APP_VERSION=.*/APP_VERSION=${VERSION}/" .env

log "Recreating app service"
docker compose up -d --no-deps app >>"$LOG" 2>&1

log "Smoke test (max 10 retries)"
for i in $(seq 1 10); do
    if curl -sf http://localhost/health > /dev/null 2>&1; then
        log "Deploy $VERSION OK (attempt $i)"
        exit 0
    fi
    log "Attempt $i/10 failed, waiting 3s..."
    sleep 3
done

log "ERROR: Smoke test failed, rolling back to $CURRENT_VERSION"
sed -i "s/^APP_VERSION=.*/APP_VERSION=${CURRENT_VERSION}/" .env
docker compose up -d --no-deps app >>"$LOG" 2>&1

LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/todos-*.db 2>/dev/null | head -1 || true)
if [[ -n "$LATEST_BACKUP" ]]; then
    log "Restoring DB from $LATEST_BACKUP"
    docker run --rm \
        -v todo-stack_todo-data:/data \
        -v "$BACKUP_DIR":/backup \
        alpine cp "/backup/$(basename "$LATEST_BACKUP")" /data/todos.db >>"$LOG" 2>&1
fi

log "Rollback to $CURRENT_VERSION complete"
exit 1
