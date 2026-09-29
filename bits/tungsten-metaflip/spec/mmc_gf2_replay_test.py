#!/usr/bin/env python3
"""matmulcatalog GF(2) replay on a synthetic catalogue: exactness, atoms, ring gates, attribution."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import mmc_gf2_alg as G  # noqa: E402
import mmc_gf2_replay as MR  # noqa: E402
import mmc_gf2_seeds as SEEDS  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402


def m(*idx):
    return sum(1 << i for i in idx)


STRASSEN = G.Alg(2, 2, 2, [
    (m(0, 3), m(0, 3), m(0, 3)), (m(2, 3), m(0), m(2, 3)), (m(0), m(1, 3), m(1, 3)),
    (m(3), m(0, 2), m(0, 2)), (m(0, 1), m(3), m(0, 1)), (m(0, 2), m(0, 1), m(3)),
    (m(1, 3), m(2, 3), m(0)),
])
assert G.check_exact(STRASSEN)


def atom_json(alg, first_u=None):
    """A catalogue atom file in the public layout: dense u/v and column-major w."""
    n, mm, p = alg.shape
    u = [[(t[0] >> i) & 1 for i in range(n * mm)] for t in alg.terms]
    v = [[(t[1] >> i) & 1 for i in range(mm * p)] for t in alg.terms]
    w = []
    for t in alg.terms:
        row = [0] * (n * p)
        for q in range(n * p):
            if (t[2] >> q) & 1:
                i, j = divmod(q, p)
                row[j * n + i] = 1
        w.append(row)
    if first_u is not None:
        u[0][0] = first_u
    return dict(n=list(alg.shape), m=alg.r, z2=False, u=u, v=v, w=w)


ATOM = "known/section2/2x2x2-r7-strassen-abcdef0.json"
QONLY = "known/section2/2x2x2-r7-rational-1111111.json"
DERIVED = "derived/section4/4x4x4-r49-derived-fedcba9.json"
FORCED_F2 = "derived/section4/4x4x4-r48-derived-2222222.json"
LINEAGE = {"op": "KronProduct", "outer": {"op": "Atom", "ref": "2x2x2-r7-strassen-abcdef0"},
           "inner": {"op": "Atom", "ref": "2x2x2-r7-strassen-abcdef0"}}


def catalog_entry(path, shape, rank, fields, **extra):
    return dict(format=list(shape), rank=rank, fields=fields, file=path, **extra)


with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp) / "mmc"
    schemes = repo / MR.Source.PREFIX
    files = {ATOM: atom_json(STRASSEN), QONLY: atom_json(STRASSEN, first_u="1/2"),
             DERIVED: dict(n=[4, 4, 4], m=49, lineage=LINEAGE),
             FORCED_F2: dict(n=[4, 4, 4], m=48, lineage=LINEAGE)}
    for path, doc in files.items():
        (schemes / path).parent.mkdir(parents=True, exist_ok=True)
        (schemes / path).write_text(json.dumps(doc))
    (repo / "docs").mkdir()
    catalog = [
        catalog_entry(ATOM, (2, 2, 2), 7, ["F2", "Z", "Q"], source="Strassen 1969", year=1969, atom=True),
        catalog_entry(QONLY, (2, 2, 2), 7, ["Q"], source="rational", atom=True),
        catalog_entry(DERIVED, (4, 4, 4), 49, ["F2", "Z"], lineage_compact="2x2x2 kron 2x2x2"),
        # A stamped-F2 target below what its recipe can reach: the catalogue over-claims.
        catalog_entry(FORCED_F2, (4, 4, 4), 48, ["F2"], lineage_compact="claims 48"),
    ]
    (repo / "docs/catalog.json").write_text(json.dumps(dict(total=len(catalog), schemes=catalog)))
    git = ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    subprocess.run(git + ["add", "-f", "."], check=True)
    subprocess.run(git + ["commit", "-qm", "fixture"], check=True)
    revision = subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip()

    source = MR.Source(repo, "HEAD", Path(tmp) / "cache")
    assert source.revision == revision
    assert source.atom_info(ATOM)["source"] == "Strassen 1969" and source.atom_info(ATOM)["year"] == 1969

    # Recipe replay: exact, and the only dependency is the Strassen atom.
    rp = MR.Replayer(source)
    a = rp.materialize_file(DERIVED)
    assert a.shape == (4, 4, 4) and a.r == 49 and G.check_exact(a)
    assert rp.deps_file[DERIVED] == {("atom", ATOM)}
    # A second replayer reads the cached tensor and reports the same dependencies.
    rp2 = MR.Replayer(source)
    b = rp2.materialize_file(DERIVED)
    assert sorted(b.terms) == sorted(a.terms) and rp2.deps_file[DERIVED] == {("atom", ATOM)}

    # An even-denominator coefficient cannot reduce to GF(2).
    try:
        MR.Replayer(source).materialize_file(QONLY)
    except MR.ReplayError:
        pass
    else:
        raise AssertionError("even denominator accepted")
    # Candidate leaves honour the F2 stamp.
    assert [e["file"] for e in rp.candidates((2, 2, 2))] == [ATOM]

    # End to end: targets -> exact seeds with attribution; the over-claiming target is a failure.
    targets = [dict(mmc_file=DERIVED, canonical="4x4x4", mmc_rank=49),
               dict(mmc_file=FORCED_F2, canonical="4x4x4", mmc_rank=48)]
    (Path(tmp) / "targets.json").write_text(json.dumps(dict(targets=targets)))
    out = Path(tmp) / "out"
    args = ["replay", "--clone", str(repo), "--cache-dir", str(Path(tmp) / "cache2"),
            "--targets", str(Path(tmp) / "targets.json"), "--out", str(out)]
    assert SEEDS.main(args) == 0
    seeds = json.loads((out / "seeds.json").read_text())
    assert len(seeds) == 1 and seeds[0]["gf2_rank"] == 49 and seeds[0]["leaf_mode"] == "pure"
    shape, terms = top.read_blob(Path(seeds[0]["mfw"]).read_bytes())
    top.exact(shape, terms)
    attribution = seeds[0]["attribution"]
    assert attribution["catalogue"]["repository"] == SEEDS.REPOSITORY
    assert attribution["catalogue"]["revision"] == revision and attribution["catalogue"]["file"] == DERIVED
    assert [x["source"] for x in attribution["atoms"]] == ["Strassen 1969"]
    results = [json.loads(line) for line in (out / "results.jsonl").read_text().splitlines()]
    failed = [r for r in results if r["status"] != "ok"]
    assert len(failed) == 1 and failed[0]["mmc_file"] == FORCED_F2 and "above catalogue rank" in failed[0]["reason"]
    # Re-running skips recorded targets.
    assert SEEDS.main(args) == 0
    assert len((out / "results.jsonl").read_text().splitlines()) == 2
print("PASS mmc_gf2_replay: recipe replay, cache parity, ring gate, over-claim failure, attribution")
