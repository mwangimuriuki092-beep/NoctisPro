#!/usr/bin/env bash
set -euo pipefail

# Auto-detect and install Noctis into /opt/noctis (or a custom destination)
# Usage:
#   sudo bash deploy/install-autodetect.sh [SOURCE_DIR] [DEST_DIR]
#
# Behavior:
# - If SOURCE_DIR not provided, attempts to auto-detect a repository directory containing manage.py
# - Syncs files to DEST_DIR (default: /opt/noctis), excluding venvs and transient files
# - Creates .env only if missing (SECRET_KEY generated if missing)
# - Ensures Python venv, installs requirements
# - Exports env vars from .env for manage.py to see them
# - Runs Django check, migrate, and collectstatic

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/install-autodetect.sh [SOURCE_DIR] [DEST_DIR]" >&2
  exit 1
fi

SRC_DIR=${1:-}
DEST_DIR=${2:-/opt/noctis}
APP_USER=${APP_USER:-www-data}

log() { printf "[install] %s\n" "$*"; }
err() { printf "[install][error] %s\n" "$*" >&2; }

has_manage_py() {
  local d="$1"
  [[ -d "$d" && -f "$d/manage.py" ]]
}

autodetect_source() {
  local candidates=()

  # If we are inside a repo with manage.py
  candidates+=("$PWD")
  # Common locations
  candidates+=("/workspace" "/noctis" "/opt/noctis-src")
  # User homes
  for d in /home/*/noctis /root/noctis; do
    candidates+=("$d")
  done

  for c in "${candidates[@]}"; do
    if has_manage_py "$c"; then
      echo "$c"
      return 0
    fi
  done

  # Broad search but bounded
  local found
  found=$(find / -maxdepth 4 -type f -name manage.py -printf '%h\n' 2>/dev/null | head -n1 || true)
  if [[ -n "${found:-}" ]] && has_manage_py "$found"; then
    echo "$found"
    return 0
  fi
  return 1
}

if [[ -z "${SRC_DIR}" ]]; then
  log "Auto-detecting source directory..."
  if ! SRC_DIR=$(autodetect_source); then
    err "Could not auto-detect a Django project (manage.py). Provide SOURCE_DIR explicitly."
    exit 1
  fi
fi

if ! has_manage_py "$SRC_DIR"; then
  err "Source directory '$SRC_DIR' does not contain manage.py"
  exit 1
fi

log "Source directory: $SRC_DIR"
log "Destination directory: $DEST_DIR"

mkdir -p "$DEST_DIR"

if ! command -v rsync >/dev/null 2>&1; then
  log "Installing rsync..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get install -y rsync
fi

log "Syncing source to destination (excluding venvs and caches)..."
rsync -a --delete \
  --exclude '.git' \
  --exclude '.env' \
  --exclude '.venv' \
  --exclude 'venv' \
  --exclude 'env' \
  --exclude '__pycache__' \
  --exclude 'node_modules' \
  "$SRC_DIR/" "$DEST_DIR/"

cd "$DEST_DIR"

# Create .env if missing only
if [[ ! -f .env ]]; then
  log "Creating .env (since none exists)"
  touch .env
fi

# Ensure SECRET_KEY exists in .env (only append if missing)
if ! grep -q '^SECRET_KEY=' .env; then
  log "Generating SECRET_KEY in .env"
  SECRET=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + string.punctuation
alphabet = alphabet.replace('"','').replace("'",'').replace('`','')
print(''.join(secrets.choice(alphabet) for _ in range(64)))
PY
)
  printf "SECRET_KEY=%s\n" "$SECRET" >> .env
fi

# Provide reasonable defaults only if missing
if ! grep -q '^ALLOWED_HOSTS=' .env; then
  HOSTNAME=$(hostname -f 2>/dev/null || hostname || echo localhost)
  printf "ALLOWED_HOSTS=%s,127.0.0.1,localhost\n" "$HOSTNAME" >> .env
fi
if ! grep -q '^DEBUG=' .env; then
  printf "DEBUG=0\n" >> .env
fi

# Ensure runtime directories exist (only create if missing)
mkdir -p media static staticfiles || true

select_python() {
  # Prefer Python 3.11 (better compatibility with pinned deps), then 3.10, else system python3
  local py_candidates=(/usr/bin/python3.11 /usr/bin/python3.10 /usr/bin/python3)
  for py in "${py_candidates[@]}"; do
    if [[ -x "$py" ]]; then
      echo "$py"
      return 0
    fi
  done
  return 1
}

PYTHON_BIN=""
if ! PYTHON_BIN=$(select_python); then
  err "No suitable python3 found. Installing python3.11..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y python3.11 python3.11-venv python3-pip || true
  if ! PYTHON_BIN=$(select_python); then
    err "Failed to locate python3 after installation."
    exit 1
  fi
fi
log "Using Python interpreter: $PYTHON_BIN ($($PYTHON_BIN -V 2>&1))"

# Recreate venv if it's missing or uses a different major.minor than selected
if [[ -d .venv && -x .venv/bin/python ]]; then
  CURRENT_VENV_PY_VER=$(.venv/bin/python -c 'import sys; print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo "")
  TARGET_PY_VER=$($PYTHON_BIN -c 'import sys; print("%d.%d"%sys.version_info[:2])')
  if [[ "$CURRENT_VENV_PY_VER" != "$TARGET_PY_VER" ]]; then
    log "Existing venv uses Python $CURRENT_VENV_PY_VER; recreating for $TARGET_PY_VER"
    rm -rf .venv
  fi
fi

if [[ ! -d .venv ]]; then
  log "Creating virtual environment at $DEST_DIR/.venv"
  "$PYTHON_BIN" -m venv .venv
fi

if [[ ! -f .venv/bin/activate ]]; then
  err "Virtualenv not found at $DEST_DIR/.venv."
  exit 1
fi

source .venv/bin/activate
pip install --upgrade pip setuptools wheel

# System build dependencies for common Python packages (best-effort)
log "Installing system build dependencies (best-effort)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  build-essential pkg-config \
  libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev libopenjp2-7-dev libtiff-dev libwebp-dev \
  libharfbuzz-dev libfribidi-dev \
  libpq-dev \
  libgl1 libglib2.0-0 || true

if [[ -f requirements.txt ]]; then
  log "Installing Python requirements..."
  pip install -r requirements.txt
else
  err "requirements.txt not found in $DEST_DIR"
  exit 1
fi

# Export .env into the environment so Django can read SECRET_KEY, etc.
set -a
source .env || true
set +a

export DJANGO_SETTINGS_MODULE=noctis_pro.settings

log "Running Django checks..."
python manage.py check || true

log "Applying migrations..."
python manage.py migrate

log "Collecting static files..."
python manage.py collectstatic --noinput || true

# Ownership (best-effort)
chown -R ${APP_USER}:${APP_USER} "$DEST_DIR" || true

log "Done. To run the server (development):"
log "  cd $DEST_DIR && source .venv/bin/activate && python manage.py runserver 0.0.0.0:8000"

