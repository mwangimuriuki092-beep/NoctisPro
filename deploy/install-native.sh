#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo bash deploy/install-native.sh /path/to/repo [/opt/noctis]

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/install-native.sh /path/to/repo" >&2
  exit 1
fi

REPO_DIR=${1:-}
APP_DIR=${2:-/opt/noctis}
APP_USER=${APP_USER:-www-data}

if [[ -z "${REPO_DIR}" ]]; then
  echo "Usage: sudo bash deploy/install-native.sh /path/to/repo [/opt/noctis]" >&2
  exit 1
fi

mkdir -p "${APP_DIR}"
rsync -a --delete --exclude '.git' --exclude '.venv' --exclude 'node_modules' "${REPO_DIR}/" "${APP_DIR}/"

cd "${APP_DIR}"

# Create env file if missing
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
  else
    touch .env
  fi
fi

# Generate SECRET_KEY if missing
if ! grep -q '^SECRET_KEY=' .env; then
  SECRET=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + string.punctuation
alphabet = alphabet.replace('"','').replace("'",'').replace('`','')
print(''.join(secrets.choice(alphabet) for _ in range(64)))
PY
)
  echo "SECRET_KEY=${SECRET}" >> .env
fi

# Ensure directories
mkdir -p media static staticfiles

# Create virtualenv
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt

# Collect static and migrate
export DJANGO_SETTINGS_MODULE=noctis_pro.settings
set +e
python manage.py migrate || exit 1
python manage.py collectstatic --noinput || true
set -e

# Install systemd services
install -m 0644 deploy/noctis-web.service /etc/systemd/system/noctis-web.service
install -m 0644 deploy/noctis-worker.service /etc/systemd/system/noctis-worker.service
systemctl daemon-reload
systemctl enable noctis-web.service noctis-worker.service
systemctl restart noctis-worker.service
systemctl restart noctis-web.service

# Install Caddy site config (optional)
if [[ -f deploy/Caddyfile.native ]]; then
  install -m 0644 deploy/Caddyfile.native /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy || true
fi

chown -R ${APP_USER}:${APP_USER} "${APP_DIR}" || true

echo "Installation complete. Check services: systemctl status noctis-web noctis-worker caddy"

