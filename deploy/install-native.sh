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

# Ensure Python and virtualenv tooling, then create/activate venv
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not found. Please install Python 3 and rerun." >&2
  exit 1
fi
if [[ ! -d .venv ]]; then
  if ! python3 -m venv .venv >/dev/null 2>&1; then
    echo "Failed to create virtualenv. Attempting to install python3-venv and retry..." >&2
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3-venv python3-pip
    python3 -m venv .venv
  fi
fi
if [[ ! -f .venv/bin/activate ]]; then
  echo "Virtualenv not found at ${APP_DIR}/.venv. Create it manually: python3 -m venv ${APP_DIR}/.venv" >&2
  exit 1
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

# Enable PageKite tunnel if configured in .env
if grep -q '^PAGEKITE_ENABLE=1' .env; then
  if [[ -f deploy/noctis-tunnel.service ]]; then
    install -m 0644 deploy/noctis-tunnel.service /etc/systemd/system/noctis-tunnel.service
    systemctl daemon-reload
    systemctl enable noctis-tunnel.service
    systemctl restart noctis-tunnel.service
  fi
fi

chown -R ${APP_USER}:${APP_USER} "${APP_DIR}" || true

echo "Installation complete. Check services: systemctl status noctis-web noctis-worker caddy"

