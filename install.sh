#!/bin/bash
# github-org-mirror installer
# Usage: sudo bash install.sh [install-dir]
set -euo pipefail

[ "$(id -u)" -ne 0 ] && { echo "Run as root (sudo bash install.sh)"; exit 1; }

INSTALL_DIR="${1:-/opt/github-org-mirror}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/repos"

cp "$SCRIPT_DIR/mirror-sync.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/sync-repo.sh"   "$INSTALL_DIR/"
cp "$SCRIPT_DIR/webhook.py"     "$INSTALL_DIR/"
chmod 700 "$INSTALL_DIR/mirror-sync.sh" "$INSTALL_DIR/sync-repo.sh" "$INSTALL_DIR/webhook.py"

# .env: önce source dizinine bak, sonra install dizinine, yoksa oluştur
if [ -f "$SCRIPT_DIR/.env" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp "$SCRIPT_DIR/.env" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    echo "==> Copied .env from source directory"
elif [ ! -f "$INSTALL_DIR/.env" ]; then
    GENERATED_SECRET=$(openssl rand -hex 32)
    cat > "$INSTALL_DIR/.env" <<EOF
GITHUB_TOKEN=your_github_pat_here
GITHUB_ORG=YourOrgName
WEBHOOK_SECRET=$GENERATED_SECRET
EOF
    chmod 600 "$INSTALL_DIR/.env"
    echo ""
    echo "==> Created $INSTALL_DIR/.env"
    echo "    Edit GITHUB_TOKEN and GITHUB_ORG, then re-run install.sh"
    echo "    (WEBHOOK_SECRET is auto-generated — keep it for the GitHub webhook step)"
    echo ""
    if [ -t 0 ]; then
        read -r -p "    Press Enter after editing to continue, or Ctrl+C to stop..."
    else
        echo "ERROR: Running non-interactively but no .env found."
        echo "       Create $INSTALL_DIR/.env and re-run."
        exit 1
    fi
fi

source "$INSTALL_DIR/.env"

# Token doğrula
echo "==> Verifying GitHub token..."
gh_user=$(curl -sf \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['login'])" 2>/dev/null || echo "")
[ -z "$gh_user" ] && { echo "ERROR: GitHub token invalid or unreachable."; exit 1; }
echo "    OK (authenticated as: $gh_user)"

# systemd varsa servis kur, yoksa başlatma komutu göster
if command -v systemctl &>/dev/null && systemctl list-units &>/dev/null 2>&1; then
    SERVICE_FILE="/etc/systemd/system/github-org-mirror-webhook.service"
    sed "s|/opt/github-org-mirror|$INSTALL_DIR|g" \
      "$SCRIPT_DIR/systemd/github-org-mirror-webhook.service" > "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable --now github-org-mirror-webhook
    echo "==> systemd service enabled and started"
else
    echo "==> systemd not available — start the webhook receiver manually:"
    echo "    python3 $INSTALL_DIR/webhook.py &"
fi

# Cron
if command -v crontab &>/dev/null; then
    (crontab -l 2>/dev/null | grep -v "github-org-mirror/mirror-sync" || true
     echo "0 * * * * $INSTALL_DIR/mirror-sync.sh >> $INSTALL_DIR/sync.log 2>&1") | crontab -
    echo "==> Hourly cron job added"
else
    echo "==> crontab not found — add this manually for hourly sync:"
    echo "    0 * * * * $INSTALL_DIR/mirror-sync.sh >> $INSTALL_DIR/sync.log 2>&1"
fi

# İlk sync
echo "==> Running initial mirror sync (this may take a minute)..."
bash "$INSTALL_DIR/mirror-sync.sh"

WEBHOOK_SECRET_VAL=$(grep WEBHOOK_SECRET "$INSTALL_DIR/.env" | cut -d= -f2)

echo ""
echo "======================================================"
echo " Installation complete. Two manual steps remain:"
echo "======================================================"
echo ""
echo "  STEP 1 — Add to your nginx server block:"
echo "  (file: $SCRIPT_DIR/nginx/github-webhook.conf)"
echo ""
cat "$SCRIPT_DIR/nginx/github-webhook.conf"
echo ""
echo "  Then: nginx -t && systemctl reload nginx"
echo ""
echo "  STEP 2 — Create the GitHub org webhook:"
echo ""
echo "  curl -s -X POST \\"
echo "    -H 'Authorization: token $GITHUB_TOKEN' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{"
echo "      \"name\": \"web\", \"active\": true,"
echo "      \"events\": [\"push\",\"create\",\"delete\",\"release\",\"repository\"],"
echo "      \"config\": {"
echo "        \"url\": \"https://YOURDOMAIN/github-webhook\","
echo "        \"content_type\": \"json\","
echo "        \"secret\": \"$WEBHOOK_SECRET_VAL\","
echo "        \"insecure_ssl\": \"0\""
echo "      }"
echo "    }' \\"
echo "    \"https://api.github.com/orgs/$GITHUB_ORG/hooks\""
echo ""
echo "  Mirrors: $INSTALL_DIR/repos/"
echo "  Logs:    $INSTALL_DIR/sync.log | $INSTALL_DIR/webhook.log"
