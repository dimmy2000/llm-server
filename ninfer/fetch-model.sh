#!/usr/bin/env bash
# Скачивает артефакт Qwen3.8-27B для профиля `ninfer` и проверяет SHA-256.
#
#   ./ninfer/fetch-model.sh [каталог-назначения]
#
# Каталог по умолчанию — /opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer,
# путь внутри контейнера —
# /models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer/qwen3_8_27b_nvfp4.ninfer
# (см. ninfer/config.yaml). Нужно ~22 ГиБ свободного места.
#
# Артефакт — glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer: весовая часть
# побитово совпадает с официальным neroued/Qwen3.8-27B-nvfp4-NInfer (greedy
# выход равен), отличается только блок DFlash2 (NVFP4-драфтер и proposal-голова).
# Требует движок v0.4.6+ (движок профиля — v0.4.6 == код v0.4.7).
#
# Контрольная сумма зафиксирована из SHA256SUMS в репозитории артефакта.

set -euo pipefail

REPO='glfenix/Qwen3.8-27B-nvfp4-DFlash2NVFP4drafter-NInfer'
FILE='qwen3_8_27b_nvfp4.ninfer'
SHA256='bfc05a7077926775fb872cf227e984cb5d27487ef9aa0a346cc3d6763f72330a'
DEST="${1:-/opt/models/Qwen3.8-27B-nvfp4-DFlash2NV-MTPNV-NInfer}"

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
