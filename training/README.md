# Training pipeline — placeholder (docs/SPEC.md §9)

Nothing in this folder is shipped in the app. Implementation is V2/V3 and is planned to move to
a **separate private repository**; this README only fixes the conventions.

- Corpus: multi-reciter, both riwayat, freely published recordings, training use only.
  Per-file `sources.csv`: reciter_id, riwaya, tariq, tempo (tahqiq/tadwir/hadr), wujuh,
  recording_conditions, gender/age_group, source_url, terms_noted, date.
- Splits by reciter; no reciter > 10 % of hours; report hours per riwaya and reciter.
- One shared acoustic/phoneme model; riwaya-specific text, phonetizer, rules, duration norms.
- Approach: CTC fine-tuning on a Quranic phoneme set, GOP/anomaly scoring, per-rule duration
  norms, synthetic errors; later, real learner errors annotated by a muqriʾ.
- Base models to benchmark (all `TODO-VERIFY` licence): w2v-BERT 2.0, MMS,
  Whisper-large-v3 encoder + CTC head.
- Audio and checkpoints are git-ignored here (`training/data/`, `*.bin`, `*.onnx`, …).
