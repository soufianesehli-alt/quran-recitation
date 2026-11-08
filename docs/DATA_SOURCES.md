# Data sources and licenses: Phase 1 check

**Status: Tanzil confirmed (§1.1). Everything else is still unconfirmed.** From this sandbox the primary sites (`tanzil.net`,
`qurancomplex.gov.sa`, `huggingface.co`) were unreachable because of the network policy. What
follows comes from web search snippets and GitHub mirrors. Every item stays **`TODO-VERIFY`**
until someone reads the primary terms and records them here, with the date and the exact quote.

Rule for the whole project (docs/SPEC.md §0.4): no Quranic text, font or model goes into the
app until its row below is ✅.

## 1. Quran text

| # | Source | Riwaya | What we know | Status |
|---|---|---|---|---|
| T1 | **Tanzil** Uthmani text (tanzil.net) | Hafs | **Read from `tanzil.net/docs/text_license` on 2026-11-08** (quoted in §1.1) | ✅ Verified. Usable under the conditions in §1.1 |
| T2 | **KFGQPC** (King Fahd Glorious Qur'an Printing Complex), developer resources (`qurancomplex.gov.sa/en/techquran/dev/`) | Hafs, **Warsh** (and other riwayat) | Official publisher. Offers Unicode Uthmanic text and fonts per riwaya. Published terms disagree (see §2). | `TODO-VERIFY`. **Preferred source for Warsh.** Written permission may be needed. |
| T3 | `github.com/ibnhazm/KFGQPC` (unofficial mirror) | 9 riwayat incl. Warsh (v10) and Hafs (v18) | CSV/JSON/SQL/XML/XLSX text plus `.ttf`/`.woff2` fonts. Says "Quran Data from King Fahd Glorious Quran Printing Complex". **No LICENSE file.** | Use only to study the data format. Take the actual text from T2. |
| T4 | `quran-ws/quran-text` (Packagist) | 7 riwayat incl. `warsh.json` | Pages, lines, waqf marks. License not seen. Upstream source unknown. | `TODO-VERIFY`. Not to be used until provenance is known. |
| — | quran.com API v4 (used by the current backend) | Hafs only | Network API, so unusable offline in V1. Does not provide Warsh. | Not a V1 source |

### 1.1 Tanzil terms (verbatim, 2026-11-08)
> Tanzil Quran Text — Copyright (C) 2007-2021 Tanzil Project — License: Creative Commons Attribution 3.0
> TERMS OF USE:
> - Permission is granted to copy and distribute verbatim copies of this text, but CHANGING IT IS NOT ALLOWED.
> - This Quran text can be used in any website or application, provided that its source (Tanzil Project) is clearly indicated, and a link is made to tanzil.net to enable users to keep track of changes.
> - This copyright notice shall be included in all verbatim copies of the text, and shall be reproduced appropriately in all files derived from or containing substantial portion of this text.

What this means for us:
- The displayed `uthmani` column stays byte-identical to the source.
- Every DB file carries the notice in its `meta` table.
- The in-app attribution screen shows "Tanzil Project" and the address tanzil.net as text. V1 is
  offline, so it is not a live link.
- The `normalized` matching column is a derived file under the third term, so the notice is
  reproduced in it too.

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
| Amiri Quran (Hafs fallback) | **OFL 1.1, verified.** See §6.3 | ✅ bundled |
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

1. ~~Network access~~: done. A personal environment "quran-recitation" now allows tanzil.net and
   the qurancomplex.gov.sa hosts. However, the KFGQPC servers themselves reject connections from
   this cloud (TLS "unrecognized name" on fonts.*, HTTP 503 on the main site). If that persists,
   the product owner downloads the KFGQPC files in a browser and shares them.
2. ~~KFGQPC decision~~: decided. Build now and request written permission in parallel. Nothing
   goes to the Play Store until the terms are clear or permission arrives.

## 6. Phase 2 findings (2026-11-08)

### 6.1 Hafs: built ✅
`app/assets/quran/hafs.sqlite` comes from Tanzil Uthmani 1.1 (files and hashes in
`tools/sources/tanzil/SOURCE.md`).

- 114 surahs and 6236 ayahs. Each surah's count matches Tanzil's own `quran-data.xml`.
- 77,433 words, 4,364 pause signs, 112 basmala prefixes.
- Every word is an exact substring of the untouched source line, checked on every build.

**Basmala.** Tanzil prefixes the basmala to ayah 1 of surahs 2–114, except 9.
- It stays in `ayahs.text_uthmani` exactly as in the source.
- `basmala_prefix_chars` records its length.
- It is excluded from `words`, because it is not part of the ayah in the Kufan count.

**For review (`TODO-VERIFY` with Tanzil and the muqriʾ):**
1. In **surahs 95 and 97** the Tanzil basmala starts `بِّسْمِ`, with a **shadda** on the bāʾ.
   In the other 110 it starts `بِسْمِ`. Left as is (no modification allowed). Detection
   compares normalized keys, so these two are handled correctly.
2. The sakta sign `ۜ` stands alone after **five** words: 18:1 `عِوَجَا`, 36:52 `مَرْقَدِنَا`
   (followed by a pause sign as well), 69:28 `مَالِيَهْ`, 75:27 `مَنْ`, 83:14 `بَلْ`.
   The spec (§6) lists four saktat. The fifth position (69:28) must be classified by the muqriʾ
   before any sakta rule uses it.
3. Inside a word, `ۜ` is the sīn-over-ṣād spelling sign (2:245 `وَيَبْصُۜطُ`, 7:69 `بَصْۜطَةً`).
   It is not read as a pause sign.

### 6.2 Warsh: pipeline ready, DB **not** built ⛔
- The KFGQPC servers still reject this cloud: TLS "unrecognized name" on `fonts.*` and no
  response from `qurancomplex.gov.sa`. The decision stands: the Warsh text must come from the
  official download.
- I validated the parser on the **unofficial** mirror `ibnhazm/KFGQPC` (Warsh data v10,
  2021-08-05), in a scratch build only. Nothing from the mirror is committed. Results: 114
  surahs, **6214 ayahs**, 1:1 = `اِ۬لْحَمْدُ` (the basmala is not counted), Al-Fātiḥa has 7
  ayahs with 1:6 ending at `عَلَيْهِمْ`, Al-Baqarah has 285.
- Format facts the build handles:
  - The text uses the **KFGQPC font encoding**, so it must be shown with the KFGQPC Warsh font.
  - Each `aya_text` ends with a non-breaking space and the ayah number.
  - Pause signs are attached to the word (U+06D6 is used for all of them).
  - `ے` (U+06D2) is the dotless yāʾ, e.g. `فِے`.
- KFGQPC publishes **no separate per-surah ayah counts**, so the build can only check
  contiguity and the total. **`TODO-VERIFY`**: an independent per-surah Madani count is needed
  to cross-check (from the printed Warsh mushaf or a KFGQPC document).

To build Warsh: download the official KFGQPC Warsh Uthmanic data (JSON) and font, then run
```
python3 tools/build_quran_db.py warsh --text <warshData_vN.json> --version N --license "<official terms>" --out app/assets/quran/warsh.sqlite
WARSH_JSON=<warshData_vN.json> python3 -m pytest tools/tests
```
Then add the DB to `pubspec.yaml`.

### 6.3 Fonts
**Hafs: Amiri Quran ✅** (fallback approved by the product owner on 2026-11-08)
- Source: Google Fonts repository `google/fonts/ofl/amiriquran/` (Amiri 1.003, Khaled Hosny and
  Sebastian Kosch).
- License **SIL Open Font License 1.1**, read from the shipped `OFL.txt`: "Copyright 2010-2022
  The Amiri Quran Project Authors (https://github.com/aliftype/amiri)."
- Bundled as `app/assets/fonts/AmiriQuran-Regular.ttf`
  (sha256 `e2a47644762d16bdfb6d33e0d8db8c6ff30beae84150ef5a705316bbd829455c`) with
  `AmiriQuran-OFL.txt`. The license is registered with the app's license screen.
- Coverage: all 70 distinct characters of the Tanzil Hafs text have glyphs (checked with
  fontTools). A visual check of 1:1–1:4, 2:2, 2:245, 18:1 and 36:52 shows harakat, superscript
  alef, pause signs, the sakta sign and the sin-over-sad sign all placed correctly.
- Will be replaced by the KFGQPC Hafs font if its terms allow.

**Warsh: pending ⛔.** There is no fallback, by design (`QuranFonts.familyFor(warsh) == null`).
Text in the KFGQPC encoding needs the KFGQPC Warsh font.

Earlier notes:
- The **Warsh text cannot render correctly without the KFGQPC Warsh font**, because of its
  encoding.
- For Hafs, the Tanzil text needs a font that supports the Quranic marks. The KFGQPC Hafs font
  is blocked the same way.
- I am not substituting another font without the product owner's approval (§2).
