#!/usr/bin/env python3
"""GF(2) lineage bundle verifier: every row kind, and rejection of tampered bundles."""
import base64
import copy
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import gf2_record_board as grb  # noqa: E402
import mmc_gf2_alg as G  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
import verify_gf2_lineage as V  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402


def m(*idx):
    return sum(1 << i for i in idx)


STRASSEN = G.Alg(2, 2, 2, [
    (m(0, 3), m(0, 3), m(0, 3)), (m(2, 3), m(0), m(2, 3)), (m(0), m(1, 3), m(1, 3)),
    (m(3), m(0, 2), m(0, 2)), (m(0, 1), m(3), m(0, 1)), (m(0, 2), m(0, 1), m(3)),
    (m(1, 3), m(2, 3), m(0)),
])
SEVEN = dict(kind="seed", rank=7, shape=[2, 2, 2], source="lib/metaflip/seeds/gf2/strassen.txt")


def add_row(bundle, rows, terms, shape, kind, parent, details):
    raw = top.blob(shape, terms)
    digest = hashlib.sha256(raw).hexdigest()
    name = f"{'x'.join(map(str, shape))}-r{len(terms)}-{digest[:8]}.mfw.gz.b64"
    (bundle / name).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
    rows.append(dict(kind=kind, parent=parent, shape="x".join(map(str, shape)), rank=len(terms),
                     sha256=digest, file=name, details=details))
    return digest


def write_manifest(bundle, rows):
    (bundle / "manifest.json").write_text(json.dumps(
        dict(schema=1, field="GF(2)", record_claim=False, rows=rows), indent=1))


def run(bundle, *extra):
    return V.main([str(bundle), "--no-ruby", *extra])


# Recipe arithmetic on its own: split adds, product multiplies, mutations are rejected.
NAIVE = dict(kind="naive", shape=[2, 2, 3])
assert V.recipe_rank(dict(kind="split", rank=19, axis=2, left=SEVEN, right=NAIVE)) == 19
assert V.recipe_rank(dict(kind="product", rank=49, left=SEVEN, right=SEVEN)) == 49
for broken in (dict(kind="split", rank=20, axis=2, left=SEVEN, right=NAIVE),
               dict(kind="product", rank=48, left=SEVEN, right=SEVEN),
               dict(kind="magic", rank=7, left=SEVEN, right=SEVEN)):
    try:
        V.recipe_rank(broken)
    except AssertionError:
        continue
    raise AssertionError(f"inconsistent recipe accepted: {broken}")

# A packaged repo seed whose basis rewrites really change the tensor (modes 6..9 differ).
SEED = Path(__file__).resolve().parents[1] / "lib/metaflip/seeds/gf2/matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"

