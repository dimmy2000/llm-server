# NInfer TP=2 backend for llama-swap.
#
# Базовый образ — ubuntu:26.04, потому что готовые бинарники ninfer-tp2
# собраны под glibc 2.42 / FFmpeg 8 / CUDA 13 runtime (та же ОС, что и хост).
# llama-swap берётся из того же образа, что и llama-профиль, поэтому версии
# маршрутизатора у профилей совпадают.
#
# Сборка: docker compose --profile ninfer build

FROM ghcr.io/mostlygeek/llama-swap:cuda13 AS llama_swap

FROM ubuntu:26.04

# Движок v0.4.6 == релиз v0.4.7 по C++-дереву (release notes v0.4.7: «the
# C++ tree is the same as v0.4.6, v0.4.6 tarball runs it»). У v0.4.7 нет
# published-ассетов, поэтому ставим архив v0.4.6, зафиксированный по SHA-256;
# v0.4.6 также объявлен минимумом, требуемым артефактом glfenix (см.
# ninfer/fetch-model.sh).
ARG NINFER_VERSION=v0.4.6
ARG NINFER_ASSET=ninfer-tp2-v0.4.6-linux-x86_64-sm120a-ubuntu26.04.tar.gz
ARG NINFER_SHA256=aadbaaf99e3204fd97a5afe130254a7dd06430f404f1951c5d3ab74f8588c614

# FFmpeg 8 (libav*62) — зависимость ninfer-serve для видео-входа,
# libcurl4t64 — HTTP-клиент и healthcheck из образа llama-swap.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libavcodec62 \
        libavformat62 \
        libavutil60 \
        libswscale9 \
        libcurl4t64 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=llama_swap /app/llama-swap /app/llama-swap

RUN curl -fsSL -o /tmp/ninfer.tar.gz \
        "https://github.com/ValerioDolci/ninfer-tp2/releases/download/${NINFER_VERSION}/${NINFER_ASSET}" \
    && echo "${NINFER_SHA256}  /tmp/ninfer.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/ninfer \
    && tar -xzf /tmp/ninfer.tar.gz --strip-components=1 -C /opt/ninfer \
    && cd /opt/ninfer \
    && sha256sum -c SHA256SUMS \
    && rm -f /tmp/ninfer.tar.gz

ENV LD_LIBRARY_PATH=/opt/ninfer/lib

WORKDIR /app

EXPOSE 8080

HEALTHCHECK --interval=5s --timeout=5s --start-period=900s --retries=60 \
    CMD curl -f http://localhost:8080/ || exit 1

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml"]
