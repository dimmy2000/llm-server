# ADR-0002: Публичные model-ID qwen3.8 переименованы без backcompat-алиасов

Status: accepted.

В llama-профиле режимы qwen3.8-27b реструктурированы: голый ключ
`qwen3.8-27b` стал instruct-режимом, алиас `qwen3.8` удалён, вместо
`-chat`/`-agent-code`/`-agent-plan` появились шесть режимов
`-chat-{low,medium,xhigh}` и `-agent-{low,medium,xhigh}` (chat скрывает
thinking, agent возвращает; внутри типа режимы различаются только
`reasoning_effort`). Старые ID удалены без backcompat-алиасов, чтобы не
мусорить в `/v1/models`; откат тривиален (одна секция конфига). Миграция
внешних потребителей (llm-monitoring) — отдельный процесс вне этого
репозитория.
