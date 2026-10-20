# Ребут-тест автомата (тикет 11, 2026-10-20 07:28)

Хост перезагружен, docker llama-swap поднят автоматически (`restart: unless-stopped`, docker.service enabled), strata-юнит демонтирован в тикете 10. Все проверки — только HTTP.

| проверка | | деталь |
|---|---|---|
| :8080 /health после загрузки | ✅ | {"wall": 0.0, "body": "OK"} |
| /api/profiles: активен дефолт ninfer | ✅ | ninfer |
| /v1/models: три ID | ✅ | qwen3.8-27b strata-iq2 strata-iq3 |
| qwen3.8-27b отвечает (preload ninfer) | ✅ | wall=0.12s |
| strata-iq3 по обычному запросу (автостарт) | ✅ | wall=14.75s model_resp=qwen3.8-flash-next-iq3_xxs |
| возврат на родителя | ✅ | wall=7.9s |
| strata-iq2 по обычному запросу (автостарт) | ✅ | wall=12.75s model_resp=qwen3.8-flash-next-iq2_xs |
| домашний стан после цикла | ✅ | wall=7.8s |
| итог: три ID видимы, профиль ninfer | ✅ | model=ninfer red-line GPU1=710MiB |
| очередь inhibitor: ни одного ручного шага | ✅ | весь тест — только HTTP-запросы |
| p2p read NV0↔NV1 | ✅ |  	[4mGPU0	GPU1	[0m  GPU0	X	OK	  GPU1	OK	X	  Legend:    X   |

Нормы: qwen cold ~7–9 c (preload ninfer должен дать ответ сразу, warm < 1 c), strata gets 14–22 c.
