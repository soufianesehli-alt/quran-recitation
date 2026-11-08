#!/usr/bin/env python3
"""Convert a Quran fine-tuned Whisper model to whisper.cpp (ggml) and quantise it.

Reproducible: model revision and weight hash are pinned; every output hash is written to
`<out>/<name>.manifest.json`. Model binaries are NOT committed (see .gitignore); the manifest
is, so anyone can rebuild and verify the exact file shipped in the app.

Requirements (run in a virtualenv): torch, transformers, numpy; a clone of
github.com/openai/whisper (mel filters); a whisper.cpp checkout at the SAME version as
app/native/whisper.cpp with `whisper-quantize` built.

  python3 tools/convert_model.py tiny --whisper-cpp <whisper.cpp> --openai-whisper <whisper> \
      --work <scratch dir> --out <dir>
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

# Pinned sources (licences verified in docs/DATA_SOURCES.md §3).
MODELS = {
    "tiny": {
        "repo": "tarteel-ai/whisper-tiny-ar-quran",
        "revision": "c3d7e624af5c81bef25a10a2af3a5a84cb4dd0f0",
        "weights_sha256": "f26c96202427524ec015bcf25bd932414df0474e538d765c16759f1095757688",
        "license": "apache-2.0",
        "base_model": "openai/whisper-tiny",
    },
    "base": {
        "repo": "tarteel-ai/whisper-base-ar-quran",
        "revision": "5c3c53fdf9272c4f6ee0bee09a1e5a4a615ee25c",
        "weights_sha256": "ec75894993a4570a237b2b1c19fd8a448f1e8f6e083cfab699574f7be53874fa",
        "license": "apache-2.0",
        "base_model": "openai/whisper-base",
    },
}
FILES = [
    "config.json", "pytorch_model.bin", "vocab.json", "merges.txt", "added_tokens.json",
    "special_tokens_map.json", "tokenizer_config.json", "normalizer.json",
    "preprocessor_config.json",
]
QUANTS = ["q8_0", "q5_1"]


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(spec: dict, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        target = dest / name
        if not target.exists():
            url = f"https://huggingface.co/{spec['repo']}/resolve/{spec['revision']}/{name}"
            print(f"download {url}")
            with urllib.request.urlopen(url) as r, target.open("wb") as f:
                shutil.copyfileobj(r, f)
    got = sha256(dest / "pytorch_model.bin")
    if got != spec["weights_sha256"]:
        raise SystemExit(f"weights hash mismatch: {got} != {spec['weights_sha256']}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("size", choices=sorted(MODELS))
    ap.add_argument("--whisper-cpp", type=Path, required=True)
    ap.add_argument("--openai-whisper", type=Path, required=True)
    ap.add_argument("--work", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()

    spec = MODELS[a.size]
    hf_dir = a.work / "hf" / spec["repo"].split("/")[1]
    download(spec, hf_dir)

    # whisper.cpp's converter takes the decoder context size from config "max_length", which
    # in the base fine-tune is a generation setting (1024), not the architecture (448 =
    # "max_target_positions", matching the weights). Convert from a copy whose max_length is
    # set to max_target_positions; the weights themselves are not touched.
    conv_dir = a.work / f"hf-conv-{a.size}"
    conv_dir.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        link = conv_dir / name
        if not link.exists():
            link.symlink_to((hf_dir / name).resolve())
    cfg = json.loads((hf_dir / "config.json").read_text())
    config_fix = None
    if cfg.get("max_length") != cfg["max_target_positions"]:
        config_fix = {"max_length": [cfg.get("max_length"), cfg["max_target_positions"]]}
        cfg["max_length"] = cfg["max_target_positions"]
    (conv_dir / "config.json").unlink()
    (conv_dir / "config.json").write_text(json.dumps(cfg, indent=2))

    ggml_dir = a.work / f"ggml-{a.size}"
    ggml_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [sys.executable, str(a.whisper_cpp / "models/convert-h5-to-ggml.py"), str(conv_dir), str(a.openai_whisper), str(ggml_dir)],
        check=True,
    )
    f16 = ggml_dir / "ggml-model.bin"
    a.out.mkdir(parents=True, exist_ok=True)
    name = f"quran-whisper-{a.size}"
    outputs = {}
    for q in QUANTS:
        dst = a.out / f"{name}-{q}.bin"
        subprocess.run([str(a.whisper_cpp / "build/bin/whisper-quantize"), str(f16), str(dst), q], check=True, stdout=subprocess.DEVNULL)
        outputs[dst.name] = {"sha256": sha256(dst), "bytes": dst.stat().st_size, "quant": q}

    wcpp_rev = subprocess.run(["git", "-C", str(a.whisper_cpp), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    manifest = {
        "source": spec,
        "whisper_cpp_commit": wcpp_rev,
        "converted_on": dt.date.today().isoformat(),
        "conversion_config_fix": config_fix,
        "f16_sha256": sha256(f16),
        "outputs": outputs,
    }
    (a.out / f"{name}.manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
