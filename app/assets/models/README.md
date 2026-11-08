# Bundled ASR models (not committed)

The app loads `quran-whisper-base-q8_0.bin` (and optionally `quran-whisper-tiny-q8_0.bin`)
from this folder. They are produced by `tools/convert_model.py` and are git-ignored because of
their size. Their exact SHA-256 values are in `tools/models/*.manifest.json`; verify them
before building a release.
