# Architecture

Companion to `docs/SPEC.md`. If the two disagree, the spec wins; record the disagreement in
`CHANGELOG.md`.

## 1. Repository layout

```
/                      FastAPI backend (main.py, Procfile). Stays at the root for now; see AUDIT §4.
app/                   Flutter Android app (package `tilawa`, applicationId com.almathaba.tilawa*)
docs/                  SPEC, AUDIT, ARCHITECTURE, DATA_SOURCES, (Phase 4) RULES_REVIEW
tools/                 build_quran_db.py (P2), convert_model.py (P3), benchmark_device.md,
                       check_release_manifest.sh
eval/                  evaluation set layout and scripts (P5). Audio is never committed.
training/              README only in V1 (§9). The real pipeline lives in a separate private repo.
```
\* The applicationId is provisional. It is final once published on the Play Store.

## 2. App layers

```
features/  (selection, recitation, feedback, settings, debug)      ← Flutter widgets + Riverpod
   │ watches
   ▼
session controller  ── uses ──►  AyahGate (domain policy, pure Dart)
   │ start/stop
   ▼
engine/RecitationEngine  ◄── OfflineEngine (V1) | OnlineEngine (V2, same interface)
   │                              │
   │                              ├─ audio_stream → ring buffer (memory only)
   │                              ├─ vad
   │                              ├─ AsrBackend (whisper.cpp | ONNX Runtime) via FFI, in an isolate
   │                              ├─ word_aligner
   │                              └─ tajweed/rule_engine (madd, ghunnah …) ← phonetizer + rules YAML
   ▼
data/  quran_repository (SQLite per riwaya), rules_repository (YAML), settings/progress store
```

Dependencies only point downward. `domain/` imports nothing from Flutter, so the gate, the
aligner and the phonetizer can be tested as plain Dart.

**Implemented in Phase 1:** `domain/models/*`, `domain/ayah_gate.dart`,
`engine/recitation_engine.dart`, `engine/live_event.dart`, `engine/engine_capabilities.dart`,
an `OfflineEngine` skeleton, the `OnlineEngine` V2 stub, the Arabic RTL app shell, and the
Android permissions.

## 3. Engine contract

```dart
abstract class RecitationEngine {
  Future<void> init(Riwaya riwaya);
  Stream<LiveEvent> start(AyahRef ayah);
  Future<void> stop();
  EngineCapabilities get capabilities;
}
```

- `LiveEvent` is a sealed class: `CurrentWordEvent`, `WordResultEvent`, `FindingEvent`,
  `AyahCompleteEvent(findings)` and `EngineErrorEvent(messageAr)`.
- `AyahRef` always carries its `Riwaya`, because `1:1` is the basmala in Hafs but not in Warsh
  (Madani count).
- `EngineCapabilities` has three fields:
  - `families`: which result types the UI may show.
  - `usesNetwork`: must be `false` for anything that ships in V1.
  - `acousticallyValidated`: the riwayat whose acoustic findings may be shown as `error`. Any
    acoustic finding for another riwaya is forced to `needsReview`. In V1 this set is empty, so
    every madd and ghunnah result is a warning. That is what spec §2 asks for Warsh, and Hafs
    gets the same treatment until §8 validation is done.
- V2 adds `OnlineEngine` behind the same interface. A `HybridEngine` decorator does the online
  call with offline fallback. No caller changes.

## 4. Offline pipeline (Phase 3 and 4)

| Step | Component | Notes |
|---|---|---|
| 1 | `audio_stream.dart` | 16 kHz mono PCM16 in 200–500 ms chunks, using a **streaming** recorder API (never record-to-file). The ring buffer is about 30 s, overwritten in place, and zeroed on `stop()`. Plugin choice is `TODO-VERIFY` in Phase 3: it must support PCM streaming without a temp file. |
| 2 | `vad.dart` | Starts as energy + zero-crossing VAD (no model, deterministic, testable). Silero VAD (ONNX) is an optional upgrade, `TODO-VERIFY` license. Pauses of at least X ms are waqf candidates; X is tuned in Phase 5. |
| 3 | `asr_native.dart` → `AsrBackend` | Runs in a background isolate. Rolling 2–3 s windows with about 0.5 s overlap. **Constrained to the expected ayah**, see §4.1. |
| 4 | `word_aligner.dart` | Word-level Needleman-Wunsch on normalized text. The substitution cost is the character edit distance normalized to [0, 1]. Repetition is detected as an insertion equal to a neighbouring expected word. Output is a status per word plus a confidence. |
| 5 | `tajweed/` + checkers | At waqf or ayah end. Madd: measured vowel duration ÷ the reciter's own haraka unit (median short-vowel length in the same segment), compared with the phonetizer's expected harakat for this riwaya and the user's wajh setting. Ghunnah: duration plus a nasal-energy proxy. |
| 6 | Findings | `Finding` exactly as §5.6 of the spec, plus `ruleIsBlocking`, copied from the rule YAML. |

### 4.1 "Constrained" ASR: two candidate strategies, both benchmarked in Phase 3
- **A. Biased Whisper.** Whisper with the expected ayah as the initial prompt (and optionally
  logit bias toward the expected tokens), then alignment of the hypothesis. Main risk: prompting
  can make the model *output the expected words even when the reciter skipped them*. That gives
  missed errors, which is the safer direction under ground rule 5, but it still has to be
  measured.
