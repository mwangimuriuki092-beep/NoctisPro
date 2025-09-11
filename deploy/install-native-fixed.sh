#!/usr/bin/env bash
set -euo pipefail

# FIXED Native installation script for Noctis Pro
# Usage: sudo bash deploy/install-native-fixed.sh /path/to/repo [/opt/noctis]

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/install-native-fixed.sh /path/to/repo" >&2
  exit 1
fi

REPO_DIR=${1:-}
APP_DIR=${2:-/opt/noctis}
APP_USER=${APP_USER:-www-data}

log() { printf "[install] %s\n" "$*"; }
err() { printf "[install][ERROR] %s\n" "$*" >&2; }
success() { printf "[install][SUCCESS] %s\n" "$*"; }

# Better error diagnostics
trap 'err "Failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

# Ensure system dependencies are present (apt-based systems)
APT_UPDATED=false
ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    if [[ "$APT_UPDATED" == "false" ]]; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      APT_UPDATED=true
    fi
    apt-get install -y "$pkg"
  fi
}

log "Checking and installing system dependencies if needed..."
ensure_pkg rsync
ensure_pkg curl
ensure_pkg python3
ensure_pkg python3-venv
ensure_pkg python3-pip
ensure_pkg python3-dev
ensure_pkg build-essential
ensure_pkg libpq-dev
ensure_pkg postgresql
ensure_pkg postgresql-contrib
ensure_pkg redis-server

# Ensure required services are enabled and running
systemctl enable --now postgresql >/dev/null 2>&1 || true
systemctl enable --now redis-server >/dev/null 2>&1 || true

# Ensure PostgreSQL cluster is started, even without systemd
ensure_postgres_running() {
  if sudo -u postgres psql -tAc "SELECT 1" >/dev/null 2>&1; then
    return 0
  fi
  if command -v pg_lsclusters >/dev/null 2>&1 && command -v pg_ctlcluster >/dev/null 2>&1; then
    while read -r ver name _; do
      pg_ctlcluster "$ver" "$name" start >/dev/null 2>&1 || true
      pg_ctlcluster --skip-systemctl "$ver" "$name" start >/dev/null 2>&1 || true
    done < <(pg_lsclusters -h | awk '{print $1" "$2" "$3}')
  else
    service postgresql start >/dev/null 2>&1 || systemctl start postgresql >/dev/null 2>&1 || true
  fi
  # Wait up to 15s for socket
  for i in $(seq 1 15); do
    if sudo -u postgres psql -tAc "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  err "PostgreSQL is not running after attempts to start it. Proceeding may fail."
}

if [[ -z "${REPO_DIR}" ]]; then
  err "Usage: sudo bash deploy/install-native-fixed.sh /path/to/repo [/opt/noctis]"
  exit 1
fi

# Helper function to clean up malformed .env files
clean_env() {
  if [[ -f .env ]]; then
    # Remove lines that don't follow KEY=VALUE format
    grep -E '^[A-Z_][A-Z0-9_]*=' .env > .env.tmp || touch .env.tmp
    mv .env.tmp .env
    # Ensure file ends with newline
    if [[ -s .env ]]; then
      if [ "$( (tail -c1 .env 2>/dev/null | wc -l) || true )" -eq 0 ]; then
        echo "" >> .env
      fi
    fi
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
    if [[ -s .env ]]; then
      if [ "$( (tail -c1 .env 2>/dev/null | wc -l) || true )" -eq 0 ]; then
        echo "" >> .env
      fi
    fi
    echo "${key}=${value}" >> .env
  fi
}

log "Starting Noctis Pro installation..."
log "Source: $REPO_DIR"
log "Destination: $APP_DIR"

# Ensure destination directory exists
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
    log "Creating minimal .env file"
    cat > .env << 'EOF'
DEBUG=False
SECRET_KEY=your-secret-key
POSTGRES_PASSWORD=your-postgres-password
ADMIN_PASSWORD=your-admin-password
DATABASE_URL=postgres://noctis_user:password@localhost:5432/noctis_pro
ALLOWED_HOSTS=localhost,127.0.0.1
COLLECTSTATIC=1
EOF
  fi
fi

# Clean up any existing malformed .env file
clean_env

