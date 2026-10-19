# Верификационный проход интеграции

Status: open
Type: task
Blocked by: 01, 02, 03

## Question

(Исполняемый тикет, AFK) Сокращённый (не полный матричный) проход по готовой
интеграции; метрика перепроверяется санити, не тайминги-матрицы:

- Смена состояний по `strata-use.sh`: полный цикл llama → strata-iq3 → strata-iq2 →
  ninfer → off, 2 цикла подряд; лог journald + `GET /api/profiles` + `/v1/models`
  после каждого шага; VRAM/RAM-пик на переходах (watch 2 c, как в selection-карте).
- Санити decode на калиброванной конфигурации каждого размера через `:8080`:
  короткий chat-bench ≈ 130 (iq3) / 145 (iq2) tok/s ± разумный допуск; присутствие MTP
  admission в разумных пределах (46–93 %).
- Гэп-профиль через llama-swap: forced tool choice, structured+tools (ожидаемо 400),
  невалидный effort (400), xhigh/low (200) — на обоих strata-ID.
- Vision smoke через `:8080` (CPU-энкодер — наш стандарт): один запрос с картинкой
  на strata-iq3.
- Красная линия: VRAM GPU1 ≥ 512 MiB во всех состояниях цикла; RAM не в постоянный
  своп.
- Сырье в `.scratch/strata-integration/assets/` (watch-логи, очки цикла).

Resolved when: цикл стабилен ×2, красные линии не тронуты, санити-числа в пределах,
гэп-профиль совпадает с selection-картой.
