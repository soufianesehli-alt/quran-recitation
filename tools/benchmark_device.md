# On-device ASR benchmark plan (executed in Phase 3)

Goal: pick the V1 ASR backend and model size with measured data, against spec targets
**live highlighting p95 ≤ 1 s** and **end-of-ayah checks p95 ≤ 2 s**.

## Devices
- **Reference mid-range device** (to be confirmed by product owner — `TODO`): e.g. a 2022–2024
  Android with 4–6 GB RAM, arm64. All go/no-go decisions use this device.
- One low-end device (3–4 GB RAM, Android 7/API 24 if available) to check the min-SDK floor.
- Emulator numbers are NOT used for decisions (no representative NPU/CPU behaviour).

## Candidates (each `TODO-VERIFY` licence before benchmarking, see docs/DATA_SOURCES.md)
| ID | Model | Runtime | Quantisation |
|---|---|---|---|
| W-tiny | tarteel-ai/whisper-tiny-ar-quran (if it exists) | whisper.cpp | q8_0, q5_1 |
| W-base | tarteel-ai/whisper-base-ar-quran | whisper.cpp | q8_0, q5_1 |
| W-base-ort | same | ONNX Runtime Mobile | int8 dynamic |
| W-small | Whisper small (Quran fine-tune if available) | whisper.cpp | q5_1 |
| C-ctc | small Arabic wav2vec2/CTC model (to be identified) | ONNX Runtime Mobile | int8 |

Conversion via `tools/convert_model.py` (Phase 3); record the exact source revision hash.

## Test material
- `eval/` dev split only (never the test split). Both riwayat, ≥ 3 reciters each, tempos
  tahqiq/tadwir/hadr, plus deliberate word errors (omission, substitution, repetition).
- Al-Fatiha + 20 ayahs of juzʾ ʿAmma minimum for Phase 3; full eval set in Phase 5.

## Metrics (per candidate × device × riwaya)
| Metric | How |
|---|---|
| Model file size (MB) | on disk, after quantisation |
| Peak RSS (MB) | `dumpsys meminfo` during a 60 s session |
| Cold load time (s) | `init()` wall-clock |
| Window latency p50/p95 (ms) | per 2–3 s window, audio-end → hypothesis |
| Highlight latency p95 (ms) | word spoken (from annotation) → `WordResultEvent` |
| End-of-ayah latency p95 (ms) | final pause → `AyahCompleteEvent` |
| WER on normalized text | vs annotated transcript |
| Word-error detection precision / recall | per error type, via the word aligner |
| Timestamp error (ms) | word boundary vs annotation (matters for madd) |
| Battery drain (%/10 min), thermal | 10-min continuous session |

Timings are logged as numbers only; no audio leaves the device or is written to disk
during benchmarking on the app side (eval audio is fed from the test harness).

## Decision rule
1. Discard any candidate failing p95 latency targets on the reference device.
2. Among the rest, maximise **word-error precision** (primary), then recall, then size.
3. If no Whisper candidate gives usable word timestamps, madd/ghunnah use C-ctc alignment
   even if Whisper is kept for word recognition.

Report: `tools/benchmark_results.md` (table per candidate + raw CSV, no audio).
