# Data sources and licenses: Phase 1 check

**Status: no license below is confirmed.** From this sandbox the primary sites (`tanzil.net`,
`qurancomplex.gov.sa`, `huggingface.co`) were unreachable because of the network policy. What
follows comes from web search snippets and GitHub mirrors. Every item stays **`TODO-VERIFY`**
until someone reads the primary terms and records them here, with the date and the exact quote.

Rule for the whole project (docs/SPEC.md §0.4): no Quranic text, font or model goes into the
app until its row below is ✅.

## 1. Quran text

| # | Source | Riwaya | What we know | Status |
|---|---|---|---|---|
| T1 | **Tanzil** Uthmani text (tanzil.net) | Hafs | Third-party copies of the Tanzil notice (an npm README, a thesis) say: **CC BY 3.0**, verbatim copying allowed, **no change to the text**, and apps must credit Tanzil and link to tanzil.net. Tanzil describes its Uthmani text as an encoding of the Madina mushaf. | `TODO-VERIFY` primary page `tanzil.net/docs/text_license` |
| T2 | **KFGQPC** (King Fahd Glorious Qur'an Printing Complex), developer resources (`qurancomplex.gov.sa/en/techquran/dev/`) | Hafs, **Warsh** (and other riwayat) | Official publisher. Offers Unicode Uthmanic text and fonts per riwaya. Published terms disagree (see §2). | `TODO-VERIFY`. **Preferred source for Warsh.** Written permission may be needed. |
| T3 | `github.com/ibnhazm/KFGQPC` (unofficial mirror) | 9 riwayat incl. Warsh (v10) and Hafs (v18) | CSV/JSON/SQL/XML/XLSX text plus `.ttf`/`.woff2` fonts. Says "Quran Data from King Fahd Glorious Quran Printing Complex". **No LICENSE file.** | Use only to study the data format. Take the actual text from T2. |
| T4 | `quran-ws/quran-text` (Packagist) | 7 riwayat incl. `warsh.json` | Pages, lines, waqf marks. License not seen. Upstream source unknown. | `TODO-VERIFY`. Not to be used until provenance is known. |
| — | quran.com API v4 (used by the current backend) | Hafs only | Network API, so unusable offline in V1. Does not provide Warsh. | Not a V1 source |

Decisions to confirm (Phase 2):
- **No text modification.** The DB stores `uthmani` byte-for-byte as received. The `normalized`
  column is a derived matching key that is never displayed. I need to confirm with T1/T2 terms
  that a derived search index counts as acceptable use (`TODO-VERIFY`).
- **Ayah counts.** Hafs (Kufan) is expected to have 6236 ayahs. Warsh (Madani) is commonly given
  as 6214 (al-Madani al-Akhir). `TODO-VERIFY` against the text file actually chosen. The
  integrity test will assert the counts **from the source's own metadata**, not from this
  document.
- The attribution screen (Arabic) lists source, version and license, read from the `meta` table.

## 2. Fonts

| Source | What we know | Status |
|---|---|---|
| KFGQPC Uthmanic Hafs font | Two conflicting texts are in circulation. (a) ScanCode's "Uthmanic Script License": the font is the Complex's property and "may not be reproduced, modified without the express written approval". (b) A 2009 EULA mirrored on OpenHub: free to use, copy and distribute, with conditions. | `TODO-VERIFY` the "Usage Rights" clause on the official font page |
| KFGQPC Uthmanic Warsh font (v2.1 on the Complex's Warsh page) | Download page exists. License text not read. | `TODO-VERIFY` |
| `github.com/nuqayah/qpc-fonts` (mirror) | Mostly **page fonts that use one glyph per word** (QPC mushaf fonts), plus "various" fonts. Its license link points to `dm.qurancomplex.gov.sa/copyright-2/` (not read). | Not used. Page-glyph fonts do not fit word-level highlighting on Unicode text. |

Fallback if the KFGQPC terms forbid bundling: ask the Complex for written permission. **I will
not substitute another font without the product owner's approval**, because the Warsh rasm
needs a font that supports its marks.

## 3. ASR models and runtimes

| Item | What we know | Status |
|---|---|---|
| `tarteel-ai/whisper-base-ar-quran` | Search results quoting its Hugging Face card: `license: apache-2.0`. A fine-tune of Whisper base. Reported WER about 5.75% on its own eval set. **Training data, intended use and limitations are "More information needed"** on the card. | `TODO-VERIFY` (card not fetched directly). Unknown whether Warsh audio is in the training data; assume Hafs only. |
| `tarteel-ai/whisper-tiny-ar-quran` | Listed by a third-party model index. | `TODO-VERIFY` that it exists and its license |
| OpenAI Whisper base weights | Believed MIT. | `TODO-VERIFY` (needed because the fine-tune inherits from it) |
| whisper.cpp (runtime) | Believed MIT. | `TODO-VERIFY` |
| ONNX Runtime Mobile (runtime) | Believed MIT. | `TODO-VERIFY` |
| Small Arabic CTC model (wav2vec2-type) | **No specific model named yet.** Candidates are searched for in Phase 3. | `TODO-VERIFY` |
| Training bases (§9): w2v-BERT 2.0, MMS, Whisper-large-v3 | Licenses not checked. Some MMS checkpoints may carry a **non-commercial** license; must check before relying on it. | `TODO-VERIFY` (V2/V3) |

## 4. Rules (tajweed content)

No external dataset. Rules are written in `assets/rules/{hafs,warsh}.yaml` from the spec's list
(§6). Each rule has `review_status: pending` until a qualified muqriʾ approves it in
`docs/RULES_REVIEW.md`. **Phase 4 needs a named reviewer** (question for the product owner).

## 5. What Phase 2 needs from the product owner

1. Either allow `tanzil.net` and `qurancomplex.gov.sa` in this cloud environment's network
   settings, or download the files yourself and share them.
2. A decision on the KFGQPC terms: proceed under the published terms, or write to the Complex
   first.
