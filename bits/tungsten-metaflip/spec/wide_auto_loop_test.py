#!/usr/bin/env python3
"""Focused exact-gate and basis-diversity checks for the cold loop."""
import argparse
import base64
from contextlib import redirect_stdout
import gzip
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as top  # noqa: E402
import search_wide_auto_loop as loop  # noqa: E402
import retain_wide_auto_loop as retain  # noqa: E402

CERT = TOOLS / "certificates/7x12x16-directed-20260925/7x16x12-r873.mfw.gz.b64"


class WideAutoLoopTest(unittest.TestCase):
    def source(self):
        return gzip.decompress(base64.b64decode(CERT.read_bytes()))

    def test_compressed_certificate_is_direct_seed(self):
        self.assertEqual(loop.read_seed(CERT), self.source())
        with tempfile.TemporaryDirectory() as tmp:
            raw = Path(tmp) / "seed.mfw"
            raw.write_bytes(self.source())
            self.assertEqual(loop.read_seed(raw), self.source())
            corrupt = Path(tmp) / "bad.mfw.gz.b64"
            corrupt.write_text("not base64")
            with self.assertRaises(ValueError):
                loop.read_seed(corrupt)

    def test_retained_lineage_keeps_best_and_ancestors(self):
        def row(shape, rank, old_price, sha, parent=None):
            return dict(shape=shape, rank=rank, old_price=old_price,
                        sha256=sha, parent=parent)
        manifest = dict(schema=1, field="GF(2)", record_claim=False,
                        status="complete", rows=[
                            row([3, 3, 3], 25, 25, "source"),
                            row([2, 3, 3], 20, 22, "projection", "source"),
                            row([2, 3, 3], 19, 20, "walk", "projection"),
                            row([2, 2, 3], 19, 19, "tie", "source")])
        self.assertEqual([r["sha256"] for r in retain.retained_rows(manifest)],
                         ["source", "projection", "walk"])
        manifest["status"] = "running"
        with self.assertRaises(ValueError):
            retain.retained_rows(manifest)

    def test_basis_beam_covers_distinct_axis_orders(self):
        shape, terms = top.read_blob(self.source())
        rows = loop.basis_proposals(shape, terms, 2)
        self.assertEqual([row["mode"] for row in rows], [6, 12])
        self.assertEqual([row["rank"] for row in rows], [873, 873])

    def test_round_budget_keeps_descendant_slots_and_both_basis_orders(self):
        self.assertEqual(loop.round_walk_limit(0, 6, 0, 2), 3)
        self.assertEqual(loop.round_walk_limit(3, 6, 1, 2), 6)
        projected = [dict(shape=(7, 16, 11), rank=835, mode="p0"),
                     dict(shape=(7, 16, 11), rank=836, mode="p1")]
        basis = [dict(shape=(7, 16, 12), rank=871, mode=mode)
                 for mode in ("b6", "b12", "b7", "b13")]
        prices = {(7, 11, 16): 822, (7, 12, 16): 871}
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order],
                         ["b6", "p0", "b12", "b7", "b13", "p1"])
        prices[(7, 11, 16)] = 835
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order][:3],
                         ["p0", "b6", "b12"])
        states = [dict(shape=(7, 16, 11), terms=[0] * 833, sha256="projected"),
                  dict(shape=(7, 16, 12), terms=[0] * 871, sha256="basis")]
        prices[(7, 11, 16)] = 822
        states.sort(key=lambda state: loop.frontier_priority(
            state, lambda shape: prices[shape]))
        self.assertEqual([state["sha256"] for state in states],
                         ["basis", "projected"])

    def test_projection_admission_uses_live_price_without_losing_ties(self):
        gate = loop.projection_admission_kind
        self.assertEqual(gate(6871, 7128, 7128), "projection-improvement")
        self.assertEqual(gate(6871, 7128, 6871), "projection-tie")
        self.assertIsNone(gate(6736, 6878, 6725))
        self.assertIsNone(gate(7128, 7128, 7128))

    def test_two_strong_child_shapes_precede_parent_basis_tie(self):
        projected = [dict(shape=(19, 22, 23), rank=5583, mode="child-a"),
                     dict(shape=(20, 21, 23), rank=5502, mode="child-b")]
        basis = [dict(shape=(20, 22, 23), rank=5702, mode="basis")]
        prices = {(19, 22, 23): 5748, (20, 21, 23): 5654,
                  (20, 22, 23): 5702}
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order],
                         ["child-a", "child-b", "basis"])
        prices[(20, 22, 23)] = 6000
        order = loop.ordered_choices(projected, basis,
                                     lambda shape: prices[shape])
        self.assertEqual([row["mode"] for row in order][:2],
                         ["basis", "child-a"])

    def test_composed_direct_choice_excludes_sources(self):
        state = dict(kind="source", shape=(2, 2, 2), terms=[0] * 7,
                     raw=b"source", sha256="source")
        self.assertIsNone(loop.composed_direct_choice(state))
        state["kind"] = "strassen-product"
        choice = loop.composed_direct_choice(state)
        self.assertEqual((choice["kind"], choice["raw"], choice["sha256"]),
                         ("composed-direct", b"source", "source"))
        state["kind"] = "shared-pair-product"
        self.assertIsNotNone(loop.composed_direct_choice(state))

    def test_incumbent_source_walk_follows_first_two_neighborhoods(self):
        state = dict(kind="source", shape=(2, 2, 2), terms=[0] * 7,
                     raw=b"source", sha256="source")
        choices = [dict(kind="projection", mode="p"),
                   dict(kind="basis", mode="b0"),
                   dict(kind="basis", mode="b1")]
        result = loop.include_incumbent_source_walk(state, choices, lambda _: 7)
        self.assertEqual([row["kind"] for row in result],
                         ["projection", "basis", "source-direct", "basis"])
        self.assertEqual(result[2]["sha256"], "source")
        self.assertEqual(choices, result[:2] + result[3:])
        self.assertIs(loop.include_incumbent_source_walk(state, choices,
                                                        lambda _: 6), choices)
        state["kind"] = "basis"
        self.assertIs(loop.include_incumbent_source_walk(state, choices,
                                                        lambda _: 7), choices)

    def test_incumbent_direct_walk_is_consumed_once_across_rounds(self):
        terms = top.parse_terms(loop.STRASSEN.read_bytes(), 7)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed = root / "seed.mfw"
            seed.write_bytes(top.blob((2, 2, 2), terms))
            catalog = root / "catalog.json"
            catalog.write_text('{"schemes": []}')
            walker = root / "copy-walker"
            walker.write_text("#!/usr/bin/env python3\nimport shutil, sys\n"
                              "shutil.copyfile(sys.argv[2], sys.argv[3])\n")
            walker.chmod(0o755)
            args = argparse.Namespace(
                seed=seed, catalog=catalog, walker=walker,
                output_dir=root / "output", rounds=2, max_walks=2,
                steps=1, projection_beam=1, basis_beam=1,
                frontier_cap=1, max_composed_rank=1, max_search_rank=10,
                nonce_base=25001)
            with patch.object(loop, "initial_seeds", return_value={(2, 2, 2): 7}), \
                 patch.object(loop, "proposals", return_value=[]), \
                 patch.object(loop, "basis_proposals", return_value=[]), \
                 redirect_stdout(io.StringIO()):
                loop.run(args)
            report = json.loads((args.output_dir / "manifest.json").read_text())
            self.assertEqual((report["status"], report["walks"]), ("complete", 1))

    def test_checked_certificates_update_prices_and_reject_false_improvements(self):
        source = loop.STRASSEN.read_bytes()
        terms = top.parse_terms(source, 7)
        top.exact((2, 2, 2), terms)
        valid = top.blob((2, 2, 2), terms)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "rank7.mfw.gz.b64").write_bytes(
                base64.b64encode(gzip.compress(valid)))
            self.assertEqual(loop.certificate_minima({(2, 2, 2): 8}, root)
                             [(2, 2, 2)], 7)
            (root / "false-rank1.mfw").write_bytes(
                top.blob((2, 2, 2), [(1, 1, 1)]))
            with self.assertRaises(AssertionError):
                loop.certificate_minima({(2, 2, 2): 8}, root)

    def test_latest_checked_in_certificate_updates_price(self):
        seeds = loop.certificate_minima({(7, 12, 16): 876},
                                        CERT.parent.parent / "7x12x16-r871-directed-20260925")
        self.assertEqual(seeds[(7, 12, 16)], 871)

    def test_projected_walk_certificate_updates_price(self):
        root = TOOLS / "certificates/impact-projection-children-20260925"
        seeds = loop.certificate_minima({(12, 13, 23): 2203}, root)
        self.assertEqual(seeds[(12, 13, 23)], 2142)

    def test_multiround_certificate_keeps_best_continuation(self):
        root = TOOLS / "certificates/impact-grandchildren-20260925"
        seeds = loop.certificate_minima({(19, 24, 27): 7128}, root)
        self.assertEqual(seeds[(19, 24, 27)], 6827)

    def test_catalogue_projection_leads_update_prices(self):
        root = TOOLS / "certificates/catalogue-projection-leads-20260925"
        seeds = loop.certificate_minima({(19, 24, 28): 7253,
                                        (16, 22, 23): 4716}, root)
        self.assertEqual(seeds[(19, 24, 28)], 6990)
        self.assertEqual(seeds[(16, 22, 23)], 4618)

    def test_20x23x23_catalogue_lead_updates_price(self):
        root = TOOLS / "certificates/20x23x23-catalogue-lead-20260925"
        seeds = loop.certificate_minima({(20, 23, 23): 6095,
                                        (20, 22, 24): 5902,
                                        (19, 23, 24): 6032}, root)
        self.assertEqual(seeds[(20, 23, 23)], 5883)
        self.assertEqual(seeds[(20, 22, 24)], 5851)
        self.assertEqual(seeds[(19, 23, 24)], 5894)

    def test_wide_auto_loop_descendants_update_prices(self):
        root = TOOLS / "certificates/20x22x23-auto-loop-20260925"
        seeds = loop.certificate_minima({(20, 22, 23): 5940,
                                        (19, 22, 23): 5748,
                                        (20, 21, 23): 5654}, root)
        self.assertEqual(seeds[(20, 22, 23)], 5702)
        self.assertEqual(seeds[(19, 22, 23)], 5551)
        self.assertEqual(seeds[(20, 21, 23)], 5463)

    def test_second_wide_auto_loop_generation_updates_prices(self):
        root = TOOLS / "certificates/20x21x23-auto-loop-20260925"
        seeds = loop.certificate_minima({(19, 21, 23): 5540,
                                        (20, 20, 23): 5261,
                                        (20, 21, 22): 5347}, root)
        self.assertEqual(seeds[(19, 21, 23)], 5316)
        self.assertEqual(seeds[(20, 20, 23)], 5146)
        self.assertEqual(seeds[(20, 21, 22)], 5345)

    def test_20x22x25_feedback_continuations_update_prices(self):
        root = TOOLS / "certificates/20x22x25-auto-loop-20260925"
        seeds = loop.certificate_minima({(19, 22, 25): 6128,
                                        (20, 21, 25): 5923,
                                        (19, 21, 25): 5833,
                                        (19, 22, 24): 5829}, root)
        self.assertEqual(seeds[(19, 22, 25)], 5954)
        self.assertEqual(seeds[(20, 21, 25)], 5875)
        self.assertEqual(seeds[(19, 21, 25)], 5682)
        self.assertEqual(seeds[(19, 22, 24)], 5733)

    def test_bounded_frontier_preserves_composition_continuation(self):
        walked = [dict(shape=(2, 2, 2), terms=[0] * 7, sha256="walk-a"),
                  dict(shape=(2, 2, 2), terms=[0] * 7, sha256="walk-b")]
        composed = [dict(shape=(4, 4, 4), terms=[0] * 49, sha256="product")]
        price = lambda shape: {(2, 2, 2): 7, (4, 4, 4): 49}[shape]
        frontier = loop.select_frontier(walked, composed, 2, price)
        self.assertEqual({state["sha256"] for state in frontier},
                         {"walk-a", "product"})
        self.assertEqual(loop.select_frontier(walked, composed, 1, price)[0]
                         ["sha256"], "walk-a")

    def test_archived_incumbent_prevents_stale_price(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            catalog = root / "catalog.json"
            catalog.write_text('{"schemes": []}')
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({
                "catalog_sha256": hashlib.sha256(catalog.read_bytes()).hexdigest(),
                "rows": []}))
            with patch.object(loop.old, "MANIFEST", manifest), \
                 patch.object(loop.old, "CANDIDATES", []), \
                 patch.object(loop.top, "initial_seeds", return_value={}), \
                 patch.object(loop, "certificate_minima", side_effect=lambda s: s):
                seeds = loop.initial_seeds(catalog)
            self.assertEqual(seeds[(7, 12, 12)], 651)
            self.assertEqual(seeds[(12, 14, 16)], 1601)

    def test_external_best_is_not_scheme_rank_or_tensor_price(self):
        with tempfile.TemporaryDirectory() as tmp:
            catalog = Path(tmp) / "catalog.json"
            catalog.write_text(json.dumps({"schemes": [
                {"format": [20, 22, 23], "rank": 5722,
                 "external_best_rank": 5596,
                 "external_best_source": "fmm-lille"}]}))
            self.assertEqual(loop.external_minima(catalog)[(20, 22, 23)],
                             (5596, "fmm-lille"))

    def test_projection_walk_composition_handoff(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "seed.mfw"
            source.write_bytes(self.source())
            catalog = root / "catalog.json"
            catalog.write_text(json.dumps({"schemes": [
                {"format": [7, 12, 16], "rank": 876,
                 "external_best_rank": 870,
                 "external_best_source": "fmm-lille"}]}))
            walker = root / "copy-walker"
            walker.write_text("#!/usr/bin/env python3\nimport shutil, sys\n"
                              "shutil.copyfile(sys.argv[2], sys.argv[3])\n")
            walker.chmod(0o755)
            output = root / "output"
            args = argparse.Namespace(seed=source, catalog=catalog,
                                      walker=walker,
                                      output_dir=output, rounds=2,
                                      max_walks=2, steps=1,
                                      projection_beam=1, basis_beam=2,
                                      frontier_cap=4,
                                      max_composed_rank=8000,
                                      max_search_rank=3000,
                                      nonce_base=24001)
            with patch.object(loop, "initial_seeds", return_value={
                    (7, 12, 16): 876, (14, 24, 32): 6132}):
                with redirect_stdout(io.StringIO()):
                    loop.run(args)
            report = json.loads((output / "manifest.json").read_text())
            self.assertEqual((report["status"], report["walks"],
                              report["record_claim"]), ("complete", 2, False))
            kinds = {row["kind"] for row in report["rows"]}
            self.assertTrue({"source", "projection-improvement",
                             "strassen-product"} <= kinds)
            source_row = next(row for row in report["rows"] if row["kind"] == "source")
            self.assertEqual((source_row["old_price"], source_row["rank"]),
                             (876, 873))
            self.assertEqual((source_row["external_best_rank"],
                              source_row["external_best_source"],
                              source_row["external_gap"]),
                             (870, "fmm-lille", 3))
            for row in report["rows"]:
                path = output / row["path"]
                shape, terms = top.read_blob(path.read_bytes())
                self.assertEqual((list(shape), len(terms)),
                                 (row["shape"], row["rank"]))
                top.exact(shape, terms)

    def test_composed_parent_gets_direct_walk_without_displacing_source(self):
        terms = top.parse_terms(loop.STRASSEN.read_bytes(), 7)
        raw = top.blob((2, 2, 2), terms)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed = root / "seed.mfw"
            seed.write_bytes(raw)
            catalog = root / "catalog.json"
            catalog.write_text('{"schemes": []}')
            walker = root / "copy-walker"
            calls = root / "walker-calls"
            walker.write_text("#!/usr/bin/env python3\nimport shutil, sys\n"
                              f"with open({str(calls)!r}, 'a') as log:\n"
                              "    log.write(sys.argv[2] + '\\n')\n"
                              "shutil.copyfile(sys.argv[2], sys.argv[3])\n")
            walker.chmod(0o755)
            output = root / "output"
            args = argparse.Namespace(seed=seed, catalog=catalog, walker=walker,
                                      output_dir=output, rounds=1, max_walks=2,
                                      steps=1, projection_beam=1, basis_beam=1,
                                      frontier_cap=2, max_composed_rank=100,
                                      max_search_rank=100, nonce_base=25001)
            with patch.object(loop, "initial_seeds", return_value={
                    (2, 2, 2): 7, (4, 4, 4): 49}):
                with redirect_stdout(io.StringIO()):
                    loop.run(args)
            rows = json.loads((output / "manifest.json").read_text())["rows"]
            by_sha = {row["sha256"]: row for row in rows}
            walked = [by_sha[Path(path).stem]["kind"]
                      for path in calls.read_text().splitlines()]
            self.assertEqual(len(walked), 2)
            self.assertNotIn(walked[0],
                             ("strassen-product", "shared-pair-product"))
            self.assertIn(walked[1],
                          ("strassen-product", "shared-pair-product"))

    def test_missing_seed_does_not_create_campaign(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            walker = root / "walker"
            walker.write_text("#!/bin/sh\n")
            args = argparse.Namespace(seed=root / "absent.mfw",
                                      walker=walker,
                                      output_dir=root / "output")
            with self.assertRaises(FileNotFoundError):
                loop.run(args)
            self.assertFalse(args.output_dir.exists())


if __name__ == "__main__":
    unittest.main()
