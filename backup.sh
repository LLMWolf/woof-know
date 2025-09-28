#!/usr/bin/env bash
set -euo pipefail

# WOOF-KNOW (СПРИ) — backup.sh
# Ежедневный бэкап SQLite БД с проверками и ротацией.
# Использует VACUUM INTO для атомарного снапшота.
#
# Переменные (с дефолтами):
#   DB_PATH        — путь к рабочей БД (./data/spree.sqlite)
#   BACKUPS_DIR    — каталог бэкапов (./backup)
#   KEEP_DAYS      — хранить не меньше N дней (90)
#   TAG            — суффикс для файла (например, env имя)
#
# Примеры:
#   DB_PATH=./data/spree.sqlite BACKUPS_DIR=./backup ./backup.sh
#   KEEP_DAYS=30 ./backup.sh

DB_PATH=${DB_PATH:-./data/spree.sqlite}
BACKUPS_DIR=${BACKUPS_DIR:-./backup}
KEEP_DAYS=${KEEP_DAYS:-90}
TAG=${TAG:-}

# --- Предусловия ---
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "❌ sqlite3 не найден в PATH" >&2; exit 2
fi

if [ ! -f "$DB_PATH" ]; then
  echo "❌ БД не найдена: $DB_PATH" >&2; exit 2
fi

mkdir -p "$BACKUPS_DIR"
STAMP=$(date -u +%Y%m%d)
BNAME="spree-${STAMP}${TAG:+-$TAG}.sqlite"
BPATH="$BACKUPS_DIR/$BNAME"

# --- Создание снапшота ---
set +e
sqlite3 "$DB_PATH" \
  "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; VACUUM INTO '$BPATH'" 2>/tmp/backup.err
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "❌ Ошибка VACUUM INTO (код $RC)" >&2
  cat /tmp/backup.err >&2 || true
  exit 1
fi

# --- Верификация файла ---
if [ ! -s "$BPATH" ]; then
  echo "❌ Пустой бэкап: $BPATH" >&2; exit 1
fi

# Проверка целостности бэкапа
sqlite3 "$BPATH" "PRAGMA quick_check;" | grep -q "ok" || {
  echo "❌ quick_check не прошёл для $BPATH" >&2; exit 1
}

# --- Ротация старых файлов ---
find "$BACKUPS_DIR" -maxdepth 1 -type f -name 'spree-*.sqlite' -mtime +$((KEEP_DAYS-1)) -print -delete || true

# --- Итог ---
echo "✅ Бэкап создан: $BPATH"
ls -lh "$BPATH" | awk '{print "   размер:", $5}'
