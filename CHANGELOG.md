# Changelog

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
