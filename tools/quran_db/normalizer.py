"""Arabic matching normalizer (build-time twin of app/lib/core/arabic/normalizer.dart).

The output is a MATCHING KEY only. It is never displayed and never replaces the source text
(Tanzil terms: "CHANGING IT IS NOT ALLOWED"). Both implementations are checked against the
same vectors in tools/normalizer_vectors.json, so they cannot drift apart.

Rules (code-point based; no Unicode NFC, so Dart and Python behave identically):
  1. Remove harakat and Quranic annotation marks: U+064B-U+065F, U+0670 (superscript alef),
     U+06D6-U+06ED (small high letters, pause/sajdah/rub marks, small waw/yeh),
     U+08D3-U+08FF, tatweel U+0640, and format characters U+200B-U+200F, U+FEFF.
  2. Unify letters: alef forms (U+0622, U+0623, U+0625, U+0671, U+0672, U+0673) -> ا;
     ى U+0649, ے U+06D2 (dotless final yeh in the KFGQPC Warsh encoding), ی U+06CC -> ي;
     ؤ -> و; ئ -> ي; ة -> ه; ک U+06A9 -> ك.
  3. Drop everything that is not an Arabic base letter (digits, spaces, punctuation).
     Hamza on the line (ء) is kept.
"""

from __future__ import annotations

_REMOVE_RANGES = (
    (0x064B, 0x065F),
    (0x0670, 0x0670),
    (0x06D6, 0x06ED),
    (0x08D3, 0x08FF),
    (0x0640, 0x0640),
    (0x200B, 0x200F),
    (0xFEFF, 0xFEFF),
)

_MAP = {
    0x0622: "ا", 0x0623: "ا", 0x0625: "ا", 0x0671: "ا", 0x0672: "ا", 0x0673: "ا",
    0x0649: "ي", 0x06D2: "ي", 0x06CC: "ي",
    0x0624: "و",
    0x0626: "ي",
    0x0629: "ه",
    0x06A9: "ك",
}

# Arabic base letters kept in the key: ء U+0621, ا U+0627 .. ي U+064A minus tatweel.
ALLOWED = frozenset(chr(c) for c in range(0x0621, 0x064B) if c != 0x0640) - frozenset(
    chr(c) for c in _MAP
)


def _removed(cp: int) -> bool:
    return any(lo <= cp <= hi for lo, hi in _REMOVE_RANGES)


def normalize(text: str) -> str:
    out = []
    for ch in text:
        cp = ord(ch)
        if _removed(cp):
            continue
        ch = _MAP.get(cp, ch)
        if ch in ALLOWED:
            out.append(ch)
    return "".join(out)
