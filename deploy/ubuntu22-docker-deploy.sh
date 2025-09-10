#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo bash deploy/ubuntu22-docker-deploy.sh \
#     --domain your-domain.com \
#     --email admin@your-domain.com \
#     --project-dir /opt/noctis_pro \
#     [--compose-file docker-compose.yml]

DOMAIN=""
ACME_EMAIL=""
PROJECT_DIR="/opt/noctis_pro"
COMPOSE_FILE="docker-compose.yml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"; shift 2;;
    --email|--acme-email)
      ACME_EMAIL="$2"; shift 2;;
    --project-dir)
      PROJECT_DIR="$2"; shift 2;;
    --compose-file)
      COMPOSE_FILE="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$DOMAIN" || -z "$ACME_EMAIL" ]]; then
  echo "ERROR: --domain and --email are required"
  exit 1
fi

echo "==> Updating apt and installing prerequisites"
apt-get update -y
apt-get install -y ca-certificates curl gnupg ufw

echo "==> Installing Docker Engine"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "==> Allowing firewall ports 80/443 (if ufw is active)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
fi

echo "==> Preparing project directory at ${PROJECT_DIR}"
mkdir -p "$PROJECT_DIR"

if [[ ! -f "$PROJECT_DIR/${COMPOSE_FILE}" ]]; then
  echo "Copying project files into ${PROJECT_DIR} (first deployment)"
  rsync -a --exclude '.venv' --exclude '.git' --exclude 'node_modules' ./ "$PROJECT_DIR"/
fi

cd "$PROJECT_DIR"

echo "==> Creating .env if missing"
if [[ ! -f .env ]]; then
  cp .env.example .env
fi

echo "==> Writing environment values"
sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" .env || echo "DOMAIN=${DOMAIN}" >> .env
sed -i "s/^ACME_EMAIL=.*/ACME_EMAIL=${ACME_EMAIL}/" .env || echo "ACME_EMAIL=${ACME_EMAIL}" >> .env
sed -i "s/^ALLOWED_HOSTS=.*/ALLOWED_HOSTS=${DOMAIN},localhost,127.0.0.1/" .env || echo "ALLOWED_HOSTS=${DOMAIN},localhost,127.0.0.1" >> .env
sed -i "s/^CSRF_TRUSTED_ORIGINS=.*/CSRF_TRUSTED_ORIGINS=https:\/\/${DOMAIN},http:\/\/localhost:8000,http:\/\/127.0.0.1:8000/" .env || true
sed -i "s/^CORS_ALLOWED_ORIGINS=.*/CORS_ALLOWED_ORIGINS=https:\/\/${DOMAIN},http:\/\/localhost:3000,http:\/\/127.0.0.1:3000/" .env || true
sed -i "s/^SECURE_SSL_REDIRECT=.*/SECURE_SSL_REDIRECT=True/" .env || echo "SECURE_SSL_REDIRECT=True" >> .env

echo "==> Verifying DNS resolves to this host"
HOST_IP=$(curl -fsS ifconfig.me || curl -fsS https://ipinfo.io/ip || echo "")
if [[ -n "$HOST_IP" ]]; then
  DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)
  if [[ -n "$DOMAIN_IP" && "$DOMAIN_IP" != "$HOST_IP" ]]; then
    echo "WARNING: ${DOMAIN} resolves to ${DOMAIN_IP}, but this host public IP is ${HOST_IP}. Let's Encrypt may fail."
  fi
else
  echo "WARNING: Could not determine public IP. Skipping DNS check."
fi

echo "==> Pulling/building containers"
docker compose -f "$COMPOSE_FILE" pull || true
docker compose -f "$COMPOSE_FILE" build --no-cache

echo "==> Starting stack"
docker compose -f "$COMPOSE_FILE" up -d

echo "==> Running database migrations"
docker compose -f "$COMPOSE_FILE" exec -T web python manage.py migrate --noinput

echo "==> Health check"
sleep 3
set +e
curl -fsS http://localhost:8000/ >/dev/null && echo "HTTP OK" || echo "HTTP check failed"
curl -IkfsS https://$DOMAIN/ >/dev/null && echo "HTTPS OK" || echo "HTTPS check failed (may need DNS/propagation)"
set -e

echo "==> Done. Visit: https://${DOMAIN}"

