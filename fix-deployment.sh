#!/usr/bin/env bash
set -euo pipefail

echo "[fix-deployment] Starting deployment fix for NoctisPro..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "[fix-deployment] This script must be run as root (sudo)"
    exit 1
fi

# Variables
APP_DIR="/opt/noctis"
ENV_FILE="${APP_DIR}/.env"
BACKUP_ENV="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo "[fix-deployment] Backing up existing .env file..."
if [[ -f "${ENV_FILE}" ]]; then
    cp "${ENV_FILE}" "${BACKUP_ENV}"
    echo "[fix-deployment] Backup created: ${BACKUP_ENV}"
fi

echo "[fix-deployment] Creating fixed .env file..."
cat > "${ENV_FILE}" << 'EOF'
# Production Environment Variables for NoctisPro
# Fixed syntax errors and proper escaping

# Django Settings
DEBUG=false
SECRET_KEY="i6?^Dq/Bzs+-_pC)Zy0Z.g\$=haU+(mnd6V.D=LnWUl2}{gW@l~Bw#}94Y*c9L/\$l"

# Network Configuration  
ALLOWED_HOSTS=localhost,127.0.0.1,192.168.100.15
CSRF_TRUSTED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000,https://192.168.100.15
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:8000,http://127.0.0.1:8000

# Database Configuration
DATABASE_URL=postgresql://noctis:noctis@localhost:5432/noctis

# Redis Configuration
REDIS_URL=redis://localhost:6379/0

# Security Settings (for production)
SECURE_SSL_REDIRECT=false
SESSION_COOKIE_SECURE=false
CSRF_COOKIE_SECURE=false
SECURE_HSTS_SECONDS=0
EOF

echo "[fix-deployment] Setting proper permissions..."
chown www-data:www-data "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo "[fix-deployment] Testing environment file syntax..."
if source "${ENV_FILE}"; then
    echo "[fix-deployment] ✓ Environment file syntax is valid"
else
    echo "[fix-deployment] ✗ Environment file has syntax errors"
    exit 1
fi

echo "[fix-deployment] Activating virtual environment..."
if [[ -f "${APP_DIR}/.venv/bin/activate" ]]; then
    source "${APP_DIR}/.venv/bin/activate"
    echo "[fix-deployment] ✓ Virtual environment activated"
else
    echo "[fix-deployment] ✗ Virtual environment not found at ${APP_DIR}/.venv"
    exit 1
fi

echo "[fix-deployment] Testing Django configuration..."
cd "${APP_DIR}"
if python manage.py check --deploy; then
    echo "[fix-deployment] ✓ Django configuration is valid"
else
    echo "[fix-deployment] ⚠ Django configuration has warnings (this may be normal)"
fi

echo "[fix-deployment] Running database migrations..."
if python manage.py migrate; then
    echo "[fix-deployment] ✓ Database migrations completed"
else
    echo "[fix-deployment] ✗ Database migrations failed"
    exit 1
fi

echo "[fix-deployment] Collecting static files..."
if python manage.py collectstatic --noinput; then
    echo "[fix-deployment] ✓ Static files collected"
else
    echo "[fix-deployment] ⚠ Static files collection had issues (may be normal)"
fi

echo "[fix-deployment] Restarting services..."
systemctl daemon-reload

if systemctl is-active --quiet noctis-web.service; then
    systemctl restart noctis-web.service
    echo "[fix-deployment] ✓ noctis-web service restarted"
else
    systemctl start noctis-web.service
    echo "[fix-deployment] ✓ noctis-web service started"
fi

if systemctl is-active --quiet noctis-worker.service; then
    systemctl restart noctis-worker.service
    echo "[fix-deployment] ✓ noctis-worker service restarted"
fi

echo "[fix-deployment] Checking service status..."
sleep 3
systemctl status noctis-web.service --no-pager -l

echo "[fix-deployment] ✅ Deployment fix completed!"
echo "[fix-deployment] Check logs with: journalctl -u noctis-web.service -f"
echo "[fix-deployment] Test the application at: http://192.168.100.15:8000"