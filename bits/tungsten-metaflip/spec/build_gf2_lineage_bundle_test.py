#!/usr/bin/env python3
"""Lineage bundle builder: chains -> compressed certificates + manifest the verifier accepts."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import build_gf2_lineage_bundle as B  # noqa: E402
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
import verify_gf2_lineage as V  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402

SEED = TOOLS.parent / "lib/metaflip/seeds/gf2/matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"
RECIPE = dict(kind="seed", rank=29, shape=[3, 3, 4], source=str(SEED.relative_to(TOOLS.parents[2])),
              source_sha256=hashlib.sha256(SEED.read_bytes()).hexdigest())

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    shape, terms = grb.decode(SEED, grb.load(SEED))
    base = sorted(terms)
    mode = next(m for m in range(6, 12) if top.blob(shape, two_pass(base, shape, m)) != top.blob(shape, base))
    (tmp / "basis.mfw").write_bytes(top.blob(shape, two_pass(base, shape, mode)))
    child_shape, projected = top.project(shape, base, 2, 0)
    width = max(child_shape[0] * child_shape[1], child_shape[1] * child_shape[2], child_shape[0] * child_shape[2])
    child, _ = top.compress_shared(projected, max_bits=width)
    (tmp / "child.mfw").write_bytes(top.blob(child_shape, child))

    root = dict(kind="closure", file=str(SEED), details=dict(recipe=RECIPE))
    chains = [[root, dict(kind="basis", file=str(tmp / "basis.mfw"), details=dict(mode=mode))],
              [root, dict(kind="projection", file=str(tmp / "child.mfw"),
                          details=dict(mode=None, axis=2, coordinate=0))]]
    spec = dict(walker="bits/tungsten-metaflip/tools/wide_rect_walk.w", chains=chains)
    B.build(spec, tmp / "bundle")
    manifest = json.loads((tmp / "bundle/manifest.json").read_text())
    assert [r["kind"] for r in manifest["rows"]] == ["closure", "basis", "projection"]   # root stored once
    assert manifest["rows"][1]["parent"] == manifest["rows"][2]["parent"] == manifest["rows"][0]["sha256"]
    assert V.main([str(tmp / "bundle")]) == 0                 # Python and Ruby

    # The same tensor reached with different provenance is rejected, as is a seed kind mid-chain.
    for bad, label in (([[root, dict(kind="basis", file=str(tmp / "basis.mfw"), details=dict(mode=mode)),
                          dict(kind="basis", file=str(SEED), details=dict(mode=mode))]], "cycle-back"),
                       ([[dict(kind="basis", file=str(SEED), details=dict(mode=mode))]], "unseeded chain"),
                       ([[root, dict(kind="closure", file=str(tmp / "basis.mfw"), details=dict(recipe=RECIPE))]],
                        "seed kind mid-chain")):
        try:
            B.build(dict(chains=bad), tmp / ("bad-" + label.replace(" ", "-")))
        except AssertionError:
            continue
        raise AssertionError(f"accepted: {label}")
print("PASS build_gf2_lineage_bundle: shared roots stored once, parents linked, verifier passes, bad chains rejected")
