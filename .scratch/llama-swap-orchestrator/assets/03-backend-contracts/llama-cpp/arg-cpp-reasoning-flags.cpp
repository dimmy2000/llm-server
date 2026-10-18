            auto parsed = json::parse(value);
            for (const auto & item : parsed.items()) {
                if (item.key() == "enable_thinking") {
                    LOG_WRN("Setting 'enable_thinking' via --chat-template-kwargs is deprecated. "
                            "Use --reasoning on / --reasoning off instead.\n");
                }
                if (item.key() == "preserve_reasoning") {
                    LOG_WRN("Setting 'preserve_reasoning' via --chat-template-kwargs is deprecated. "
                            "Use --reasoning-preserve / --no-reasoning-preserve instead.\n");
                }
                params.default_template_kwargs[item.key()] = item.value().dump();

---
        {"--reasoning-format"}, "FORMAT",
        "controls whether thought tags are allowed and/or extracted from the response, and in which format they're returned; one of:\n"
        "- none: leaves thoughts unparsed in `message.content`\n"
        "- deepseek: puts thoughts in `message.reasoning_content`\n"
        "- deepseek-legacy: keeps `<think>` tags in `message.content` while also populating `message.reasoning_content`\n"
        "(default: auto)",
        [](common_params & params, const std::string & value) {
            params.reasoning_format = common_reasoning_format_from_name(value);
        }
    ).set_examples({LLAMA_EXAMPLE_SERVER, LLAMA_EXAMPLE_COMPLETION, LLAMA_EXAMPLE_CLI}).set_env("LLAMA_ARG_THINK"));
    add_opt(common_arg(
        {"-rea", "--reasoning"}, "[on|off|auto]",
        "Use reasoning/thinking in the chat ('on', 'off', or 'auto', default: 'auto' (detect from template))",
        [](common_params & params, const std::string & value) {
            if (is_truthy(value)) {
                params.enable_reasoning = 1;
                params.default_template_kwargs["enable_thinking"] = "true";
            } else if (is_falsey(value)) {
                params.enable_reasoning = 0;
                params.default_template_kwargs["enable_thinking"] = "false";
            } else if (is_autoy(value)) {
                params.enable_reasoning = -1;
            } else {
                throw std::invalid_argument(
                    string_format("error: unknown value for --reasoning: '%s'\n", value.c_str()));
            }
        }
    ).set_examples({LLAMA_EXAMPLE_SERVER, LLAMA_EXAMPLE_COMPLETION, LLAMA_EXAMPLE_CLI}).set_env("LLAMA_ARG_REASONING"));
    add_opt(common_arg(
        {"--reasoning-effort"}, "LEVEL",
        "reasoning effort level given to the chat template: 'default' to keep the template default,\n"
        "or a level such as 'minimal', 'low', 'medium', 'high', 'xhigh' or 'max' (default: default)",
        [](common_params & params, const std::string & value) {
            if (value == "default") {
                params.default_template_kwargs.erase("reasoning_effort");
            } else {
                params.default_template_kwargs["reasoning_effort"] = json(value).dump();
            }
        }
    ).set_examples({LLAMA_EXAMPLE_SERVER, LLAMA_EXAMPLE_COMPLETION, LLAMA_EXAMPLE_CLI}).set_env("LLAMA_ARG_REASONING_EFFORT"));
    add_opt(common_arg(
        {"--reasoning-budget"}, "N",
        "token budget for thinking: -1 for unrestricted, 0 for immediate end, N>0 for token budget (default: -1)",
        [](common_params & params, int value) {
            if (value < -1) { throw std::invalid_argument("invalid value"); }
            params.sampling.reasoning_budget_tokens = value;
        }
    ).set_examples({LLAMA_EXAMPLE_SERVER, LLAMA_EXAMPLE_COMPLETION, LLAMA_EXAMPLE_CLI}).set_env("LLAMA_ARG_THINK_BUDGET"));
    add_opt(common_arg(
        {"--reasoning-budget-message"}, "MESSAGE",
