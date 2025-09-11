#!/usr/bin/env bash
set -euo pipefail

# Enhanced native installation script for Noctis Pro
# Usage: sudo bash deploy/install-native.sh /path/to/repo [/opt/noctis]

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/install-native.sh /path/to/repo" >&2
  exit 1
fi

REPO_DIR=${1:-}
APP_DIR=${2:-/opt/noctis}
APP_USER=${APP_USER:-www-data}

log() { printf "[install] %s\n" "$*"; }
err() { printf "[install][ERROR] %s\n" "$*" >&2; }
success() { printf "[install][SUCCESS] %s\n" "$*"; }

if [[ -z "${REPO_DIR}" ]]; then
  err "Usage: sudo bash deploy/install-native.sh /path/to/repo [/opt/noctis]"
  exit 1
fi

log "Starting Noctis Pro installation..."
log "Source: $REPO_DIR"
log "Destination: $APP_DIR"

mkdir -p "${APP_DIR}"
log "Syncing application files..."
rsync -a --delete --exclude '.git' --exclude '.venv' --exclude 'node_modules' "${REPO_DIR}/" "${APP_DIR}/"

cd "${APP_DIR}"

# Create env file if missing
log "Setting up environment configuration..."
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    log "Created .env from .env.example"
  else
    err ".env.example not found, creating minimal .env"
    touch .env
  fi
fi

# Helper function to clean up malformed .env files
clean_env() {
  if [[ -f .env ]]; then
    # Remove lines that don't follow KEY=VALUE format
    grep -E '^[A-Z_][A-Z0-9_]*=' .env > .env.tmp || touch .env.tmp
    mv .env.tmp .env
    # Ensure file ends with newline
    [[ -s .env && $(tail -c1 .env | wc -l) -eq 0 ]] && echo "" >> .env
  fi
}

# Helper function to set environment variables
set_env() {
  local key="$1"; shift
  local value="$*"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    # Ensure the .env file ends with a newline before appending
    [[ -s .env && $(tail -c1 .env | wc -l) -eq 0 ]] && echo "" >> .env
    echo "${key}=${value}" >> .env
  fi
}

# Clean up any existing malformed .env file
clean_env

# Generate SECRET_KEY if missing
if ! grep -q '^SECRET_KEY=' .env || grep -q 'your-secret-key' .env; then
  log "Generating Django SECRET_KEY..."
  SECRET=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + string.punctuation
alphabet = alphabet.replace('"','').replace("'",'').replace('`','')
print(''.join(secrets.choice(alphabet) for _ in range(64)))
PY
)
  set_env SECRET_KEY "$SECRET"
fi

# Generate PostgreSQL password if missing
if ! grep -q '^POSTGRES_PASSWORD=' .env || grep -q 'your-postgres-password' .env; then
  log "Generating PostgreSQL password..."
  PG_PASS=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
)
  set_env POSTGRES_PASSWORD "$PG_PASS"
  
  # Create/update PostgreSQL user and database
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS noctis_pro;" || true
  sudo -u postgres psql -c "DROP USER IF EXISTS noctis_user;" || true
  sudo -u postgres psql -c "CREATE DATABASE noctis_pro;"
  sudo -u postgres psql -c "CREATE USER noctis_user WITH PASSWORD '$PG_PASS';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE noctis_pro TO noctis_user;"
  sudo -u postgres psql -c "ALTER USER noctis_user CREATEDB;"
fi

# Generate admin password if missing
ADMIN_PASSWORD=""
if ! grep -q '^ADMIN_PASSWORD=' .env || grep -q 'your-admin-password' .env; then
  log "Generating admin user password..."
  ADMIN_PASSWORD=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(16)))
PY
)
  set_env ADMIN_PASSWORD "$ADMIN_PASSWORD"
fi

# Set database URL for PostgreSQL
set_env DATABASE_URL "postgres://noctis_user:$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2):@localhost:5432/noctis_pro"

# Set production defaults
set_env DEBUG False
set_env COLLECTSTATIC 1

# Ensure directories
log "Creating application directories..."
mkdir -p media static staticfiles logs
mkdir -p /var/log/noctis

# Ensure Python and virtualenv tooling, then create/activate venv
log "Setting up Python virtual environment..."
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 is required but not found. Please install Python 3 and rerun."
  exit 1
fi

if [[ ! -d .venv ]]; then
  log "Creating Python virtual environment..."
  if ! python3 -m venv .venv >/dev/null 2>&1; then
    log "Failed to create virtualenv. Installing python3-venv and retrying..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y python3-venv python3-pip python3-dev build-essential libpq-dev
    python3 -m venv .venv
  fi
fi

if [[ ! -f .venv/bin/activate ]]; then
  err "Virtualenv not found at ${APP_DIR}/.venv"
  exit 1
fi

source .venv/bin/activate
log "Installing Python dependencies..."
pip install --upgrade pip setuptools wheel

# Install requirements with error handling
if [[ -f requirements.txt ]]; then
  pip install -r requirements.txt
else
  log "requirements.txt not found, installing basic Django stack..."
  pip install django daphne psycopg2-binary redis celery pillow
