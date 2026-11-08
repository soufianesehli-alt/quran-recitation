"""Build the per-riwaya SQLite Quran database bundled in the app (docs/SPEC.md §3).

Text is NEVER modified: `ayahs.text_uthmani` is the source line byte-for-byte and every
`words.uthmani` is an exact substring of it. Verified by `verify()`, which runs on every build.
"""

from __future__ import annotations

import dataclasses
import datetime as _dt
import hashlib
import json
import re
import sqlite3
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from .normalizer import ALLOWED, normalize

SCHEMA_VERSION = 1

# Pause (waqf) signs as standalone tokens or as the last character of a word.
# U+06DC (small high seen) is a pause sign only as a standalone token: inside a word it is the
# sin-over-sad spelling sign (e.g. Tanzil 2:245), so it is never read from the end of a word.
PAUSE_STANDALONE = frozenset("ۖۗۘۙۚۛۜ")
PAUSE_TRAILING = frozenset("ۖۗۘۙۚۛ")
# Non-word signs that attach to a neighbouring word: rub el hizb (before), sajdah (after).
RUB_EL_HIZB = "۞"
SAJDAH = "۩"
FORMAT_CHARS = frozenset("​‌‍‎‏﻿")
ARABIC_DIGITS = frozenset(chr(c) for c in range(0x0660, 0x066A))
# KFGQPC v2.x encodes the ayah-end marker as ONE font-specific glyph: ayah n is drawn by the
# code point U+FC00 + (n - 1) (Unicode "presentation form" slots reused by the KFGQPC font).
KFGQPC_AYAH_MARK_BASE = 0xFC00
KFGQPC_AYAH_MARK_LAST = 0xFDFF
_TOKEN = re.compile(r"[^\s ]+")


class IntegrityError(Exception):
    pass


@dataclasses.dataclass
class SourceAyah:
    surah: int
    ayah: int
    text: str


@dataclasses.dataclass
class Source:
    riwaya: str
    numbering: str
    source_id: str
    source_name: str
    source_url: str
    version: str
    license: str
    notice: str
    sha256: str
    ayahs: list[SourceAyah]
    surah_names: dict[int, str]
    # Expected ayahs per surah from the source's OWN metadata, if it publishes any.
    expected_counts: dict[int, int] | None
    # True when the source prefixes the basmala to ayah 1 (Tanzil does).
    basmala_prefixed: bool


@dataclasses.dataclass
class Word:
    index: int
    uthmani: str
    normalized: str
    waqf_mark: str | None
    start: int
    end: int


@dataclasses.dataclass
class BuiltAyah:
    surah: int
    ayah: int
    text: str
    basmala_prefix_chars: int
    words: list[Word]


# ── Sources ──────────────────────────────────────────────────────────────────────────────


def _sha256(*paths: Path) -> str:
    h = hashlib.sha256()
    for p in paths:
        h.update(p.read_bytes())
    return h.hexdigest()


def load_tanzil(text_path: Path, metadata_path: Path) -> Source:
    """Tanzil `txt-2` export (`surah|ayah|text`, copyright block in `#` comments)."""
    raw = text_path.read_text(encoding="utf-8")
    ayahs, notice_lines = [], []
    for line in raw.splitlines():
        if line.startswith("#"):
            notice_lines.append(line)
            continue
        if not line.strip():
            continue
        s, a, t = line.split("|", 2)
        ayahs.append(SourceAyah(int(s), int(a), t))
    notice = "\n".join(notice_lines)
    m = re.search(r"Tanzil Quran Text \(([^)]*)\)", notice)
    version = m.group(1) if m else "unknown"
    if "CHANGING IT IS NOT ALLOWED" not in notice:
        raise IntegrityError("Tanzil copyright block missing from source file")

    root = ET.parse(metadata_path).getroot()
    names, counts = {}, {}
    for s in root.iter("sura"):
        i = int(s.get("index"))
        names[i] = s.get("name")
        counts[i] = int(s.get("ayas"))
    return Source(
        riwaya="hafs",
        numbering="kufan",
        source_id="tanzil",
        source_name="Tanzil Project",
        source_url="https://tanzil.net",
        version=version,
        license="CC BY 3.0 — verbatim copies only, changing the text is not allowed; "
        "attribute Tanzil Project and link to tanzil.net",
        notice=notice,
        sha256=_sha256(text_path, metadata_path),
        ayahs=ayahs,
        surah_names=names,
        expected_counts=counts,
        basmala_prefixed=True,
    )