with tempfile.TemporaryDirectory() as tmp:
    good = Path(tmp) / "good"
    good.mkdir()
    rows = []
    shape, seed_terms = grb.decode(SEED, grb.load(SEED))
    base = sorted(seed_terms)
    recipe = dict(kind="seed", rank=len(base), shape=list(shape), source=str(SEED.relative_to(SEED.parents[3])),
                  source_sha256=hashlib.sha256(SEED.read_bytes()).hexdigest())
    root = add_row(good, rows, base, shape, "closure", None, dict(recipe=recipe))
    outs = {mode: two_pass(base, shape, mode) for mode in range(6, 12)}
    blobs = {mode: top.blob(shape, terms) for mode, terms in outs.items()}   # canonical bytes
    mode_a = next(mode for mode in outs if blobs[mode] != top.blob(shape, base))
    mode_b = next(mode for mode in outs if blobs[mode] not in (top.blob(shape, base), blobs[mode_a]))
    basis_terms = list(outs[mode_a])
    basis = add_row(good, rows, basis_terms, shape, "basis", root, dict(mode=mode_a))
    add_row(good, rows, basis_terms, shape, "walk", basis, dict(steps=1000, nonce=7))
    child_shape, projected = top.project(shape, base, 2, 0)
    width = max(child_shape[0] * child_shape[1], child_shape[1] * child_shape[2], child_shape[0] * child_shape[2])
    child, _ = top.compress_shared(projected, max_bits=width)
    add_row(good, rows, child, child_shape, "projection", root, dict(mode=None, axis=2, coordinate=0))
    # a coordinate whose projection differs from coordinate 0
    other_shape, other_projected = top.project(shape, base, 2, 3)
    other, _ = top.compress_shared(other_projected, max_bits=width)
    assert top.blob(other_shape, other) != top.blob(child_shape, child)
    write_manifest(good, rows)
    assert run(good) == 0

    # The independent Ruby reconstruction agrees.
    assert V.main([str(good)]) == 0

    def rejects(mutate, label):
        bad = Path(tmp) / label
        shutil.copytree(good, bad)
        manifest = json.loads((bad / "manifest.json").read_text())
        mutate(bad, manifest["rows"])
        (bad / "manifest.json").write_text(json.dumps(manifest))
        try:
            run(bad)
        except (AssertionError, KeyError, ValueError):
            return
        raise AssertionError(f"tampered bundle accepted: {label}")

    def corrupt_file(bundle, rows_):
        rows_[0]["file"] = rows_[3]["file"]                    # digest of another tensor
    rejects(corrupt_file, "file-swap")

    def bad_recipe(bundle, rows_):
        rows_[0]["details"]["recipe"]["rank"] = 30            # a seed recipe must state the row rank
    rejects(bad_recipe, "recipe-rank")

    def bad_projection(bundle, rows_):
        rows_[3]["details"]["coordinate"] = 3                  # different coordinate, same file
    rejects(bad_projection, "projection-coordinate")

    def bad_basis(bundle, rows_):
        rows_[1]["details"]["mode"] = mode_b                   # a different basis order
    rejects(bad_basis, "basis-mode")

    def unknown_kind(bundle, rows_):
        rows_[2]["kind"] = "magic"
    rejects(unknown_kind, "unknown-kind")

    def walk_grows(bundle, rows_):                             # a "walk" may never raise the rank
        rows_[2], rows_[0] = rows_[0], rows_[2]
        rows_[0]["parent"], rows_[2]["parent"] = None, rows_[1]["sha256"]
        rows_[1]["parent"] = rows_[0]["sha256"]
    rejects(walk_grows, "walk-shape")

    def missing_provenance(bundle, rows_):
        rows_[0]["kind"] = "public-mod2"
        rows_[0]["details"] = dict(repository="https://example.org/x")
    rejects(missing_provenance, "provenance")

# `retained` (a committed certificate) and `archived` (re-read from git history) seed rows.
REPO = SEED.parents[3]
with tempfile.TemporaryDirectory() as tmp:
    shape, seed_terms = grb.decode(SEED, grb.load(SEED))
    base = sorted(seed_terms)
    kept = Path(tmp) / "retained"
    kept.mkdir()
    rows = []
    add_row(kept, rows, base, shape, "retained", None, dict(path=str(SEED.relative_to(REPO))))
    write_manifest(kept, rows)
    assert V.main([str(kept), "--no-ruby", "--repo-root", str(REPO)]) == 0
    other = SEED.with_name("matmul_3x3x4_rank29_gf2.txt")   # a different rank-29 tensor of the same shape
    assert other.exists() and other != SEED
    bad = json.loads((kept / "manifest.json").read_text())
    bad["rows"][0]["details"]["path"] = str(other.relative_to(REPO))
    (kept / "manifest.json").write_text(json.dumps(bad))
    try:
        V.main([str(kept), "--no-ruby", "--repo-root", str(REPO)])
    except AssertionError:
        pass
    else:
        raise AssertionError("retained mismatch accepted")

    history = Path(tmp) / "history"
    (history / "benchmarks").mkdir(parents=True)
    old_name = "benchmarks/matmul_3x3x4_rank29_archive_gf2.txt"
    (history / old_name).write_bytes(SEED.read_bytes())
    git = ["git", "-C", str(history), "-c", "user.name=t", "-c", "user.email=t@t"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    subprocess.run(git + ["add", "-f", "."], check=True)
    subprocess.run(git + ["commit", "-qm", "certificate"], check=True)
    revision = subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip()
    details = dict(repository="https://example.org/tungsten-history", revision=revision, path=old_name,
                   source_sha256=hashlib.sha256(SEED.read_bytes()).hexdigest())
    archived = Path(tmp) / "archived"
    archived.mkdir()
    rows = []
    add_row(archived, rows, base, shape, "archived", None, details)
    write_manifest(archived, rows)
    assert V.main([str(archived), "--no-ruby", "--source", f"tungsten-history={history}"]) == 0
    bad = json.loads((archived / "manifest.json").read_text())
    bad["rows"][0]["details"]["source_sha256"] = "0" * 64
    (archived / "manifest.json").write_text(json.dumps(bad))
    try:
        V.main([str(archived), "--no-ruby", "--source", f"tungsten-history={history}"])
    except AssertionError:
        pass
    else:
        raise AssertionError("archived digest mismatch accepted")
print("PASS verify_gf2_lineage: closure, basis, projection, walk, retained, archived rows; tampering rejected")
