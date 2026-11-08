# PROJECT SPEC — تطبيق تصحيح التلاوة (Quran Recitation Correction App)
# Riwayat: ورش عن نافع (Warsh ʿan Nāfiʿ — Azraq route) & حفص عن عاصم (Hafs ʿan ʿĀṣim)

> Single source of truth for this project. Saved verbatim from the product owner's brief
> (2026-11-08). Any change to this file must be approved by the product owner and noted in
> `CHANGELOG.md`.

You are the lead engineer on this project. Read this whole spec before doing anything.
Save it in the repo as `docs/SPEC.md` and treat it as the single source of truth.

---

## 0. GROUND RULES (non-negotiable)

1. **Existing project**: a FastAPI backend (deployed at https://quran-recitation.onrender.com,
   endpoint `/check` with surah/ayah/riwaya/transcribed_text) and a Flutter frontend already exist.
   FIRST explore the repo, summarize what exists, list what is reusable. Never break `/check`.
2. **Work in phases** (§10). At the end of each phase: run the tests, commit, and report
   (done / not done / known limits / next step). **STOP after Phase 1 for my validation.**
3. **Ask before anything irreversible**: deleting files, force-push, paid APIs/keys,
   deployment, Play Store publishing.
4. **Never invent**: Quranic text, a Tajweed rule, a dataset, a model name, a license.
   Anything unverified is marked `TODO-VERIFY` and reported to me.
5. **Religious accuracy first**: a false correction is worse than a missed error.
   Low confidence ⇒ "needs review" (مراجعة), never an assertive correction.
6. Code and comments in English; ALL user-facing text in Arabic (RTL).

---

## 1. PRODUCT CONCEPT

- Android app (Flutter, min SDK 24), full Arabic UI, RTL, Uthmani script per riwaya.
- The user chooses a riwaya (Hafs or Warsh), a surah and a starting ayah, then recites.
- **Real-time correction**: the app listens, follows the recitation word by word, and
  highlights errors live. Below the error: the rule name + a short explanation in Arabic.
- **Ayah gating**: the next ayah unlocks ONLY after the current ayah is recited without
  high-confidence errors.
- **Nothing is recorded or stored**: audio is processed in memory and discarded immediately.
  No audio file, no audio in logs, ever.
- **No reciter audio in the app**: reciter recordings are used only to train models offline;
  they are never bundled, served or played in the app. Feedback is TEXT only.
- **Delivery strategy**: V1 = 100% offline (zero network calls). V2 = hybrid, with an in-app
  switch for online analysis (OFF by default).

---

## 2. V1 SCOPE (build now) — 100% OFFLINE

| Feature | V1 behaviour |
|---|---|
| Word errors: omission, addition, substitution, repeated word, skipped ayah | Detected, can block |
| Madd duration (per riwaya) | Detected; warning-only until validated (§8) |
| Ghunnah (presence/duration) | Warning-only |
| Qalqalah, waqf | Warning-only (if feasible in V1) |
| Fine makharij & sifat (ض/د, ظ/ذ, ح/ه, ص/س, tafkhim/tarqiq, taqlil/imala) | NOT in V1 → V2 online |
| Warsh | Supported in text/rules; acoustic results flagged needs_review until a Warsh-trained model exists |

Out of scope for V1: server calls, accounts, analytics, cloud sync.

---

## 3. DATA LAYER (bundled in the app)

- **Quran text**: separate Uthmani text per riwaya (rasm and diacritics differ between Hafs and Warsh).
  Candidates: Tanzil (Hafs), KFGQPC / Mushaf Al-Madina digital editions (Hafs & Warsh) → `TODO-VERIFY` licenses.
  Respect source terms (e.g. attribution, no text modification).
- Build script `tools/build_quran_db.py` → SQLite per riwaya:
  `words(surah, ayah, word_index, uthmani, normalized, waqf_mark)`,
  `ayahs(surah, ayah, text_uthmani)`, `meta(source, version, license)`.
- **Fonts**: KFGQPC Uthmanic Hafs & Warsh fonts (`TODO-VERIFY` license).
- **Rules**: `assets/rules/hafs.yaml`, `assets/rules/warsh.yaml` (§6), versioned.
- Validate integrity: 114 surahs, ayah counts per riwaya (counts differ between Hafs/Kufan and Warsh/Madani numbering — handle both).

---

## 4. FLUTTER ARCHITECTURE

