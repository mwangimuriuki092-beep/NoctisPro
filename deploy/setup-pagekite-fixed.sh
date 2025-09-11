#!/usr/bin/env bash
set -euo pipefail

# FIXED PageKite setup script for Noctis Pro
# Usage: sudo bash deploy/setup-pagekite-fixed.sh --subdomain noctispro --email you@example.com --secret YOUR_SECRET [--app-dir /opt/noctis]

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/setup-pagekite-fixed.sh ..." >&2
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
  echo "  sudo bash deploy/setup-pagekite-fixed.sh --subdomain noctispro --email you@example.com --secret XXXXX" >&2
  exit 1
fi

log() { printf "[pagekite] %s\n" "$*"; }
err() { printf "[pagekite][ERROR] %s\n" "$*" >&2; }
success() { printf "[pagekite][SUCCESS] %s\n" "$*"; }

log "Setting up PageKite tunnel for ${SUBDOMAIN}.pagekite.me"

# Ensure PageKite is installed
if ! command -v pagekite >/dev/null 2>&1; then
  log "Installing PageKite..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y pagekite
fi

# Ensure app directory exists
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
    [[ -s .env && $(tail -c1 .env | wc -l) -eq 0 ]] && echo "" >> .env
    echo "${key}=${value}" >> .env
  fi
}

log "Configuring PageKite settings in .env..."
set_env PAGEKITE_ENABLE 1
set_env PAGEKITE_SUBDOMAIN "$SUBDOMAIN"
set_env PAGEKITE_EMAIL "$EMAIL"
set_env PAGEKITE_SECRET "$SECRET"

# Django host/security for PageKite URL
DOMAIN_HOST="${SUBDOMAIN}.pagekite.me"
log "Setting up Django security for ${DOMAIN_HOST}..."

set_env ALLOWED_HOSTS "${DOMAIN_HOST},localhost,127.0.0.1"
set_env CSRF_TRUSTED_ORIGINS "https://${DOMAIN_HOST},http://localhost:8000,http://127.0.0.1:8000"
set_env CORS_ALLOWED_ORIGINS "https://${DOMAIN_HOST}"
set_env SECURE_SSL_REDIRECT True

# Create PageKite service file
log "Creating PageKite systemd service..."
cat > /etc/systemd/system/noctis-tunnel.service << EOF
[Unit]
Description=Noctis PageKite Tunnel
After=network.target noctis-web.service
Wants=noctis-web.service

[Service]
Type=simple
EnvironmentFile=${APP_DIR}/.env
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/pagekite --clean --defaults --service_on=${SUBDOMAIN}.pagekite.me:443 https:127.0.0.1:8000 ${EMAIL} ${SECRET}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start tunnel service
log "Starting PageKite tunnel service..."
systemctl daemon-reload
systemctl enable noctis-tunnel.service
systemctl restart noctis-tunnel.service

# Restart web service to pick up env changes
if systemctl is-active --quiet noctis-web.service; then
  log "Restarting web service to apply new settings..."
  systemctl restart noctis-web.service
fi

# Wait a moment for service to start
sleep 3

# Check service status
if systemctl is-active --quiet noctis-tunnel.service; then
  success "✅ PageKite tunnel is running!"
else
  err "❌ PageKite tunnel failed to start"
  log "Check status with: systemctl status noctis-tunnel.service"
  log "Check logs with: journalctl -u noctis-tunnel.service -f"
fi

echo ""
echo "🌍 ====================================="
echo "   PAGEKITE TUNNEL CONFIGURED"
echo "===================================== 🌍"
echo ""
echo "🌐 External URL: https://${DOMAIN_HOST}"
echo "🏠 Local URL: http://localhost:8000"
echo ""
echo "🔧 Service Management:"
echo "   Status: systemctl status noctis-tunnel.service"
echo "   Logs:   journalctl -u noctis-tunnel.service -f"
echo "   Restart: systemctl restart noctis-tunnel.service"
echo ""
echo "⚠️  Note: It may take a few minutes for the tunnel to become active."
echo "   Test the external URL in a few minutes."
echo ""
success "PageKite setup completed!"