def load_kfgqpc_json(json_path: Path, license_text: str, version: str) -> Source:
    """KFGQPC Uthmanic data JSON (list of {sura_no, aya_no, aya_text, sura_name_ar, ...}).

    `json_path` may be the JSON file itself or the official KFGQPC zip, read without unpacking
    (the single `*.json` under its data folder). The recorded sha256 is that of the given file.
    The text uses the KFGQPC font encoding and must be displayed with the matching KFGQPC font.
    """
    if json_path.suffix.lower() == ".zip":
        with zipfile.ZipFile(json_path) as z:
            members = [n for n in z.namelist() if n.lower().endswith(".json") and " data/" in n]
            if len(members) != 1:
                raise IntegrityError(f"expected one data JSON in {json_path.name}, got {members}")
            raw = z.read(members[0]).decode("utf-8-sig")
    else:
        raw = json_path.read_text(encoding="utf-8-sig")
    rows = json.loads(raw)
    ayahs = [SourceAyah(int(r["sura_no"]), int(r["aya_no"]), r["aya_text"]) for r in rows]
    names = {}
    for r in rows:
        names.setdefault(int(r["sura_no"]), r["sura_name_ar"])
    return Source(
        riwaya="warsh",
        numbering="madani",
        source_id="kfgqpc",
        source_name="King Fahd Glorious Qur'an Printing Complex (KFGQPC)",
        source_url="https://qurancomplex.gov.sa",
        version=version,
        license=license_text,
        notice=f"KFGQPC Warsh Uthmanic data, version {version}. {license_text}",
        sha256=_sha256(json_path),
        ayahs=ayahs,
        surah_names=names,
        expected_counts=None,
        basmala_prefixed=False,
    )


# ── Tokenization ─────────────────────────────────────────────────────────────────────────


def _is_word(tok: str) -> bool:
    return any(normalize(ch) for ch in tok)


def ayah_number_value(tok: str) -> int | None:
    """Value of an ayah-number token (Arabic-Indic digits or a KFGQPC ayah-mark glyph)."""
    core = "".join(ch for ch in tok if ch not in FORMAT_CHARS)
    if core and all(ch in ARABIC_DIGITS for ch in core):
        return int("".join(str(ord(ch) - 0x0660) for ch in core))
    if len(core) == 1 and KFGQPC_AYAH_MARK_BASE <= ord(core) <= KFGQPC_AYAH_MARK_LAST:
        return ord(core) - KFGQPC_AYAH_MARK_BASE + 1
    return None


def _is_ayah_number(tok: str) -> bool:
    return ayah_number_value(tok) is not None


