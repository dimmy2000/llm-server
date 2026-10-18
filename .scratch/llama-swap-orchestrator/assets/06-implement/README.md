# Evidence — тикет 06 «Реализация», offline-проверки router-образа

Дата: 2026-10-17. Образ собран командой
`docker compose build llama-swap` (сервис `llama-swap`, контекст `router/`).
GPU не использовался: `-validate`, `--version`, `ldd` и разбор конфига.

## Образ

`llm-server/router:v265` (`sha256:190c9b48…`, 5.51 GB)

```
== llama-swap --version
version: v265 (d1e743f), built at 2026-10-14T08:30:34Z
== llama-server --version
version: 10068 (571d0d540)
built with GNU 14.2.0 for Linux x86_64
== router config -validate (mounted, как в compose)
config is valid: 2 model(s), 0 peer(s)
== платформа
glibc 2.43
Ubuntu 26.04.1 LTS
== ninfer-serve ldd с пер-модельным LD_LIBRARY_PATH
	libcuda.so.1 => not found
	libavcodec.so.62 => /usr/lib/x86_64-linux-gnu/libavcodec.so.62
	libcudart.so.13 => /opt/ninfer/lib/libcudart.so.13
== sizes
226M	/app
1.7G	/usr/local/cuda-13.3
782M	/opt/ninfer
```

`libcuda.so.1 => not found` ожидаемо: его даёт runtime хоста. Ключевой факт —
`libcudart.so.13` берётся из `/opt/ninfer/lib` (пер-модельный `env`), а не из
CUDA 13.3, как требовал тикет «Топология».

## Offline-смоук (фиктивные backend'ы)

Скрипт `run-smoke.sh`, лог `smoke.log`, конфиги `smoke/`. Заглушки `sleep 3600`
вместо движков, `proxy` на `router-smoke-backend.py`.

Проверено (v265, без GPU):
- `/v1/models` при старте = ровно `['qwen3.8-27b']` (стартовый профиль
  `ninfer` из `hooks.on_startup.profile`); записи `backend-*` скрыты
  (`unlisted`).
- Смена профиля `llama` → `ninfer` → `none` через
  `PUT /api/profiles/active`; на `none` публичный ID исчезает из `/v1/models`.
- Пин `~` на неактивный backend → `404` и на `/v1/chat/completions`, и на
  `/upstream/<model>/…`.
- `useModelName` (ninfer) доходит до backend'а как `model: qwen3.8-27b`;
  у llama backend'а — `model: backend-llama` (llama-server имя не проверяет).
- `filters.stripParams: repetition_penalty` вырезает `repetition_penalty` на
  обоих backend'ах; `temperature` и `reasoning_effort` проходят как есть.
- Непараллельность: у процесса llama-swap в любой момент ровно один `cmd`-ребёнок
  (`ps --ppid <ls>`); на смене профиля pid ребёнка меняется (старый движок
  остановлен до старта нового). Второй видимый ребёнок — собственный
  `nvidia-smi --loop` llama-swap.
