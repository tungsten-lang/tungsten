#!/usr/bin/env python3
"""Verify a GF(2) lineage bundle: exact tensors, parent links, replayable steps, provenance.

A bundle directory holds `manifest.json` and one `<shape>-r<rank>-<sha8>.mfw.gz.b64` per row.
Rows form chains (`parent` is the parent row's SHA-256). What is checked, by row kind:

  public-mod2    upstream repository, revision and path recorded; with --source NAME=CLONE the
                 tensor is re-derived from the pinned upstream file (coefficients mod two)
  recipe-replay  catalogue repository, revision, file and lineage recorded; with
                 --source NAME=CLONE the recipe is replayed over GF(2) (mmc_gf2_replay) and must
                 give the same bytes when the row is marked rederivable
  closure        block-sum/Kronecker recipe with consistent rank arithmetic
  retained       a tensor already kept in a committed certificate; with --repo-root ROOT the
                 recorded repo-relative file must decode to the same tensor
  archived       a certificate recovered from git history (repository, revision, path,
                 source_sha256); with --source NAME=CLONE it is re-read at that revision and
                 must decode to the same tensor
  basis          two-pass basis rewrite of the parent reproduces the row
  projection     basis rewrite (optional), coordinate deletion and shared-factor compression of
                 the parent reproduce the row
  walk           same shape as the parent, rank never above it; with --replay-walk BINARY the
                 deterministic native walk (steps, nonce) reproduces the row byte-for-byte
                 (--replay-max-rank N replays only walks whose result has rank at most N)

Every tensor is expanded against the complete matrix-multiplication tensor in Python and, unless
--no-ruby, again by the independent Ruby reconstruction. `--source NAME=PATH` matches a row when
NAME occurs in its recorded repository URL.
"""
import argparse
import base64
import gzip
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

if not __debug__:
    raise RuntimeError("certificate verification requires Python assertions")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from search_wide_projection_walks import verify_file  # noqa: E402
from screen_public_ternary_gf2 import reduce_mod2  # noqa: E402

PROVENANCE = {"public-mod2": ("repository", "revision", "path", "source_sha256", "source_rank"),
              "recipe-replay": ("repository", "revision", "file", "lineage"),
              "retained": ("path",),
              "archived": ("repository", "revision", "path", "source_sha256")}
SEED_KINDS = ("public-mod2", "recipe-replay", "closure", "retained", "archived")


def decode(bundle, name):
    raw = (bundle / name).read_bytes().replace(b"\n", b"")
    return gzip.decompress(base64.b64decode(raw, validate=True))


def recipe_rank(node):
    """Rank implied by a composition recipe; split and product must add or multiply exactly."""
    kind = node["kind"]
    if kind == "naive":
        return math.prod(node["shape"])
    if kind in ("seed", "projection"):
        return node["rank"]
    left, right = recipe_rank(node["left"]), recipe_rank(node["right"])
    implied = left + right if kind == "split" else left * right
    assert kind in ("split", "product") and implied == node["rank"], f"inconsistent {kind} rank"
    return implied


def upstream_file(clone, details):
    """Bytes of the pinned upstream file: from git when the revision is present, else the tree."""
    path = details.get("path") or details.get("file")
    rev = details["revision"]
    if (Path(clone) / ".git").exists():
        shown = subprocess.run(["git", "-C", str(clone), "show", f"{rev}:{path}"], capture_output=True)
        if shown.returncode == 0:
            return shown.stdout
    return (Path(clone) / path).read_bytes()


