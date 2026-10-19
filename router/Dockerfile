# Единый образ-оркестратор: llama-swap v265 + два движка (llama.cpp b10438,
# NInfer TP=2 v0.4.6).
#
# База — ubuntu:26.04: готовые бинарники ninfer-tp2 собраны под glibc 2.42 /
# FFmpeg 8 (libavcodec62). Бинарники и CUDA-библиотеки llama.cpp копируются
# из запиненного образа ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438
# (Ubuntu 24.04 + CUDA 13.3, бинарники в /app). llama-swap — запиненный
# релиз v265; бинарник и тарбол NInfer проверяются по SHA-256 при сборке.
#
# Оба движка родителя и Strata запускаются llama-swap как дочерние процессы
# через `cmd` в config.d/. docker.sock не используется. LD_LIBRARY_PATH
# задаётся пер-модельным `env:` (у NInfer `/opt/ninfer/lib` обязан быть первым:
# своего RPATH у бинарника нет) и lib_dirs конфига Strata, поэтому глобальный
# ENV здесь не выставляется.
#
# Сборка: docker compose build  (сервис llama-swap без профиля, см.
# docker-compose.yaml). Обновление движка = новый тег образа + новые build-args.
#
# Strata собирается на стадии strata-build по upstream-пути /opt/strata/
# Dockerfile (нативный код — под CPU машины сборки; исходники приходят
# additional-контекстом strata-src, см. docker-compose.yaml). В образ идут
# только бинарники движка + serve/ + venv; веса/артефакты — маунты compose
# (RO /opt/strata/{models,packs,mtp,data}).

# Стадия сборки Strata: devel-образ с nvcc (upstream-база). Движок собирается
# под CUDA 13.0 и работает с рантайм-библиотеками CUDA 13.3 образа ggml-org
# (same-major soname libcudart.so.13 / libcublas.so.13 — minor-совместимость).
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS strata-build

