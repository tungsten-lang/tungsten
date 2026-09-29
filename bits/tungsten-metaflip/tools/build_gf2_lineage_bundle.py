#!/usr/bin/env python3
"""Write a GF(2) lineage bundle (see verify_gf2_lineage.py) from explicit chain descriptions.

usage: build_gf2_lineage_bundle.py CHAINS.json OUT_DIR

CHAINS.json:
  {"walker": "bits/tungsten-metaflip/tools/wide_rect_walk.w",      # optional
   "chains": [[STEP, ...], ...]}       # each chain runs from a seed row to the retained tensor
STEP: {"kind": "public-mod2|recipe-replay|closure|basis|projection|walk",
       "file": "path to the MFW1 tensor (MFW1 text or .mfw.gz.b64)",
       "details": {...}}               # per-kind fields checked by verify_gf2_lineage.py

Shape, rank and SHA-256 come from the tensor itself; a step's parent is the previous step of its
chain. Identical tensors shared by several chains are stored once, and a row reached by two
chains with different provenance is rejected. The builder finishes by running the verifier.
"""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402

SEED_KINDS = ("public-mod2", "recipe-replay", "closure")


def build(spec, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=False)
    rows, by_sha = [], {}
    for chain in spec["chains"]:
        parent = None
        for index, step in enumerate(chain):
            path = Path(step["file"])
            shape, terms = grb.decode(path, grb.load(path))      # exact-checked
            raw = top.blob(shape, terms)
            digest = hashlib.sha256(raw).hexdigest()
            assert (index == 0) == (step["kind"] in SEED_KINDS), f"{path}: seed kinds start a chain"
            row = dict(kind=step["kind"], parent=parent, shape="x".join(map(str, shape)), rank=len(terms),
                       sha256=digest, details=step.get("details", {}))
            if digest in by_sha:
                old = by_sha[digest]
                assert (old["kind"], old["parent"], old["details"]) == (row["kind"], row["parent"], row["details"]), \
                    f"{path}: same tensor reached with different provenance"
            else:
                row["file"] = f"{row['shape']}-r{row['rank']}-{digest[:8]}.mfw.gz.b64"
                (out / row["file"]).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
                by_sha[digest] = row
                rows.append(row)
            parent = digest
    manifest = dict(schema=1, field="GF(2)", record_claim=False, rows=rows)
    if spec.get("walker"):
        manifest["walker"] = spec["walker"]
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    return manifest


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        print(__doc__)
        return 2
    spec = json.loads(Path(argv[0]).read_text())
    manifest = build(spec, argv[1])
    import verify_gf2_lineage as V
    V.main([argv[1], "--no-ruby"])
    print(f"{len(manifest['rows'])} rows written to {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
