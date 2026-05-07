# github-org-mirror

[![CI](https://github.com/Uruba-Software/github-org-mirror/actions/workflows/ci.yml/badge.svg)](https://github.com/Uruba-Software/github-org-mirror/actions/workflows/ci.yml)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/downloads/)
[![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black)](https://www.linux.org/)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![nginx](https://img.shields.io/badge/Proxy-nginx-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![No Dependencies](https://img.shields.io/badge/Dependencies-none-lightgrey)](https://github.com/Uruba-Software/github-org-mirror)

Automatically mirrors all repositories of a GitHub organization to a self-hosted Linux server. Any push triggers an instant sync via webhook; a cron job runs hourly as fallback and picks up newly created repositories automatically.

**Use case:** Protection against GitHub account suspension, accidental deletion, or org-level bans. Every repo — including private ones — is kept as a full bare mirror with all branches, tags, CI configs, and commit history.

---

## How It Works

```
GitHub org
    │  push / create / delete / release / repository.created
    ▼
https://yourdomain.com/github-webhook
    │  nginx → 127.0.0.1:9876
    ▼
webhook.py  (HMAC-SHA256 signature verified)
    │  calls sync-repo.sh <repo-name>
    ▼
repos/<repo-name>.git  (git remote update --prune)

Hourly cron → mirror-sync.sh → full org scan, clones any new repos
```

---

## Requirements

| Requirement | Min. Version | Notes |
|-------------|-------------|-------|
| Linux | Ubuntu 20.04+ / Debian 11+ | Other distros work; installer targets `apt` |
| Python 3 | 3.8+ | Webhook receiver uses stdlib only |
| Git | 2.x | For `clone --mirror` and `remote update` |
| curl | any | GitHub API calls in shell scripts |
| openssl | any | Auto-generating `WEBHOOK_SECRET` |
| nginx | 1.18+ | Reverse proxy for the webhook endpoint |
| SSL certificate | — | Required for GitHub to send webhook events |
| GitHub PAT | — | Needs `repo` + `admin:org_hook` scopes |

### Installing requirements

<details>
<summary><strong>Ubuntu / Debian</strong></summary>

```bash
sudo apt update
sudo apt install -y python3 git curl openssl nginx
```

</details>

<details>
<summary><strong>RHEL / CentOS / Fedora</strong></summary>

```bash
sudo dnf install -y python3 git curl openssl nginx
```

</details>

<details>
<summary><strong>nginx setup guide</strong></summary>

Official docs: https://nginx.org/en/docs/install.html

Quick start on Ubuntu:
```bash
sudo apt install nginx
sudo systemctl enable --now nginx
```

</details>

<details>
<summary><strong>SSL certificate (Let's Encrypt / Certbot)</strong></summary>

Official guide: https://certbot.eff.org/instructions

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

GitHub requires HTTPS to deliver webhook events. Certbot auto-renews the certificate.

</details>

<details>
<summary><strong>GitHub Personal Access Token</strong></summary>

Official guide: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens

Required scopes:
- `repo` — to clone and pull private repositories
- `admin:org_hook` — to create the org-level webhook via API

Classic token recommended (fine-grained tokens have limited org webhook support).

</details>

---

## File Structure

```
github-org-mirror/
├── install.sh                              ← One-command setup
├── mirror-sync.sh                          ← Full org sync (cron + manual)
├── sync-repo.sh                            ← Single repo update (called by webhook)
├── webhook.py                              ← GitHub webhook receiver (port 9876)
├── systemd/
│   └── github-org-mirror-webhook.service  ← systemd unit file
└── nginx/
    └── github-webhook.conf                ← nginx location snippet
```

After installation, on your server:

```
/opt/github-org-mirror/      (or your chosen path)
├── repos/
│   ├── repo-one.git
│   ├── repo-two.git
│   └── ...
├── .env                     ← credentials (chmod 600, never committed)
├── sync.log
└── webhook.log
```

---

## Install

```bash
git clone https://github.com/Uruba-Software/github-org-mirror
cd github-org-mirror
sudo bash install.sh
```

The installer will:
1. Copy files to `/opt/github-org-mirror/` (pass a different path as argument to override)
2. Create a `.env` template and wait for you to fill in your token and org name
3. Verify the GitHub token works
4. Enable and start the webhook receiver as a systemd service
5. Add an hourly cron job
6. Run the initial mirror sync (clones all org repos)
7. Print the two remaining manual steps below

### Step 1 — nginx

Add the contents of `nginx/github-webhook.conf` to your server block, **before** the catch-all `location /`, then reload:

```nginx
location = /github-webhook {
    proxy_pass http://127.0.0.1:9876;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 30;
    client_max_body_size 1M;
}
```

```bash
nginx -t && systemctl reload nginx
```

### Step 2 — GitHub org webhook

The installer prints the exact `curl` command with your secret pre-filled. Or run it manually:

```bash
source /opt/github-org-mirror/.env

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"web\",
    \"active\": true,
    \"events\": [\"push\", \"create\", \"delete\", \"release\", \"repository\"],
    \"config\": {
      \"url\": \"https://YOURDOMAIN/github-webhook\",
      \"content_type\": \"json\",
      \"secret\": \"$WEBHOOK_SECRET\",
      \"insecure_ssl\": \"0\"
    }
  }" \
  "https://api.github.com/orgs/$GITHUB_ORG/hooks"
```

---

## Common Commands

```bash
# Manual full sync
bash /opt/github-org-mirror/mirror-sync.sh

# Update a single repo immediately
bash /opt/github-org-mirror/sync-repo.sh repo-name

# Webhook service status
systemctl status github-org-mirror-webhook

# Live logs
tail -f /opt/github-org-mirror/sync.log
tail -f /opt/github-org-mirror/webhook.log
```

## Restoring from a Mirror

```bash
# Clone locally on the same server
git clone /opt/github-org-mirror/repos/your-repo.git ~/recovered-repo

# Clone over SSH from another machine
git clone ssh://user@your-server/opt/github-org-mirror/repos/your-repo.git
```

---

## License

GPL v3 — see [LICENSE](LICENSE)