def tokenize(text: str) -> tuple[list[Word], list[tuple[int, int, str]]]:
    """Split an ayah into words. Standalone signs attach to a neighbouring word's span.

    Returns (words, ignored) where `ignored` lists (start, end, kind) spans that belong to no
    word (only the trailing ayah number in the KFGQPC encoding).
    """
    words: list[Word] = []
    ignored: list[tuple[int, int, str]] = []
    pending_prefix: int | None = None  # start of a rub-el-hizb sign waiting for its word
    for m in _TOKEN.finditer(text):
        tok, start, end = m.group(0), m.start(), m.end()
        if _is_word(tok):
            core = tok.rstrip("".join(FORMAT_CHARS))
            mark = core[-1] if core and core[-1] in PAUSE_TRAILING else None
            words.append(
                Word(
                    index=len(words),
                    uthmani="",
                    normalized=normalize(tok),
                    waqf_mark=mark,
                    start=pending_prefix if pending_prefix is not None else start,
                    end=end,
                )
            )
            pending_prefix = None
        elif _is_ayah_number(tok):
            ignored.append((start, end, f"ayah_number:{ayah_number_value(tok)}"))
        else:
            core = "".join(ch for ch in tok if ch not in FORMAT_CHARS)
            if core == RUB_EL_HIZB:
                pending_prefix = start
            elif words and (core in PAUSE_STANDALONE or core == SAJDAH):
                words[-1].end = end
                if core in PAUSE_STANDALONE:
                    # Keep every sign, in order: 36:52 (Hafs) carries the sakta sign AND a
                    # pause sign after the same word.
                    words[-1].waqf_mark = (words[-1].waqf_mark or "") + core
            else:
                raise IntegrityError(f"unexpected token {tok!r} ({[hex(ord(c)) for c in tok]})")
    if pending_prefix is not None:
        raise IntegrityError("rub el hizb sign with no following word")
    for w in words:
        w.uthmani = text[w.start : w.end]
    return words, ignored


def build_ayahs(src: Source) -> list[BuiltAyah]:
    basmala_key: list[str] | None = None
    if src.basmala_prefixed:
        first = next(a for a in src.ayahs if a.surah == 1 and a.ayah == 1)
        basmala_key = [w.normalized for w in tokenize(first.text)[0]]

    built = []
    for a in src.ayahs:
        words, _ = tokenize(a.text)
        prefix = 0
        if (
            basmala_key
            and a.ayah == 1
            and a.surah not in (1, 9)
            and [w.normalized for w in words[: len(basmala_key)]] == basmala_key
        ):
            n = len(basmala_key)
            # The basmala is kept in text_uthmani (verbatim) but is not part of the ayah's words.
            prefix = words[n].start
            words = [dataclasses.replace(w, index=i) for i, w in enumerate(words[n:])]
        built.append(BuiltAyah(a.surah, a.ayah, a.text, prefix, words))
    return built


# ── Verification ─────────────────────────────────────────────────────────────────────────


def verify(src: Source, built: list[BuiltAyah]) -> dict[str, int]:
    by_surah: dict[int, list[int]] = {}
    for a in built:
        by_surah.setdefault(a.surah, []).append(a.ayah)

    if sorted(by_surah) != list(range(1, 115)):
        raise IntegrityError(f"expected surahs 1..114, got {len(by_surah)}")
    for s, nums in by_surah.items():
        if nums != list(range(1, len(nums) + 1)):
            raise IntegrityError(f"surah {s}: ayah numbers not contiguous from 1")
        if src.expected_counts is not None and len(nums) != src.expected_counts[s]:
            raise IntegrityError(
                f"surah {s}: {len(nums)} ayahs, source metadata says {src.expected_counts[s]}"
            )
    if set(src.surah_names) != set(range(1, 115)):
        raise IntegrityError("surah names missing")

    basmala_count = 0
    for a in built:
        if not a.words:
            raise IntegrityError(f"{a.surah}:{a.ayah}: no words")
        basmala_count += a.basmala_prefix_chars > 0
        # Verbatim coverage: word spans are exact, ordered, non-overlapping substrings, and
        # everything outside them is whitespace, the basmala prefix, or the ayah number.
        covered = [False] * len(a.text)
        for i in range(a.basmala_prefix_chars):
            covered[i] = True
        last_end = a.basmala_prefix_chars
        for w in a.words:
            if w.start < last_end:
                raise IntegrityError(f"{a.surah}:{a.ayah}: overlapping word spans")
            if a.text[w.start : w.end] != w.uthmani:
                raise IntegrityError(f"{a.surah}:{a.ayah}: word is not a verbatim substring")
            if not w.normalized or set(w.normalized) - ALLOWED:
                raise IntegrityError(f"{a.surah}:{a.ayah}: bad normalized key {w.normalized!r}")
            for i in range(w.start, w.end):
                covered[i] = True
            last_end = w.end
        for s0, e0, kind in tokenize(a.text)[1]:
            if kind.startswith("ayah_number:") and int(kind.split(":")[1]) != a.ayah:
                raise IntegrityError(f"{a.surah}:{a.ayah}: ayah marker says {kind.split(':')[1]}")
            for i in range(s0, e0):
                covered[i] = True
        leftover = {a.text[i] for i, c in enumerate(covered) if not c}
        if leftover - {" ", " "}:
            raise IntegrityError(f"{a.surah}:{a.ayah}: uncovered characters {leftover!r}")

    if src.basmala_prefixed and basmala_count != 112:
        raise IntegrityError(f"expected 112 basmala-prefixed ayahs, found {basmala_count}")

    return {
        "surahs": len(by_surah),
        "ayahs": len(built),
        "words": sum(len(a.words) for a in built),
        "words_with_waqf_mark": sum(1 for a in built for w in a.words if w.waqf_mark),
        "waqf_signs": sum(len(w.waqf_mark or "") for a in built for w in a.words),
        "basmala_prefixed_ayahs": basmala_count,
    }


