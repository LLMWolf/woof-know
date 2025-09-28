# WOOF-KNOW (СПРИ) — Quickstart (RU)

Добро пожаловать! Этот репозиторий содержит минимальный каркас системы **СПРИ** (Graph‑aware Q&A, privacy‑first). Ниже — быстрый старт для локального стенда.

> MVP‑фокус: локальный запуск, RU‑интерфейс, `strict_local` по умолчанию, измеримые KPI.

---

## 1. Предпосылки

* **OS:** Linux/macOS/WSL2 (x86_64).
* **Python:** 3.11+
* **Docker:** 24+ и **Docker Compose** 2.
* **Ollama:** для локального LLM (модель `llama3.1:8b`).

### Установка Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b
```

---

## 2. Клонирование и окружение

```bash
git clone <repo-url> spree
cd spree
cp .env.example .env
```

Заполните `.env` при необходимости (порты/пути/токены).

---

## 3. Конфигурация

Схема настроек: `settings.schema.json` (см. канвас). Готовый пример: `settings.example.json`.

Создайте рабочий конфиг:

```bash
cp settings.example.json settings.json
```

Ключевые поля:

* `privacy.profile`: `strict_local|hybrid|cloud_ok`
* `privacy.kill_switch`: глобальная блокировка внешних вызовов
* `llm.provider/model/temperature/timeout_s`
* `retriever.k` и `retriever.threshold` (по умолчанию `0.8`)
* `storage.db_path` и директории данных/бэкапов

Проверка JSON по схеме (опционально):

```bash
# пример: с ajv (или любым валидатором draft 2020-12)
ajv validate -s settings.schema.json -d settings.json
```

---

## 4. Запуск: вариант А — Docker Compose (рекомендуется)

> Файл `docker-compose.yaml` будет добавлен отдельно. Стандартная схема: **api** + **ollama** + (опц.) **otel-collector**.

Базовые шаги:

```bash
# 1) старт сервисов
docker compose up -d

# 2) проверка состояния
curl -s http://localhost:8080/v1/health | jq
```

Ожидаемый ответ: `{ "status": "ok" }`.

Остановка:

```bash
docker compose down
```

---

## 5. Запуск: вариант B — локально (без контейнеров)

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# переменные окружения из .env
export $(grep -v '^#' .env | xargs)
# старт API (FastAPI/Uvicorn)
uvicorn spree.app:app --host 0.0.0.0 --port 8080 --reload
```

Проверка здоровья:

```bash
curl -s http://localhost:8080/v1/health | jq
```

---

## 6. Импорт данных (ingest)

Подготовьте папку `sample-data/` (будет добавлена) или укажите свои пути.

Через API:

```bash
curl -X POST http://localhost:8080/v1/ingest \
  -H 'Content-Type: application/json' \
  -d '{
    "paths": ["./sample-data", "./docs/specs.md"],
    "profile": "text",
    "limits": { "max_pages": 1000, "max_mb": 512 }
  }' | jq
```

Ожидаемый ответ: счётчики `ingested` и список `nodes`.

---

## 7. Вопрос‑ответ (query)

```bash
curl -X POST http://localhost:8080/v1/query \
  -H 'Content-Type: application/json' \
  -d '{
    "q": "Каковы KPI MVP?",
    "k": 10,
    "threshold": 0.8,
    "show_sources": true,
    "allow_external_context": false
  }' | jq
```

Ключевые поля ответа: `answer`, `sources[]`, `count`, `no_answer`, `latency_ms`.

---

## 8. Проверка KPI (smoke)

Скрипт: `kpi_smoke.py`.

```bash
python kpi_smoke.py --base-url http://localhost:8080 \
  --q "Каковы KPI MVP?" --k 10 --threshold 0.8 \
  --n 25 --warmup 3 --show-sources
```

Репорт покажет: `error_rate`, `p50/p95`, `hit_rate`, долю `нет ответа` и итог соответствия KPI.

---

## 9. Privacy‑профили и Kill‑switch

* Профиль по умолчанию — `strict_local`: внешние вызовы запрещены.
* Режимы `hybrid` и `cloud_ok` включаются в `settings.json` или через админ‑API.
* Глобальный kill‑switch блокирует любые внешние вызовы независимo от профиля.

Пример запроса:

```bash
curl -X POST http://localhost:8080/v1/admin/killswitch \
  -H 'Content-Type: application/json' \
  -d '{ "enabled": true }' | jq
```

---

## 10. Бэкапы и восстановление (SQLite)

Рекомендуется ежедневный снапшот:

```bash
sqlite3 ./data/spree.sqlite "VACUUM INTO './backup/spree-$(date -u +%Y%m%d).sqlite'"
```

Восстановление:

```bash
cp ./backup/spree-YYYYMMDD.sqlite ./data/spree.sqlite
```

---

## 11. Диагностика

* **LLM не отвечает:** убедитесь, что `ollama serve` активен; проверьте сеть к `127.0.0.1:11434`; перезапустите службу.
* **DB locked:** завершите долгие транзакции; перезапустите API; проверьте режим WAL.
* **429 Too Many Requests:** уменьшите частоту; проверьте `limits.rate_per_min`.
* **Нет ответа часто:** снизьте `threshold` или увеличьте `k`; проверьте качество корпуса.

---

## 12. Makefile и CI

> Будут добавлены отдельными файлами. Ожидаемые цели:

* `make up/down/logs` — управление Compose‑стендом.
* `make lint-openapi` — Spectral‑линт `openapi.yaml`.
* `make kpi` — запуск `kpi_smoke.py`.
* `make backup` — бэкап SQLite.

CI (GitHub Actions):

* Валидация `settings.json` по схеме; Spectral для OpenAPI; линт Python (ruff/flake8).

---

## 13. Лицензия и вклад

* Лицензия: будет добавлена (`LICENSE`).
* Вклад: `CONTRIBUTING.md
