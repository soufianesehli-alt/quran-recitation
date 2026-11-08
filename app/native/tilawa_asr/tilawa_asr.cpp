#include "tilawa_asr.h"

#include <string>
#include <vector>

#include "whisper.h"

namespace {
struct Token {
    std::string bytes;
    float p;
    int64_t t0_ms;
    int64_t t1_ms;
};

// Silences whisper.cpp logging: nothing about a session is written to logcat.
void quiet_log(enum ggml_log_level, const char *, void *) {}
}  // namespace

struct tilawa_asr {
    whisper_context * ctx = nullptr;
    std::vector<Token> tokens;
};

extern "C" tilawa_asr * tilawa_asr_init(const char * model_path) {
    whisper_log_set(quiet_log, nullptr);
    whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = false;
    whisper_context * ctx = whisper_init_from_file_with_params(model_path, cp);
    if (!ctx) return nullptr;
    auto * h = new tilawa_asr();
    h->ctx = ctx;
    return h;
}

extern "C" int tilawa_asr_transcribe(tilawa_asr * h, const float * samples, int n_samples,
                                     const char * initial_prompt, int n_threads, int audio_ctx,
                                     int beam_size) {
    if (!h || !h->ctx || !samples || n_samples <= 0) return -1;
    h->tokens.clear();

    const bool beam = beam_size > 1;
    whisper_full_params p = whisper_full_default_params(beam ? WHISPER_SAMPLING_BEAM_SEARCH
                                                             : WHISPER_SAMPLING_GREEDY);
    if (beam) p.beam_search.beam_size = beam_size;
    p.language = "ar";
    p.detect_language = false;
    p.translate = false;
    p.n_threads = n_threads > 0 ? n_threads : 4;
    p.no_context = true;        // each window is independent
    p.single_segment = true;    // short streaming windows
    p.token_timestamps = true;  // word timing for highlighting / madd windows
    p.audio_ctx = audio_ctx;
    p.initial_prompt = initial_prompt;
    p.suppress_blank = true;
    p.temperature = 0.0f;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_timestamps = false;
    p.print_special = false;

    if (whisper_full(h->ctx, p, samples, n_samples) != 0) return -1;

    const whisper_token eot = whisper_token_eot(h->ctx);
    const int n_seg = whisper_full_n_segments(h->ctx);
    for (int s = 0; s < n_seg; ++s) {
        const int n_tok = whisper_full_n_tokens(h->ctx, s);
        for (int t = 0; t < n_tok; ++t) {
            whisper_token_data d = whisper_full_get_token_data(h->ctx, s, t);
            if (d.id >= eot) continue;  // special / timestamp tokens
            const char * text = whisper_full_get_token_text(h->ctx, s, t);
            h->tokens.push_back({text ? text : "", d.p, d.t0 * 10, d.t1 * 10});
        }
    }
    return static_cast<int>(h->tokens.size());
}

extern "C" int tilawa_asr_token_bytes(tilawa_asr * h, int i, const char ** out_bytes) {
    if (!h || i < 0 || i >= static_cast<int>(h->tokens.size())) return -1;
    *out_bytes = h->tokens[i].bytes.data();
    return static_cast<int>(h->tokens[i].bytes.size());
}

extern "C" float tilawa_asr_token_p(tilawa_asr * h, int i) {
    return (h && i >= 0 && i < static_cast<int>(h->tokens.size())) ? h->tokens[i].p : 0.0f;
}

extern "C" int64_t tilawa_asr_token_t0_ms(tilawa_asr * h, int i) {
    return (h && i >= 0 && i < static_cast<int>(h->tokens.size())) ? h->tokens[i].t0_ms : -1;
}

extern "C" int64_t tilawa_asr_token_t1_ms(tilawa_asr * h, int i) {
    return (h && i >= 0 && i < static_cast<int>(h->tokens.size())) ? h->tokens[i].t1_ms : -1;
}

extern "C" void tilawa_asr_free(tilawa_asr * h) {
    if (!h) return;
    if (h->ctx) whisper_free(h->ctx);
    delete h;
}
