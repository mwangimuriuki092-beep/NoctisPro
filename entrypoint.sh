#!/usr/bin/env sh
set -e

# Apply database migrations
python manage.py migrate

# Optionally collect static files (set COLLECTSTATIC=1 to enable)
if [ "${COLLECTSTATIC:-0}" = "1" ]; then
  python manage.py collectstatic --noinput
fi

# Start ASGI server (Daphne) for Django Channels support
exec daphne -b 0.0.0.0 -p 8000 noctis_pro.asgi:application

