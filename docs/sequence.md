[Назад](../README.md)

# Последовательность запроса и автоматического свапа

Запрос к `strata-iq3`, когда резидентен NInfer (дефолтный старт контейнера).

```mermaid
sequenceDiagram
    autonumber
    participant C as Клиент
    participant R as Роутер (llama-swap :8080)
    participant N as NInfer (резидент)
    participant S as Strata (strata-iq3)

    C->>R: POST /v1/chat/completions, model strata-iq3
    Note over R: Целевой движок не резидентен, работает exclusive-группа
    R->>N: SIGTERM, выгрузка резидентного бэкенда
    N-->>R: процесс вышел, page-locked RAM освобождена
    R->>R: cmd strata-launch.sh 48234496 config port
    Note over R: Порог MemAvailable 46 GiB, при нехватке - мгновенный 500
    R->>S: exec serve/server.py, движок слушает выделенный порт
    S-->>R: GET /health - 200, движок готов
    Note over R,S: Тело запроса: стрипается repetition_penalty
    R->>S: запрос клиента
    S-->>R: поток ответа, поле model - native-ID движка
    R-->>C: поток ответа
```

Другие переходы (`iq3` на `iq2`, strata-ID на `qwen3.8-27b`) идут тем же
путём: выгрузка текущего движка, старт целевого, прокси запроса. Окна молчания
холодной загрузки (12-21 c у Strata, 7-9 c на тёплом page cache у llama.cpp,
до 40-60 c на холодном диске) при `sendLoadingState: false` не показываются
клиенту - индикатор только в логах контейнера (ADR-0006).
