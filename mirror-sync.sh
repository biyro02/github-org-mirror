#!/bin/bash
# Full sync — mirrors all org repos, clones any new ones automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

MIRROR_DIR="$SCRIPT_DIR/repos"
LOG_FILE="$SCRIPT_DIR/sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$MIRROR_DIR"

repos=$(curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&type=all" \
  | python3 -c "import json,sys; [print(r['name']) for r in json.load(sys.stdin)]")

count=0
for repo in $repos; do
    repo_path="$MIRROR_DIR/${repo}.git"
    clone_url="https://oauth2:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${repo}.git"
    if [ -d "$repo_path" ]; then
        log "UPDATE: $repo"
        git -C "$repo_path" remote update --prune >> "$LOG_FILE" 2>&1
    else
        log "CLONE: $repo (new)"
        git clone --mirror "$clone_url" "$repo_path" >> "$LOG_FILE" 2>&1
    fi
    count=$((count + 1))
done

log "Sync complete — $count repos processed."
