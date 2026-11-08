#!/usr/bin/env python3
"""Build a per-riwaya Quran SQLite DB for the app (docs/SPEC.md §3).

Hafs (Tanzil):
  python3 tools/build_quran_db.py hafs \
      --text tools/sources/tanzil/quran-uthmani.txt \
      --metadata tools/sources/tanzil/quran-data.xml \
      --out app/assets/quran/hafs.sqlite

Warsh (KFGQPC JSON, official download only — see docs/DATA_SOURCES.md):
  python3 tools/build_quran_db.py warsh --text path/to/warshData_vN.json --version N \
      --license "<terms as published by KFGQPC>" --out app/assets/quran/warsh.sqlite

The build fails (non-zero exit, no output file) on any integrity problem.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from quran_db.build import IntegrityError, build_ayahs, load_kfgqpc_json, load_tanzil, verify, write_db


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("riwaya", choices=["hafs", "warsh"])
    p.add_argument("--text", type=Path, required=True)
    p.add_argument("--metadata", type=Path, help="Tanzil quran-data.xml (hafs)")
    p.add_argument("--version", help="KFGQPC data version (warsh)")
    p.add_argument("--license", help="KFGQPC terms text (warsh)")
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args(argv)

    if a.riwaya == "hafs":
        if not a.metadata:
            p.error("hafs needs --metadata")
        src = load_tanzil(a.text, a.metadata)
    else:
        if not (a.version and a.license):
            p.error("warsh needs --version and --license")
        src = load_kfgqpc_json(a.text, a.license, a.version)

    try:
        built = build_ayahs(src)
        stats = verify(src, built)
    except IntegrityError as e:
        print(f"INTEGRITY FAILURE: {e}", file=sys.stderr)
        return 1
    write_db(src, built, stats, a.out)
    print(json.dumps({"riwaya": src.riwaya, "out": str(a.out), "sha256_source": src.sha256, **stats}, ensure_ascii=False))
    return 0


if __name__ == "__main__":

    sys.exit(main())
