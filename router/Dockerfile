# Единый образ-оркестратор: llama-swap v265 + два движка (llama.cpp b10068,
# NInfer TP=2 v0.4.6).
#
# База — ubuntu:26.04: готовые бинарники ninfer-tp2 собраны под glibc 2.42 /
# FFmpeg 8 (libavcodec62). Бинарники и CUDA-библиотеки llama.cpp копируются
# из запиненного образа ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068
# (Ubuntu 24.04 + CUDA 13.3, бинарники в /app). llama-swap — запиненный
# релиз v265; бинарник и тарбол NInfer проверяются по SHA-256 при сборке.
#
# Оба движка запускаются llama-swap как дочерние процессы через `cmd` в
# config.d/. docker.sock не используется. LD_LIBRARY_PATH задаётся
# пер-модельным `env:` (у NInfer `/opt/ninfer/lib` обязан быть первым: своего
# RPATH у бинарника нет), поэтому глобальный ENV здесь не выставляется.
#
# Сборка: docker compose build  (сервис llama-swap без профиля, см.
# docker-compose.yaml). Обновление движка = новый тег образа + новые build-args.

FROM ubuntu:26.04

# ca-certificates/curl — healthcheck и скачивание тарболов; libssl3t64 и
# libgomp1 — зависимости llama.cpp/llama-swap; libav*62 — FFmpeg 8 для
# видео-входа ninfer-serve; libcurl4t64 — HTTP-клиент.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libssl3t64 \
        libgomp1 \
        libavcodec62 \
        libavformat62 \
        libavutil60 \
        libswscale9 \
        libcurl4t64 \
    && rm -rf /var/lib/apt/lists/*

# llama.cpp b10068 (пин тикета «Выбор версии образа llama-swap»): индекс
# ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865…708e,
# amd64-ребёнок sha256:1c0cc37e…4fea.
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865bd031283c5f66ff2a82984cdb282ec37484cf2a9bfc7b4cb1f85708e /app /app
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10068@sha256:6447a865bd031283c5f66ff2a82984cdb282ec37484cf2a9bfc7b4cb1f85708e /usr/local/cuda-13.3/lib64 /usr/local/cuda-13.3/lib64

# llama-swap v265: релизный бинарник (member llama-swap), проверяется по SHA-256.
ARG LLAMA_SWAP_VERSION=v265
ARG LLAMA_SWAP_ASSET=llama-swap_265_linux_amd64.tar.gz
ARG LLAMA_SWAP_SHA256=cb1f9a94be05afa129d3c17868f1dd2ca710b919333c7b868239dc31575dcfa1

RUN curl -fsSL -o /tmp/llama-swap.tar.gz \
        "https://github.com/mostlygeek/llama-swap/releases/download/${LLAMA_SWAP_VERSION}/${LLAMA_SWAP_ASSET}" \
    && echo "${LLAMA_SWAP_SHA256}  /tmp/llama-swap.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/llama-swap.tar.gz -C /app llama-swap \
    && chmod +x /app/llama-swap \
    && rm -f /tmp/llama-swap.tar.gz

# NInfer TP=2 v0.4.6 == v0.4.7 по C++-дереву (release notes v0.4.7: «the C++
# tree is the same as v0.4.6, v0.4.6 tarball runs it»); у v0.4.7 нет
# published-ассетов, поэтому ставится архив v0.4.6. v0.4.6 — минимум,
# требуемый артефактом glfenix (см. fetch-model.sh).
ARG NINFER_VERSION=v0.4.6
ARG NINFER_ASSET=ninfer-tp2-v0.4.6-linux-x86_64-sm120a-ubuntu26.04.tar.gz
ARG NINFER_SHA256=aadbaaf99e3204fd97a5afe130254a7dd06430f404f1951c5d3ab74f8588c614

RUN curl -fsSL -o /tmp/ninfer.tar.gz \
        "https://github.com/ValerioDolci/ninfer-tp2/releases/download/${NINFER_VERSION}/${NINFER_ASSET}" \
    && echo "${NINFER_SHA256}  /tmp/ninfer.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/ninfer \
    && tar -xzf /tmp/ninfer.tar.gz --strip-components=1 -C /opt/ninfer \
    && cd /opt/ninfer \
    && sha256sum -c SHA256SUMS \
    && rm -f /tmp/ninfer.tar.gz

WORKDIR /app

EXPOSE 8080

# Прогрев NInfer на старте — до минуты, поэтому большой start-period.
HEALTHCHECK --interval=5s --timeout=5s --start-period=900s --retries=60 \
    CMD curl -f http://localhost:8080/ || exit 1

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "-config-dir", "/app/config.d"]
