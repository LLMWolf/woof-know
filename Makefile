# WOOF-KNOW (СПРИ) — Makefile
# Требования: docker compose, curl, jq, python3

SHELL := /bin/bash
BASE_URL ?= http://localhost:8080

.PHONY: help
help:
	@echo "Доступные цели:"
	@echo "  up / down / logs      — поднять/остановить стенд (docker-compose)"
	@echo "  lint-openapi          — линт openapi.yaml через spectral.yaml"
	@echo "  kpi                   — e2e KPI smoke (kpi_smoke.py)"
	@echo "  backup                — VACUUM INTO бэкап SQLite"
	@echo "  restore FILE=...      — восстановление из бэкапа"

.PHONY: up
up:
	docker compose up -d

.PHONY: down
down:
	docker compose down

.PHONY: logs
logs:
	docker compose logs -f --tail=200

.PHONY: lint-openapi
lint-openapi:
	@which spectral >/dev/null 2>&1 || (echo "Установите spectral: npm i -g @stoplight/spectral" && exit 2)
	spectral lint openapi.yaml -r spectral.yaml

.PHONY: kpi
kpi:
	python3 kpi_smoke.py --base-url $(BASE_URL) --q "Каковы KPI MVP?" --k 10 --threshold 0.8 --n 25 --warmup 3 --show-sources

.PHONY: backup
backup:
	@mkdir -p backup
	@sqlite3 ./data/spree.sqlite "VACUUM INTO 'backup/spree-$$(date -u +%Y%m%d).sqlite'"
	@echo "Бэкап готов: backup/spree-$$(date -u +%Y%m%d).sqlite"

.PHONY: restore
restore:
	@if [ -z "$$FILE" ]; then echo "Укажите путь к бэкапу: make restore FILE=backup/spree-YYYYMMDD.sqlite"; exit 2; fi
	@cp "$$FILE" ./data/spree.sqlite
	@echo "Восстановлено из $$FILE"
