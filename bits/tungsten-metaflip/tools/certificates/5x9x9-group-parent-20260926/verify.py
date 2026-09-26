#!/usr/bin/env python3
"""Replay the group construction, static leaf lineage and complete MFW tensor."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
ROOT = TOOLS.parents[2]
sys.path.insert(0, str(TOOLS))
import search_wide_auto_loop as loop  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402
from wide_composition_recipes import replay_recipe  # noqa: E402


def check(condition, message):
    if not condition:
        raise ValueError(message)


meta = json.loads((HERE / "metadata.json").read_text())
check((meta["schema"], meta["field"], meta["record_claim"],
       meta["shape"], meta["rank"]) == (1, "GF(2)", False, [9, 9, 5], 294),
      "unsupported group-parent metadata")
source = (ROOT / meta["source"]).resolve()
check(source.is_relative_to(ROOT) and
      hashlib.sha256(source.read_bytes()).hexdigest() == meta["source_sha256"],
      "packaged parent changed")
recipe_path = (HERE / meta["recipe"]).resolve()
file_path = (HERE / meta["file"]).resolve()
check(recipe_path.is_relative_to(HERE) and file_path.is_relative_to(HERE),
      "unsafe certificate path")
recipe = json.loads(recipe_path.read_text())
check(recipe["parent"]["sha256"] == meta["source_sha256"], "parent lineage mismatch")
check(recipe["field"] == "GF(2)" and recipe["record_claim"] is False and
      recipe["scale"] == [3, 3, 1], "construction metadata mismatch")
check({leaf["snapshot"] for leaf in meta["static_leaves"]} ==
      {group["leaf"]["path"] for group in recipe["groups"]},
      "missing static leaf lineage")
for leaf in meta["static_leaves"]:
    terms = replay_recipe(leaf["plan"])
    terms = loop.top.orient(tuple(leaf["plan"]["shape"]), terms, tuple(leaf["shape"]))
    snapshot = (HERE / leaf["snapshot"]).resolve()
    check(snapshot.is_relative_to(HERE) and
          sorted(loop.top.parse_terms(snapshot.read_bytes(), leaf["rank"])) == sorted(terms),
          "static leaf lineage mismatch")
audit = json.loads(subprocess.check_output(
    ["ruby", str(TOOLS / "bud_products.rb"), "--replay", str(recipe_path)],
    text=True))
check(audit["exact"] and audit["rank"] == 294 and audit["shape"] == "9x9x5",
      "independent construction failed")
check(audit["sha256"] == recipe["result"]["sha256"], "construction result changed")
snapshot = (HERE / recipe["result"]["path"]).resolve()
check(snapshot.is_relative_to(HERE), "unsafe result snapshot")
raw = loop.read_seed(file_path)
shape, terms = loop.top.read_blob(raw)
check(shape == (9, 9, 5) and terms == sorted(loop.top.parse_terms(snapshot.read_bytes(), 294)),
      "MFW encoding differs from construction")
with tempfile.TemporaryDirectory() as temp:
    witness = Path(temp) / "group-parent.mfw"
    witness.write_bytes(raw)
    checked = verify_file(witness)
check(checked == (shape, terms, meta["sha256"]), "full tensor or MFW hash mismatch")
print("PASS exact rank-294 group parent, independent construction and static leaf lineage")