# Generate SECRET_KEY if missing
if ! grep -q '^SECRET_KEY=' .env || grep -q 'your-secret-key' .env; then
  log "Generating Django SECRET_KEY..."
  SECRET=$(python3 -c "
import secrets, string
alphabet = string.ascii_letters + string.digits + '!@#$%^&*(-_=+)'
print(''.join(secrets.choice(alphabet) for _ in range(50)))
")
  set_env SECRET_KEY "$SECRET"
fi

# Generate PostgreSQL password if missing
if ! grep -q '^POSTGRES_PASSWORD=' .env || grep -q 'your-postgres-password' .env; then
  log "Generating PostgreSQL password..."
  PG_PASS=$(python3 -c "
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
")
  set_env POSTGRES_PASSWORD "$PG_PASS"
  
  # Create/update PostgreSQL user and database
  log "Setting up PostgreSQL database..."
  ensure_postgres_running
  # Terminate connections and recreate database and role without DO blocks
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='noctis_pro';" || true
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS noctis_pro;"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "DROP ROLE IF EXISTS noctis_user;" || true
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE noctis_pro;"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE USER noctis_user WITH PASSWORD '${PG_PASS}';"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE noctis_pro TO noctis_user;"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER USER noctis_user CREATEDB;"
fi

# Generate admin password if missing
ADMIN_PASSWORD=""
if ! grep -q '^ADMIN_PASSWORD=' .env || grep -q 'your-admin-password' .env; then
  log "Generating admin user password..."
  ADMIN_PASSWORD=$(python3 -c "
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(16)))
")
  set_env ADMIN_PASSWORD "$ADMIN_PASSWORD"
fi

# Set database URL for PostgreSQL
PG_PASSWORD=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2)
set_env DATABASE_URL "postgres://noctis_user:${PG_PASSWORD}@localhost:5432/noctis_pro"

# Set production defaults
set_env DEBUG False
set_env COLLECTSTATIC 1

# Ensure directories
log "Creating application directories..."
mkdir -p media static staticfiles logs
mkdir -p /var/log/noctis

# Set up Python virtual environment
log "Setting up Python virtual environment..."

# Prefer Python 3.11 for wide binary wheel support
PYTHON_BIN="python3.11"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  log "${PYTHON_BIN} not found. Attempting to install..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || true
  apt-get install -y python3.11 python3.11-venv python3.11-dev || true
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  log "Falling back to system python3"
  PYTHON_BIN="python3"
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  err "No suitable python interpreter found (looked for python3.11 or python3)"
  exit 1
fi

if [[ ! -d .venv ]]; then
  log "Creating Python virtual environment with ${PYTHON_BIN}..."
  "$PYTHON_BIN" -m venv .venv
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
  if ! pip install -r requirements.txt; then
    err "requirements install failed; attempting minimal stack install..."
    pip install django daphne psycopg2-binary redis celery pillow || true
  fi
else
  log "requirements.txt not found, installing basic Django stack..."
  pip install django daphne psycopg2-binary redis celery pillow
fi

# Ensure core Django extras used by the project are present
pip install dj-database-url python-dotenv whitenoise gunicorn djangorestframework django-cors-headers channels channels-redis || true

# Set up Django
export DJANGO_SETTINGS_MODULE=noctis_pro.settings

# Load environment variables
set -a
source .env || true
set +a

log "Running database migrations..."
if ! python manage.py migrate; then
  err "Migration failed. Attempting to reset database..."
  PG_PASSWORD=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2)
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
if [[ -f deploy/noctis-web.service ]]; then
  install -m 0644 deploy/noctis-web.service /etc/systemd/system/noctis-web.service
fi
if [[ -f deploy/noctis-worker.service ]]; then
  install -m 0644 deploy/noctis-worker.service /etc/systemd/system/noctis-worker.service
fi

systemctl daemon-reload
systemctl enable noctis-web.service noctis-worker.service

log "Starting services..."
systemctl restart noctis-worker.service
systemctl restart noctis-web.service

# Install Caddy site config
log "Configuring web server..."
if [[ -f deploy/Caddyfile.native ]] && command -v caddy >/dev/null 2>&1; then
  install -m 0644 deploy/Caddyfile.native /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy
fi

# Set proper ownership
log "Setting file permissions..."
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  log "App user ${APP_USER} not found; defaulting ownership to root:root"
  APP_USER=root
fi
chown -R ${APP_USER}:${APP_USER} "${APP_DIR}"
chmod -R 755 "${APP_DIR}"
chmod 600 "${APP_DIR}/.env"

# Wait for services to start
log "Waiting for services to start..."
sleep 5

# Check service status
log "Checking service status..."
SERVICES_OK=true
for service in noctis-web noctis-worker; do
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

echo "👤 Admin Credentials:"
echo "   Username: ${ADMIN_USER:-admin}"
echo "   Password: ${ADMIN_PASSWORD:-<check .env file>}"
echo "   Email: ${ADMIN_EMAIL:-admin@example.com}"
echo ""

echo "🔧 Service Management:"
echo "   Status: systemctl status noctis-web noctis-worker"
echo "   Logs:   journalctl -u noctis-web -f"
echo "   Restart: systemctl restart noctis-web"
echo ""

echo "📁 Application Directory: ${APP_DIR}"
echo "📄 Configuration File: ${APP_DIR}/.env"
echo ""

# Health check
log "Performing health check..."
sleep 3
if curl -sf http://localhost:8000/health/ >/dev/null 2>&1 || curl -sf http://localhost:8000/ >/dev/null 2>&1; then
  success "✅ Application is responding"
else
  log "⚠️  Application health check failed, but installation completed"
fi

echo "✨ Installation completed successfully!"
echo "Visit your application at the URLs shown above."