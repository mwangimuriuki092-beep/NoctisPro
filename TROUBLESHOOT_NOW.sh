#!/bin/bash

# IMMEDIATE TROUBLESHOOTING - RUN THIS IF SYSTEM IS DOWN

echo "🚨 EMERGENCY TROUBLESHOOTING"
echo "============================"

# Check what's running
echo "📊 Current system status:"
echo "-------------------------"

# Check if services exist and their status
for service in noctis-web noctis-worker caddy postgresql redis-server; do
    if systemctl list-unit-files | grep -q "$service"; then
        status=$(systemctl is-active $service 2>/dev/null || echo "not-found")
        echo "$service: $status"
        if [[ "$status" != "active" ]]; then
            echo "  ❌ FAILED - Last 5 log lines:"
            journalctl -u $service --no-pager -n 5 | sed 's/^/    /'
        fi
    else
        echo "$service: not-installed"
    fi
done

echo ""
echo "🌐 Network tests:"
echo "----------------"

# Test local connectivity
if curl -s http://localhost:8000/ > /dev/null; then
    echo "✅ App responding on localhost:8000"
else
    echo "❌ App NOT responding on localhost:8000"
    
    # Check if port 8000 is in use
    if netstat -tlnp | grep -q ":8000"; then
        echo "   Port 8000 is in use by:"
        netstat -tlnp | grep ":8000"
    else
        echo "   Port 8000 is not in use"
    fi
fi

# Check port 80
if curl -s http://localhost:80/ > /dev/null; then
    echo "✅ Web server responding on port 80"
else
    echo "❌ Web server NOT responding on port 80"
fi

echo ""
echo "🔧 QUICK FIXES:"
echo "=============="

echo "1. RESTART ALL SERVICES:"
echo "   sudo systemctl restart noctis-web noctis-worker caddy"
echo ""

echo "2. CHECK LOGS:"
echo "   sudo journalctl -u noctis-web -f"
echo ""

echo "3. MANUAL START (if services fail):"
echo "   cd /opt/noctis"
echo "   source .venv/bin/activate"
echo "   python manage.py runserver 0.0.0.0:8000"
echo ""

echo "4. RESET DATABASE (if corrupted):"
echo "   sudo -u postgres psql -c \"DROP DATABASE noctis_pro; CREATE DATABASE noctis_pro;\""
echo "   cd /opt/noctis && source .venv/bin/activate"
echo "   python manage.py migrate"
echo ""

echo "5. NUCLEAR OPTION - REDEPLOY:"
echo "   sudo bash EMERGENCY_DEPLOY.sh"
echo ""

# Show current processes
echo "📈 Current Python processes:"
ps aux | grep python | grep -v grep || echo "No Python processes running"

echo ""
echo "💾 Disk space:"
df -h / | tail -1

echo ""
echo "🧠 Memory usage:"
free -h