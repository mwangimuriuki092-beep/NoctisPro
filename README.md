# Noctis Deployment Guide

## Quick start (production)

1. SSH to your server as a sudo-enabled user.
2. Clone or sync this repo to the server (e.g., `/opt/noctis`).
3. Copy and edit environment variables:
```bash
cp .env.example .env
nano .env
```
4. Provision the host (Docker, firewall):
```bash
sudo bash deploy/provision.sh
```
5. Enable systemd service to run the stack:
```bash
sudo bash deploy/install-systemd.sh /opt/noctis
sudo systemctl status noctis
```

The app will be served by Caddy on ports 80/443 and proxy to `web:8000`.

## Requirements
- Ubuntu 22.04+ (or Debian-based)
- Open ports: 80, 443 (and 22 for SSH)
- DNS A record pointing `DOMAIN` to your server IP

## Services
- `web` (Django via Daphne on 8000)
- `worker` (Celery worker)
- `redis` (cache/broker)
- `db` (PostgreSQL)
- `caddy` (TLS termination, static/media)

## Common operations
```bash
make up            # start stack
make logs          # follow logs
make migrate       # run migrations
make createsuperuser
make collectstatic # collect static files
make down          # stop stack
```

## Notes
- Set strong `SECRET_KEY` and `POSTGRES_PASSWORD` in `.env`.
- Ensure `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, and `CORS_ALLOWED_ORIGINS` match your domain.
- If using GPU or large ML libs, adjust Docker resources accordingly.