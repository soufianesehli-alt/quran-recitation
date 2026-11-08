"""Tests for the Quran DB build (run: python3 -m pytest tools/tests)."""

import dataclasses
import json
import sqlite3
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))

from quran_db.build import (  # noqa: E402
    IntegrityError,
    build_ayahs,
    load_kfgqpc_json,
    load_tanzil,
    tokenize,
    verify,
    write_db,
)
from quran_db.normalizer import normalize  # noqa: E402

TANZIL_TEXT = TOOLS / "sources/tanzil/quran-uthmani.txt"
TANZIL_META = TOOLS / "sources/tanzil/quran-data.xml"
HAFS_DB = ROOT / "app/assets/quran/hafs.sqlite"


@pytest.fixture(scope="module")
def hafs():
    src = load_tanzil(TANZIL_TEXT, TANZIL_META)
    return src, build_ayahs(src)


def _ayah(built, s, a):
    return next(x for x in built if x.surah == s and x.ayah == a)


def test_normalizer_vectors():
    vectors = json.loads((TOOLS / "normalizer_vectors.json").read_text(encoding="utf-8"))["vectors"]
    for v in vectors:
        assert normalize(v["in"]) == v["out"], v


def test_hafs_integrity(hafs):
    src, built = hafs
    stats = verify(src, built)
    assert stats["surahs"] == 114
    assert stats["ayahs"] == sum(src.expected_counts.values()) == 6236
    assert stats["basmala_prefixed_ayahs"] == 112


def test_tanzil_notice_is_kept(hafs):
    src, _ = hafs
    assert "CHANGING IT IS NOT ALLOWED" in src.notice
    assert "tanzil.net" in src.notice


def test_basmala_is_ayah_in_fatiha_but_prefix_elsewhere(hafs):
    _, built = hafs
    fatiha1 = _ayah(built, 1, 1)
    assert fatiha1.basmala_prefix_chars == 0 and len(fatiha1.words) == 4
    nas1 = _ayah(built, 114, 1)
    assert nas1.basmala_prefix_chars > 0
    assert [w.normalized for w in nas1.words] == ["قل", "اعوذ", "برب", "الناس"]
    assert _ayah(built, 9, 1).basmala_prefix_chars == 0
    # Surahs 95 and 97: Tanzil writes the basmala's first word with a shadda (بِّسْمِ).
    for s in (95, 97):
        assert _ayah(built, s, 1).basmala_prefix_chars > 0


def test_words_are_verbatim_and_text_untouched(hafs):
    src, built = hafs
    raw = {(a.surah, a.ayah): a.text for a in src.ayahs}
    for a in built:
        assert a.text == raw[(a.surah, a.ayah)]
        for w in a.words:
            assert a.text[w.start : w.end] == w.uthmani


def test_two_signs_after_one_word_are_both_kept(hafs):
    # 36:52 مَّرْقَدِنَا is followed by the sakta sign and a pause sign.
    w = next(w for w in _ayah(hafs[1], 36, 52).words if w.normalized == "مرقدنا")
    assert w.waqf_mark == "ۜۗ"


def test_sakta_sign_positions_come_from_source(hafs):
    _, built = hafs
    found = sorted(
        (a.surah, a.ayah, w.normalized)
        for a in built
        for w in a.words
        if w.waqf_mark and "ۜ" in w.waqf_mark
    )
    assert found == [
        (18, 1, "عوجا"),
        (36, 52, "مرقدنا"),
        (69, 28, "ماليه"),
        (75, 27, "من"),
        (83, 14, "بل"),
    ]


def test_sin_over_sad_inside_a_word_is_not_a_waqf_mark(hafs):
    # Inside a word, U+06DC is a spelling sign (sin over sad), not a pause sign. Taken from
    # the source, not typed by hand.
    inner = [w for a in hafs[1] for w in a.words if "\u06dc" in w.uthmani.split(" ")[0]]
    assert len(inner) == 2, [w.uthmani for w in inner]  # Tanzil spells two words this way
    for w in inner:
        assert "\u06dc" not in (w.waqf_mark or "")


def test_rub_el_hizb_and_sajdah_attach_to_words(hafs):
    _, built = hafs
    rub = [a for a in built if "\u06de" in a.text]
    sajdah = [a for a in built if "\u06e9" in a.text]
    assert rub and sajdah
    for a in rub:
        assert a.words[0].uthmani.startswith("\u06de")
    for a in sajdah:
        assert any(w.uthmani.endswith("\u06e9") for w in a.words)


