#!/usr/bin/env bash
set -euo pipefail
alembic upgrade head
# --proxy-headers + --forwarded-allow-ips="*" make uvicorn trust the
# X-Forwarded-Proto/Host headers set by Caddy, so request.url_for() builds
# https:// callback URLs (required for the Google OAuth redirect_uri to match).
# Safe here because the API is only reachable through Caddy (host port bound to
# 127.0.0.1 in docker-compose.yml), never directly from the internet.
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 \
  --proxy-headers --forwarded-allow-ips="*"
