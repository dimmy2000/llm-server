[Назад](../README.md)

# Схема работы роутера

```mermaid
graph TD
    A["Клиент: OpenAI-совместимый запрос на :8080"] --> B["llama-swap v265: разбор model-ID"]
    B --> C{"Запрошен qwen3.8-27b или strata-ID?"}

    C -- "qwen3.8-27b" --> D{"Активный профиль llama-swap"}
    D -- "ninfer (дефолт)" --> E["backend-ninfer: ninfer-serve TP=2"]
    D -- "llama (ручной выбор)" --> F["backend-llama: llama-server"]

    C -- "strata-iq3 или strata-iq2" --> G["strata-launch.sh (cmd без shell)"]
    G --> H{"RAM-гейт: MemAvailable >= порога 46 GiB (iq3) / 36 GiB (iq2)?"}
    H -- "нет" --> I["Быстрый отказ 500, причина в логах контейнера"]
    I --> J["Освободить RAM на хосте и повторить запрос"]
    J --> G
    H -- "да" --> K["exec serve/server.py: движок = тот же PID, что трекает llama-swap"]

    B --> L{"Целевой движок уже резидентен?"}
    L -- "нет" --> M["Exclusive-группа v265: unload вытесняемого движка (SIGTERM)"]
    M --> C
    L -- "да" --> C

    E --> N["Health-check целевого движка, прокси запроса"]
    F --> N
    K --> N
    N --> O["Ответ клиенту, cold-start платит первый запрос"]
```

Порядок unload -> start даёт дефолтная exclusive-группа llama-swap: старт
целевого движка начинается только после выхода вытесненных бэкендов, поэтому
RAM-гейт Strata видит реальные остатки памяти. Ручного шага переключения нет:
выбор model-ID в клиенте и есть переключение движка (ADR-0008).
