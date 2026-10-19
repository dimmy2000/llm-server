# Vision smoke через :8080 на strata-iq3 (тикет 04, 2026-10-19)

Одна картинка, один запрос. PNG 64×64 сгенерирован локально (python PIL): белый фон,
красный круг (RGB 220,30,30), эллипс [16,16,48,48] — `/tmp/opencode/04-red-circle.png`,
в запрос ушёл как `image_url` c data-URL base64.

Запрос: `POST :8080/v1/chat/completions`, модель `strata-iq3`,
`chat_template_kwargs: {"enable_thinking": false}`, max_tokens 120,
промпт «Что изображено на картинке? Ответь одним коротким предложением, назови фигуру и цвет.»

## Результат

- HTTP **200**
- content: **«На картинке изображён красный круг.»** — фигура и цвет названы верно.
- usage: prompt_tokens 46 (включая изображение), completion_tokens 10.
- `model` ответа: `qwen3.8-flash-next-iq3_xxs` (native canon, не сверяется).

## Энкодер — CPU (наш стандарт)

Лог движка (`/opt/strata/strata-iq3_xxs.log`, старт 16:33:55):

```
strata-vision: model files loaded in 0.4 s
strata-vision: on the CPU, 8 threads, no warm-up
```

Флаг `--vision` в cmd движка (без `--vision-device` — на нативном Strata башня
Vision на CPU, GPU не занимает).

## Сырьё

Ответ: `/tmp/opencode/04-raw/vision-iq3.json`.
