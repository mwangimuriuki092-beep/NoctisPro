#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo bash deploy/ubuntu22-docker-deploy.sh \
#     [--domain your-domain.com] \
#     [--email admin@your-domain.com] \
#     --project-dir /opt/noctis_pro \
#     [--compose-file docker-compose.yml] \
#     [--force-rebuild]

DOMAIN=""
ACME_EMAIL=""
PROJECT_DIR="/opt/noctis_pro"
COMPOSE_FILE="docker-compose.yml"
FORCE_REBUILD="0"

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
    --force-rebuild)
      FORCE_REBUILD="1"; shift 1;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

echo "==> Domain provided: ${DOMAIN:-<none>}"
echo "==> ACME email provided: ${ACME_EMAIL:-<none>}"

echo "==> Updating apt and installing prerequisites"
apt-get update -y
apt-get install -y ca-certificates curl gnupg ufw git wget

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
# Helper to set or replace KEY=VALUE in .env
set_env() {
  local key="$1"; shift
  local value="$1"; shift || true
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}
# Generate SECRET_KEY if missing
if ! grep -q '^SECRET_KEY=' .env; then
  echo "Generating SECRET_KEY"
  SECRET=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + string.punctuation
alphabet = alphabet.replace('"','').replace("'",'').replace('`','')
print(''.join(secrets.choice(alphabet) for _ in range(64)))
PY
)
  echo "SECRET_KEY=${SECRET}" >> .env
fi
# Set DEBUG appropriately
if [[ -n "$DOMAIN" ]]; then
  sed -i "s/^DEBUG=.*/DEBUG=False/" .env || echo "DEBUG=False" >> .env
else
  sed -i "s/^DEBUG=.*/DEBUG=True/" .env || echo "DEBUG=True" >> .env
fi
if [[ -n "$DOMAIN" ]]; then
  sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" .env || echo "DOMAIN=${DOMAIN}" >> .env
  if [[ -n "$ACME_EMAIL" ]]; then
    sed -i "s/^ACME_EMAIL=.*/ACME_EMAIL=${ACME_EMAIL}/" .env || echo "ACME_EMAIL=${ACME_EMAIL}" >> .env
  fi
  sed -i "s/^ALLOWED_HOSTS=.*/ALLOWED_HOSTS=${DOMAIN},localhost,127.0.0.1/" .env || echo "ALLOWED_HOSTS=${DOMAIN},localhost,127.0.0.1" >> .env
  sed -i "s/^CSRF_TRUSTED_ORIGINS=.*/CSRF_TRUSTED_ORIGINS=https:\/\/${DOMAIN},http:\/\/localhost:8000,http:\/\/127.0.0.1:8000/" .env || true
  sed -i "s/^CORS_ALLOWED_ORIGINS=.*/CORS_ALLOWED_ORIGINS=https:\/\/${DOMAIN},http:\/\/localhost:3000,http:\/\/127.0.0.1:3000/" .env || true
  sed -i "s/^SECURE_SSL_REDIRECT=.*/SECURE_SSL_REDIRECT=True/" .env || echo "SECURE_SSL_REDIRECT=True" >> .env
else
  # Use localhost as DOMAIN to keep Caddyfile valid when no public domain is set
  sed -i "s/^DOMAIN=.*/DOMAIN=localhost/" .env || echo "DOMAIN=localhost" >> .env
  sed -i "s/^ALLOWED_HOSTS=.*/ALLOWED_HOSTS=localhost,127.0.0.1/" .env || echo "ALLOWED_HOSTS=localhost,127.0.0.1" >> .env
  sed -i "s/^CSRF_TRUSTED_ORIGINS=.*/CSRF_TRUSTED_ORIGINS=http:\/\/localhost:8000,http:\/\/127.0.0.1:8000/" .env || true
  sed -i "s/^CORS_ALLOWED_ORIGINS=.*/CORS_ALLOWED_ORIGINS=http:\/\/localhost:3000,http:\/\/127.0.0.1:3000/" .env || true
  sed -i "s/^SECURE_SSL_REDIRECT=.*/SECURE_SSL_REDIRECT=False/" .env || echo "SECURE_SSL_REDIRECT=False" >> .env
