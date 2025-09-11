# Noctis Pro Installation Guide

## Prerequisites

- Python 3.9 or higher
- Redis server (for Celery and Django Channels)
- Virtual environment (recommended)

## Installation Steps

### 1. Create and activate virtual environment
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 2. Install dependencies

For production:
```bash
pip install -r requirements.txt
```

For development (includes testing and debugging tools):
```bash
pip install -r requirements-dev.txt
```

### 3. Set up Redis
Make sure Redis is installed and running on your system:
```bash
# Ubuntu/Debian
sudo apt-get install redis-server

# macOS
brew install redis

# Start Redis
redis-server
```

### 4. Database setup
```bash
python manage.py migrate
python manage.py createsuperuser
```

### 5. Collect static files (for production)
```bash
python manage.py collectstatic
```

### 6. Run the development server
```bash
# Start Django development server
python manage.py runserver

# In another terminal, start Celery worker (if using background tasks)
celery -A noctis_pro worker --loglevel=info
```

## Environment Variables

Consider creating a `.env` file for environment-specific settings (or start from `.env.example`):
```
DEBUG=True
SECRET_KEY=your-secret-key
REDIS_URL=redis://localhost:6379
```

## Notes

- This is a Django-based DICOM medical imaging viewer application
- The application uses WebSockets for real-time features (chat and notifications)
- Make sure Redis is running before starting the application
- For production deployment, consider using gunicorn and nginx

## Native (non-Docker) production deployment on Ubuntu/Debian

1) Provision host (as root):
```bash
sudo bash deploy/provision-native.sh
```

2) Copy/sync repo to server, then install to `/opt/noctis` and set up services:
```bash
sudo bash deploy/install-native.sh /path/to/repo /opt/noctis
```

3) Configure Caddy (TLS and reverse proxy):
```bash
# Edit /opt/noctis/.env (set DOMAIN, ACME_EMAIL, ALLOWED_HOSTS, etc.)
sudo cp /opt/noctis/deploy/Caddyfile.native /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

4) Manage services:
```bash
sudo systemctl status noctis-web noctis-worker caddy
sudo journalctl -u noctis-web -f | cat
```

Notes:
- Set `DATABASE_URL` to your PostgreSQL instance, or leave it empty to use SQLite.
- Ensure `REDIS_URL=redis://localhost:6379/0` unless you customize Redis.
- Static files are collected to `staticfiles/`; Caddy serves `/media/*` directly from `/opt/noctis/media`.