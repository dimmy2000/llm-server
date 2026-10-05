#!/usr/bin/env bash
# Скачивает артефакт Qwen3.8-27B для профиля `ninfer` и проверяет SHA-256.
#
#   ./ninfer/fetch-model.sh [каталог-назначения]
#
# Каталог по умолчанию — /opt/models/Qwen3.8-27B-nvfp4-NInfer, путь внутри
# контейнера — /models/Qwen3.8-27B-nvfp4-NInfer/qwen3_8_27b_nvfp4.ninfer
# (см. ninfer/config.yaml). Нужно ~24 ГиБ свободного места.
#
# Контрольная сумма зафиксирована из SHA256SUMS в репозитории артефакта
# (ревизия a107ba1b5b0609d9ca90d5ed61439f5f5cc7d64d).

set -euo pipefail

REPO='neroued/Qwen3.8-27B-nvfp4-NInfer'
FILE='qwen3_8_27b_nvfp4.ninfer'
SHA256='74d2c57145e6ff11d1d2faa79594477f9bc903a611af1fb20218189fbbb77d82'
DEST="${1:-/opt/models/Qwen3.8-27B-nvfp4-NInfer}"

mkdir -p "$DEST"
target="$DEST/$FILE"

if [[ -f "$target" ]] && echo "$SHA256  $target" | sha256sum -c - >/dev/null 2>&1; then
    echo "Артефакт уже на месте и контрольная сумма совпадает: $target"
    exit 0
fi

if command -v hf >/dev/null 2>&1; then
    hf download "$REPO" "$FILE" --local-dir "$DEST"
else
    echo "hf CLI не найден, используется curl (докачка поддерживается)."
    curl -fL -C - -o "$target" \
        "https://huggingface.co/$REPO/resolve/main/$FILE"
fi

echo "$SHA256  $target" | sha256sum -c -
echo "Готово: $target"
