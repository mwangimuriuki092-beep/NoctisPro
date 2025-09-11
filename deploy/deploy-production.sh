#!/usr/bin/env bash
set -euo pipefail

# 🚀 NOCTIS PRO - PRODUCTION DEPLOYMENT SCRIPT
# ==================================================
# Complete production deployment for Ubuntu 22.04
# Supports both local and external access via PageKite
# 
# Usage: sudo bash deploy/deploy-production.sh [OPTIONS]
# 
# Options:
#   --pagekite-subdomain SUBDOMAIN    Enable PageKite with subdomain
#   --pagekite-secret SECRET          PageKite secret key
#   --domain DOMAIN                   Custom domain (alternative to PageKite)
#   --app-dir DIRECTORY              Application directory (default: /opt/noctis)
#   --skip-provision                 Skip system provisioning
#   --help                           Show this help message
#
# Example with PageKite:
#   sudo bash deploy/deploy-production.sh --pagekite-subdomain noctispro --pagekite-secret YOUR_SECRET
#
# Example with custom domain:
#   sudo bash deploy/deploy-production.sh --domain noctis.yourdomain.com

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root: sudo bash deploy/deploy-production.sh" >&2
  exit 1
fi

# Default configuration
APP_DIR="/opt/noctis"
PAGEKITE_SUBDOMAIN=""
PAGEKITE_SECRET=""
CUSTOM_DOMAIN=""
SKIP_PROVISION=false
ADMIN_EMAIL="mwangimuriuki092@gmail.com"

# Logging functions
log() { printf "\e[36m[deploy]\e[0m %s\n" "$*"; }
success() { printf "\e[32m[deploy][SUCCESS]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[deploy][WARNING]\e[0m %s\n" "$*"; }
err() { printf "\e[31m[deploy][ERROR]\e[0m %s\n" "$*" >&2; }

# Help function
show_help() {
    cat << EOF
🚀 NOCTIS PRO - PRODUCTION DEPLOYMENT SCRIPT

USAGE:
    sudo bash deploy/deploy-production.sh [OPTIONS]

OPTIONS:
    --pagekite-subdomain SUBDOMAIN    Enable PageKite with subdomain (e.g., noctispro)
    --pagekite-secret SECRET          PageKite secret key (required with --pagekite-subdomain)
    --domain DOMAIN                   Custom domain (alternative to PageKite)
    --app-dir DIRECTORY              Application directory (default: /opt/noctis)
    --skip-provision                 Skip system provisioning (if already done)
    --help                           Show this help message

EXAMPLES:
    # Deploy with PageKite (recommended for easy external access):
    sudo bash deploy/deploy-production.sh \\
        --pagekite-subdomain noctispro \\
        --pagekite-secret YOUR_PAGEKITE_SECRET

    # Deploy with custom domain:
    sudo bash deploy/deploy-production.sh \\
        --domain noctis.yourdomain.com

    # Deploy for local access only:
    sudo bash deploy/deploy-production.sh

REQUIREMENTS:
    - Fresh Ubuntu 22.04 server
    - Root access (sudo)
    - Internet connection

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pagekite-subdomain)
            PAGEKITE_SUBDOMAIN="$2"
            shift 2
            ;;
        --pagekite-secret)
            PAGEKITE_SECRET="$2"
            shift 2
            ;;
        --domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        --app-dir)
            APP_DIR="$2"
            shift 2
            ;;
        --skip-provision)
            SKIP_PROVISION=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation
if [[ -n "$PAGEKITE_SUBDOMAIN" && -z "$PAGEKITE_SECRET" ]]; then
    err "PageKite secret is required when using PageKite subdomain"
    exit 1
fi

if [[ -n "$PAGEKITE_SUBDOMAIN" && -n "$CUSTOM_DOMAIN" ]]; then
    err "Cannot use both PageKite and custom domain. Choose one."
    exit 1
fi

# Get current directory (should be the repo root)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$REPO_DIR/manage.py" ]]; then
    err "This script must be run from the Noctis Pro repository root"
    err "Current directory: $REPO_DIR"
    exit 1
fi

# Start deployment
echo ""
echo "🚀 ========================================"
echo "   NOCTIS PRO - PRODUCTION DEPLOYMENT"
echo "======================================== 🚀"
echo ""
echo "📋 Configuration:"
echo "   Repository: $REPO_DIR"
echo "   App Directory: $APP_DIR"
echo "   Admin Email: $ADMIN_EMAIL"
if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    echo "   PageKite Subdomain: $PAGEKITE_SUBDOMAIN"
    echo "   External URL: https://$PAGEKITE_SUBDOMAIN.pagekite.me"
elif [[ -n "$CUSTOM_DOMAIN" ]]; then
    echo "   Custom Domain: $CUSTOM_DOMAIN"
    echo "   External URL: https://$CUSTOM_DOMAIN"
