import copy
import hashlib
from itertools import combinations_with_replacement, product
import json
from pathlib import Path
import tempfile
import unittest

from check_public_parent_references import Headings, verify as reference_check
from verify_public_parent_composition import check_screen
from verify_representation_portfolio import identity


def fixture(root):
    shape = [2, 2, 3]
    terms = [(1 << (i*2+j), 1 << (j*3+k), 1 << (i*3+k))
             for i, j, k in product(range(2), range(2), range(3))]
    raw = ("12\n" + "".join(" ".join(map(str, t))+"\n" for t in terms)).encode()
    (root/"parent.txt").write_bytes(raw)
    baseline = dict(complete=True, field="GF(2)", record_claim=False, rows=[
        dict(shape=list(s), augmented_rank=s[0]*s[1]*s[2]) for s in combinations_with_replacement(range(2, 7), 3)])
    parents, rows, by_target, pairs = [], [], {}, {}
    for i, role in enumerate(("public", "control")):
        parents.append(dict(id=i, role=role, shape=shape, rank=12, density=36, canonical_id=identity(shape, terms),
            snapshot=dict(shape=shape, path="parent.txt", sha256=hashlib.sha256(raw).hexdigest())))
        for scale in product(range(1, 3), repeat=3):
            if scale == (1, 1, 1):
                continue
            target = sorted(d*s for d, s in zip(shape, scale))
            formula = 12*scale[0]*scale[1]*scale[2]
            row = dict(parent=i, scale=list(scale), target=target, baseline=formula, formula=formula, gain=0,
                groups=[dict(axis=None, indices=[j]) for j in range(12)], exact_within_packing_model=True)
            rows.append(row)
            by_target.setdefault(tuple(target), []).append(row)
            pairs.setdefault(scale, []).append(row)
    selected = [min(rr, key=lambda r: (r["formula"], r["parent"], r["scale"])) for rr in by_target.values()]
    comparisons = [dict(shape=shape, scale=list(s), target=rr[0]["target"], public_formula=rr[0]["formula"],
        control_formula=rr[1]["formula"], gain=0) for s, rr in pairs.items()]
    screen = dict(complete=True, field="GF(2)", record_claim=False, screen_only=True, canonical_archive_changed=False,
        options=dict(max_scale=2, max_leaf=6), parents=parents, rows=rows, selected=selected, comparisons=comparisons,
        summary=dict(parents=2, parent_scales=14, targets=len(selected), positive_formula_targets=0,
            public_better_than_control=0, public_worse_than_control=0, packing_cutoffs=0))
    return screen, baseline


class PublicParentChecks(unittest.TestCase):
    def test_screen_and_rejected_mutations(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            screen, baseline = fixture(root)
            self.assertEqual(check_screen(root, screen, baseline)["parent_scales"], 14)
            bad = copy.deepcopy(screen)
            bad["rows"][0]["groups"][-1]["indices"] = [0]
            with self.assertRaises(AssertionError):
                check_screen(root, bad, baseline)
            bad = copy.deepcopy(screen)
            bad["comparisons"][0]["gain"] = 1
            with self.assertRaises(AssertionError):
                check_screen(root, bad, baseline)
            bad = copy.deepcopy(screen)
            bad["rows"][0]["target"] = [1, 1, 1]
            with self.assertRaises(AssertionError):
                check_screen(root, bad, baseline)
            bad = copy.deepcopy(screen)
            bad["parents"][0]["snapshot"]["sha256"] = "0"*64
            with self.assertRaises(AssertionError):
                check_screen(root, bad, baseline)
            bad = copy.deepcopy(screen)
            lines = (root/"parent.txt").read_text().splitlines()
            terms = [tuple(map(int, s.split())) for s in lines[1:]]
            terms[0] = (terms[0][0] ^ 2, terms[0][1], terms[0][2])
            raw = ("12\n"+"".join(" ".join(map(str, t))+"\n" for t in terms)).encode()
            (root/"parent.txt").write_bytes(raw)
            for row in bad["parents"]:
                row["snapshot"]["sha256"] = hashlib.sha256(raw).hexdigest()
                row["canonical_id"] = identity([2, 2, 3], terms)
                row["density"] = sum(v.bit_count() for t in terms for v in t)
            with self.assertRaises(AssertionError):
                check_screen(root, bad, baseline)

    def test_reference_composition_eliminates_pointwise_false_positive(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            body = b"<h1>Description of fast matrix multiplication algorithm: &lang;2,2,4:16&rang;</h1>"
            (root/"page.html").write_bytes(body)
            report = dict(complete=True, record_claim=False, rows=[dict(shape=[2, 2, 4], candidate_rank=15,
                listed_rank=16, status=200, path="page.html", sha256=hashlib.sha256(body).hexdigest())])
            baseline = dict(complete=True, record_claim=False, field="GF(2)", rows=[
                dict(shape=list(s), augmented_rank=s[0]*s[1]*s[2]) for s in combinations_with_replacement(range(2, 5), 3)])
            catalog = dict(schemes=[dict(format=[2, 2, 2], rank=7, verified=True, fields=["F2"])])
            for name, value in (("report.json", report), ("baseline.json", baseline), ("catalog.json", catalog), ("wide.json", {})):
                (root/name).write_text(json.dumps(value))
            checked = reference_check(root, root/"baseline.json", root/"catalog.json", root/"wide.json", [])
            row = checked["checks"][0]
            self.assertTrue(row["below_available_pointwise"])
            self.assertEqual(row["composed_reference_bound"], 14)
            self.assertFalse(row["below_composed_reference"])
            # A recursive closure has rows/recipes, not parent outputs. Its
            # checked materialized rank must be the rank used for comparison.
            materialized = dict(complete=True, field="GF(2)", record_claim=False,
                rows=[dict(shape=[2, 2, 4], gain=2, augmented_rank=14, recipe="output.recipe.json")])
            path = root/"materialized.json"
            path.write_text(json.dumps(materialized))
            checked = reference_check(root, root/"baseline.json", root/"catalog.json", root/"wide.json", [], path)
            self.assertTrue(checked["materialized_counts"])
            self.assertEqual(checked["checks"][0]["rank"], 14)
            self.assertFalse(checked["checks"][0]["below_composed_reference"])
            for changes in ({"recipe": None}, {"shape": [2, 3, 4]}, {"augmented_rank": 17}):
                bad = copy.deepcopy(materialized)
                bad["rows"][0].update(changes)
                path.write_text(json.dumps(bad))
                with self.assertRaises(AssertionError):
                    reference_check(root, root/"baseline.json", root/"catalog.json", root/"wide.json", [], path)

    def test_heading_entities(self):
        h = Headings()
        h.feed("<h1>A &lt; B</h1><p>not a heading</p><h1>C</h1>")
        self.assertEqual(h.headings, ["A < B", "C"])

    def test_search_role_has_separate_comparison_provenance(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            screen, baseline = fixture(root)
            screen['options']['candidate_role'] = 'search'
            screen['parents'][0]['role'] = 'search'
            for row in screen['comparisons']:
                row['search_formula'] = row.pop('public_formula')
            for suffix in ('better_than_control', 'worse_than_control'):
                screen['summary']['search_'+suffix] = screen['summary'].pop('public_'+suffix)
            checked = check_screen(root, screen, baseline)
            self.assertEqual(checked['search_better_than_control'], 0)
            screen['parents'][0]['role'] = 'public'
            with self.assertRaises(AssertionError):
                check_screen(root, screen, baseline)


if __name__ == "__main__":
    unittest.main()
