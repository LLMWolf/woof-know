#!/usr/bin/env bash
set -euo pipefail

# redoc-build.sh — генерация статического HTML из openapi.yaml
# Требования: Node.js (для npx), доступ в интернет для загрузки redoc-cli
# Выход: docs/openapi.html

OAS=${OAS:-openapi.yaml}
OUT_DIR=${OUT_DIR:-docs}
OUT_HTML=${OUT_HTML:-${OUT_DIR}/openapi.html}

mkdir -p "$OUT_DIR"

# Установка и генерация (через npx без глобальной инсталляции)
COMMAND=(npx --yes redoc-cli@latest build "$OAS" -o "$OUT_HTML")
echo "→ ${COMMAND[@]}"
"${COMMAND[@]}"

# Короткое резюме
if [ -f "$OUT_HTML" ]; then
  echo "✅ Сгенерировано: $OUT_HTML"
  ls -lh "$OUT_HTML" | awk '{print "   размер:", $5}'
else
  echo "❌ Не удалось создать $OUT_HTML" >&2
  exit 1
fi
