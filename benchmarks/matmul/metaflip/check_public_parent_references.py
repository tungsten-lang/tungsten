#!/usr/bin/env python3
"""Compare candidate counts with a finite closure of public reference bounds.

No reference-only number is admitted as a tensor witness. Mixed reference
fields make this a deliberately conservative novelty screen, not an oracle.
"""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re

from verify_recursive_portfolio import catalog_minima, solver


class Headings(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.active = False
        self.headings = []

    def handle_starttag(self, tag, attrs):
        if tag == "h1":
            self.active = True
            self.headings.append("")

    def handle_endtag(self, tag):
        if tag == "h1":
            self.active = False

    def handle_data(self, text):
        if self.active:
            self.headings[-1] += text


def verify(root, baseline_path, catalog_path, wide_path, previous_paths, materialized_path=None):
    pins = {}
    def read(path):
        raw = path.read_bytes()
        pins[str(path.resolve())] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)
    report = read(root / "report.json")
    baseline = read(baseline_path)
    catalog = catalog_minima(read(catalog_path))
    wide = read(wide_path)
    assert report["complete"] and not report["record_claim"]
    assert baseline["complete"] and baseline["field"] == "GF(2)" and not baseline["record_claim"]
    # Previously known, exact local prices are also valid comparisons. Adding
    # reference-only prices strengthens the comparator, never the constructor.
    known = {tuple(r["shape"]): r["augmented_rank"] for r in baseline["rows"]}
    for shape, rank in catalog.items():
        known[shape] = min(known.get(shape, rank), rank)
    reference = dict(known)
    for tag, entry in wide.items():
        shape = tuple(sorted(map(int, tag.split("x"))))
        rank = entry.get("serendipitous_rank")
        if rank is not None:
            reference[shape] = min(reference.get(shape, rank), rank)
    previous_rows = []
    for path in previous_paths:
        prior = read(path)
        assert prior["complete"] and not prior["record_claim"]
        previous_rows += prior.get("references", prior.get("rows", []))
    for row in previous_rows + report["rows"]:
        if row.get("listed_rank") is not None:
            shape, rank = tuple(sorted(row["shape"])), row["listed_rank"]
            reference[shape] = min(reference.get(shape, rank), rank)
    ranks = {}
    if materialized_path is not None:
        materialized = read(materialized_path)
        assert materialized["complete"] and materialized["field"] == "GF(2)" and not materialized["record_claim"]
        if "outputs" in materialized:
            ranks = {tuple(row["target"]): row["rank"] for row in materialized["outputs"]}
        else:
            # Completed recursive closure: positive rows are materialized and
            # carry their recipe, rather than using the parent's output schema.
            selected = [row for row in materialized["rows"] if row["gain"] > 0]
            assert all(row["recipe"] for row in selected)
            ranks = {tuple(row["shape"]): row["augmented_rank"] for row in selected}
        assert set(ranks) == {tuple(row["shape"]) for row in report["rows"]}
    cost = solver(reference)
    checks = []
    for row in report["rows"]:
        shape = tuple(row["shape"])
        rank = ranks.get(shape, row["candidate_rank"])
        assert rank <= row["candidate_rank"]
        path = (root / row["path"]).resolve()
        assert path.is_relative_to(root.resolve())
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == row["sha256"]
        h = Headings()
        h.feed(raw.decode("utf-8"))
        parsed = [re.search(r"Description of fast matrix multiplication algorithm:.*:(\d+)", s) for s in h.headings]
        values = [int(m.group(1)) for m in parsed if m]
        assert len(values) <= 1
        listed = values[0] if values and row["status"] == 200 else None
        assert listed == row.get("listed_rank")
        wider = wide.get("x".join(map(str, shape)), {}).get("serendipitous_rank")
        pointwise = [v for v in (listed, catalog.get(shape), wider) if v is not None]
        composed = cost(shape)
        checks.append(dict(shape=shape, rank=rank, listed_rank=listed, catalog_minimum=catalog.get(shape),
            wider_reported_rank=wider, composed_reference_bound=composed,
            below_available_pointwise=bool(pointwise) and rank < min(pointwise),
            below_composed_reference=rank < composed))
    return dict(complete=True, field="GF(2)", record_claim=False, source_sha256=pins,
        materialized_counts=materialized_path is not None, comparison_only=True,
        reference_fields_not_all_reverified=True, checks=checks,
        below_lille=sum(r["listed_rank"] is not None and r["rank"] < r["listed_rank"] for r in checks),
        below_available_pointwise=sum(r["below_available_pointwise"] for r in checks),
        below_composed_reference=sum(r["below_composed_reference"] for r in checks))


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "baseline", "catalog", "wide", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--previous", type=Path, action="append", default=[])
    p.add_argument("--materialized", type=Path)
    a = p.parse_args()
    result = verify(a.root, a.baseline, a.catalog, a.wide, a.previous, a.materialized)
    a.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k not in ("checks", "source_sha256")}))
    print(json.dumps([r for r in result["checks"] if r["below_available_pointwise"]]))