- **B. CTC forced alignment / verification.** A CTC model scores the expected token sequence
  against the audio. Low-scoring spans are suspects, and a free decode over that span says what
  was actually read. This gives native timestamps, which madd needs, and per-word scores
  (GOP-like).
- The aligner and the rule engine only see `(word, startMs, endMs, score)`, so the backend can be
  swapped behind `AsrBackend` without touching the UI. The choice is made on benchmark data
  (`tools/benchmark_device.md`).

### 4.2 Confidence → severity (initial values, tuned in Phase 5)

| Condition | Severity |
|---|---|
| Word-level deviation, confidence ≥ 0.90 and rule validated (`blocking: true`) | `error`, **blocks** |
| Word-level deviation, confidence ≥ 0.90, rule not yet validated | `error`, shown red, does **not** block |
| Any deviation with confidence < 0.90 | `needsReview` (orange, «مراجعة») |
| Any acoustic finding for a riwaya not in `acousticallyValidated` | `needsReview` |

In the current code the gate threshold (0.90) is a constructor parameter of `AyahGate`. It moves
to settings in Phase 3.

## 4.3 Quran data (Phase 2)

One SQLite file per riwaya (`app/assets/quran/{riwaya}.sqlite`), schema v1:

| Table | Columns |
|---|---|
| `meta` | key/value: riwaya, numbering, source, source_url, version, license, copyright_notice, source_sha256, counts |
| `surahs` | surah, name_ar, ayah_count |
| `ayahs` | surah, ayah, text_uthmani (verbatim), basmala_prefix_chars |
| `words` | surah, ayah, word_index, uthmani (verbatim substring), normalized (matching key), waqf_mark (sign or signs, in order) |

`QuranRepository.openBundled` copies the asset to the app's DB directory once, then opens it
read-only. The Python and Dart normalizers are kept identical by shared vectors and by a check
over every word in the DB.

## 5. Gating and session state machine

```
idle ─start─► listening ─ayahComplete─► evaluating
                 ▲                         │ gate.canAdvance?
                 │ re-recite segment       ├─ yes ─► unlocked ─next─► listening(next ayah)
                 └─────────────────────────┤
                                           └─ no ─► failed(attempt++)
                                                     └─ attempts ≥ N ─► offer «متابعة على أي حال»
```
- Re-recitation starts at the waqf segment that contains the first blocking finding (setting:
  segment or full ayah).
- Session state lives in memory. Only progress per surah (last unlocked ayah per riwaya) is
  saved. No audio and no transcripts.

## 6. Privacy and offline guarantees and how each is enforced

| Guarantee | Enforcement |
|---|---|
| No `INTERNET` in V1 release | `src/release/AndroidManifest.xml` removes it (`tools:node="remove"`). `test/manifest_test.dart` checks the source manifests. `tools/check_release_manifest.sh` checks the **built** APK; it runs in CI from Phase 3. |
| Only `RECORD_AUDIO` | Same test and script. |
| No audio on disk | Streaming recorder only. Planned lint test (Phase 3) fails if `engine/offline/**` imports `dart:io` file APIs or `path_provider`. |
| No audio in logs | The metrics logger takes numbers only (`Map<String, num>`), so no buffer can be passed to it. |
| No reciter audio in the app | The `.gitignore` blocks audio extensions. The asset list is reviewed in the Phase 6 release check. |

## 7. Riwaya-awareness

Everything riwaya-specific is selected by `Riwaya`:
- the DB file `assets/quran/{hafs,warsh}.sqlite`;
- the font;
- the rules `assets/rules/{hafs,warsh}.yaml` plus `common.yaml`;
- the phonetizer layer `common + {hafs|warsh}`;
- duration norms.

The acoustic model is shared.

## 8. Product-owner decisions (2026-11-08)

| # | Question | Decision |
|---|---|---|
| 1 | Existing Flutter frontend? | None exists. Build fresh in `app/`. |
| 2 | Committed `.env`, `venv/`, `__pycache__/` | Untracked (commit 4650266). The owner rotates the Anthropic key and sets `ANTHROPIC_API_KEY` in Render **before merging**. |
| 3a | Access to official text and fonts | Personal cloud environment "quran-recitation" allows tanzil.net and the qurancomplex.gov.sa hosts. Tanzil works. The KFGQPC servers reject this cloud (fallback: owner downloads the files). |
| 3b | KFGQPC terms | Build now. The owner requests written permission in parallel. No Play Store release until the terms are clear. |
| 4a | Target devices | **All Android phones, Android 7.0+ (API 24), arm64-v8a, armeabi-v7a and x86_64.** Device tiers (low, mid, high) with a model per tier and a degraded per-segment mode when live latency can't be met. The app never refuses to run. Test phone: Samsung Galaxy S25 FE (high tier). See `tools/benchmark_device.md`. |
| 4b | Muqriʾ reviewer | None yet. All rules stay `review_status: pending` and warning-only until approved. |
| 5 | Android application id | `com.almathaba.tilawa` stays provisional. Final id to be decided before Phase 6 (first signed release). |
