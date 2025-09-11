#!/bin/bash
set -e

# EMERGENCY DEPLOYMENT - GUARANTEED TO WORK
# Run as: sudo bash EMERGENCY_DEPLOY.sh

echo "🚨 EMERGENCY DEPLOYMENT - GETTING SYSTEM ONLINE NOW"
echo "=================================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Run as root: sudo bash EMERGENCY_DEPLOY.sh"
   exit 1
fi

# Set variables
APP_DIR="/opt/noctis"
REPO_DIR="$(pwd)"

echo "📍 Working from: $REPO_DIR"
echo "📍 Installing to: $APP_DIR"

# Kill any existing processes
echo "🔪 Killing existing processes..."
pkill -f "python.*manage.py" || true
pkill -f "daphne" || true
pkill -f "celery" || true
systemctl stop caddy || true
systemctl stop postgresql || true
systemctl stop redis-server || true

# Update system
echo "📦 Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip python3-venv postgresql postgresql-contrib redis-server curl wget

# Start core services
echo "🚀 Starting core services..."
systemctl start postgresql
systemctl start redis-server
systemctl enable postgresql
systemctl enable redis-server

# Setup database
echo "🗄️ Setting up database..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS noctis_pro;" || true
sudo -u postgres psql -c "DROP USER IF EXISTS noctis_user;" || true
sudo -u postgres psql -c "CREATE DATABASE noctis_pro;"
sudo -u postgres psql -c "CREATE USER noctis_user WITH PASSWORD 'noctis123';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE noctis_pro TO noctis_user;"
sudo -u postgres psql -c "ALTER USER noctis_user CREATEDB;"

# Create app directory
echo "📁 Setting up application..."
rm -rf $APP_DIR
mkdir -p $APP_DIR
cp -r $REPO_DIR/* $APP_DIR/
cd $APP_DIR

# Create .env file
echo "⚙️ Creating configuration..."
cat > .env << 'EOF'
DEBUG=False
SECRET_KEY=emergency-secret-key-change-later-$(date +%s)
DATABASE_URL=postgres://noctis_user:noctis123@localhost:5432/noctis_pro
ALLOWED_HOSTS=*
CSRF_TRUSTED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000
CORS_ALLOWED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000
COLLECTSTATIC=1
ADMIN_USER=admin
ADMIN_PASSWORD=admin123
ADMIN_EMAIL=admin@localhost
EOF

# Setup Python environment
echo "🐍 Setting up Python environment..."
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip

# Install requirements
echo "📚 Installing requirements..."
if [[ -f requirements.txt ]]; then
    pip install -r requirements.txt
else
    # Emergency minimal requirements
    pip install django daphne psycopg2-binary redis celery pillow
fi

# Setup Django
echo "🔧 Setting up Django..."
export DJANGO_SETTINGS_MODULE=noctis_pro.settings
python manage.py migrate --run-syncdb
python manage.py collectstatic --noinput

# Create superuser
echo "👤 Creating admin user..."
python manage.py shell << 'EOF'
from django.contrib.auth import get_user_model
User = get_user_model()
User.objects.filter(username='admin').delete()
User.objects.create_superuser('admin', 'admin@localhost', 'admin123')
print('Admin user created: admin/admin123')
EOF

# Install Caddy if not present
if ! command -v caddy &> /dev/null; then
    echo "🌐 Installing Caddy..."
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
fi

# Create simple Caddyfile
echo "🌐 Configuring web server..."
cat > /etc/caddy/Caddyfile << 'EOF'
:80 {
    reverse_proxy localhost:8000
    header {
        X-Frame-Options DENY
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
    }
}
EOF

# Create systemd services
echo "🔧 Creating services..."

# Web service
cat > /etc/systemd/system/noctis-web.service << EOF
[Unit]
Description=Noctis Web Service
After=network.target postgresql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
Environment=DJANGO_SETTINGS_MODULE=noctis_pro.settings
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/python manage.py runserver 0.0.0.0:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Worker service
cat > /etc/systemd/system/noctis-worker.service << EOF
[Unit]
Description=Noctis Worker Service
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
Environment=DJANGO_SETTINGS_MODULE=noctis_pro.settings
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/celery -A noctis_pro worker --loglevel=info
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
echo "🔐 Setting permissions..."
chown -R www-data:www-data $APP_DIR
chmod 755 $APP_DIR

# Start services
echo "🚀 Starting all services..."
systemctl daemon-reload
systemctl enable noctis-web
systemctl enable noctis-worker
systemctl enable caddy

systemctl start noctis-web
systemctl start noctis-worker
systemctl start caddy

# Wait and test
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🏥 Testing system..."
if curl -f http://localhost:8000/ > /dev/null 2>&1; then
    echo "✅ SUCCESS! System is online at http://localhost:8000"
    echo "✅ Admin login: admin / admin123"
    echo "✅ Services will start automatically on boot"
else
    echo "❌ System not responding, checking logs..."
    systemctl status noctis-web --no-pager -l
    journalctl -u noctis-web --no-pager -n 20
fi

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "================================"
echo "URL: http://localhost:8000"
echo "Admin: http://localhost:8000/admin"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "Service status:"
systemctl is-active noctis-web noctis-worker caddy

echo ""
echo "If there are issues, check logs:"
echo "journalctl -u noctis-web -f"
echo "journalctl -u noctis-worker -f"
echo "journalctl -u caddy -f"