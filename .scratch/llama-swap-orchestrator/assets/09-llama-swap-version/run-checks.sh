#!/bin/bash
# Evidence for ticket 09 «Выбор версии образа llama-swap» (2026-10-17).
#
# Запуск: bash run-checks.sh  (вывод дублируется в run.log)
# Требуется: docker, сеть до ghcr.io/github.com. GPU не нужен: все cmd в
# тестовых конфигах — `sleep`, proxy смотрит на фиктивные HTTP-серверы.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="/home/dimmy/projects/00 infra/llm-server"
UPSTREAM_IMAGE="ghcr.io/mostlygeek/llama-swap:cuda13"
LS_DIGEST="sha256:3d49d5d957e1642b1719b1e5edc9e1d102f6a88198074e29f7f3b49e8fb0e0f8"

WORK="$(mktemp -d)"
cd "$WORK"
echo "=== workdir: $WORK"

echo
echo "=== [1] плавающий тег vs локальный образ ==="
docker inspect "$UPSTREAM_IMAGE" --format 'local image: {{.Id}} created {{.Created}}'
docker run --rm --entrypoint /app/llama-swap "$UPSTREAM_IMAGE" --version
docker run --rm --entrypoint /app/llama-server "$UPSTREAM_IMAGE" --version
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:mostlygeek/llama-swap:pull&service=ghcr.io" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
ACC="application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json"
echo -n "remote :cuda13 digest: "
curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: $ACC" \
  "https://ghcr.io/v2/mostlygeek/llama-swap/manifests/cuda13" | grep -i docker-content-digest | tr -d '\r'
echo -n "remote :v265-cuda13-b11706 digest: "
curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: $ACC" \
  "https://ghcr.io/v2/mostlygeek/llama-swap/manifests/v265-cuda13-b11706" | grep -i docker-content-digest | tr -d '\r'
echo -n "local image digest still in registry (expect 404): "
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" -H "Accept: $ACC" \
  "https://ghcr.io/v2/mostlygeek/llama-swap/manifests/$LS_DIGEST"

echo
echo "=== [2] пинуемый релиз llama-swap v265 ==="
curl -sL -o ls265.tar.gz \
  https://github.com/mostlygeek/llama-swap/releases/download/v265/llama-swap_265_linux_amd64.tar.gz
sha256sum ls265.tar.gz
tar -xzf ls265.tar.gz
./llama-swap --version

echo
echo "=== [3] текущие конфиги проекта на v265 ==="
for c in "$PROJ/llama/config.yaml" "$PROJ/ninfer/config.yaml"; do
  echo "--- $c"
  ./llama-swap -config "$c" -validate
  echo "exit: $?"
done

echo
echo "=== [4] v240 как negative control: пины не принимаются ==="
echo "--- v240: -validate неизвестен"
docker run --rm -v "$HERE/pins-test.yaml:/t.yaml:ro" --entrypoint /app/llama-swap \
  "$UPSTREAM_IMAGE" -config /t.yaml -validate
echo "exit: $?"
echo "--- v265: тот же конфиг с пинами"
./llama-swap -config "$HERE/pins-test.yaml" -validate
echo "exit: $?"

echo
echo "=== [5] единый ID переключается между backend'ами ==="
python3 "$HERE/fake_backend.py" llama.cpp 19001 >/dev/null 2>&1 &
BE1=$!
python3 "$HERE/fake_backend.py" ninfer 19002 >/dev/null 2>&1 &
BE2=$!
sleep 1
./llama-swap -config "$HERE/pins-test2.yaml" -listen 127.0.0.1:8127 >ls.log 2>&1 &
LS=$!
sleep 2

echo "--- /v1/models без активного профиля"
curl -s http://127.0.0.1:8127/v1/models \
  | python3 -c 'import sys,json;print([m["id"] for m in json.load(sys.stdin)["data"]])'

for p in llama ninfer; do
  curl -s -X PUT http://127.0.0.1:8127/api/profiles/active -d "{\"name\":\"$p\"}" >/dev/null
  echo "--- профиль $p: /v1/models"
  curl -s http://127.0.0.1:8127/v1/models \
    | python3 -c 'import sys,json;print([m["id"] for m in json.load(sys.stdin)["data"]])'
  echo -n "--- профиль $p: POST model=qwen3.8-27b -> "
  curl -s -X POST http://127.0.0.1:8127/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}],"temperature":0.3,"reasoning_effort":"medium"}'
  echo
done

echo "--- профиль disabled (пин ~) убирает публичный ID"
curl -s -X PUT http://127.0.0.1:8127/api/profiles/active -d '{"name":"disabled"}' >/dev/null
curl -s http://127.0.0.1:8127/v1/models \
  | python3 -c 'import sys,json;print([m["id"] for m in json.load(sys.stdin)["data"]])'

kill "$LS" 2>/dev/null
kill "$BE1" "$BE2" 2>/dev/null
echo
echo "=== done ==="
