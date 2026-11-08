# Changelog

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
### Not done
- Warsh DB: waiting for the official KFGQPC download (servers unreachable from the cloud).
- Fonts: waiting for KFGQPC fonts or a product-owner decision.

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
