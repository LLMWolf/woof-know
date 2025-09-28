#!/usr/bin/env bash
set -euo pipefail

# WOOF-KNOW (СПРИ) — restore.sh
# Восстановление рабочей БД из бэкапа, с проверкой целостности и резервной копией текущего файла.
#
# Использование:
#   ./restore.sh --file backup/spree-YYYYMMDD.sqlite [--db ./data/spree.sqlite]
#
# Параметры:
#   --file  Путь к файлу бэкапа (обязателен)
#   --db    Путь к рабочей БД (по умолчанию ./data/spree.sqlite)

DB_PATH=./data/spree.sqlite
BFILE=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      BFILE="$2"; shift 2 ;;
    --db)
      DB_PATH="$2"; shift 2 ;;
    *) echo "Неизвестный параметр: $1"; exit 2 ;;
  esac
done

if [ -z "$BFILE" ]; then
  echo "❌ Укажите путь к бэкапу: --file backup/spree-YYYYMMDD.sqlite" >&2
  exit 2
fi

if [ ! -f "$BFILE" ]; then
  echo "❌ Файл бэкапа не найден: $BFILE" >&2
  exit 2
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "❌ sqlite3 не найден в PATH" >&2; exit 2
fi

# Проверка целостности бэкапа
sqlite3 "$BFILE" "PRAGMA quick_check;" | grep -q "ok" || {
  echo "❌ quick_check не прошёл для $BFILE" >&2; exit 1
}

# Резервное копирование текущей БД (если есть)
if [ -f "$DB_PATH" ]; then
  TS=$(date -u +%Y%m%d%H%M%S)
  BK="${DB_PATH%/*.sqlite}/spree-before-restore-${TS}.sqlite"
  cp "$DB_PATH" "$BK"
  echo "ℹ️  Текущая БД сохранена: $BK"
fi

# Замена
cp "$BFILE" "$DB_PATH"
echo "✅ Восстановлено из $BFILE → $DB_PATH"

# Финальная проверка
sqlite3 "$DB_PATH" "PRAGMA quick_check;" | grep -q "ok" && echo "✅ quick_check: ok"
