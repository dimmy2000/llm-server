# 01 — Скачать и проверить официальный артефакт Qwen3.8-27B для NInfer

Type: task
Status: resolved

## Question

Скачать `neroued/Qwen3.8-27B-nvfp4-NInfer` (файл
`qwen3_8_27b_nvfp4.ninfer`, 23.7 GB) в `/opt/models/Qwen3.8-27B-nvfp4-NInfer/`
и убедиться, что файл целый и пригодный:

- `./ninfer/fetch-model.sh` отрабатывает без ошибок (с `hf` CLI и без него —
  через curl с докачкой);
- SHA-256 совпадает с `74d2c57145e6ff11d1d2faa79594477f9bc903a611af1fb20218189fbbb77d82`
  (значение из `SHA256SUMS` в репозитории артефакта);
- размер ровно 23719715844 байта;
- манифест артефакта (`artifact-manifest.json`) сообщает `container_version: 3`
  и `cuda_architecture: sm_120a` — то есть формат совпадает с тем, который
  понимает `ninfer-tp2 v0.4.5`.

Перед скачиванием проверить свободное место в `/opt/models` (нужно ~24 ГиБ
сверх текущего) и получить согласие пользователя на загрузку 23.7 GB.

## Acceptance

- Файл лежит по `/opt/models/Qwen3.8-27B-nvfp4-NInfer/qwen3_8_27b_nvfp4.ninfer`.
- `sha256sum` совпадает, размер совпадает.
- В комментарии к тикету зафиксированы вывод `sha256sum -c` и содержимое
  манифеста (container_version, cuda_architecture, components).

## Answer

Артефакт скачан пользователем вручную в
`/opt/models/Qwen3.8-27B-nvfp4-NInfer/qwen3_8_27b_nvfp4.ninfer` и проверен:

- `sha256sum -c` → `qwen3_8_27b_nvfp4.ninfer: OK` (41.652 s);
- размер ровно 23719715844 байта;
- манифест артефакта: `container_version: 3`, `cuda_architecture: sm_120a`,
  компоненты `text`, `vision`, `mtp`, `dflash2` — совпадает с форматом,
  который принимает `ninfer-tp2 v0.4.5` (движок стартует и грузит веса).

Побочный результат: `./ninfer/fetch-model.sh` на этой машине не
использовался, потому что файл уже был скачан до него; скрипт остаётся
воспроизводимым путём для других машин.
