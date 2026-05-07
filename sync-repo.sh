#!/bin/bash
# Single repo sync — called by the webhook receiver on push events.
REPO_NAME="$1"
[ -z "$REPO_NAME" ] && { echo "Usage: $0 <repo-name>"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

MIRROR_DIR="$SCRIPT_DIR/repos"
LOG_FILE="$SCRIPT_DIR/sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$REPO_NAME] $*" | tee -a "$LOG_FILE"; }

repo_path="$MIRROR_DIR/${REPO_NAME}.git"
clone_url="https://oauth2:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${REPO_NAME}.git"

if [ -d "$repo_path" ]; then
    log "Updating mirror..."
    git -C "$repo_path" remote update --prune >> "$LOG_FILE" 2>&1
else
    log "New repo — cloning mirror..."
    git clone --mirror "$clone_url" "$repo_path" >> "$LOG_FILE" 2>&1
fi

log "Done."
