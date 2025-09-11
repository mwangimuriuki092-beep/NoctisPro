#!/usr/bin/env bash
set -euo pipefail

# Native (non-Docker) provisioning for Ubuntu/Debian
# - Installs Python, Redis, PostgreSQL, Caddy, UFW basics
# - Enables and starts services

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/provision-native.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

apt-get install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https \
  software-properties-common ufw \
  python3 python3-venv python3-pip build-essential libpq-dev \
  redis-server postgresql postgresql-contrib

systemctl enable --now redis-server
systemctl enable --now postgresql

# Install Caddy from official repo
if ! command -v caddy >/dev/null 2>&1; then
  echo "Installing Caddy"
  apt-get install -y debian-keyring debian-archive-keyring
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

systemctl enable --now caddy

# Firewall: allow SSH, HTTP, HTTPS
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  yes | ufw enable || true
fi

echo "Provisioning complete. Next: run deploy/install-native.sh /path/to/repo"

