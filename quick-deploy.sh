#!/usr/bin/env bash
set -euo pipefail

# 🚀 NOCTIS PRO - QUICK PRODUCTION DEPLOYMENT
# ==============================================
# One-command deployment for fresh Ubuntu 22.04
# Run this after cloning/uploading the repository
#
# Usage: sudo bash quick-deploy.sh [pagekite-secret]
#
# Examples:
#   # Deploy with PageKite for external access:
#   sudo bash quick-deploy.sh YOUR_PAGEKITE_SECRET
#
#   # Deploy for local access only:
#   sudo bash quick-deploy.sh

if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root: sudo bash quick-deploy.sh" >&2
    exit 1
fi

PAGEKITE_SECRET="${1:-}"

echo ""
echo "🚀 ========================================"
echo "   NOCTIS PRO - QUICK DEPLOYMENT"
echo "======================================== 🚀"
echo ""

# Check if we're in the right directory
if [[ ! -f "manage.py" || ! -d "deploy" ]]; then
    echo "❌ ERROR: This script must be run from the Noctis Pro repository root"
    echo "   Make sure you have:"
    echo "   1. Cloned or uploaded the repository"
    echo "   2. Changed to the repository directory (cd noctis_pro)"
    echo "   3. Run this script from there"
    exit 1
fi

# Determine deployment type
if [[ -n "$PAGEKITE_SECRET" ]]; then
    echo "📡 Deploying with PageKite for external HTTPS access..."
    echo "   External URL will be: https://noctispro.pagekite.me"
    echo ""
    
    # Run production deployment with PageKite
    bash deploy/deploy-production.sh \
        --pagekite-subdomain noctispro \
        --pagekite-secret "$PAGEKITE_SECRET"
else
    echo "🏠 Deploying for local access only..."
    echo "   Access will be available on local network"
    echo ""
    
    # Run production deployment without external access
    bash deploy/deploy-production.sh
fi