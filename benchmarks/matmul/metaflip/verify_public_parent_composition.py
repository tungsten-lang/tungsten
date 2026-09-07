#!/usr/bin/env python3
"""Independent partition, orientation, leaf-substitution and full-tensor replay.

This checks constructive upper bounds, not global records or packing optimality.
"""
import argparse
from collections import defaultdict
import hashlib
from itertools import product
import json
from pathlib import Path

from verify_bud_renewal import factor_maps, verify_products
from verify_matrix_pockets import signature
from verify_representation_portfolio import contained, identity, parse_terms


def check_screen(root, screen, baseline):
    assert screen["complete"] and screen["field"] == "GF(2)" and not screen["record_claim"]
    assert screen["screen_only"] and not screen["canonical_archive_changed"]
    prices = {tuple(r["shape"]): r["augmented_rank"] for r in baseline["rows"]}
    maximum = max(max(s) for s in prices)
    options = screen["options"]
    role = options.get('candidate_role', 'public')
    assert role in ('public', 'search')
    max_scale, max_leaf = options["max_scale"], options["max_leaf"]
    assert type(max_scale) is int and 1 <= max_scale <= max_leaf <= maximum <= 32

    def rank(shape):
        assert len(shape) == 3 and all(type(d) is int and 1 <= d <= maximum for d in shape)
        return shape[0]*shape[1]*shape[2] if 1 in shape else prices[tuple(sorted(shape))]

    parents = []
    for i, row in enumerate(screen["parents"]):
        assert row["id"] == i and row["role"] in (role, "control")
        e = row["snapshot"]
        shape = e["shape"]
        assert shape == sorted(shape) == row["shape"]
        raw = contained(root, e["path"]).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == e["sha256"]
        terms = parse_terms(raw, row["rank"])
        assert all(0 < v < 1 << (shape[r]*shape[c])
                   for t in terms for v, (r, c) in zip(t, ((0, 1), (1, 2), (0, 2))))
        n, m, p = shape
        assert signature(terms) == {(i*m+j, j*p+k, i*p+k)
                                    for i, j, k in product(range(n), range(m), range(p))}
        assert identity(shape, terms) == row["canonical_id"]
        assert sum(v.bit_count() for t in terms for v in t) == row["density"]
        parents.append((shape, terms))
    expected = {(i, scale) for i, (shape, _) in enumerate(parents)
                for scale in product(*(range(1, min(max_scale, maximum//d)+1) for d in shape))
                if scale != (1, 1, 1)}
    seen, by_target, comparisons = set(), defaultdict(list), defaultdict(list)
    for row in screen["rows"]:
        i, scale = row["parent"], tuple(row["scale"])
        key = i, scale
        assert key in expected and key not in seen
        seen.add(key)
        shape, terms = parents[i]
        assert sorted(j for g in row["groups"] for j in g["indices"]) == list(range(len(terms)))
        formula = 0
        for group in row["groups"]:
            block, _ = factor_maps(terms, group)
            leaf = [d*s for d, s in zip(block, scale)]
            assert max(leaf) <= max_leaf
            formula += rank(leaf)
        target = sorted(d*s for d, s in zip(shape, scale))
        assert target == row["target"]
        assert (row["baseline"], row["formula"], row["gain"]) == (rank(target), formula, rank(target)-formula)
        by_target[tuple(target)].append(row)
        comparisons[(tuple(shape), scale)].append(row)
    assert seen == expected
    selected = [min(rr, key=lambda r: (r["formula"], r["parent"], r["scale"])) for rr in by_target.values()]
    assert selected == screen["selected"]
    paired = []
    for (shape, scale), rr in comparisons.items():
        public = [r for r in rr if screen["parents"][r["parent"]]["role"] == role]
        control = [r for r in rr if screen["parents"][r["parent"]]["role"] == "control"]
        if public and control:
            a = min(public, key=lambda r: r["formula"])
            b = min(control, key=lambda r: r["formula"])
            paired.append(dict(shape=list(shape), scale=list(scale), target=a["target"],
                **{role+'_formula': a["formula"]}, control_formula=b["formula"], gain=b["formula"]-a["formula"]))
    assert paired == screen["comparisons"]
    summary = dict(parents=len(parents), parent_scales=len(seen), targets=len(by_target),
        positive_formula_targets=sum(r["gain"] > 0 for r in selected),
        **{role+'_better_than_control': sum(r["gain"] > 0 for r in paired),
           role+'_worse_than_control': sum(r["gain"] < 0 for r in paired)},
        packing_cutoffs=sum(not r["exact_within_packing_model"] for r in screen["rows"]))
    assert summary == screen["summary"]
    return dict(**summary, packing_optimality_independently_proved=False)


def verify(root, workers=2):
    root = root.resolve()
    read = lambda p: json.loads(p.read_text())
    report = read(root/"report.json")
    assert report["complete"] and report["kind"] in ("public-parent-composition", "search-parent-composition")
    assert report["field"] == "GF(2)" and not report["record_claim"]
    assert not report["canonical_archive_changed"] and not report["redistribution_cleared"]
    screen, baseline = read(root/"screen.json"), read(root/"baseline-grid.json")
    assert report['kind'] == screen['options'].get('candidate_role', 'public')+'-parent-composition'
    checked = check_screen(root, screen, baseline)
    selected = {tuple(r["target"]): r for r in screen["selected"] if r["gain"] > 0}
    assert len(report["outputs"]) == len(selected) == report["materialized_targets"]
    for row in report["outputs"]:
        source = selected[tuple(row["target"])]
        assert all(row[k] == source[k] for k in ("parent", "scale", "formula", "baseline", "gain"))
        recipe = read(contained(root, row["recipe"]))
        assert [{k: v for k, v in g.items() if k != "leaf"} for g in recipe["groups"]] == source["groups"]
        assert recipe["parent"] == dict(screen["parents"][row["parent"]]["snapshot"],
            path=recipe["parent"]["path"])
    products = verify_products(root, report["outputs"], baseline, workers)
    return dict(complete=True, field="GF(2)", record_claim=False,
        report_sha256=hashlib.sha256((root/"report.json").read_bytes()).hexdigest(),
        screen=checked, products=products)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--workers", type=int, choices=(1, 2, 3, 4), default=2)
    p.add_argument("--report", type=Path, required=True)
    a = p.parse_args()
    result = verify(a.root, a.workers)
    a.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(result, products={k: v for k, v in result["products"].items() if k != "results"})))