def find_source(sources, details):
    for name, path in sources.items():
        if name in details["repository"]:
            return path
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--replay-walk", help="compiled tools/wide_rect_walk.w")
    parser.add_argument("--replay-max-rank", type=int, default=10 ** 9,
                        help="replay only walks whose result has at most this rank")
    parser.add_argument("--source", action="append", default=[], help="NAME=CLONE for re-derivation")
    parser.add_argument("--cache-dir", default="mmc-cache", help="matmulcatalog replay cache")
    parser.add_argument("--repo-root", type=Path, help="checkout root for `retained` rows")
    parser.add_argument("--no-ruby", action="store_true", help="skip the independent Ruby check")
    args = parser.parse_args(argv)
    sources = dict(item.split("=", 1) for item in args.source)
    manifest = json.loads((args.bundle / "manifest.json").read_text())
    assert (manifest["schema"], manifest["field"], manifest["record_claim"]) == (1, "GF(2)", False)
    states, counts, notes = {}, {}, []
    for row in manifest["rows"]:
        raw = decode(args.bundle, row["file"])
        assert hashlib.sha256(raw).hexdigest() == row["sha256"], row["file"]
        shape, terms = top.read_blob(raw)
        assert ("x".join(map(str, shape)), len(terms)) == (row["shape"], row["rank"]), row["file"]
        if args.no_ruby:
            top.exact(shape, terms)
        else:
            with tempfile.TemporaryDirectory() as temp:
                witness = Path(temp) / "tensor.mfw"
                witness.write_bytes(raw)
                assert verify_file(witness) == (shape, terms, row["sha256"])  # Python + Ruby
        kind, details = row["kind"], row.get("details", {})
        for key in PROVENANCE.get(kind, ()):
            assert details.get(key) not in (None, ""), f"{row['file']}: missing provenance {key}"
        checked = kind
        assert (row["parent"] is None) == (kind in SEED_KINDS), f"{row['file']}: parent link disagrees with kind"
        if kind in ("retained", "archived"):
            if kind == "retained" and args.repo_root is None:
                notes.append(f"{row['file']}: not checked against the committed certificate (no --repo-root)")
            elif kind == "retained":
                kept = args.repo_root / details["path"]
                kept_shape, kept_terms = grb.decode(kept, grb.load(kept))
                assert top.blob(kept_shape, kept_terms) == raw, f"retained tensor differs: {details['path']}"
                checked += "+matched"
            else:
                clone = find_source(sources, details)
                if clone is None:
                    notes.append(f"{row['file']}: not re-read from history (no --source for {details['repository']})")
                else:
                    original = upstream_file(clone, details)
                    assert hashlib.sha256(original).hexdigest() == details["source_sha256"]
                    old_shape, old_terms = grb.decode(Path(details["path"]), original)
                    assert top.blob(old_shape, old_terms) == raw, f"archived tensor differs: {details['path']}"
                    checked += "+rederived"
        elif kind in ("public-mod2", "recipe-replay"):
            clone = find_source(sources, details)
            if clone is None:
                notes.append(f"{row['file']}: not re-derived (no --source for {details['repository']})")
            elif kind == "public-mod2":
                source = upstream_file(clone, details)
                assert hashlib.sha256(source).hexdigest() == details["source_sha256"]
                public_shape, public_rank, public_terms = reduce_mod2(json.loads(source))
                assert public_rank == details["source_rank"]
                assert top.blob(public_shape, public_terms) == raw
                checked += "+rederived"
            elif details.get("rederivable", True):
                import mmc_gf2_replay as MR
                catalogue = MR.Source(clone, details["revision"], args.cache_dir)
                replayed = MR.Replayer(catalogue).materialize_file(details["file"])
                assert top.blob(replayed.shape, sorted(replayed.terms)) == raw, "replay differs"
                checked += "+rederived"
            else:
                notes.append(f"{row['file']}: recipe-replay seed is an equal-rank variant; not re-derived")
        elif kind == "closure":
            assert recipe_rank(details["recipe"]) == row["rank"]
        else:
            parent_shape, parent_terms, parent_raw = states[row["parent"]]
            if kind == "basis":
                assert top.blob(parent_shape, two_pass(parent_terms, parent_shape, details["mode"])) == raw
            elif kind == "projection":
                basis = parent_terms if details.get("mode") is None else \
                    two_pass(parent_terms, parent_shape, details["mode"])
                child_shape, projected = top.project(parent_shape, basis, details["axis"], details["coordinate"])
                width = max(child_shape[0] * child_shape[1], child_shape[1] * child_shape[2],
                            child_shape[0] * child_shape[2])
                compressed, _ = top.compress_shared(projected, max_bits=width)
                assert top.blob(child_shape, compressed) == raw
            elif kind == "walk":
                assert shape == parent_shape and len(terms) <= len(parent_terms)
                if args.replay_walk and len(terms) <= args.replay_max_rank:
                    with tempfile.TemporaryDirectory() as temp:
                        seed, out = Path(temp) / "seed.mfw", Path(temp) / "out.mfw"
                        seed.write_bytes(parent_raw)
                        subprocess.run([args.replay_walk, row["shape"], str(seed), str(out),
                                        str(details["steps"]), str(details["nonce"])],
                                       check=True, capture_output=True)
                        assert out.read_bytes() == raw, f"walk replay differs: {row['file']}"
                    checked += "+replayed"
            else:
                raise AssertionError(f"unknown row kind {kind}")
        counts[checked] = counts.get(checked, 0) + 1
        states[row["sha256"]] = shape, terms, raw
    finals = {}
    for row in manifest["rows"]:
        finals[row["shape"]] = min(finals.get(row["shape"], row["rank"]), row["rank"])
    print(f"PASS {len(states)} exact GF(2) tensors (Python{'' if args.no_ruby else ' and Ruby'}); rows: " +
          ", ".join(f"{n} {k}" for k, n in sorted(counts.items())))
    for note in notes:
        print("  note:", note)
    for shape, rank in sorted(finals.items(), key=lambda kv: tuple(map(int, kv[0].split("x")))):
        print(f"  {shape} rank {rank}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