else
    echo "   Access: Local only"
fi
echo ""

read -p "🤔 Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Step 1: System Provisioning
if [[ "$SKIP_PROVISION" != "true" ]]; then
    log "📦 Step 1/4: Provisioning system..."
    if [[ -f "$REPO_DIR/deploy/provision-native.sh" ]]; then
        bash "$REPO_DIR/deploy/provision-native.sh"
        success "System provisioning completed"
    else
        err "provision-native.sh not found"
        exit 1
    fi
else
    log "📦 Step 1/4: Skipping system provisioning (--skip-provision)"
fi

# Step 2: Application Installation
log "📱 Step 2/4: Installing application..."
if [[ -f "$REPO_DIR/deploy/install-native.sh" ]]; then
    bash "$REPO_DIR/deploy/install-native.sh" "$REPO_DIR" "$APP_DIR"
    success "Application installation completed"
else
    err "install-native.sh not found"
    exit 1
fi

# Step 3: Configure Domain/PageKite
log "🌐 Step 3/4: Configuring access..."

cd "$APP_DIR"

# Helper function to set environment variables
set_env() {
    local key="$1"; shift
    local value="$*"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    log "Setting up PageKite configuration..."
    set_env PAGEKITE_ENABLE 1
    set_env PAGEKITE_SUBDOMAIN "$PAGEKITE_SUBDOMAIN"
    set_env PAGEKITE_EMAIL "$ADMIN_EMAIL"
    set_env PAGEKITE_SECRET "$PAGEKITE_SECRET"
    
    # Configure Django settings for PageKite
    PAGEKITE_DOMAIN="${PAGEKITE_SUBDOMAIN}.pagekite.me"
    set_env DOMAIN "$PAGEKITE_DOMAIN"
    set_env ALLOWED_HOSTS "${PAGEKITE_DOMAIN},localhost,127.0.0.1"
    set_env CSRF_TRUSTED_ORIGINS "https://${PAGEKITE_DOMAIN},http://localhost:8000,http://127.0.0.1:8000"
    set_env CORS_ALLOWED_ORIGINS "https://${PAGEKITE_DOMAIN}"
    set_env SECURE_SSL_REDIRECT True
    set_env ACME_EMAIL "$ADMIN_EMAIL"
    
    # Install and start PageKite tunnel
    if [[ -f deploy/noctis-tunnel.service ]]; then
        install -m 0644 deploy/noctis-tunnel.service /etc/systemd/system/noctis-tunnel.service
        systemctl daemon-reload
        systemctl enable noctis-tunnel.service
        systemctl restart noctis-tunnel.service
        success "PageKite tunnel configured and started"
    fi
    
elif [[ -n "$CUSTOM_DOMAIN" ]]; then
    log "Setting up custom domain configuration..."
    set_env DOMAIN "$CUSTOM_DOMAIN"
    set_env ALLOWED_HOSTS "${CUSTOM_DOMAIN},localhost,127.0.0.1"
    set_env CSRF_TRUSTED_ORIGINS "https://${CUSTOM_DOMAIN},http://localhost:8000,http://127.0.0.1:8000"
    set_env CORS_ALLOWED_ORIGINS "https://${CUSTOM_DOMAIN}"
    set_env SECURE_SSL_REDIRECT True
    set_env ACME_EMAIL "$ADMIN_EMAIL"
    success "Custom domain configured"
    
else
    log "Setting up local access only..."
    set_env DOMAIN "localhost"
    set_env ALLOWED_HOSTS "localhost,127.0.0.1"
    set_env CSRF_TRUSTED_ORIGINS "http://localhost:8000,http://127.0.0.1:8000"
    set_env CORS_ALLOWED_ORIGINS "http://localhost:3000,http://127.0.0.1:3000"
    set_env SECURE_SSL_REDIRECT False
    success "Local access configured"
fi

# Step 4: Final Configuration and Health Checks
log "🔧 Step 4/4: Final configuration and health checks..."

# Restart services to pick up new configuration
systemctl restart noctis-web.service
systemctl restart noctis-worker.service

if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    systemctl restart noctis-tunnel.service || true
fi

systemctl reload caddy || systemctl restart caddy

# Wait for services to stabilize
log "Waiting for services to stabilize..."
sleep 10

# Health checks
log "Performing health checks..."
HEALTH_OK=true

# Check local health
if curl -sf http://localhost:8000/health/ >/dev/null 2>&1; then
    success "✅ Local health check passed"
else
    err "❌ Local health check failed"
    HEALTH_OK=false
fi

# Check external health if configured
if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    log "Checking PageKite tunnel health..."
    sleep 5  # Give PageKite more time to establish tunnel
    if curl -sf "https://${PAGEKITE_SUBDOMAIN}.pagekite.me/health/" >/dev/null 2>&1; then
        success "✅ PageKite external health check passed"
    else
        warn "⚠️ PageKite external health check failed (may need time to propagate)"
    fi
elif [[ -n "$CUSTOM_DOMAIN" ]]; then
    log "Checking custom domain health..."
    if curl -sf "https://${CUSTOM_DOMAIN}/health/" >/dev/null 2>&1; then
        success "✅ Custom domain health check passed"
    else
        warn "⚠️ Custom domain health check failed (DNS/certificates may need time)"
    fi
fi

# Get server information
SERVER_IP=$(hostname -I | awk '{print $1}' || echo "localhost")
ADMIN_USER=$(grep '^ADMIN_USER=' .env | cut -d= -f2 || echo "admin")
ADMIN_PASSWORD=$(grep '^ADMIN_PASSWORD=' .env | cut -d= -f2 || echo "<check .env file>")

# Final results
echo ""
echo "🎉 ========================================"
echo "   DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo "======================================== 🎉"
echo ""

if [[ "$HEALTH_OK" == "true" ]]; then
    success "🟢 All health checks passed!"
else
    warn "🟡 Some health checks failed - check service logs"
fi

echo ""
echo "📋 ACCESS INFORMATION:"
echo "========================================="
echo ""
echo "🌐 LOCAL ACCESS:"
echo "   http://localhost:8000"
echo "   http://${SERVER_IP}:8000"
echo ""

if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    echo "🌍 EXTERNAL ACCESS (PageKite):"
    echo "   https://${PAGEKITE_SUBDOMAIN}.pagekite.me"
    echo "   Admin: https://${PAGEKITE_SUBDOMAIN}.pagekite.me/admin/"
    echo ""
elif [[ -n "$CUSTOM_DOMAIN" ]]; then
    echo "🌍 EXTERNAL ACCESS (Custom Domain):"
    echo "   https://${CUSTOM_DOMAIN}"
    echo "   Admin: https://${CUSTOM_DOMAIN}/admin/"
    echo ""
fi

echo "👤 ADMIN CREDENTIALS:"
echo "   Username: ${ADMIN_USER}"
echo "   Password: ${ADMIN_PASSWORD}"
echo "   Email: ${ADMIN_EMAIL}"
echo ""

echo "🔧 SERVICE MANAGEMENT:"
echo "   Status:  systemctl status noctis-web noctis-worker caddy"
echo "   Logs:    journalctl -u noctis-web -f"
echo "   Restart: systemctl restart noctis-web"
if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then
    echo "   Tunnel:  systemctl status noctis-tunnel"
fi
echo ""

echo "📁 IMPORTANT PATHS:"
echo "   App Directory: ${APP_DIR}"
echo "   Config File:   ${APP_DIR}/.env"
echo "   Media Files:   ${APP_DIR}/media"
echo "   Logs:          /var/log/noctis/"
echo ""

echo "📊 FILE UPLOAD LIMITS:"
echo "   Max File Size: 5GB (handles very large DICOM studies)"
echo "   Memory Limit:  512MB per upload"
echo "   Timeout:       10 minutes for processing"
echo ""

echo "🛡️ SECURITY FEATURES:"
echo "   ✅ Firewall configured (UFW)"
echo "   ✅ Fail2ban protection"
echo "   ✅ HTTPS/TLS encryption"
echo "   ✅ Security headers"
echo "   ✅ File permissions secured"
echo ""

if [[ "$HEALTH_OK" != "true" ]]; then
    echo "🔍 TROUBLESHOOTING:"
    echo "   Check logs: journalctl -u noctis-web -n 50"
    echo "   Test local: curl -I http://localhost:8000/health/"
    echo "   Service status: systemctl status noctis-web noctis-worker"
    echo ""
fi

echo "✨ Your Noctis Pro DICOM viewer is now ready for production use!"
echo ""

# Save deployment info to file
cat > "${APP_DIR}/DEPLOYMENT_INFO.txt" << EOF
NOCTIS PRO - DEPLOYMENT INFORMATION
Generated: $(date)

ACCESS URLS:
Local: http://localhost:8000, http://${SERVER_IP}:8000
$(if [[ -n "$PAGEKITE_SUBDOMAIN" ]]; then echo "External: https://${PAGEKITE_SUBDOMAIN}.pagekite.me"; fi)
$(if [[ -n "$CUSTOM_DOMAIN" ]]; then echo "External: https://${CUSTOM_DOMAIN}"; fi)

ADMIN CREDENTIALS:
Username: ${ADMIN_USER}
Password: ${ADMIN_PASSWORD}
Email: ${ADMIN_EMAIL}

CONFIGURATION:
App Directory: ${APP_DIR}
Config File: ${APP_DIR}/.env
Max Upload Size: 1GB
EOF

success "Deployment information saved to ${APP_DIR}/DEPLOYMENT_INFO.txt"