```
app/
  lib/
    main.dart
    app/                     # router, theme (RTL, Uthmani fonts), DI (Riverpod)
    core/
      l10n/                  # ARB Arabic strings
      arabic/normalizer.dart # strip tashkeel for matching, unify alef/hamza/ya/ta marbuta
    domain/
      models/                # Riwaya, Surah, Ayah, Word, Finding, Severity, SessionState
    data/
      quran_repository.dart  # SQLite access per riwaya
      rules_repository.dart  # YAML loader
    engine/
      recitation_engine.dart # ABSTRACT interface (see §5) — designed for V2 from day one
      offline/
        offline_engine.dart
        audio_stream.dart    # mic → 16 kHz mono PCM chunks (200–500 ms), in memory only
        vad.dart             # voice activity / pause detection (waqf endpoint)
        asr_native.dart      # FFI/platform channel to whisper.cpp or ONNX Runtime Mobile
        word_aligner.dart    # hypothesis vs expected ayah (Needleman-Wunsch / Levenshtein)
        madd_checker.dart
        ghunnah_checker.dart
      online/
        online_engine.dart   # V2 stub only (throws UnimplementedError in V1)
    tajweed/
      phonetizer/            # text → expected phonemes + rule tags (common, hafs, warsh)
      rule_engine.dart
    features/
      selection/             # riwaya, surah, starting ayah
      recitation/            # live screen: mushaf line, current word, highlighting, mic
      feedback/              # bottom sheet: word, rule (Arabic), expected vs observed, explanation
      settings/              # riwaya, madd options (wujuh), thresholds, re-recite mode, max attempts
      debug/                 # DEV BUILDS ONLY: confidence scores, timings, raw hypothesis
  assets/ quran/ fonts/ rules/ models/
  test/
tools/                       # Python: build_quran_db.py, convert_model.py, benchmark_device.md
training/                    # LATER (separate, private, never shipped) — see §9
backend/                     # existing FastAPI — untouched in V1
```

- State: Riverpod. Persistence (settings, progress per surah, NO audio): Hive or SQLite.
- Permissions: RECORD_AUDIO only. Manifest must NOT request INTERNET in V1 release builds
  (verify the release manifest; add a test/CI check).

---

## 5. ENGINE INTERFACE & PIPELINE

```dart
abstract class RecitationEngine {
  Future<void> init(Riwaya riwaya);
  Stream<LiveEvent> start(AyahRef ayah);   // currentWord, wordResult, finding, ayahComplete
  Future<void> stop();
  EngineCapabilities get capabilities;     // which rule families this engine supports
}
```
V1 = `OfflineEngine`. V2 adds `OnlineEngine` behind the same interface, without refactoring.

