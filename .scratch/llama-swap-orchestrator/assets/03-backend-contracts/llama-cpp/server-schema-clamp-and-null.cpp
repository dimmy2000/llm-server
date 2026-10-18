//

static void handle_with_catch(const char * name, std::function<void()> func) {
    try {
        func();
    } catch (const std::exception & e) {
        throw std::invalid_argument(string_format("Field '%s': %s", name, e.what()));
    }
}

// treat a null value as absent so clients can send null to request the server default
static bool has_value(const json & data, const char * n) {
    return data.contains(n) && !data.at(n).is_null();
}

template <typename T>
void field_num<T>::eval(field_eval_context & ctx, const json & data) {
    for (const auto & n : name) {
        if (has_value(data, n)) {
            handle_with_catch(n, [&]() {
                if (custom_handler) {
                custom_handler(ctx, data);
                } else if (!is_hard_limit) {
                    val = std::max(min, std::min(max, data.at(n).template get<T>()));
                } else {
                    T tmp = data.at(n).template get<T>();
                    if (tmp < min || tmp > max) {
                        throw std::invalid_argument(std::string("Value must be between ") + std::to_string(min) + " <= value <= " + std::to_string(max) + ", but got " + std::to_string(tmp));
                    }
                    val = tmp;
                }
            });
            return;