fi

# Set up Django
export DJANGO_SETTINGS_MODULE=noctis_pro.settings

# Load environment variables
set -a
source .env || true
set +a

log "Running database migrations..."
if ! python manage.py migrate; then
  err "Migration failed. Attempting to reset database..."
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS noctis_pro;"
  sudo -u postgres psql -c "CREATE DATABASE noctis_pro;"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE noctis_pro TO noctis_user;"
  python manage.py migrate
fi

log "Collecting static files..."
python manage.py collectstatic --noinput || log "Static collection failed, continuing..."

# Create superuser if configured
if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
  log "Creating admin superuser..."
  ADMIN_USER="${ADMIN_USER:-admin}"
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
  
  python manage.py shell << EOF
import os
from django.contrib.auth import get_user_model
User = get_user_model()

username = '${ADMIN_USER}'
email = '${ADMIN_EMAIL}'
password = '${ADMIN_PASSWORD}'

if User.objects.filter(username=username).exists():
    user = User.objects.get(username=username)
    user.set_password(password)
    user.save()
    print(f'Updated existing superuser: {username}')
else:
    User.objects.create_superuser(username=username, email=email, password=password)
    print(f'Created new superuser: {username}')
EOF
fi

# Install systemd services
log "Installing systemd services..."
install -m 0644 deploy/noctis-web.service /etc/systemd/system/noctis-web.service
install -m 0644 deploy/noctis-worker.service /etc/systemd/system/noctis-worker.service
systemctl daemon-reload
systemctl enable noctis-web.service noctis-worker.service

log "Starting services..."
systemctl restart noctis-worker.service
systemctl restart noctis-web.service

# Install Caddy site config
log "Configuring web server..."
if [[ -f deploy/Caddyfile.native ]]; then
  install -m 0644 deploy/Caddyfile.native /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy
fi

# Enable PageKite tunnel if configured in .env
PAGEKITE_URL=""
if grep -q '^PAGEKITE_ENABLE=1' .env; then
  log "Setting up PageKite tunnel..."
  if [[ -f deploy/noctis-tunnel.service ]]; then
    install -m 0644 deploy/noctis-tunnel.service /etc/systemd/system/noctis-tunnel.service
    systemctl daemon-reload
    systemctl enable noctis-tunnel.service
    systemctl restart noctis-tunnel.service
    
    # Extract PageKite subdomain for URL display
    PAGEKITE_SUBDOMAIN=$(grep '^PAGEKITE_SUBDOMAIN=' .env | cut -d= -f2 || echo "")
    if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
      PAGEKITE_URL="https://${PAGEKITE_SUBDOMAIN}.pagekite.me"
    fi
  fi
fi

# Set proper ownership
log "Setting file permissions..."
chown -R ${APP_USER}:${APP_USER} "${APP_DIR}"
chmod -R 755 "${APP_DIR}"
chmod 600 "${APP_DIR}/.env"

# Wait for services to start
log "Waiting for services to start..."
sleep 5

# Check service status
log "Checking service status..."
SERVICES_OK=true
for service in noctis-web noctis-worker caddy; do
  if ! systemctl is-active --quiet $service; then
    err "Service $service is not running"
    SERVICES_OK=false
  fi
done

# Get server IP for local access
SERVER_IP=$(hostname -I | awk '{print $1}' || echo "localhost")

# Display installation results
echo ""
echo "🎉 ====================================="
echo "   NOCTIS PRO INSTALLATION COMPLETE"
echo "===================================== 🎉"
echo ""

if [[ "$SERVICES_OK" == "true" ]]; then
  success "All services are running successfully!"
else
  err "Some services failed to start. Check logs with: journalctl -u noctis-web -f"
fi

echo ""
echo "📋 ACCESS INFORMATION:"
echo "----------------------------------------"
echo "🌐 Local Access:"
echo "   http://localhost:8000"
echo "   http://${SERVER_IP}:8000"
echo ""

if [[ -n "$PAGEKITE_URL" ]]; then
  echo "🌍 External Access (PageKite):"
  echo "   $PAGEKITE_URL"
  echo ""
fi

echo "👤 Admin Credentials:"
echo "   Username: ${ADMIN_USER:-admin}"
echo "   Password: ${ADMIN_PASSWORD:-<check .env file>}"
echo "   Email: ${ADMIN_EMAIL:-admin@example.com}"
echo ""

echo "🔧 Service Management:"
echo "   Status: systemctl status noctis-web noctis-worker caddy"
echo "   Logs:   journalctl -u noctis-web -f"
echo "   Restart: systemctl restart noctis-web"
echo ""

echo "📁 Application Directory: ${APP_DIR}"
echo "📄 Configuration File: ${APP_DIR}/.env"
echo ""

# Health check
log "Performing health check..."
sleep 3
if curl -sf http://localhost:8000/health/ >/dev/null 2>&1; then
  success "✅ Application is responding to health checks"
else
  err "❌ Application health check failed"
fi

echo "✨ Installation completed successfully!"
echo "Visit your application at the URLs shown above."

