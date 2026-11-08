// Thin C API over whisper.cpp for the Flutter app (Dart FFI). Audio is passed in memory only
// and never written anywhere (docs/SPEC.md §1).
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct tilawa_asr tilawa_asr;

// Loads a ggml model file. Returns NULL on failure.
tilawa_asr * tilawa_asr_init(const char * model_path);

// Transcribes `n_samples` mono float32 samples at 16 kHz, biased with `initial_prompt`
// (the expected text; may be NULL). `audio_ctx` = 0 for the model default, or a smaller
// encoder context for short windows (faster). `beam_size` <= 1 = greedy decoding, otherwise
// beam search (slower, more robust). Returns the number of text tokens, or -1.
int tilawa_asr_transcribe(tilawa_asr * h, const float * samples, int n_samples,
                          const char * initial_prompt, int n_threads, int audio_ctx,
                          int beam_size);

// Token accessors for the last transcription (0 <= i < count).
int     tilawa_asr_token_bytes(tilawa_asr * h, int i, const char ** out_bytes);
float   tilawa_asr_token_p(tilawa_asr * h, int i);
int64_t tilawa_asr_token_t0_ms(tilawa_asr * h, int i);
int64_t tilawa_asr_token_t1_ms(tilawa_asr * h, int i);

void tilawa_asr_free(tilawa_asr * h);

#ifdef __cplusplus
}
#endif
