#!/usr/bin/env bash
set -euo pipefail

# Native (non-Docker) provisioning for Ubuntu/Debian
# - Installs Python, Redis, PostgreSQL, Caddy, UFW basics
# - Enables and starts services
# - Enhanced error handling and logging

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/provision-native.sh" >&2
  exit 1
fi

log() { printf "[provision] %s\n" "$*"; }
err() { printf "[provision][ERROR] %s\n" "$*" >&2; }

export DEBIAN_FRONTEND=noninteractive

log "Starting system provisioning for Ubuntu 22.04..."

# Check system requirements for 5GB file handling
TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
AVAILABLE_DISK=$(df / | awk 'NR==2{printf "%.0f", $4/1024/1024}')

log "System Requirements Check:"
log "  RAM: ${TOTAL_RAM}GB (Recommended: 8GB+ for 5GB file processing)"
log "  Disk Space: ${AVAILABLE_DISK}GB available"

if [[ $TOTAL_RAM -lt 4 ]]; then
    warn "⚠️  Low RAM detected (${TOTAL_RAM}GB). Recommended: 8GB+ for optimal 5GB file processing"
fi

if [[ $AVAILABLE_DISK -lt 50 ]]; then
    warn "⚠️  Low disk space (${AVAILABLE_DISK}GB). Recommended: 100GB+ for medical imaging storage"
fi

log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

log "Installing base system dependencies..."
apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common ufw wget rsync \
  python3 python3-venv python3-pip build-essential libpq-dev \
  redis-server postgresql postgresql-contrib \
  fail2ban logrotate \
  htop tree vim nano

# Install PageKite (handle if not available in repos)
log "Installing PageKite..."
if ! apt-get install -y pagekite; then
  log "PageKite not available in repos, installing from source..."
  wget -O /tmp/pagekite.py https://pagekite.net/pk/pagekite.py
  install -m 755 /tmp/pagekite.py /usr/local/bin/pagekite
  chmod +x /usr/local/bin/pagekite
fi

log "Enabling and starting core services..."
systemctl enable --now redis-server
systemctl enable --now postgresql
systemctl enable --now fail2ban

# Configure fail2ban
log "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[caddy-auth]
enabled = true
port = http,https
logpath = /var/log/caddy/*.log
maxretry = 3
EOF

systemctl restart fail2ban

# Install Caddy from official repo
if ! command -v caddy >/dev/null 2>&1; then
  log "Installing Caddy web server..."
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null || true
  apt-get update -y
  if ! apt-get install -y caddy; then
    log "Failed to install Caddy from repo, installing from GitHub..."
    curl -L "https://github.com/caddyserver/caddy/releases/latest/download/caddy_linux_amd64.tar.gz" -o /tmp/caddy.tar.gz
    tar -xzf /tmp/caddy.tar.gz -C /tmp
    install -m 755 /tmp/caddy /usr/bin/caddy
    
    # Create systemd service for manual install
    cat > /etc/systemd/system/caddy.service << 'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    # Create caddy user
    useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy || true
    mkdir -p /etc/caddy
    chown caddy:caddy /etc/caddy
  fi
else
  log "Caddy already installed"
fi

systemctl daemon-reload
systemctl enable --now caddy || log "Caddy service enable failed, will configure later"

# Configure PostgreSQL
log "Configuring PostgreSQL..."
sudo -u postgres createdb noctis_pro || log "Database noctis_pro already exists"
sudo -u postgres createuser noctis_user || log "User noctis_user already exists"
sudo -u postgres psql -c "ALTER USER noctis_user CREATEDB;" || true

# Configure log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/noctis << 'EOF'
/opt/noctis/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload noctis-web || true
        systemctl reload noctis-worker || true
    endscript
}
EOF

# Create log directory
mkdir -p /opt/noctis/logs
chown www-data:www-data /opt/noctis/logs

# Firewall: allow SSH, HTTP, HTTPS
log "Configuring firewall..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  yes | ufw enable || true
fi

# System optimization
log "Applying system optimizations..."
# Increase file limits for web server
cat >> /etc/security/limits.conf << 'EOF'
www-data soft nofile 65536
www-data hard nofile 65536
EOF

# Configure kernel parameters
cat >> /etc/sysctl.conf << 'EOF'
# Network optimizations
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 5000
EOF

sysctl -p

log "✅ Provisioning complete!"
log "System is ready for application deployment."
log "Next step: run deploy/install-native.sh /path/to/repo"

