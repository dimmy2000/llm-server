# Установка NVIDIA-драйвера и nvidia-container-toolkit

Выполнялось на:
- Ubuntu 26.04 LTS (kernel 7.0.0-27-generic)
- GPU: 2 × NVIDIA GeForce RTX 5070 Ti (Blackwell, sm_120), по 16 GB VRAM
- NVIDIA driver 595.84, CUDA API 13.2
- Docker 29.7.2, Compose v5.4.0


## Установка NVIDIA-драйвера

`ubuntu-drivers` определил для RTX 5070 Ti ветку 595 как `recommended` (поддержка
Blackwell / sm_120). Ставим open-variant — именно его рекомендует `ubuntu-drivers`.

- Проверяем доступные драйверы для оборудования:

```bash
ubuntu-drivers devices
```

- Обновляем индексы пакетов:

```bash
sudo apt update
```

- Устанавливаем рекомендованный драйвер (`-open` вариант):

```bash
sudo DEBIAN_FRONTEND=noninteractive apt install -y nvidia-driver-595-open
```

- DKMS собрал модули под текущее ядро `7.0.0-27-generic`. Проверяем, что модуль
  подгрузился без перезагрузки (на безголовом сервере обычно подхватывается сразу):

```bash
modinfo nvidia | head -5
```

- Проверяем наличие device-нод и состояние GPU:

```bash
ls /dev/nvidia*
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
```

Ожидаемый результат: обе GPU видны, версия драйвера относится к ветке 595,
`CUDA Version` не ниже требуемой образом, объём VRAM определяется корректно.
Перезагрузка в нашем случае не потребовалась —
если `nvidia-smi` после установки пустой, выполняем `sudo reboot`.

- Проверяем топологию двух GPU:

```bash
nvidia-smi topo -m
nvidia-smi topo -p2p r
```

В текущей машине GPU соединены через PCIe Host Bridge (`PHB`), а P2P
помечен `CNS`. Поэтому профиль vLLM использует tensor parallelism 2 через
NCCL и задаёт `NCCL_P2P_DISABLE=1`.

## Установка nvidia-container-toolkit

Контейнерный runtime, который пробрасывает GPU в Docker. Источник — официальный
репозиторий NVIDIA (не Ubuntu archive).

- Добавляем GPG-ключ репозитория NVIDIA:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

- Подключаем стабильный apt-репозиторий с привязкой к ключу через `signed-by`:

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

- Обновляем индексы и ставим пакет:

```bash
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y nvidia-container-toolkit
```

- Регистрируем runtime `nvidia` в конфигурации Docker (`/etc/docker/daemon.json`)
  и перезапускаем демон:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

- Проверяем, что runtime появился:

```bash
docker info | grep -iA3 Runtimes
```

Ожидаемый вывод содержит `nvidia` в списке: `Runtimes: io.containerd.runc.v2 nvidia runc`.

## Проверка проброса GPU в контейнер

Финальная проверка: тестовый контейнер должен видеть GPU через `--gpus all`.

- Пробный запуск контейнера с пробросом GPU (тянет `ubuntu:latest`, если нет локально):

```bash
docker run --rm --gpus all ubuntu nvidia-smi
```

- В выводе должны быть: та же версия драйвера (595.84), та же модель GPU
  (RTX 5070 Ti) и корректный объём VRAM. Если `--gpus all` ругается на
  `could not select device driver` — `nvidia-ctk runtime configure` не применился
  или Docker не перезапущен.

## Итог

| Компонент | Версия |
|---|---|
| NVIDIA driver | 595.84 (`nvidia-driver-595-open`) |
| CUDA (из драйвера) | 13.2 |
| nvidia-container-toolkit | 1.19.1 |
| Docker runtime | `nvidia` зарегистрирован |
| Тестовый контейнер `--gpus all` | проходит |

## Требования профилей инференса

Профиль `llama` рассчитан на NVIDIA GPU с 16+ ГиБ VRAM. Роутер
(`router/`, llama.cpp и NInfer) и vLLM-профиль для Qwen3.8-27B NVFP4 требуют
обе RTX 5070 Ti: размер checkpoint больше памяти одной карты, поэтому
используется `tensor-parallel-size: 2`.

Одна из GPU обслуживает графическую сессию и может занимать около 1 ГиБ VRAM.
Безопасный базовый профиль vLLM использует `gpu-memory-utilization: 0.85`,
`max-model-len: 49152`, `max-num-seqs: 1` и
`max-num-batched-tokens: 1024`; публичный model-ID: `qwen3.8-27b`. Второй
конкурентный запрос ожидает scheduler. Под пиковой нагрузкой на GPU1 должно
оставаться не менее 512 MiB физически свободной памяти. FlashInfer autotune
отключен. Не повышать utilization только ради прохождения startup-проверки KV
cache; максимальный стабильный context limit выбирается отдельным cold-start и
нагрузочным тестом. На текущей машине `49152` прошёл проверку, а `65536` не
прошёл startup из-за недостаточного KV cache; поэтому максимальный проверенный
context limit равен `49152`.

Обе топологии занимают порт `8080` и все GPU. Роутер поднимается всегда
(без compose-профилей); vLLM — отдельный профиль, одновременно с роутером не
запускать:

```bash
docker compose down --remove-orphans
```

После этого запускается только одна топология:

```bash
# vLLM
docker compose --profile vllm up -d --wait --wait-timeout 1800

# Роутер (llama.cpp / NInfer за llama-swap)
docker compose up -d --wait --wait-timeout 1800
```
