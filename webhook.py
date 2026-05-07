#!/usr/bin/env python3
"""GitHub org webhook receiver — triggers mirror sync on push/create/repository events."""

import hashlib
import hmac
import http.server
import json
import logging
import os
import subprocess
import sys

PORT = 9876
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SYNC_REPO = os.path.join(SCRIPT_DIR, "sync-repo.sh")
LOG_FILE = os.path.join(SCRIPT_DIR, "webhook.log")


def load_env():
    env = {}
    try:
        with open(os.path.join(SCRIPT_DIR, ".env")) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return env


ENV = load_env()
WEBHOOK_SECRET = ENV.get("WEBHOOK_SECRET", "")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


def verify_signature(body: bytes, signature: str) -> bool:
    if not WEBHOOK_SECRET:
        log.warning("No WEBHOOK_SECRET set — skipping verification")
        return True
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(), body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature, expected)


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/github-webhook":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        if not verify_signature(body, self.headers.get("X-Hub-Signature-256", "")):
            log.warning("Rejected: bad signature from %s", self.client_address[0])
            self.send_response(401)
            self.end_headers()
            return

        event = self.headers.get("X-GitHub-Event", "")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        repo_name = payload.get("repository", {}).get("name", "")

        if event in ("push", "create", "release", "delete"):
            if repo_name:
                log.info("event=%s repo=%s — sync triggered", event, repo_name)
                subprocess.Popen([SYNC_REPO, repo_name])
        elif event == "repository" and payload.get("action") == "created":
            log.info("New repo created: %s — cloning", repo_name)
            subprocess.Popen([SYNC_REPO, repo_name])
        else:
            log.debug("Ignored event=%s", event)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK\n")

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    log.info("Webhook receiver started on 127.0.0.1:%d", PORT)
    server = http.server.HTTPServer(("127.0.0.1", PORT), WebhookHandler)
    server.serve_forever()