# ── Output ───────────────────────────────────────────────────────────────────────────────

DDL = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE surahs (
  surah INTEGER PRIMARY KEY, name_ar TEXT NOT NULL, ayah_count INTEGER NOT NULL);
CREATE TABLE ayahs (
  surah INTEGER NOT NULL, ayah INTEGER NOT NULL,
  text_uthmani TEXT NOT NULL,               -- verbatim source text
  basmala_prefix_chars INTEGER NOT NULL,    -- >0 when the source prefixes the basmala
  PRIMARY KEY (surah, ayah));
CREATE TABLE words (
  surah INTEGER NOT NULL, ayah INTEGER NOT NULL, word_index INTEGER NOT NULL,
  uthmani TEXT NOT NULL,                    -- verbatim substring of ayahs.text_uthmani
  normalized TEXT NOT NULL,                 -- matching key, never displayed
  waqf_mark TEXT,
  PRIMARY KEY (surah, ayah, word_index));
"""


def write_db(src: Source, built: list[BuiltAyah], stats: dict[str, int], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    con = sqlite3.connect(tmp)
    try:
        con.executescript(DDL)
        counts: dict[int, int] = {}
        for a in built:
            counts[a.surah] = counts.get(a.surah, 0) + 1
        meta = {
            "schema_version": str(SCHEMA_VERSION),
            "riwaya": src.riwaya,
            "numbering": src.numbering,
            "source": src.source_name,
            "source_id": src.source_id,
            "source_url": src.source_url,
            "version": src.version,
            "license": src.license,
            "copyright_notice": src.notice,
            "source_sha256": src.sha256,
            "built_at": _dt.date.today().isoformat(),
            **{f"count_{k}": str(v) for k, v in stats.items()},
        }
        con.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
        con.executemany(
            "INSERT INTO surahs VALUES (?, ?, ?)",
            [(s, src.surah_names[s], counts[s]) for s in sorted(counts)],
        )
        con.executemany(
            "INSERT INTO ayahs VALUES (?, ?, ?, ?)",
            [(a.surah, a.ayah, a.text, a.basmala_prefix_chars) for a in built],
        )
        con.executemany(
            "INSERT INTO words VALUES (?, ?, ?, ?, ?, ?)",
            [
                (a.surah, a.ayah, w.index, w.uthmani, w.normalized, w.waqf_mark)
                for a in built
                for w in a.words
            ],
        )
        con.commit()
        con.execute("VACUUM")
    finally:
        con.close()
    tmp.replace(out)
