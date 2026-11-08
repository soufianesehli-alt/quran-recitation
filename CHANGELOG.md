# Changelog

## [Unreleased] — Phase 3 fix: speed and capture (2026-11-08)
- Field report (S22 Ultra): too slow, recitation not captured easily.
- Runtime ARM CPU variants (dotprod/fp16/i8mm/SVE), encoder window sized to the clip, greedy
  live previews with beam only for the final pass, PCM16 straight to C, noise suppression off,
  more sensitive VAD, microphone level meter, model install without reloading, engine preload,
  profile build for device tests. Host: 670–890 ms → 130–290 ms per 4 s clip (synthetic audio).

## [Unreleased] — Phase 3: offline engine MVP (2026-11-08)
### Added
- On-device ASR: whisper.cpp v1.9.5 (submodule) with a C API, built for 3 ABIs; Dart FFI in an
  isolate; models from `tools/convert_model.py` (tarteel-ai Quran Whisper base and tiny,
  Apache-2.0, pinned and hashed).
- Audio: `record` PCM stream (no file), in-memory ring buffer zeroed after use, energy VAD.
- Word aligner, findings policy (conservative), skipped-ayah detection, live word events.
- Session controller with ayah gating, segment re-recitation, "continue anyway", progress.
- Screens: first launch, selection, recitation (live colours), feedback sheet, settings,
  sources and licences, dev diagnostics and speed test.
- Device tiers (low, mid, high) choosing the recogniser setup.
- Tests: 72 Dart (unit, engine with fake mic and ASR, session, widget, privacy lint, manifest)
  plus an opt-in native end-to-end test; 17 Python.
### Known limits
- No accuracy figures: no real recitation audio has been evaluated (Phase 5).
- No word rule blocks yet (precision gate). Word timestamps are not usable for madd yet.
- Warsh: text, font and rules are in place, but the acoustic model is assumed Hafs-only.

## [Unreleased] — Phase 2: data (2026-11-08)
### Added
- `tools/build_quran_db.py` + `tools/quran_db/`: per-riwaya SQLite builder (Tanzil txt and KFGQPC
  JSON parsers). Text is stored verbatim; the build fails on any integrity problem (surah and
  ayah contiguity, counts vs source metadata, verbatim word spans, basmala prefixes).
- Arabic matching normalizer in Python (`tools/quran_db/normalizer.py`) and Dart
  (`app/lib/core/arabic/normalizer.dart`), with shared vectors `tools/normalizer_vectors.json`.
- `app/assets/quran/hafs.sqlite` (Tanzil Uthmani 1.1, 6236 ayahs) and its verbatim sources in
  `tools/sources/tanzil/` with provenance and hashes.
- `QuranRepository` (sqflite, read-only) and `Ayah.basmalaPrefixChars`.
- Tests: 12 pytest (+1 Warsh test, enabled with `WARSH_JSON`), and Dart repository
  integrity plus normalizer parity over all 77,433 words.
- Amiri Quran font (OFL 1.1) as the approved Hafs fallback, with its license registered in the
  app. `QuranFonts.familyFor` gives no fallback for Warsh.
- Warsh DB from the official KFGQPC `UthmanicWarsh_v2-1.zip` (checksums equal the published
  ones; Word document signed by KFGQPC; 6214 ayahs; ayah-end glyphs decoded and checked), plus
  the official KFGQPC Warsh font v2.1 with its embedded license.
- Build reads the KFGQPC zip directly. Python tests now cover Warsh (17 total); Dart adds Warsh
  integrity, numbering-difference and normalizer-parity tests (31 total).
### Open
- KFGQPC written permission (release gate). Independent per-surah Madani count check.

## [Unreleased] — Phase 1: audit + architecture (2026-11-08)
### Added
- `docs/SPEC.md` (single source of truth), `docs/AUDIT.md`, `docs/ARCHITECTURE.md`,
  `docs/DATA_SOURCES.md`, `tools/benchmark_device.md`, `eval/README.md`, `training/README.md`.
- `app/`: Flutter Android project (`tilawa`, minSdk 24), Arabic RTL shell with the offline banner.
- Domain models (`Riwaya`, `AyahRef`, `Surah`, `Ayah`, `Word`, `Finding`, `Severity`, `ErrorType`),
  `AyahGate` policy, `RecitationEngine` interface, `LiveEvent`, `EngineCapabilities`,
  `OfflineEngine` skeleton, `OnlineEngine` V2 stub.
- Android: `RECORD_AUDIO` only; release manifest strips `INTERNET`/`ACCESS_NETWORK_STATE`;
  `tools/check_release_manifest.sh` verifies a built APK.
- Tests: gating policy, riwaya model, engine contract, manifest permissions, RTL widget test.
### Changed
- `.gitignore` rewritten in UTF-8 (the previous UTF-16 file was ignored by git).
- Stopped tracking `.env`, `venv/`, `__pycache__/` (approved by the product owner). The files are still on disk.
- `docs/DATA_SOURCES.md`: Tanzil license verified from the primary page and quoted verbatim.
- `docs/ARCHITECTURE.md` §8: product-owner decisions recorded.
### Not changed
- Backend (`main.py`, `/check`) untouched.
