
    // messages_override is already built for this template, do not touch its content parts
    json inp = json{
        {"messages", messages_override.has_value()
            ? *messages_override
            : messages_inp_normalizer(tmpl.original_caps()).normalize(inputs.messages)},
        {"bos_token", tmpl.bos_token()},
        {"eos_token", tmpl.eos_token()},
        {"enable_thinking", inputs.enable_thinking},
    };
    if (tools_override.has_value() || !inputs.tools.empty()) {
        inp["tools"] = tools_override.has_value() ? *tools_override : inputs.tools;
    }
    if (inputs.extra_context.is_object()) {
        // TODO: do we need to merge, or replacing is fine?
        for (const auto & [k, v] : inputs.extra_context.items()) {
            inp[k] = v;
        }
    }
    if (additional_context.has_value()) {
        // TODO: merge properly instead of overwriting (matching old behavior)
        for (const auto & [k, v] : additional_context->items()) {
            inp[k] = v;
        }
    }
    if (inputs.add_generation_prompt) {
        inp["add_generation_prompt"] = true;
    }
    if (inp.contains("preserve_reasoning") && inp["preserve_reasoning"].is_boolean()) {
        bool enabled = inp["preserve_reasoning"].get<bool>();
        jinja::caps_apply_preserve_reasoning(ctx, enabled);
    }
    if (inp.contains("reasoning_effort") && inp["reasoning_effort"].is_string() && !inp["reasoning_effort"].empty()) {
        std::string reasoning_effort = inp["reasoning_effort"].get<std::string>();
        jinja::caps_apply_reasoning_effort(ctx, reasoning_effort);
    }

    jinja::global_from_json(ctx, inp, inputs.mark_input);

