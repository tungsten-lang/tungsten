#!/usr/bin/env python3
"""Check the retained GF(2) walks from public integer schemes.

Default: every SHA-256, rank, and full GF(2) tensor (Python and Ruby), plus
the lineage (each walk keeps its parent's shape and never raises rank).
  --replay-walk BINARY    rerun every walk with tools/wide_rect_walk.w and
                          require a byte-identical result
  --source NAME=PATH      re-derive each public mod-2 seed from a local clone
                          (perminov=..., merlijn=...) at the pinned revision
"""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

if not __debug__:
    raise RuntimeError("certificate verification requires Python assertions")

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as top  # noqa: E402
from screen_public_ternary_gf2 import reduce_mod2  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402


def decode(name):
    return gzip.decompress(base64.b64decode((HERE / name).read_bytes().replace(b"\n", b""), validate=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--replay-walk")
    parser.add_argument("--source", action="append", default=[])
    args = parser.parse_args()
    sources = dict(item.split("=", 1) for item in args.source)
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert (manifest["schema"], manifest["field"], manifest["record_claim"]) == (1, "GF(2)", False)
    states = {}
    replayed = rederived = 0
    for row in manifest["rows"]:
        raw = decode(row["file"])
        assert hashlib.sha256(raw).hexdigest() == row["sha256"], row["file"]
        shape, terms = top.read_blob(raw)
        assert ("x".join(map(str, shape)), len(terms)) == (row["shape"], row["rank"]), row["file"]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "tensor.mfw"
            path.write_bytes(raw)
            assert verify_file(path) == (shape, terms, row["sha256"])  # Python + Ruby
            if row["kind"] == "public-mod2":
                assert row["parent"] is None
                details = row["details"]
                repo = sources.get("merlijn" if "fmm-schemes" in details["repository"] else "perminov")
                if repo:
                    name = details["path"]
                    if "fmm-schemes" in details["repository"]:
                        source = (Path(repo) / name).read_bytes()
                    else:
                        source = subprocess.check_output(
                            ["git", "-C", repo, "show", f"{details['revision']}:{name}"])
                    assert hashlib.sha256(source).hexdigest() == details["source_sha256"]
                    public_shape, public_rank, public_terms = reduce_mod2(json.loads(source))
                    assert public_rank == details["source_rank"]
                    assert top.blob(public_shape, public_terms) == raw
                    rederived += 1
            else:
                assert row["kind"] == "walk"
                parent_shape, parent_terms, parent_raw = states[row["parent"]]
                assert parent_shape == shape and len(terms) <= len(parent_terms)
                if args.replay_walk:
                    seed = Path(temp) / "seed.mfw"
                    seed.write_bytes(parent_raw)
                    output = Path(temp) / "out.mfw"
                    subprocess.run([args.replay_walk, row["shape"], str(seed), str(output),
                                    str(row["details"]["steps"]), str(row["details"]["nonce"])],
                                   check=True, capture_output=True)
                    assert output.read_bytes() == raw, f"walk replay differs: {row['file']}"
                    replayed += 1
        states[row["sha256"]] = shape, terms, raw
    finals = {}
    for row in manifest["rows"]:
        finals[row["shape"]] = min(finals.get(row["shape"], row["rank"]), row["rank"])
    print(f"PASS {len(states)} exact GF(2) tensors (Python and Ruby); {replayed} walks replayed; "
          f"{rederived} public seeds re-derived")
    for shape, rank in sorted(finals.items(), key=lambda kv: tuple(map(int, kv[0].split("x")))):
        print(f"  {shape} rank {rank}")


if __name__ == "__main__":
    main()
