[Назад](../README.md)

# Состояния бэкендов роутера

Ровно один бэкенд резидентен в любой момент времени; переходы запускает сам
llama-swap по запросу к любому из трёх публичных ID (ADR-0008).

```mermaid
stateDiagram-v2
    [*] --> Cold: docker compose up -d
    Cold: Контейнер поднимается, движки ещё не загружены
    Cold --> ParentReady: hooks.on_startup - профиль ninfer и прелоад backend-ninfer

    ParentReady: Резидентен движок родителя, llama или ninfer по активному профилю
    StrataReady: Резидентен Strata, iq3 или iq2
    Swapping: Exclusive-группа выгружает резидентный движок (SIGTERM)
    Starting: Целевой движок грузит веса, идёт health-check
    Refused: Быстрый 500 с причиной в логах контейнера, ретраев нет
    Stopped: Движок выключен кнопкой PowerOff в UI llama-swap

    ParentReady --> Swapping: запрос к strata-iq3 или strata-iq2
    StrataReady --> Swapping: запрос к qwen3.8-27b или другому strata-ID
    Stopped --> Swapping: любой запрос к strata-ID
    Swapping --> Starting: вытесненный движок вышел, память освобождена
    Starting --> ParentReady: целевой - движок родителя
    Starting --> StrataReady: целевой - Strata, порог MemAvailable пройден
    Starting --> Refused: RAM-гейт не пройден или движок упал на старте
    Refused --> Swapping: повторный запрос после освобождения RAM
    StrataReady --> Stopped: PowerOff в UI, SIGTERM и graceful QUIT движка
    ParentReady --> ParentReady: PUT /api/profiles/active - выбор llama или ninfer
```

Единственный ручной переход — смена профиля родителя (`llama` или `ninfer`):
это предпочтение производительности, а не условие работоспособности. Профиль
сам движок не грузит, загрузку платит первый запрос к `qwen3.8-27b`.
