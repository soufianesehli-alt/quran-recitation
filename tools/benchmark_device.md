# On-device ASR benchmark plan (executed in Phase 3)

Goal: pick the V1 ASR backend and model size with measured data, against spec targets
**live highlighting p95 ≤ 1 s** and **end-of-ayah checks p95 ≤ 2 s**.

## Devices: "all Android phones" (product-owner decision, 2026-11-08)
The app must run on **every Android phone with Android 7.0+ (API 24)**, on the three ABIs the
APK already ships (arm64-v8a, armeabi-v7a, x86_64). There is no single reference device.
Decisions are made **per device tier**, and the app picks its tier at runtime.

| Tier | Typical hardware | ASR model | Live mode |
|---|---|---|---|
| **Low** | ≤ 3 GB RAM, 32-bit (armeabi-v7a) or 4 × Cortex-A53, Android 7–9 | smallest candidate (tiny-class, int8) | Word follow per waqf segment (results after each pause) when live latency can't be met |
| **Mid** | 4–6 GB RAM, arm64, A55/A7x-class cores | base-class int8 | Live word highlighting |
| **High** | ≥ 8 GB RAM, recent arm64 | best candidate meeting the latency target | Live highlighting, end-of-ayah checks |

Rules:
- **The app never refuses to run.** If a phone can't meet the live target, it degrades to
  checking per segment (after each pause) instead of live, and says so in Arabic. Checks are
  never silently weakened.
- The tier comes from total RAM and ABI, read through a platform channel (`ActivityManager`
  memory info, `Build.SUPPORTED_ABIS`), plus a timed self-test of the first ASR window on first
  launch. The result is cached. The user can override it in settings.
- Native ASR libraries must be built for all three ABIs (`TODO-VERIFY` for each runtime
  candidate: whisper.cpp builds for armeabi-v7a; ONNX Runtime Android AAR ABI list).
- APK size: ship as an Android App Bundle (one ABI per device) and keep large models as
  install-time asset packs per tier. Nothing is downloaded at runtime in V1 (still no INTERNET).

Test devices:
- **Real phones decide**, one per tier at minimum.
  - **High tier: Samsung Galaxy S25 FE** (product owner's phone). Expected Exynos 2400 and 8 GB
    RAM; `TODO-VERIFY` on the device (Settings → About phone), and the app's tier probe will log
    it too.
  - **High tier: Samsung Galaxy S22 Ultra** (first phone actually tested; 8 or 12 GB RAM,
    Snapdragon 8 Gen 1 or Exynos 2200 depending on region, `TODO-VERIFY` via the diagnostics
    screen).
  - **Mid and low tiers: no device yet.** Low-tier latency is the riskiest number, so a cheap
    used Android 7–9 phone with 2–3 GB RAM would be the most valuable addition.
- Emulators (API 24, 28, 34; x86_64) cover functional, UI and RTL tests only. They are not
  used for latency decisions.
- A cloud device lab (e.g. Firebase Test Lab) would cover many real phones, but it is a paid
  service. **Needs the product owner's approval before use.**

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
1. Per tier: discard any candidate that fails the p95 latency targets on that tier's real phone.
2. Among the rest, maximise **word-error precision** (primary), then recall, then size.
3. If no Whisper candidate gives usable word timestamps, madd/ghunnah use C-ctc alignment
   even if Whisper is kept for word recognition.

Report: `tools/benchmark_results.md` (table per candidate + raw CSV, no audio).
