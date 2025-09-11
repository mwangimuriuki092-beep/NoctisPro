#!/bin/bash
set -euo pipefail

# Complete NoctisPro installation with PageKite
# Usage: sudo bash complete_installation.sh

echo "🚀 Completing NoctisPro Installation with PageKite..."

# Set variables
REPO_DIR="/home/noctispacs/NoctisPro"
PAGEKITE_SUBDOMAIN="noctispro"
PAGEKITE_SECRET="zzkfzcx46xxx49d87xkxf6fc87c28az8"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash complete_installation.sh" >&2
  exit 1
fi

echo "📦 Step 1: Running fixed native installation..."
cd "$REPO_DIR"
bash deploy/install-native.sh "$REPO_DIR"

echo "🌐 Step 2: Setting up PageKite tunnel..."
bash deploy/setup-pagekite.sh \
  --subdomain "$PAGEKITE_SUBDOMAIN" \
  --email "mwangimuriuki092@gmail.com" \
  --secret "$PAGEKITE_SECRET"

echo "🔍 Step 3: Checking services status..."
echo "Noctis Web Service:"
systemctl status noctis-web.service --no-pager || echo "Service not running"

echo "Noctis Worker Service:"
systemctl status noctis-worker.service --no-pager || echo "Service not running"

echo "PageKite Tunnel Service:"
systemctl status noctis-tunnel.service --no-pager || echo "Service not running"

echo "Caddy Web Server:"
systemctl status caddy.service --no-pager || echo "Service not running"

echo ""
echo "🎉 Installation completed!"
echo "🌍 Your application should be available at: https://${PAGEKITE_SUBDOMAIN}.pagekite.me"
echo "🏠 Local access: http://localhost:8000"
echo ""
echo "📋 To check logs:"
echo "   Web service: journalctl -u noctis-web.service -f"
echo "   PageKite: journalctl -u noctis-tunnel.service -f"