# Changelog — СПРИ

Все заметные изменения в этом проекте будут документироваться в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/) и проект следует [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Добавлено

* Скрипты `backup.sh` и `restore.sh` для управления бэкапами SQLite.
* Конфигурация `otel-collector.yaml` (минимальная pipeline).
* Файлы `CONTRIBUTING.md`, `CODEOWNERS`, `SECURITY.md`.
* CI workflow `.github/workflows/ci.yml` (Spectral, JSON Schema, базовые шаги).

### Изменено

* Лицензия MIT обновлена с указанием Copyright © 2025 LLMWolf.

### Исправлено

* Небольшие правки описаний в README.

## [0.1.0] — 2025-09-28

### Добавлено

* Архитектурный документ `ARCH-СПРИ.md` с полным пакетом 01–24.
* Спецификация API `openapi.yaml` (OpenAPI 3.1) + линт-правила `spectral.yaml`.
* Минимальная БД-схема `ddl.sql` (SQLite, WAL) и ER‑модель.
* Схема настроек `settings.schema.json` и пример `settings.example.json`.
* Скрипт `kpi_smoke.py` для e2e‑проверки KPI (health, query, p95/hit@k).
* Чек‑лист приёмки `acceptance-checklist-R0.1–R0.3.md`.
* Quickstart `README.md` (RU‑only, MVP), `.env.example`.
* `docker-compose.yaml` для локального стенда (api + ollama + otel).
* Скрипт `seed.sh` для генерации `sample-data/` (md, txt, csv и опц. docx/pdf/xlsx).

### Изменено

* —

### Исправлено

* —

[Unreleased]: https://example.local/spree/compare/v0.1.0...HEAD
[0.1.0]: https://example.local/spree/releases/tag/v0.1.0
