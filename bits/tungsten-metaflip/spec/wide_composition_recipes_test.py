#!/usr/bin/env python3
"""Exact cold-composition planning, admission, lineage and mutation checks."""
import argparse
import base64
from contextlib import redirect_stdout
import gzip
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import search_wide_auto_loop as loop
import retain_wide_auto_loop as retain
from verify_retained_wide_auto_loop import verify_bundle
from wide_composition_recipes import (
    CompositionLibrary, cheaper_parent, recipe_dependencies, replay_recipe,
)
from verify_recursive_portfolio import solver
from verify_composition_targets import naive


class WideCompositionRecipesTest(unittest.TestCase):
    def library(self, root):
        terms = loop.top.parse_terms(loop.STRASSEN.read_bytes(), 7)
        raw = loop.top.blob((2, 2, 2), terms)
        state = dict(shape=(2, 2, 2), terms=terms, sha256=loop.digest(raw), raw=raw)
        library = CompositionLibrary(root)
        library.add_state(state)
        return library, state

    def test_block_product_and_permuted_plans_match_independent_rank_dp(self):
        library, state = self.library(Path("."))
        price = solver({(2, 2, 2): 7})
        for shape in ((3, 2, 2), (2, 3, 2), (4, 4, 4), (4, 3, 5), (1, 5, 3)):
            terms, recipe = library.materialize(shape)
            self.assertEqual(len(terms), price(tuple(sorted(shape))))
            loop.top.exact(shape, terms)
        self.assertEqual(library.recipe((3, 2, 2))["kind"], "split")
        self.assertEqual(library.recipe((4, 4, 4))["kind"], "product")
        self.assertEqual(recipe_dependencies(library.recipe((4, 4, 4))),
                         {state["sha256"]})

    def test_cheaper_actual_parent_does_not_require_a_rank_only_body(self):
        library, _ = self.library(Path("."))
        rows = [dict(shape=(3, 2, 2), rank=12)]
        result = cheaper_parent(library, rows, lambda _: 10, 100)
        self.assertEqual(result["rank"], 11)
        self.assertEqual(result["kind"], "closure-composition")
        self.assertIsNone(cheaper_parent(library, rows, lambda _: 10, 10))
        rows[0]["rank"] = 11
        self.assertIsNone(cheaper_parent(library, rows, lambda _: 10, 100))

    def test_static_leaf_hash_and_split_mutations_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            library, state = self.library(root)
            name = "leaf.mfw.gz.b64"
            path = root / name
            encoded = base64.b64encode(gzip.compress(state["raw"], mtime=0)) + b"\n"
            path.write_bytes(encoded)
            library = CompositionLibrary(root)
            library._add(state["shape"], state["terms"], dict(
                source=name, source_sha256=loop.digest(encoded)))
            terms, recipe = library.materialize((3, 2, 2))
            loop.top.exact((3, 2, 2), terms)
            wrong = json.loads(json.dumps(recipe))
            wrong["axis"] = (wrong["axis"] + 1) % 3
            with self.assertRaisesRegex(ValueError, "split mismatch"):
                replay_recipe(wrong, root)
            path.write_bytes(encoded + b"\n")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                replay_recipe(recipe, root)
            bad = dict(kind="seed", shape=[2, 2, 2], rank=7,
                       source="../leaf.mfw", source_shape=[2, 2, 2],
                       source_sha256=loop.digest(encoded))
            with self.assertRaisesRegex(ValueError, "unsafe composition source"):
                replay_recipe(bad, root)

    def test_invalid_static_leaf_cannot_be_admitted_by_a_good_price(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            terms = [(1, 1, 1)]
            raw = loop.top.blob((2, 2, 2), terms)
            (root / "bad.mfw").write_bytes(raw)
            library = CompositionLibrary(root)
            library._add((2, 2, 2), terms, dict(source="bad.mfw",
                                              source_sha256=loop.digest(raw)))
            with self.assertRaises(AssertionError):
                library.materialize((3, 2, 2))

    def test_decimal_leaf_order_is_not_a_tensor_identity_requirement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _, state = self.library(root)
            terms = list(reversed(sorted(state["terms"])))
            raw = ("7\n" + "".join(" ".join(map(str, term)) + "\n" for term in terms)).encode()
            name = "matmul_2x2_rank7_fixture_gf2.txt"
            (root / name).write_bytes(raw)
            library = CompositionLibrary(root)
            library._add((2, 2, 2), terms, dict(source=name, source_sha256=loop.digest(raw)))
            result, _ = library.materialize((3, 2, 2))
            self.assertEqual(len(result), 11)
            loop.top.exact((3, 2, 2), result)

    def test_projected_pair_leaf_is_available_to_general_recipes(self):
        library = CompositionLibrary.from_repository()
        terms, recipe = library.materialize((3, 2, 3))
        self.assertEqual(len(terms), 15)
        self.assertEqual(recipe["kind"], "projection")
        loop.top.exact((3, 2, 3), terms)
        wrong = json.loads(json.dumps(recipe))
        wrong["deletions"][0]["axis"] = 1
        with self.assertRaises(ValueError):
            replay_recipe(wrong)

    def test_multi_parent_retention_and_full_recipe_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bundle = root / "bundle"
            bundle.mkdir()
            library, state = self.library(root)
            (root / "source.mfw").write_bytes(state["raw"])
            rows = []

            def add(shape, terms, kind, parent=None, details=None, old=100):
                raw = loop.top.blob(shape, terms)
                sha = loop.digest(raw)
                name = sha + ".mfw.gz.b64"
                (bundle / name).write_bytes(base64.b64encode(gzip.compress(raw)) + b"\n")
                row = dict(kind=kind, parent=parent, details=details or {}, shape=list(shape),
                           rank=len(terms), sha256=sha, old_price=old, file=name)
                rows.append(row)
                return sha

            source = add(state["shape"], state["terms"], "source", old=7)
            # A second verified campaign state is reached by exact composition.
            other_terms, other_recipe = library.materialize((3, 2, 2))
            other = add((3, 2, 2), other_terms, "closure-composition", source,
                        dict(recipe=other_recipe), old=11)
            library.add_state(dict(shape=(3, 2, 2), terms=other_terms, sha256=other))
            # The product consumes both states, not just its triggering parent.
            recipe = dict(kind="product", shape=[4, 4, 6], rank=77,
                          left=dict(kind="seed", shape=[2, 2, 2], rank=7,
                                    source_shape=[2, 2, 2], state=source),
                          right=dict(kind="seed", shape=[2, 2, 3], rank=11,
                                     source_shape=[3, 2, 2], state=other))
            terms = replay_recipe(recipe, root, library.states)
            child = add((4, 4, 6), terms, "closure-composition", source, dict(recipe=recipe))
            campaign = dict(schema=1, field="GF(2)", record_claim=False,
                            status="complete", rows=rows)
            self.assertEqual({r["sha256"] for r in retain.retained_rows(campaign)},
                             {source, other, child})
            report = dict(schema=1, field="GF(2)", record_claim=False,
                          source="source.mfw", rows=rows)
            (bundle / "manifest.json").write_text(json.dumps(report))
            self.assertEqual(verify_bundle(bundle, root)["tensors"], 3)
            rows[-1]["details"]["recipe"]["right"]["state"] = "missing"
            (bundle / "manifest.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, "missing composition state"):
                verify_bundle(bundle, root)

    def test_cold_loop_materializes_and_walks_the_cheaper_parent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            library, state = self.library(root)
            leaf = root / "strassen.mfw"
            leaf.write_bytes(state["raw"])
            library = CompositionLibrary(root)
            library._add(state["shape"], state["terms"], dict(
                source="strassen.mfw", source_sha256=loop.digest(state["raw"])))
            seed = root / "source.mfw"
            source_terms = naive((2, 2, 3))
            seed.write_bytes(loop.top.blob((2, 2, 3), source_terms))
            catalog = root / "catalog.json"
            catalog.write_text('{"schemes": []}')
            walker = root / "copy-walker"
            calls = root / "calls"
            walker.write_text("#!/usr/bin/env python3\nimport shutil, sys\n"
                              f"with open({str(calls)!r}, 'a') as f: f.write(sys.argv[1]+'\\n')\n"
                              "shutil.copyfile(sys.argv[2], sys.argv[3])\n")
            walker.chmod(0o755)
            shape, terms = loop.top.project((2, 2, 3), source_terms, 2, 2)
            raw = loop.top.blob(shape, terms)
            row = dict(shape=shape, rank=len(terms), raw=raw, sha256=loop.digest(raw),
                       mode=None, axis=2, coordinate=2)
            args = argparse.Namespace(seed=seed, catalog=catalog, walker=walker,
                output_dir=root / "campaign", rounds=1, max_walks=1, steps=1,
                projection_beam=1, basis_beam=1, frontier_cap=2,
                max_composed_rank=10, max_search_rank=10, nonce_base=1)
            with patch.object(loop, "initial_seeds", return_value={(2, 2, 2): 7}), \
                 patch.object(loop.CompositionLibrary, "from_repository", return_value=library), \
                 patch.object(loop, "proposals", return_value=[row]), \
                 patch.object(loop, "basis_proposals", return_value=[]), \
                 redirect_stdout(io.StringIO()):
                loop.run(args)
            report = json.loads((args.output_dir / "manifest.json").read_text())
            self.assertEqual((report["status"], report["walks"]), ("complete", 1))
            rows = [r for r in report["rows"] if r["kind"] == "closure-composition"]
            self.assertTrue(any(r["shape"] == [2, 2, 2] and r["rank"] == 7 for r in rows))
            self.assertEqual(calls.read_text(), "2x2x2\n")
            bundle = root / "bundle"
            bundle.mkdir()
            for row in report["rows"]:
                raw = (args.output_dir / row["path"]).read_bytes()
                name = row["sha256"] + ".mfw.gz.b64"
                (bundle / name).write_bytes(base64.b64encode(gzip.compress(raw)) + b"\n")
                row["file"] = name
            report["source"] = "source.mfw"
            (bundle / "manifest.json").write_text(json.dumps(report))
            self.assertEqual(verify_bundle(bundle, root)["tensors"], 2)

    def test_native_bounds_exclude_dimension_one_but_recipes_allow_it(self):
        self.assertFalse(loop.native_walkable((1, 2, 2), 4))
        self.assertTrue(loop.native_walkable((2, 2, 2), 7))
        self.assertTrue(loop.native_walkable((32, 32, 32), 16320))
        self.assertFalse(loop.native_walkable((32, 32, 32), 16321))
        self.assertTrue(loop.native_walkable((33, 2, 2), 100))
        self.assertFalse(loop.native_walkable((33, 32, 2), 100))
        state = dict(kind="closure-composition", shape=(32, 32, 32), terms=[0] * 16321)
        self.assertIsNone(loop.composed_direct_choice(state))
        library, _ = self.library(Path("."))
        terms, _ = library.materialize((1, 2, 2))
        self.assertEqual(len(terms), 4)
        loop.top.exact((1, 2, 2), terms)

    def test_dimension_one_source_is_transform_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed = root / "one.mfw"
            seed.write_bytes(loop.top.blob((1, 2, 2), naive((1, 2, 2))))
            walker = root / "walker"
            # Not executable: any attempted native walk would fail the test.
            walker.touch()
            catalog = root / "catalog.json"
            catalog.write_text('{"schemes": []}')
            args = argparse.Namespace(seed=seed, walker=walker, catalog=catalog,
                output_dir=root / "out", rounds=1, max_walks=1, steps=1,
                projection_beam=1, basis_beam=1, frontier_cap=1,
                max_composed_rank=1, max_search_rank=1, nonce_base=1)
            with patch.object(loop, "initial_seeds", return_value={}), \
                 redirect_stdout(io.StringIO()):
                loop.run(args)
            report = json.loads((args.output_dir / "manifest.json").read_text())
            self.assertEqual((report["status"], report["walks"]), ("complete", 0))
            self.assertEqual(report["rows"][0]["shape"], [1, 2, 2])


if __name__ == "__main__":
    unittest.main()