def test_kfgqpc_ayah_number_is_not_a_word():
    # Copied verbatim from KFGQPC Warsh v10 data, 1:3 (encoding sample: word-attached pause
    # sign, NBSP, trailing ayah number).
    words, ignored = tokenize("مَلِكِ يَوْمِ اِ۬لدِّينِۖ ٣")
    assert [w.normalized for w in words] == ["ملك", "يوم", "الدين"]
    assert words[-1].waqf_mark == "ۖ"
    assert ignored and ignored[0][2] == "ayah_number:3"


def test_kfgqpc_v2_ayah_mark_glyph_is_decoded():
    # KFGQPC v2.1 ends each ayah with one glyph code point U+FC00 + (n - 1).
    from quran_db.build import ayah_number_value

    assert ayah_number_value("\ufc00") == 1
    assert ayah_number_value("\ufd1c") == 285
    assert ayah_number_value("\u0661\u0660") == 10


def test_missing_ayah_fails_the_build(hafs):
    src, _ = hafs
    broken = dataclasses.replace(src, ayahs=[a for a in src.ayahs if (a.surah, a.ayah) != (2, 255)])
    with pytest.raises(IntegrityError):
        verify(broken, build_ayahs(broken))


def test_committed_db_matches_a_fresh_build(hafs, tmp_path):
    src, built = hafs
    out = tmp_path / "hafs.sqlite"
    write_db(src, built, verify(src, built), out)
    q = [
        "SELECT * FROM surahs ORDER BY surah",
        "SELECT * FROM ayahs ORDER BY surah, ayah",
        "SELECT * FROM words ORDER BY surah, ayah, word_index",
        "SELECT * FROM meta WHERE key != 'built_at' ORDER BY key",
    ]
    fresh, committed = sqlite3.connect(out), sqlite3.connect(HAFS_DB)
    for sql in q:
        assert fresh.execute(sql).fetchall() == committed.execute(sql).fetchall(), sql


KFGQPC_ZIP = TOOLS / "sources/kfgqpc/UthmanicWarsh_v2-1.zip"
WARSH_DB = ROOT / "app/assets/quran/warsh.sqlite"


@pytest.fixture(scope="module")
def warsh():
    src = load_kfgqpc_json(KFGQPC_ZIP, "test", "test")
    return src, build_ayahs(src)


def test_kfgqpc_zip_matches_checksums_published_by_kfgqpc():
    import hashlib

    data = KFGQPC_ZIP.read_bytes()
    # Published on https://qurancomplex.gov.sa/quran-dev/ (see tools/sources/kfgqpc/SOURCE.md).
    assert hashlib.md5(data).hexdigest() == "4701e8bbf053098220cf2cf4cda206a1"
    assert hashlib.sha1(data).hexdigest() == "44ecea8feb23817fdc01a8ee2162a6a0cf08cae7"


def test_warsh_integrity_and_madani_numbering(warsh):
    src, built = warsh
    stats = verify(src, built)  # also checks every ayah-end glyph against the ayah number
    assert stats["surahs"] == 114 and stats["ayahs"] == 6214
    fatiha = [a for a in built if a.surah == 1]
    assert len(fatiha) == 7
    assert fatiha[0].words[0].normalized == "الحمد"  # basmala is not ayah 1 in Warsh
    assert fatiha[5].words[-1].normalized == "عليهم"  # Madani: 1:6 ends at عليهم
    assert sum(1 for a in built if a.surah == 2) == 285


def test_hafs_and_warsh_differ_where_expected(hafs, warsh):
    h = {(a.surah, a.ayah): a for a in hafs[1]}
    w = {(a.surah, a.ayah): a for a in warsh[1]}
    assert [x.normalized for x in h[(1, 4)].words][0] == "ملك"  # Hafs 1:4
    assert [x.normalized for x in w[(1, 3)].words][0] == "ملك"  # Warsh 1:3
    assert h[(1, 4)].words[0].uthmani != w[(1, 3)].words[0].uthmani


def test_committed_warsh_db_matches_a_fresh_build(warsh, tmp_path):
    src, built = warsh
    out = tmp_path / "warsh.sqlite"
    write_db(src, built, verify(src, built), out)
    fresh, committed = sqlite3.connect(out), sqlite3.connect(WARSH_DB)
    for sql in [
        "SELECT * FROM surahs ORDER BY surah",
        "SELECT * FROM ayahs ORDER BY surah, ayah",
        "SELECT * FROM words ORDER BY surah, ayah, word_index",
    ]:
        assert fresh.execute(sql).fetchall() == committed.execute(sql).fetchall(), sql
