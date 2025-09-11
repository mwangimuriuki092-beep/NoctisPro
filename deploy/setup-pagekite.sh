#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo bash deploy/setup-pagekite.sh --subdomain noctispro \
#     --email you@example.com --secret YOUR_PAGEKITE_SECRET [--app-dir /opt/noctis]

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/setup-pagekite.sh ..." >&2
  exit 1
fi

APP_DIR="/opt/noctis"
SUBDOMAIN=""
EMAIL=""
SECRET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subdomain)
      SUBDOMAIN="$2"; shift 2;;
    --email)
      EMAIL="$2"; shift 2;;
    --secret)
      SECRET="$2"; shift 2;;
    --app-dir)
      APP_DIR="$2"; shift 2;;
    *)
      echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$SUBDOMAIN" || -z "$EMAIL" || -z "$SECRET" ]]; then
  echo "Missing required args. Example:" >&2
  echo "  sudo bash deploy/setup-pagekite.sh --subdomain noctispro --email you@example.com --secret XXXXX" >&2
  exit 1
fi

# Ensure PageKite is installed
if ! command -v pagekite >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y pagekite
fi

mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Ensure .env exists
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
  else
    touch .env
  fi
fi

# Helper to set or replace KEY=VALUE in .env
set_env() {
  local key="$1"; shift
  local value="$1"; shift || true
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env PAGEKITE_ENABLE 1
set_env PAGEKITE_SUBDOMAIN "$SUBDOMAIN"
set_env PAGEKITE_EMAIL "$EMAIL"
set_env PAGEKITE_SECRET "$SECRET"

# Django host/security for PageKite URL
DOMAIN_HOST="${SUBDOMAIN}.pagekite.me"
if grep -q '^ALLOWED_HOSTS=' .env; then
  sed -i "s|^ALLOWED_HOSTS=.*|ALLOWED_HOSTS=${DOMAIN_HOST},localhost,127.0.0.1|" .env
else
  echo "ALLOWED_HOSTS=${DOMAIN_HOST},localhost,127.0.0.1" >> .env
fi

set_env CSRF_TRUSTED_ORIGINS "https://${DOMAIN_HOST},http://localhost:8000,http://127.0.0.1:8000"

if grep -q '^CORS_ALLOWED_ORIGINS=' .env; then
  sed -i "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=https://${DOMAIN_HOST}|" .env
else
  echo "CORS_ALLOWED_ORIGINS=https://${DOMAIN_HOST}" >> .env
fi

set_env SECURE_SSL_REDIRECT True

# Install/enable tunnel service
install -m 0644 "$APP_DIR/deploy/noctis-tunnel.service" /etc/systemd/system/noctis-tunnel.service
systemctl daemon-reload
systemctl enable --now noctis-tunnel.service

# Restart web to pick up env changes
systemctl restart noctis-web.service || true

echo "PageKite configured. URL: https://${DOMAIN_HOST}"
echo "Check: systemctl status noctis-tunnel | cat"

