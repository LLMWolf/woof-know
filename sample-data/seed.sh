#!/usr/bin/env bash
set -euo pipefail

# WOOF-KNOW (СПРИ) — seed.sh
# Создаёт каталог sample-data/ с демо‑файлами под R0.1–R0.3:
# - Text-first: md, txt, (опц.) docx, (опц.) pdf (text-layer)
# - Tables: csv, (опц.) xlsx
# Скрипт идемпотентен: перезаписывает файлы при повторном запуске.

ROOT_DIR=$(pwd)
DATA_DIR="${SAMPLE_DATA_DIR:-./sample-data}"
DOCS_DIR="$DATA_DIR/docs"
POL_DIR="$DATA_DIR/policies"
TAB_DIR="$DATA_DIR/tables"

mkdir -p "$DOCS_DIR" "$POL_DIR" "$TAB_DIR"

# ---------- MD/TXT ----------
cat > "$DOCS_DIR/product_vision.md" <<'MD'
# Видение продукта — СПРИ

**Цель:** приватный Graph-aware Q&A по вашим файлам. По умолчанию — `strict_local`.

**KPI (MVP):**
- P95 латентность ≤ 7–10 с
- Hit-rate@10 ≥ 0.7 (при показе источников)
- «Нет ответа» ≤ 20%
- Net-positive ≥ +30 п.п.

**Релизы:** R0.1 (CLI), R0.2 (WebUI+Text-first), R0.3 (Tables+SQLite), V1.1+ (OCR/ASR).
MD

cat > "$DOCS_DIR/specs.md" <<'MD'
# Спецификация MVP (выписка)

- Форматы: `md, txt` (R0.1), `docx, pdf(text)` (R0.2), `csv, xlsx` (R0.3)
- LLM: Ollama `llama3.1:8b`, T=0.2, timeout=60s
- Privacy: `strict_local` по умолчанию + kill-switch
MD

cat > "$POL_DIR/security.md" <<'MD'
# Политика безопасности (кратко)

- По умолчанию внешние вызовы запрещены (`strict_local`).
- Глобальный kill-switch блокирует любые внешние вызовы.
- Логи без PII, хранение 90 дней.
MD

cat > "$DATA_DIR/notes.txt" <<'TXT'
Список дел:
- Проверить ingest каталога sample-data/
- Запустить kpi_smoke.py и убедиться, что P95 < 10 c
- Убедиться, что при kill-switch внешних вызовов нет
TXT

# ---------- CSV ----------
cat > "$TAB_DIR/team.csv" <<'CSV'
name,role,location
Алиса,BA,SPB
Борис,PO,MSK
Виктор,Architect,MSK
CSV

cat > "$TAB_DIR/faq.csv" <<'CSV'
q,a
"Какой дефолтный режим приватности?","strict_local"
"Какая модель LLM?","llama3.1:8b"
CSV

# ---------- (опц.) DOCX через python-docx ----------
if command -v python >/dev/null 2>&1; then
  python - <<'PY' 2>/dev/null || true
try:
    from docx import Document
    import os
    path = os.path.join("sample-data","docs","overview.docx")
    doc = Document()
    doc.add_heading("СПРИ — Обзор", level=1)
    doc.add_paragraph("Локальный Graph-aware Q&A. Privacy-first. R0.2 поддерживает DOCX.")
    doc.save(path)
    print("[ok] DOCX создан:", path)
except Exception as e:
    print("[skip] python-docx не установлен — пропуск DOCX", e)
PY
else
  echo "[skip] Python недоступен — пропуск DOCX"
fi

# ---------- (опц.) PDF (text-layer) через pandoc ----------
if command -v pandoc >/dev/null 2>&1; then
  pandoc -V geometry:margin=2cm -o "$DOCS_DIR/overview.pdf" "$DOCS_DIR/product_vision.md" && \
  echo "[ok] PDF создан: $DOCS_DIR/overview.pdf"
else
  echo "[skip] pandoc не найден — пропуск PDF"
fi

# ---------- (опц.) XLSX через pandas/openpyxl ----------
if command -v python >/dev/null 2>&1; then
  python - <<'PY' 2>/dev/null || true
try:
    import os
    import pandas as pd
    df1 = pd.read_csv(os.path.join('sample-data','tables','team.csv'))
    df2 = pd.read_csv(os.path.join('sample-data','tables','faq.csv'))
    xlsx_path = os.path.join('sample-data','tables','demo.xlsx')
    with pd.ExcelWriter(xlsx_path, engine='openpyxl') as w:
        df1.to_excel(w, index=False, sheet_name='team')
        df2.to_excel(w, index=False, sheet_name='faq')
    print('[ok] XLSX создан:', xlsx_path)
except Exception as e:
    print('[skip] pandas/openpyxl не установлены — пропуск XLSX', e)
PY
else
  echo "[skip] Python недоступен — пропуск XLSX"
fi

# ---------- Итого ----------
if command -v tree >/dev/null 2>&1; then
  echo "\nСтруктура sample-data/:" && tree -a "$DATA_DIR"
else
  echo "\nФайлы созданЫ:" && find "$DATA_DIR" -maxdepth 2 -type f | sed 's#^# - #' 
fi

echo "\nГотово. Используйте каталог $DATA_DIR для ingest (profile=text/table)."