# apt-шаг upstream /opt/strata/Dockerfile (усечён до нужд сборки: git/unzip не
# нужны — llama.cpp подтягивается zip'ом силами setup.py).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl libatomic1 \
        python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Только то, что нужно сборке и хэшу исходников BUILD.json (ENGINE_SOURCES /
# VISION_SOURCES в setup.py); остальное дерево /opt/strata (весами, логами) не
# копируется. llama.cpp подтягивается setup.py zip'ом на этапе сборки.
COPY --from=strata-src CMakeLists.txt requirements.txt setup.py /opt/strata/
COPY --from=strata-src src/ /opt/strata/src/
COPY --from=strata-src cmake/ /opt/strata/cmake/
COPY --from=strata-src include/ /opt/strata/include/
COPY --from=strata-src third_party/ggml/ /opt/strata/third_party/ggml/
COPY --from=strata-src tools/vision/ /opt/strata/tools/vision/
# tests/ и bench/micro/ нужны configure-стадии CMake: parity-таргеты гейтятся
# только STRATA_ENABLE_CUDA, не STRATA_BUILD_TESTS (dma_batch_parity и фикстуры
# ple_parity); сами тесты при сборке не запускаются.
COPY --from=strata-src tests/ /opt/strata/tests/
COPY --from=strata-src bench/micro/ /opt/strata/bench/micro/

WORKDIR /opt/strata
RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir --upgrade pip \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt

# RTX 5070 Ti — sm_120 (arch 120); vision-энкодер собирается (наш стандарт —
# strata-vision на CPU, конфиги несут vision.gpu: false). Скрипт — upstream-путь
# /opt/strata/Dockerfile (строка сборки через setup.cmake_build + BUILD.json).
ARG CUDA_ARCHITECTURES=120
RUN .venv/bin/python - <<'PYEOF'
import json, os, pathlib, shutil
import setup

llama = setup.get_llama_cpp()
nvcc, _ = setup.find_nvcc()
arch = os.environ.get("CUDA_ARCHITECTURES", "120").strip().strip('"').replace(",", ";")
vision = "gpu" if os.environ.get("BUILD_VISION", "1") == "1" else "none"

setup.cmake_build(setup.ROOT, setup.ROOT / "build", "strata",
    ["-DSTRATA_ENABLE_CUDA=ON", "-DSTRATA_Q6K_EXPERTS=ON", "-DSTRATA_MMQ_KQUANTS=ON", "-DSTRATA_BUILD_TESTS=OFF",
     f"-DCMAKE_CUDA_ARCHITECTURES={arch}", f"-DCMAKE_CUDA_COMPILER={nvcc}",
     f"-DSTRATA_GGML_DIR={llama}"], None, "build-strata.bat")
if vision != "none":
    setup.cmake_build(setup.ROOT / "tools" / "vision", setup.ROOT / "build-vision", "strata-vision",
        [f"-DLLAMA_DIR={llama}", "-DSTRATA_VISION_CUDA=ON", "-DSTRATA_PORTABLE=OFF",
         f"-DCMAKE_CUDA_ARCHITECTURES={arch}", f"-DCMAKE_CUDA_COMPILER={nvcc}"], None, "build-vision.bat")

eng = setup.ROOT / "engine"
eng.mkdir(exist_ok=True)
shutil.copy2(setup.ROOT / "build" / setup.EXE, eng / setup.EXE)
if (setup.ROOT / "build" / setup.KQ_LIB).exists():      # the K-quant MMQ prompt library (UD-Q4/Q5/Q6_K_XL files)
    shutil.copy2(setup.ROOT / "build" / setup.KQ_LIB, eng / setup.KQ_LIB)
if vision != "none":
    shutil.copy2(setup.ROOT / "build-vision" / "bin" / setup.VEXE, eng / setup.VEXE)
bindir = pathlib.Path(nvcc).parent
meta = {"source": "local", "version": setup.source_version(),
        "archs": [int(a.split("-")[0]) for a in arch.split(";") if a.split("-")[0].isdigit()], "vision": vision,
        "cuda_dirs": [str(d) for d in (bindir, bindir / "x64", bindir.parent / "lib64") if d.is_dir()],
        "src": setup.source_hash(setup.ENGINE_SOURCES),
        "vision_src": setup.source_hash(setup.VISION_SOURCES) if vision != "none" else None}
(eng / "BUILD.json").write_text(json.dumps(meta, indent=1))
PYEOF

FROM ubuntu:26.04

# ca-certificates/curl — healthcheck и скачивание тарболов; libssl3t64 и
# libgomp1 — зависимости llama.cpp/llama-swap; libav*62 — FFmpeg 8 для
# видео-входа ninfer-serve; libcurl4t64 — HTTP-клиент.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libssl3t64 \
        libgomp1 \
        libatomic1 \
        libavcodec62 \
        libavformat62 \
        libavutil60 \
        libswscale9 \
        libcurl4t64 \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# llama.cpp b10438 (пин тикета 11, бамп с b10068 тикета «Выбор версии образа
# llama-swap»): первая публикация образа cuda13 с обработкой OAI
# `reasoning_effort` — b10121 (`none` выключает thinking) + b10434 (остальные
# значения уходят в шаблон как `chat_template_kwargs.reasoning_effort`).
# База та же (CUDA 13.3), поэтому путь к библиотекам не меняется; с b11706
# ggml-org перешёл на CUDA 13.4 и путь стал бы /usr/local/cuda-13.4/lib64.
# Индекс образа ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4…6283,
# amd64-ребёнок sha256:551298ae…564e.
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4ef93697f025156849e55b8d6a92ef10b7cae3460bf0cf8a4d6ea6283 /app /app
COPY --from=ghcr.io/ggml-org/llama.cpp:server-cuda13-b10438@sha256:bb81f3e4ef93697f025156849e55b8d6a92ef10b7cae3460bf0cf8a4d6ea6283 /usr/local/cuda-13.3/lib64 /usr/local/cuda-13.3/lib64

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

# Strata: движок из стадии strata-build + serve/ + venv. Рантайм-зависимости
# engine — libcudart/libcublas.so.13 из /usr/local/cuda-13.3/lib64 (уже в
# образе, см. комментарий стадии сборки) и libatomic1; strata-vision также
# линкует libnccl.so.2 (в devel-образе CUDA — в /opt/strata/lib, путь добавлен
# в lib_dirs конфигов). lib_dirs конфигов Strata указывает на
# /usr/local/cuda-13.3/{bin,lib64} + /opt/strata/lib. BUILD.json при рантайме
# не проверяется (serve/ не импортирует setup.py) — источник правды по версии
# движка. Веса/артефакты приходят маунтами compose, не из образа.
COPY --from=strata-build /opt/strata/engine /opt/strata/engine
COPY --from=strata-build /usr/lib/x86_64-linux-gnu/libnccl.so.2* /opt/strata/lib/
COPY --from=strata-src serve/ /opt/strata/serve/
# server.py добавляет tools/ в sys.path (strata_tokenizer).
COPY --from=strata-src tools/ /opt/strata/tools/
COPY --from=strata-src requirements.txt /opt/strata/requirements.txt
RUN python3 -m venv /opt/strata/.venv \
    && /opt/strata/.venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/strata/.venv/bin/pip install --no-cache-dir -r /opt/strata/requirements.txt

WORKDIR /app

EXPOSE 8080

# Прогрев NInfer на старте — до минуты, поэтому большой start-period.
HEALTHCHECK --interval=5s --timeout=5s --start-period=900s --retries=60 \
    CMD curl -f http://localhost:8080/ || exit 1

ENTRYPOINT ["/app/llama-swap", "-config", "/app/config.yaml", "-config-dir", "/app/config.d"]