**Offline pipeline (per ayah):**
1. Mic stream → PCM chunks in a ring buffer (memory only).
2. VAD detects speech and pauses (waqf endpoints).
3. ASR on rolling windows (pseudo-streaming, ~2–3 s windows with overlap), **constrained to
   the expected ayah** (prompt/bias with the expected text; we verify, we don't do open ASR).
   Candidate model: Quran-fine-tuned small Whisper (e.g. `tarteel-ai/whisper-base-ar-quran`
   → `TODO-VERIFY` availability/license), converted int8 via whisper.cpp or ONNX Runtime Mobile.
   Also evaluate a small Arabic CTC model (wav2vec2-type) if it gives better streaming/timestamps.
   Benchmark tiny/base/small on a reference mid-range Android device: size, RAM, latency, accuracy.
4. Word alignment on normalized Arabic → word status: correct / omitted / added / substituted / repeated.
5. At each waqf/ayah end: madd & ghunnah checks on the aligned word time windows,
   using the reciter's own haraka unit (estimated from short vowels in the same segment) and
   the riwaya's expected harakat from the phonetizer.
6. Findings → `Finding{wordIndex, word, errorType, ruleId, ruleNameAr, expected, observed,
   severity, confidence, startMs, endMs, messageAr}`.

Latency targets: live word highlighting p95 ≤ 1 s; end-of-ayah checks p95 ≤ 2 s.
Log timings as metrics only (never audio).

---

## 6. TAJWEED RULES ENGINE (riwaya-aware)

Each rule = YAML entry + Dart module: `id, name_ar, riwayat[], text_detection (phonetizer),
acoustic_check (if any), expected_value, explanation_ar, blocking: false|true, tests`.
Rules YAML must be readable by a qualified muqriʾ who will review and approve it.
Allowed variants (wujuh) are USER SETTINGS, never hard-coded.

**Common**: noon sakinah/tanween (izhar, idgham with/without ghunnah, iqlab, ikhfa), meem sakinah,
ghunnah on mushaddad noon/meem, qalqalah, madd tabiʿi (2), madd lazim (6),
lam shamsiyya/qamariyya, tafkhim of istiʿla letters.

**Hafs**: muttasil 4–5 / munfasil 4–5 (setting), ʿarid lil-sukun 2/4/6, single imala (مَجْرٰىهَا),
saktat (عِوَجًا، مَرْقَدِنَا، مَنْ رَاقٍ، بَلْ رَانَ), tas-hil (ءَأَعْجَمِيٌّ), ishmam (تَأْمَنَّا).

**Warsh (Azraq)**: muttasil & munfasil 6, madd al-badal 2/4/6 (setting), madd al-leen before
hamza 4/6, naql of hamza, ibdal / tas-hil of hamzas, taqlil / imala, tarqiq of ra in its specific
cases, taghlidh of lam after ص/ط/ظ, silat meem al-jamʿ before hamzat qatʿ, Warsh idgham specifics.

The phonetizer must produce DIFFERENT expected sequences for Hafs vs Warsh on the same ayah
(unit-tested).

---

## 7. UX — REAL-TIME FLOW & AYAH GATING

- Recitation screen: current ayah in Uthmani font (riwaya-specific), current word underlined,
  words turn green (correct) / orange (needs review) / red (error) live.
- Tap a word → bottom sheet: rule name (Arabic), expected vs observed, short explanation.
- **Gating logic**:
  - Next ayah unlocks only with zero HIGH-confidence blocking errors.
  - `needs_review` findings = visible warning, NEVER blocking.
  - On error: re-recite from the start of the waqf segment containing the error
    (setting: segment / full ayah; default segment).
  - After N failed attempts on the same word (default 3, setting): show detailed rule
    explanation + "متابعة على أي حال" (continue anyway).
- Session state (current ayah, attempts) on device only; progress per surah saved (no audio).
- First-launch screen (Arabic): microphone permission + "لا يتم تسجيل أو حفظ أي صوت" (no audio is recorded or saved).
- V1 banner: "وضع بدون إنترنت — تحليل مبسط" (offline mode — simplified analysis).

---

## 8. QUALITY GATE & EVALUATION

- **A rule may be `blocking: true` only if its measured precision ≥ 90%** on the eval set
  for that riwaya. Until measured: warning-only. Precision is the primary metric.
- `eval/` folder: annotated test recitations (correct + deliberate errors) per riwaya, with a
  script reporting precision / recall / F1 per error type and per riwaya, plus latency.
- Splits by reciter (no speaker in both tuning and test).
- Unit tests: normalizer, word aligner, phonetizer (Hafs ≠ Warsh), each rule, gating logic.
- Golden tests: Al-Fatiha + juzʾ ʿAmma, both riwayat.
- Widget tests: recitation screen states, bottom sheet, RTL layout.

---

## 9. TRAINING PIPELINE (LATER — separate private folder/repo, never shipped)

Prepare the structure and README only in V1; implementation in V2/V3.
- Multi-reciter corpus, BOTH riwayat, freely published recordings, used for training only.
  `sources.csv` per file: reciter_id, riwaya, tariq, tempo (tahqiq/tadwir/hadr), wujuh,
  recording_conditions, gender/age_group, source_url, terms_noted, date.
- One shared acoustic/phoneme model for both riwayat; riwaya-specific: text, phonetizer,
  rules, duration norms (per riwaya + tempo + wajh).
- Splits by reciter; cap any reciter at ≤10% of hours; report hours per riwaya/reciter.
- Approach: CTC fine-tuning on a Quranic phoneme set (encoding sifat), GOP/anomaly scoring,
  per-rule duration norms, synthetic errors (time-stretch madd, nasal removal, phoneme
  substitution) for per-rule classifiers; later, real learner errors annotated by a muqriʾ
  (collected in supervised sessions, outside the app).
- Base models to benchmark (TODO-VERIFY): w2v-BERT 2.0, MMS, Whisper-large-v3 encoder + CTC head.
- Server model = teacher → distillation → int8 → improved offline model (V3).

---

## 10. PHASES

1. **Audit + architecture** — repo audit, this structure, engine interface, data sources check
   (licenses), device benchmark plan. **STOP for my validation.**
2. **Data** — Quran DBs Hafs & Warsh, fonts, integrity tests.
3. **Offline engine MVP** — mic stream, VAD, on-device ASR, word alignment, live highlighting,
   ayah gating, settings, debug screen. Deliver an installable debug APK.
4. **Rules engine** — phonetizer Hafs/Warsh, YAML rules, madd & ghunnah checks (warning-only),
   tests. YAML exported for muqriʾ review.
5. **Evaluation & tuning** — eval scripts, thresholds, enable blocking only on rules ≥ 90% precision.
6. **V1 release prep** — performance, no-INTERNET release check, signed APK, Arabic store texts
   (do not publish without my approval).
7. **V2 hybrid** (later) — settings switch "التحليل عبر الإنترنت" (OFF by default; OFF = strictly no
   network), `OnlineEngine` streaming to FastAPI `/v2` via WebSocket for fine makharij/sifat,
   auto-fallback to offline, `/check` untouched, server audio processed in memory only.

---

## 11. EXPECTED DELIVERABLES (by end of Phase 4)

- Project structure as in §4, building and running on Android.
- Main audio processing logic (stream, VAD, ASR integration, alignment, checks).
- Model integration scripts (`tools/convert_model.py`, native bridge, benchmark).
- Flutter recitation screen + corrections display component (live highlighting + bottom sheet).
- Tests passing, `docs/SPEC.md`, `docs/ARCHITECTURE.md`, `docs/RULES_REVIEW.md` (for the muqriʾ),
  `CHANGELOG.md`.

Start now with Phase 1.
