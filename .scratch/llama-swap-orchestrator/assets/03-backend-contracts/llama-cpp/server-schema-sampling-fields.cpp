
    add((new field_num("top_k", params.sampling.top_k))
        ->set_limits(0, INT32_MAX)
        ->set_desc("Limit the next token selection to the K most probable tokens (0 = disabled)"));

    add((new field_num("top_p", params.sampling.top_p))
        ->set_limits(0.0f, 1.0f)
        ->set_desc("Limit the next token selection to a subset of tokens with cumulative probability above threshold P (1.0 = disabled)"));

    add((new field_num("min_p", params.sampling.min_p))
        ->set_limits(0.0f, 1.0f)
        ->set_desc("The minimum probability for a token to be considered, relative to the probability of the most likely token (0 = disabled)"));

    add((new field_num("top_n_sigma", params.sampling.top_n_sigma))
        ->set_desc("Keep tokens within n standard deviations of the top token logit (< 0 = disabled)"));

    add((new field_num("xtc_probability", params.sampling.xtc_probability))
        ->set_limits(0.0f, 1.0f)
        ->set_desc("Set the chance for token removal via XTC sampler (0 = disabled)"));

    add((new field_num("xtc_threshold", params.sampling.xtc_threshold))
        ->set_limits(0.0f, 1.0f)
        ->set_desc("Set a minimum probability threshold for tokens to be removed via XTC sampler (> 0.5 disables XTC)"));

    add((new field_num("typical_p", params.sampling.typ_p))
        // ->set_limits(0.0f, 1.0f) // what's the valid range?
        ->set_desc("Enable locally typical sampling with parameter p (1.0 = disabled)"));

    add((new field_num("temperature", params.sampling.temp))
        ->set_limits(0.0f, std::numeric_limits<float>::infinity())
        ->set_desc("Adjust the randomness of the generated text (0 = greedy)"));

    add((new field_num("dynatemp_range", params.sampling.dynatemp_range))
        ->set_desc("Dynamic temperature range. The final temperature will be in [temperature - range, temperature + range] (0 = disabled)"));

    add((new field_num("dynatemp_exponent", params.sampling.dynatemp_exponent))
        ->set_desc("Dynamic temperature exponent, controls how entropy maps to temperature"));

    add((new field_num("repeat_last_n", params.sampling.penalty_last_n))
        ->set_hard_limits(0, INT32_MAX)
        ->set_desc("Last n tokens to consider for penalizing repetition (0 = disabled)"));

    add((new field_num("repeat_penalty", params.sampling.penalty_repeat))
        ->set_desc("Control the repetition of token sequences in the generated text (1.0 = disabled)"));

    add((new field_num("frequency_penalty", params.sampling.penalty_freq))
        ->set_desc("Repeat alpha frequency penalty (0 = disabled)"));

    add((new field_num("presence_penalty", params.sampling.penalty_present))
        ->set_desc("Repeat alpha presence penalty (0 = disabled)"));

    add((new field_num("dry_multiplier", params.sampling.dry_multiplier))
        ->set_desc("Set the DRY (Don't Repeat Yourself) repetition penalty multiplier (0 = disabled)"));

    add((new field_num("dry_base", params.sampling.dry_base))
        ->set_desc("Set the DRY repetition penalty base value (must be >= 1.0, any values < 1.0 will be replaced with the default value)")
        ->set_handler([&](field_eval_context & ctx, const json & data) {
            float v = data.at("dry_base").get<float>();
