// sampling parameters
struct common_params_sampling {
    uint32_t seed = LLAMA_DEFAULT_SEED; // the seed used to initialize llama_sampler

    int32_t n_prev             = 64;     // number of previous tokens to remember
    int32_t n_probs            = 0;      // if greater than 0, output the probabilities of top n_probs tokens.
    int32_t min_keep           = 0;      // 0 = disabled, otherwise samplers should return at least min_keep tokens
    int32_t top_k              = 40;     // <= 0 to use vocab size
    float   top_p              = 0.95f;  // 1.0 = disabled
    float   min_p              = 0.05f;  // 0.0 = disabled
    float   xtc_probability    = 0.00f;  // 0.0 = disabled
    float   xtc_threshold      = 0.10f;  // > 0.5 disables XTC
    float   typ_p              = 1.00f;  // typical_p, 1.0 = disabled
    float   temp               = 0.80f;  // <= 0.0 to sample greedily, 0.0 to not output probabilities
    float   dynatemp_range     = 0.00f;  // 0.0 = disabled
    float   dynatemp_exponent  = 1.00f;  // controls how entropy maps to temperature in dynamic temperature sampler
    int32_t penalty_last_n     = 64;     // last n tokens to penalize (0 = disable penalty)
    float   penalty_repeat     = 1.00f;  // 1.0 = disabled
    float   penalty_freq       = 0.00f;  // 0.0 = disabled
    float   penalty_present    = 0.00f;  // 0.0 = disabled
