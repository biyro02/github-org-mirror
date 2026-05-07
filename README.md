# github-org-mirror

Automatically mirrors all repositories of a GitHub organization to a self-hosted Linux server. Any push triggers an instant sync via webhook; a cron job runs hourly as fallback and picks up newly created repositories automatically.

## Features

- Full `git mirror` — all branches, tags, CI/CD configs, GitHub Actions, full history
- Instant sync on push via GitHub org-level webhook (HMAC-SHA256 verified)
- New repos auto-discovered and cloned when added to the org (no manual steps)
- Hourly cron as fallback
- Lightweight: pure bash + Python stdlib, no extra dependencies

## Requirements

- Linux server (Ubuntu/Debian recommended)
- Python 3, `git`, `curl`, `openssl`
- nginx with SSL (or any reverse proxy)
- GitHub Personal Access Token with `repo` and `admin:org_hook` scopes
- A domain pointed at your server

## File Structure

```
github-org-mirror/
├── install.sh                              ← One-command setup
├── mirror-sync.sh                          ← Full org sync (cron + manual)
├── sync-repo.sh                            ← Single repo update (webhook)
├── webhook.py                              ← GitHub webhook receiver (port 9876)
├── systemd/
│   └── github-org-mirror-webhook.service  ← systemd unit file
└── nginx/
    └── github-webhook.conf                ← nginx location snippet
```

After install, on your server:

```
/opt/github-org-mirror/   (or your chosen directory)
├── repos/
│   ├── repo-one.git
│   ├── repo-two.git
│   └── ...
├── .env                  ← credentials (chmod 600, not committed)
├── sync.log
└── webhook.log
```

## Install

```bash
git clone https://github.com/biyro02/github-org-mirror
cd github-org-mirror
sudo bash install.sh
```

The installer will:
1. Copy files to `/opt/github-org-mirror/` (configurable)
2. Create a `.env` template and wait for you to fill in your token and org name
3. Verify the GitHub token works
4. Enable and start the webhook receiver as a systemd service
5. Add an hourly cron job
6. Run the initial mirror sync
7. Print the two remaining manual steps (nginx + GitHub webhook creation)

## Manual Steps After Install

### 1. Add to nginx

Copy the contents of `nginx/github-webhook.conf` into your server block, **before** the catch-all `location /`, then reload:

```bash
nginx -t && systemctl reload nginx
```

### 2. Create the GitHub org webhook

The installer prints the exact `curl` command with your secret filled in. Point the URL at `https://yourdomain.com/github-webhook`.

Events to subscribe: `push`, `create`, `delete`, `release`, `repository`

## Common Commands

```bash
# Manual full sync
bash /opt/github-org-mirror/mirror-sync.sh

# Update a single repo
bash /opt/github-org-mirror/sync-repo.sh repo-name

# Webhook service status
systemctl status github-org-mirror-webhook

# Live logs
tail -f /opt/github-org-mirror/sync.log
tail -f /opt/github-org-mirror/webhook.log
```

## Restoring from a Mirror

```bash
# Clone locally
git clone /opt/github-org-mirror/repos/your-repo.git ~/recovered-repo

# Clone over SSH from another machine
git clone ssh://user@your-server/opt/github-org-mirror/repos/your-repo.git
```

## How It Works

```
GitHub org
    │  push / create / delete / release / repository.created
    ▼
https://yourdomain.com/github-webhook
    │  nginx proxy → 127.0.0.1:9876
    ▼
webhook.py  (HMAC-SHA256 verified)
    │  subprocess → sync-repo.sh <repo>
    ▼
repos/<repo>.git  (git remote update --prune)

Hourly cron → mirror-sync.sh → also clones any new repos
```

## License

MIT
