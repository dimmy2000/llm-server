        && !inputs.messages.back().tool_calls.empty()) {
        throw std::invalid_argument("Cannot continue an assistant message that contains tool calls.");
    }
    inputs.reasoning_format = opt.reasoning_format;
    if (body.contains("reasoning_format")) {
        inputs.reasoning_format = common_reasoning_format_from_name(body.at("reasoning_format").get<std::string>());
    }
    inputs.enable_thinking = opt.enable_thinking;
    if (!inputs.tools.empty() && inputs.tool_choice != COMMON_CHAT_TOOL_CHOICE_NONE) {
        if (body.contains("grammar")) {
            throw std::invalid_argument("Cannot use custom grammar constraints with tools.");
        }
    }

    // merge the template args provided from command line with the args provided in the user request
    auto chat_template_kwargs_object = json_value(body, "chat_template_kwargs", json::object());
    inputs.chat_template_kwargs = opt.chat_template_kwargs;
    for (const auto & item : chat_template_kwargs_object.items()) {
        inputs.chat_template_kwargs[item.key()] = item.value().dump();
    }

    // parse the "enable_thinking" kwarg to override the default value
    auto enable_thinking_kwarg = json_value(inputs.chat_template_kwargs, "enable_thinking", std::string(""));
    if (enable_thinking_kwarg == "true") {
        inputs.enable_thinking = true;
    } else if (enable_thinking_kwarg == "false") {
        inputs.enable_thinking = false;
    } else if (!enable_thinking_kwarg.empty() && enable_thinking_kwarg[0] == '"') {
        throw std::invalid_argument("invalid type for \"enable_thinking\" (expected boolean, got string)");
    }

    // Parse the OAI "reasoning_effort" field; "none" disables reasoning.
    if (body.contains("reasoning_effort")) {
        auto reasoning_effort = json_value(body, "reasoning_effort", std::string(""));
        if (reasoning_effort == "none") {
            inputs.enable_thinking = false;
            inputs.chat_template_kwargs.erase("reasoning_effort");
        } else if (!reasoning_effort.empty()) {
            inputs.chat_template_kwargs["reasoning_effort"] = json(reasoning_effort).dump();
        }
    }

    inputs.force_pure_content = opt.force_pure_content;

    // Apply chat template to the list of messages
    common_chat_session_params session_params;
    session_params.echo = json_value(body, "echo", false);
    out_session = common_chat_session(opt.tmpls.get(), vocab, inputs, session_params);

    llama_params["prompt"] = out_session.prompt().str();

    // Reasoning budget: pass parameters through to sampling layer
    {
        int reasoning_budget = json_value(body, "reasoning_budget_tokens",
                               json_value(body, "thinking_budget_tokens", -1));
        if (reasoning_budget == -1) {
            reasoning_budget = opt.reasoning_budget;
        }

        if (!out_session.thinking_end_tags().empty()) {
            llama_params["reasoning_budget_tokens"] = reasoning_budget;
            llama_params["reasoning_budget_start_tag"] = out_session.thinking_start_tag();
            llama_params["reasoning_budget_end_tags"] = out_session.thinking_end_tags();
            llama_params["reasoning_budget_message"] = json_value(body, "reasoning_budget_message", opt.reasoning_budget_message);
            llama_params["reasoning_control"] = json_value(body, "reasoning_control", false);
        }
    }

    // Handle "logprobs" field
    // TODO: The response format of this option is not yet OAI-compatible, but seems like no one really using it; We may need to fix it in the future
    if (json_value(body, "logprobs", false)) {
        if (has_tools && stream) {
            throw std::invalid_argument("logprobs is not supported with tools + stream");
        }
        llama_params["n_probs"] = json_value(body, "top_logprobs", 20);
    } else if (body.contains("top_logprobs") && !body.at("top_logprobs").is_null()) {
        throw std::invalid_argument("top_logprobs requires logprobs to be set to true");
    }

    // Copy remaining properties to llama_params
    // This allows user to use llama.cpp-specific params like "mirostat", ... via OAI endpoint.
    // See "launch_slot_with_task()" for a complete list of params supported by llama.cpp
    for (const auto & item : body.items()) {
        // Exception: if "n_predict" is present, we overwrite the value specified earlier by "max_tokens"
        if (!llama_params.contains(item.key()) || item.key() == "n_predict") {
            llama_params[item.key()] = item.value();
        }
    }

    // the session owns these, the server applies them with server_task::apply_chat_session()
    for (const char * key : { "grammar_lazy", "grammar_triggers", "preserved_tokens" }) {
