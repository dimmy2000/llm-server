# Гэп-профиль через :8080 на обоих strata-ID (тикет 04, 2026-10-19)

Каждый размер — один раз в его окно цикла 1 (iq3 @16:34–16:35, iq2 @16:35–16:36),
запросы через `http://localhost:8080/v1/chat/completions` (публичный ID → shim →
нативная Strata :8081). Поле `model` в ответах — native canon, не сверяется (тикет 01).

## Результаты

| кейс | strata-iq3 | strata-iq2 | эталон (selection-карта) |
|---|---|---|---|
| (a) forced tool choice (`tool_choice` = имя функции при `tools`) | **200**, tool_calls: `get_weather({"city":"Paris"})` | **200**, tool_calls: `get_weather({"city":"Париж"})` | работает |
| (b) `response_format: json_object` + `tools` | **400** `structured response_format with tools/MCP is not supported` | **400** `structured response_format with tools/MCP is not supported` | 400 |
| (c) `reasoning_effort: "banana"` | **400** `unknown reasoning effort 'banana': use none, low, medium or high` | **400** `unknown reasoning effort 'banana': use none, low, medium or high` | 400 с той же строкой |
| (d1) `reasoning_effort: "xhigh"` | **200** (content пуст — 60 max_tokens ушли в thinking; статус важен) | **200**, content «ок» | 200 (xhigh принимается, не даётся потребителям) |
| (d2) `reasoning_effort: "low"` | **200**, content «ок» | **200**, content «ok» | 200 |

**Вывод:** гэп-профиль совпадает с selection-картой по всем пяти кейсам на обоих
размерах; поведение размеров неразличимо на уровне кодов ответов и текстов ошибок.

## Сырьё

Ответы сохранены в `/tmp/opencode/04-raw/gap-strata-iq{3,2}-*.json` (транспорт curl).
Сырые тела ключевых ответов:

```
[a, iq3]  tool_calls: [{"id":"call_40fb0934756347d4a61fcd17","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}}]
[a, iq2]  tool_calls: [{"id":"call_6135c09c7e0e4bf6b1a12279","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"\\u041f\\u0430\\u0440\\u0438\\u0436\"}"}}]
[b, оба]  {"error": "...structured response_format with tools/MCP is not supported"}
[c, оба]  {"error": "unknown reasoning effort 'banana': use none, low, medium or high"}
```
