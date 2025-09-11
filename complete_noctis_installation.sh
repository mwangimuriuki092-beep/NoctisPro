#!/bin/bash
set -euo pipefail

# Complete NoctisPro Installation with PageKite - PROPERLY DONE
# Usage: sudo bash complete_noctis_installation.sh

echo ""
echo "🚀 ========================================"
echo "   COMPLETE NOCTIS PRO INSTALLATION"
echo "======================================== 🚀"
echo ""

# Configuration
REPO_DIR="$(pwd)"
PAGEKITE_SUBDOMAIN="noctispro"
PAGEKITE_SECRET="zzkfzcx46xxx49d87xkxf6fc87c28az8"
PAGEKITE_EMAIL="mwangimuriuki092@gmail.com"

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root: sudo bash complete_noctis_installation.sh" >&2
  exit 1
fi

if [[ ! -d "$REPO_DIR" ]]; then
  echo "❌ Repository directory not found: $REPO_DIR" >&2
  echo "Please run this script from the NoctisPro directory" >&2
  exit 1
fi

log() { printf "[main] %s\n" "$*"; }
err() { printf "[main][ERROR] %s\n" "$*" >&2; }
success() { printf "[main][SUCCESS] %s\n" "$*"; }

echo "📋 Configuration:"
echo "   Repository: $REPO_DIR"
echo "   App Directory: /opt/noctis"
echo "   PageKite Subdomain: $PAGEKITE_SUBDOMAIN"
echo "   PageKite Email: $PAGEKITE_EMAIL"
echo "   External URL: https://${PAGEKITE_SUBDOMAIN}.pagekite.me"
echo ""

read -p "🤔 Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
log "📦 Step 1/3: Installing NoctisPro application..."
cd "$REPO_DIR"

# Make scripts executable
chmod +x deploy/install-native-fixed.sh
chmod +x deploy/setup-pagekite-fixed.sh

# Run the fixed installation script
if bash deploy/install-native-fixed.sh "$REPO_DIR"; then
    success "✅ NoctisPro installation completed"
else
    err "❌ NoctisPro installation failed"
    exit 1
fi

echo ""
log "🌐 Step 2/3: Setting up PageKite tunnel..."
if bash deploy/setup-pagekite-fixed.sh \
    --subdomain "$PAGEKITE_SUBDOMAIN" \
    --email "$PAGEKITE_EMAIL" \
    --secret "$PAGEKITE_SECRET"; then
    success "✅ PageKite tunnel setup completed"
else
    err "❌ PageKite setup failed"
fi

echo ""
log "🔍 Step 3/3: Verifying system status..."

# Check all services
echo "Service Status:"
echo "---------------"

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service: RUNNING"
        return 0
    else
        echo "❌ $service: NOT RUNNING"
        return 1
    fi
}

SERVICES_OK=true
check_service "noctis-web.service" || SERVICES_OK=false
check_service "noctis-worker.service" || SERVICES_OK=false
check_service "noctis-tunnel.service" || SERVICES_OK=false
check_service "postgresql.service" || SERVICES_OK=false
check_service "redis-server.service" || SERVICES_OK=false

if command -v caddy >/dev/null 2>&1; then
    check_service "caddy.service" || echo "⚠️  caddy.service: Optional service"
fi

echo ""

# Test local connectivity
log "Testing local connectivity..."
sleep 5
if curl -sf http://localhost:8000/ >/dev/null 2>&1; then
    success "✅ Local application is responding"
else
    echo "⚠️  Local application test failed (may need more time to start)"
fi

# Get admin credentials
if [[ -f /opt/noctis/.env ]]; then
    ADMIN_USER=$(grep '^ADMIN_USER=' /opt/noctis/.env | cut -d= -f2 2>/dev/null || echo "admin")
    ADMIN_PASSWORD=$(grep '^ADMIN_PASSWORD=' /opt/noctis/.env | cut -d= -f2 2>/dev/null || echo "check .env file")
    ADMIN_EMAIL=$(grep '^ADMIN_EMAIL=' /opt/noctis/.env | cut -d= -f2 2>/dev/null || echo "admin@example.com")
else
    ADMIN_USER="admin"
    ADMIN_PASSWORD="check /opt/noctis/.env"
    ADMIN_EMAIL="admin@example.com"
fi

echo ""
echo "🎉 ========================================"
echo "   INSTALLATION COMPLETED!"
echo "======================================== 🎉"
echo ""

if [[ "$SERVICES_OK" == "true" ]]; then
    success "✅ All core services are running!"
else
    echo "⚠️  Some services need attention. Check the status above."
fi

echo ""
echo "🌐 ACCESS INFORMATION:"
echo "----------------------------------------"
echo "🌍 External Access (PageKite):"
echo "   https://${PAGEKITE_SUBDOMAIN}.pagekite.me"
echo ""
echo "🏠 Local Access:"
echo "   http://localhost:8000"
echo "   http://$(hostname -I | awk '{print $1}'):8000"
echo ""
echo "👤 Admin Login:"
echo "   Username: $ADMIN_USER"
echo "   Password: $ADMIN_PASSWORD"
echo "   Email: $ADMIN_EMAIL"
echo ""
echo "🔧 Service Management:"
echo "   View all status: systemctl status noctis-web noctis-worker noctis-tunnel"
echo "   Web logs: journalctl -u noctis-web.service -f"
echo "   Tunnel logs: journalctl -u noctis-tunnel.service -f"
echo "   Restart web: systemctl restart noctis-web.service"
echo "   Restart tunnel: systemctl restart noctis-tunnel.service"
echo ""
echo "📁 Important Files:"
echo "   App directory: /opt/noctis"
echo "   Configuration: /opt/noctis/.env"
echo "   Logs: /var/log/noctis/"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   • PageKite tunnel may take 2-3 minutes to become fully active"
echo "   • Test the external URL after a few minutes"
echo "   • Save your admin credentials in a secure location"
echo "   • The system is now ready for medical imaging workflows"
echo ""
success "🎯 NoctisPro is now online and accessible!"
echo "Visit https://${PAGEKITE_SUBDOMAIN}.pagekite.me to access your system"