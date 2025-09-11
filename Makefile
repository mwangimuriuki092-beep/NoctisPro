SHELL := /usr/bin/bash

.PHONY: help up down logs build ps restart migrate createsuperuser collectstatic worker shell

help:
	@echo "Common targets:"
	@echo "  make up              # Start stack"
	@echo "  make down            # Stop stack"
	@echo "  make logs            # Tail logs"
	@echo "  make build           # Build images"
	@echo "  make restart         # Restart stack"
	@echo "  make migrate         # Run Django migrations"
	@echo "  make createsuperuser # Create admin user"
	@echo "  make collectstatic   # Collect static files"
	@echo "  make worker          # Start Celery worker (foreground)"
	@echo "  make shell           # Django shell in web container"

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

build:
	docker compose build --pull

restart: down up

migrate:
	docker compose exec -T web python manage.py migrate

createsuperuser:
	docker compose exec web python manage.py createsuperuser

collectstatic:
	docker compose exec -e COLLECTSTATIC=1 -T web python manage.py collectstatic --noinput

worker:
	docker compose run --rm worker

shell:
	docker compose exec web python manage.py shell

