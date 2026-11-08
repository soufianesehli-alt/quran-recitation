# Evaluation set (Phase 5)

Annotated recitations used to measure precision / recall / F1 per error type and per riwaya
(docs/SPEC.md §8). **A rule may only become `blocking: true` with precision ≥ 90 % here.**

Layout (audio is never committed to git — stored privately, referenced by id):
```
eval/
  manifest.csv     # clip_id, riwaya, reciter_id, split(dev|test), surah, ayah_start, ayah_end,
                   #   tempo, source/consent note
  annotations/     # one JSON per clip: words with start/end ms, deliberate errors with type
  scripts/         # run_eval.py → per-rule / per-riwaya precision, recall, F1, latency
```
Splits are by reciter: no reciter appears in both dev (tuning) and test.