fi

# Ensure Postgres credentials exist
if ! grep -q '^POSTGRES_DB=' .env; then set_env POSTGRES_DB app; fi
if ! grep -q '^POSTGRES_USER=' .env; then set_env POSTGRES_USER app; fi
if ! grep -q '^POSTGRES_PASSWORD=' .env; then
  echo "Generating POSTGRES_PASSWORD"
  PGPASS=$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
)
  set_env POSTGRES_PASSWORD "$PGPASS"
fi
if ! grep -q '^DATABASE_URL=' .env; then
  set_env DATABASE_URL "postgres://$(grep '^POSTGRES_USER=' .env | cut -d= -f2):$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2)@db:5432/$(grep '^POSTGRES_DB=' .env | cut -d= -f2)"
fi

DNS_OK="0"
if [[ -n "$DOMAIN" ]]; then
  echo "==> Verifying DNS resolves to this host"
  HOST_IP=$(curl -fsS ifconfig.me || curl -fsS https://ipinfo.io/ip || echo "")
  if [[ -n "$HOST_IP" ]]; then
    DOMAIN_IP=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)
    if [[ -n "$DOMAIN_IP" && "$DOMAIN_IP" == "$HOST_IP" ]]; then
      DNS_OK="1"
      echo "DNS check OK: ${DOMAIN} -> ${DOMAIN_IP}"
    else
      echo "WARNING: ${DOMAIN} resolves to ${DOMAIN_IP:-<none>}, host IP is ${HOST_IP}. Falling back to HTTP-only."
    fi
  else
    echo "WARNING: Could not determine public IP. Falling back to HTTP-only."
  fi
fi

echo "==> Ensuring static and media directories exist"
mkdir -p static staticfiles media
sed -i "s/^COLLECTSTATIC=.*/COLLECTSTATIC=1/" .env || echo "COLLECTSTATIC=1" >> .env

echo "==> Pulling/building containers"
docker compose -f "$COMPOSE_FILE" pull || true
if [[ "$FORCE_REBUILD" == "1" ]]; then
  docker compose -f "$COMPOSE_FILE" build --no-cache
else
  docker compose -f "$COMPOSE_FILE" build --pull
fi

echo "==> Running Django deploy checks"
docker compose -f "$COMPOSE_FILE" run --rm web python manage.py check --deploy | cat

echo "==> Starting stack"
docker compose -f "$COMPOSE_FILE" up -d

echo "==> Ensuring superuser (optional)"
if [[ -n "${ADMIN_USER:-}" && -n "${ADMIN_EMAIL:-}" && -n "${ADMIN_PASSWORD:-}" ]]; then
  docker compose -f "$COMPOSE_FILE" exec -T web python - << 'PY'
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE','noctis_pro.settings')
import django
django.setup()
from django.contrib.auth import get_user_model
User = get_user_model()
u, created = User.objects.get_or_create(username=os.environ['ADMIN_USER'], defaults={'email': os.environ['ADMIN_EMAIL']})
if created:
    u.is_superuser = True
    u.is_staff = True
    u.set_password(os.environ['ADMIN_PASSWORD'])
    u.save()
print('Superuser ready:', u.username)
PY
fi

echo "==> Waiting for health endpoint"
set +e
for i in {1..30}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health/)
  if [[ "$code" == "200" ]]; then
    echo "Local health OK"
    break
  fi
  sleep 2
done
if [[ "$DNS_OK" == "1" ]]; then
  for i in {1..30}; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" https://${DOMAIN}/health/)
    if [[ "$code" == "200" ]]; then
      echo "Public HTTPS health OK"
      break
    fi
    sleep 2
  done
else
  echo "Skipping public HTTPS health (DNS not OK or no domain)"
fi
set -e

if [[ "$DNS_OK" == "1" ]]; then
  echo "==> Done. Visit: https://${DOMAIN}"
else
  echo "==> Done. Visit: http://<server-ip>:8000 (no domain detected)"
fi

