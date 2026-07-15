import argparse
import json
import itertools
import os
import sys
import tempfile
import time
import unittest
from unittest import mock


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)

from bench_decomp import cost, naive_scheme, parse_scheme, verify  # noqa: E402
from bucket_gen import gen, gen_worker  # noqa: E402
from flipfleet import (C3_RECORD_SEEDS, Fleet, RECORD_SEEDS, build_arg_parser,
                       main as flipfleet_main, parse_move_budgets, read_dump,
                       write_dump)  # noqa: E402
from metaflip_proto2 import recon  # noqa: E402
from sym_start import (  # noqa: E402
    check_c3,
    check_reversal,
    diagonal_partition_scheme,
    parse_partition,
)
from sym_escape import best_bridge, describe as describe_escape  # noqa: E402
from tensor_profiles import profile_for_tensor  # noqa: E402


def density_increasing_flip(terms, n):
    """Return an exact same-rank flip that is denser than ``terms``."""
    baseline = cost(terms, n, n, n)["bits"]
    for left_index, left in enumerate(terms):
        for right_index in range(left_index + 1, len(terms)):
            right = terms[right_index]
            for axis in range(3):
                if left[axis] != right[axis]:
                    continue
                changed_left = list(left)
                changed_right = list(right)
                if axis == 0:
                    changed_left[2] ^= right[2]
                    changed_right[1] ^= left[1]
                elif axis == 1:
                    changed_left[2] ^= right[2]
                    changed_right[0] ^= left[0]
                else:
                    changed_left[1] ^= right[1]
                    changed_right[0] ^= left[0]
                candidate = [term for index, term in enumerate(terms)
                             if index not in (left_index, right_index)]
                candidate.extend((tuple(changed_left), tuple(changed_right)))
                if (len(candidate) == len(terms) and verify(candidate, n, n, n) and
                        cost(candidate, n, n, n)["bits"] > baseline):
                    return sorted(candidate)
    raise AssertionError("fixture has no density-increasing exact flip")


class DiagonalStartTest(unittest.TestCase):
    def test_published_and_target_aligned_starts(self):
        cases = (
            (3, "1,2,3", 49),
            (4, "1,2,3,4", 121),
            (5, "1,5;2,4;3", 135),
            (5, "1,2,4,5;3", 182),
            (6, "1,2;3,4;5,6", 231),
            (6, "1,2,5,6;3,4", 278),
        )
        for n, spec, expected_rank in cases:
            with self.subTest(n=n, spec=spec):
                terms = diagonal_partition_scheme(n, parse_partition(spec, n))
                self.assertEqual(expected_rank, len(terms))
                self.assertTrue(check_c3(terms, n))
                self.assertTrue(check_reversal(terms, n))

    def test_partition_must_cover_every_index_once(self):
        with self.assertRaises(ValueError):
            parse_partition("1,2;2,3", 3)


class PlusTransitionTest(unittest.TestCase):
    def test_generated_variants(self):
        w_only = gen(3, 3, 3, 22, cap=10, plusper=2, plus_axes="w")
        any_axis = gen(3, 3, 3, 22, cap=10, plusper=2, plus_axes="any")
        worker = gen_worker(3, 3, 3, 22, plusper=2, plus_axes="any")
        self.assertNotIn("paxis", w_only)
        self.assertIn("paxis", any_axis)
        self.assertIn("paxis", worker)
        runtime_budget = gen(3, 3, 3, 22, cap=10, world_record=23,
                             record_bandq=10_000_000_000, runtime_seed=True,
                             adaptive_esc="cal2zone2")
        self.assertIn("if av0.size() > 6", runtime_budget)
        self.assertIn("workqv = 10000000000 ## i64", runtime_budget)
        self.assertIn("workqv = av0[6].to_i()", runtime_budget)
        self.assertIn("wanderqv = 500000000 ## i64", runtime_budget)
        self.assertIn("if av0.size() > 7", runtime_budget)
        self.assertIn("wanderqv = av0[7].to_i()", runtime_budget)
        self.assertIn(
            '<< "ZONEQ work=" + workqv.to_s() + " wander=" + wanderqv.to_s()',
            runtime_budget)
        self.assertIn("nextesc = workqv", runtime_budget)
        self.assertIn("      q = workqv ## i64\n      if aband > wthr\n"
                      "        q = wanderqv", runtime_budget)
        self.assertNotIn("recordqv", runtime_budget)
        self.assertNotIn("RECORDQ", runtime_budget)
        self.assertIn("    if cycleout == 0\n      aband = nb", runtime_budget)
        self.assertIn("    wraps = 0\n    nextesc = mv + workqv", runtime_budget)

        legacy_schedule = gen(
            3, 3, 3, 22, cap=10, world_record=23,
            record_bandq=10_000_000_000, runtime_seed=True,
            adaptive_esc="cal2zone")
        self.assertIn("recordqv = av0[6].to_i()", legacy_schedule)
        self.assertIn("q = recordqv", legacy_schedule)
        self.assertIn('<< "RECORDQ " + recordqv.to_s()', legacy_schedule)
        self.assertNotIn("ZONEQ", legacy_schedule)

    def test_split_identity_on_every_axis(self):
        term = (0b101001, 0b11010, 0b100101)
        primes = (0b110001, 0b10110, 0b111000)
        old = recon({term}, 2, 3, 3)
        for axis in range(3):
            left = list(term)
            right = list(term)
            left[axis] = primes[axis]
            right[axis] ^= primes[axis]
            self.assertEqual(old, recon({tuple(left), tuple(right)}, 2, 3, 3))


class RecordSeedTest(unittest.TestCase):
    def test_tracked_square_frontiers_are_exact(self):
        for n, path in list(RECORD_SEEDS.items()) + list(C3_RECORD_SEEDS.items()):
            with self.subTest(n=n, path=path):
                terms = parse_scheme(path)
                self.assertTrue(verify(terms, n, n, n))

    def test_default_record_cost_frontiers(self):
        expected_bits = {3: 139, 4: 450, 5: 1155, 6: 2502}
        for n, bits in expected_bits.items():
            with self.subTest(n=n):
                terms = parse_scheme(RECORD_SEEDS[n])
                self.assertEqual(bits, cost(terms, n, n, n)["bits"])


class ExactGateTest(unittest.TestCase):
    def test_torn_dump_is_rejected(self):
        with tempfile.NamedTemporaryFile("w") as f:
            f.write("1\n1 2\n")
            f.flush()
            self.assertEqual((None, None), read_dump(f.name))

    def test_out_of_range_and_duplicate_masks_are_rejected(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            terms = naive_scheme(3, 3, 3)
            self.assertTrue(fleet.exact_valid(len(terms), terms))
            high = list(terms)
            high[0] = (high[0][0] | (1 << 9), high[0][1], high[0][2])
            self.assertFalse(fleet.exact_valid(len(high), high))
            duplicate = terms + [terms[0], terms[0]]
            self.assertFalse(fleet.exact_valid(len(duplicate), duplicate))

    def test_explicit_empty_seed_does_not_fall_back_to_naive(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=[])
            self.assertEqual([], fleet.initial)

    def test_same_rank_spool_snapshot_is_discovered(self):
        with tempfile.TemporaryDirectory() as run_dir:
            terms = naive_scheme(3, 3, 3)
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=27,
                          initial_terms=terms)
            path = os.path.join(fleet.spool, "tie1l1_1.txt")
            write_dump(terms, path)
            found = fleet.drain_spool(27)
            self.assertEqual([(27, 1, terms, "spool/tie1l1_1.txt")], found)
            self.assertEqual([], fleet.drain_spool(27))

    def test_mid_write_spool_snapshot_is_retried(self):
        with tempfile.TemporaryDirectory() as run_dir:
            terms = naive_scheme(3, 3, 3)
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=27,
                          initial_terms=terms)
            path = os.path.join(fleet.spool, "tie1l1_1.txt")
            broken = list(terms)
            broken[-1] = (broken[-1][0], broken[-1][1], broken[-1][2] ^ 1)
            write_dump(broken, path)
            self.assertEqual([], fleet.drain_spool(27))
            write_dump(terms, path)
            self.assertEqual(1, len(fleet.drain_spool(27)))

    def test_unexpected_failure_publishes_terminal_status(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)

            def fail_build():
                raise RuntimeError("synthetic compile failure")

            fleet.build_walker = fail_build
            with self.assertRaisesRegex(RuntimeError, "synthetic compile failure"):
                fleet.run()
            with open(fleet.status_path) as f:
                status = json.load(f)
            self.assertTrue(status["done"])
            self.assertFalse(status["compiling"])
            self.assertIn("synthetic compile failure", status["error"])

    def test_unowned_nonempty_run_directory_is_refused_without_data_loss(self):
        with tempfile.TemporaryDirectory() as run_dir:
            sentinel = os.path.join(run_dir, "keep-me.txt")
            with open(sentinel, "w") as stream:
                stream.write("user data")
            with self.assertRaisesRegex(ValueError, "unowned run directory"):
                Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            with open(sentinel) as stream:
                self.assertEqual("user data", stream.read())

    def test_generic_owned_filename_is_not_a_legacy_signature(self):
        with tempfile.TemporaryDirectory() as run_dir:
            status_path = os.path.join(run_dir, "status.json")
            with open(status_path, "w") as stream:
                json.dump({"application": "something else"}, stream)
            with self.assertRaisesRegex(ValueError, "unowned run directory"):
                Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            with open(status_path) as stream:
                self.assertEqual({"application": "something else"}, json.load(stream))
            self.assertFalse(os.path.exists(os.path.join(run_dir, ".flipfleet-owned")))

    def test_content_validated_legacy_run_can_be_marked_owned(self):
        with tempfile.TemporaryDirectory() as run_dir:
            with open(os.path.join(run_dir, "status.json"), "w") as stream:
                json.dump({"format": "3x3x3", "strategy": "islands", "walkers": []},
                          stream)
            with open(os.path.join(run_dir, "events.log"), "w") as stream:
                stream.write("[00:00:00] flipfleet start: legacy\n")
            with open(os.path.join(run_dir, "walker.w"), "w") as stream:
                stream.write('# generated worker emits "CYCLEOUT"\n')
            Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            with open(os.path.join(run_dir, ".flipfleet-owned")) as stream:
                self.assertEqual("flipfleet-v2", stream.read().strip())

    def test_owned_cleanup_preserves_unknown_files_and_lock_is_exclusive(self):
        with tempfile.TemporaryDirectory() as run_dir:
            first = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            sentinel = os.path.join(run_dir, "keep-me.txt")
            with open(sentinel, "w") as stream:
                stream.write("user data")
            first.acquire_lock()
            second = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            with self.assertRaisesRegex(RuntimeError, "run directory is active"):
                second.run()
            first.release_lock()
            second.prepare_run()
            second.release_lock()
            with open(sentinel) as stream:
                self.assertEqual("user data", stream.read())

    def test_recover_frontier_and_final_drain(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            first = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            write_dump(record, os.path.join(first.record, "rank23_saved.txt"))
            resumed = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23)
            requested, recovered, path = resumed.recover_frontier()
            self.assertEqual((27, 23), (requested, recovered))
            self.assertTrue(path.endswith("rank23_saved.txt"))
            self.assertEqual(record, resumed.initial)

            open(resumed.curve_path, "w").close()
            resumed.best = (27, naive_scheme(3, 3, 3))
            write_dump(density_increasing_flip(record, 3), resumed.dump_file(1))
            sparser = record
            self.assertTrue(verify(sparser, 3, 3, 3))
            write_dump(sparser, os.path.join(resumed.spool, "tie1l1_1.txt"))
            resumed.final_drain(time.time())
            self.assertEqual(23, resumed.best[0])
            self.assertEqual(cost(sparser, 3, 3, 3)["bits"],
                             resumed.score(*resumed.best)["bits"])


class EscapeFleetTest(unittest.TestCase):
    def test_record5_escape_kinds_are_exact_launch_excursions(self):
        record = parse_scheme(C3_RECORD_SEEDS[5])
        expected = {
            "break": (94, 2, False),
            "orbit-split": (98, 2, True),
            "polarize": (98, 2, True),
        }
        for kind, (rank, fixed, c3) in expected.items():
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as run_dir:
                fleet = Fleet(run_dir, 1, 0, n=5, m=5, p=5, record=93,
                              initial_terms=record, escape_kind=kind,
                              escape_every=1)
                escaped, metadata = fleet.prepare_launch_seed(record, "startup",
                                                               strict=True)
                info = describe_escape(set(escaped), 5)
                self.assertEqual((rank, fixed, c3, True),
                                 (len(escaped), info["fixed"], info["c3"],
                                  info["exact"]))
                self.assertTrue(metadata["applied"])
                self.assertEqual(sorted(record), fleet.initial)
                self.assertIsNone(fleet.best)
                self.assertEqual({}, fleet.archive)

    def test_generic_split_covers_non_c3_records_and_is_deterministic(self):
        for n in (3, 4):
            record = parse_scheme(RECORD_SEEDS[n])
            with self.subTest(n=n), tempfile.TemporaryDirectory() as first_dir, \
                    tempfile.TemporaryDirectory() as second_dir:
                first = Fleet(first_dir, 1, 0, n=n, m=n, p=n,
                              record=len(record), initial_terms=record,
                              escape_kind="split", escape_every=1)
                second = Fleet(second_dir, 1, 0, n=n, m=n, p=n,
                               record=len(record), initial_terms=list(reversed(record)),
                               escape_kind="split", escape_every=1)
                left, left_meta = first.prepare_launch_seed(record, "startup", strict=True)
                right, right_meta = second.prepare_launch_seed(
                    list(reversed(record)), "startup", strict=True)
                self.assertEqual(left, right)
                self.assertEqual(len(record) + 1, len(left))
                self.assertTrue(verify(left, n, n, n))
                self.assertEqual(left_meta["part"], right_meta["part"])
                self.assertEqual(left_meta["axis"], right_meta["axis"])

    def test_escape_cadence_and_trigger_do_not_stack(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, escape_kind="split",
                          escape_at="both", escape_every=2)
            first, first_meta = fleet.prepare_launch_seed(record, "startup", strict=True)
            second, second_meta = fleet.prepare_launch_seed(record, "startup", strict=True)
            third, third_meta = fleet.prepare_launch_seed(record, "cycleout")
            self.assertEqual((24, 23, 24), tuple(map(len, (first, second, third))))
            self.assertTrue(first_meta["applied"])
            self.assertIsNone(second_meta)
            self.assertTrue(third_meta["applied"])
            self.assertEqual(first, third)  # both derive from the rank-23 base
            self.assertEqual((3, 2, 1), (fleet.escape_considered,
                                         fleet.escape_applied,
                                         fleet.escape_bypassed))

    def test_cycleout_only_leaves_startup_unchanged_and_skips_ineligible_base(self):
        record4 = parse_scheme(RECORD_SEEDS[4])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=4, m=4, p=4, record=47,
                          initial_terms=record4, escape_kind="orbit-split",
                          escape_at="cycleout", escape_every=1)
            startup, metadata = fleet.prepare_launch_seed(record4, "startup")
            cycleout, skipped = fleet.prepare_launch_seed(record4, "cycleout")
            self.assertEqual(record4, startup)
            self.assertIsNone(metadata)
            self.assertEqual(record4, cycleout)
            self.assertFalse(skipped["applied"])
            self.assertIn("fixed C3", skipped["reason"])

    def test_invalid_generated_escape_is_never_returned(self):
        record = parse_scheme(RECORD_SEEDS[3])
        bad = set(record)
        term = next(iter(bad))
        bad.remove(term)
        bad.add((term[0] ^ 1, term[1], term[2]))
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, escape_kind="split",
                          escape_every=1)
            with mock.patch("flipfleet.best_bridge",
                            return_value=(bad, {"kind": "split", "x": None,
                                                "factor": term[0], "part": 1,
                                                "axis": 0, "term": term})):
                with self.assertRaisesRegex(RuntimeError, "failed exact"):
                    fleet.prepare_launch_seed(record, "startup", strict=True)

    def test_escape_configuration_validation(self):
        with tempfile.TemporaryDirectory() as run_dir:
            with self.assertRaisesRegex(ValueError, "square format"):
                Fleet(run_dir, 1, 0, n=2, m=3, p=2, record=12,
                      escape_kind="split")
        with tempfile.TemporaryDirectory() as run_dir:
            with self.assertRaisesRegex(ValueError, "escape_every"):
                Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                      escape_kind="split", escape_every=0)

    def test_default_policy_never_calls_escape_generator(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record)
            with mock.patch("flipfleet.best_bridge",
                            side_effect=AssertionError("escape should be off")):
                seed, metadata = fleet.prepare_launch_seed(record, "startup")
            self.assertEqual(record, seed)
            self.assertIsNone(metadata)
            self.assertEqual(0, fleet.escape_considered)

    def test_ineligible_startup_fails_before_compilation(self):
        record4 = parse_scheme(RECORD_SEEDS[4])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=4, m=4, p=4, record=47,
                          initial_terms=record4, escape_kind="orbit-split",
                          escape_at="startup", escape_every=1)
            fleet.build_walker = mock.Mock(
                side_effect=AssertionError("must fail before compilation"))
            with self.assertRaisesRegex(ValueError, "startup escape.*fixed C3"):
                fleet.run()
            fleet.build_walker.assert_not_called()
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=1, m=1, p=1, record=1,
                          escape_kind="split", escape_at="startup",
                          escape_every=1, escape_part=1)
            fleet.build_walker = mock.Mock(
                side_effect=AssertionError("must fail before compilation"))
            with self.assertRaisesRegex(ValueError, "startup escape.*no nontrivial"):
                fleet.run()
            fleet.build_walker.assert_not_called()

    def test_recovery_preserves_requested_c3_escape_profile(self):
        c3 = parse_scheme(C3_RECORD_SEEDS[5])
        # Apply an exact row-coordinate symmetry to break local C3 closure
        # without changing rank or density.  Recovery must prefer the eligible
        # C3 seed at this exact tie.
        identity = tuple(range(5))
        row_swap = (1, 0, 2, 3, 4)

        def permute_mask(mask, row_perm, col_perm):
            out = 0
            for bit in range(25):
                if mask >> bit & 1:
                    row, col = divmod(bit, 5)
                    out |= 1 << (row_perm[row] * 5 + col_perm[col])
            return out

        sparse_non_c3 = sorted(
            (permute_mask(u, row_swap, identity),
             permute_mask(v, identity, identity),
             permute_mask(w, row_swap, identity))
            for u, v, w in c3)
        self.assertTrue(verify(sparse_non_c3, 5, 5, 5))
        self.assertFalse(describe_escape(set(sparse_non_c3), 5)["c3"])
        with tempfile.TemporaryDirectory() as run_dir:
            first = Fleet(run_dir, 1, 0, n=5, m=5, p=5, record=93,
                          initial_terms=c3, escape_kind="orbit-split")
            write_dump(sparse_non_c3,
                       os.path.join(first.record, "rank93_non_c3_tie.txt"))
            resumed = Fleet(run_dir, 1, 0, n=5, m=5, p=5, record=93,
                            initial_terms=c3, escape_kind="orbit-split")
            requested, recovered, path = resumed.recover_frontier()
            self.assertEqual((93, 93, None), (requested, recovered, path))
            self.assertEqual(sorted(c3), resumed.initial)
            self.assertTrue(describe_escape(set(resumed.initial), 5)["c3"])

    def test_recovery_rank_precedes_escape_eligibility(self):
        naive2 = set(naive_scheme(2, 2, 2))
        c3_rank13, _ = best_bridge(naive2, 2, kind="orbit-split")
        non_c3_rank9, _ = best_bridge(naive2, 2, kind="split")
        self.assertEqual((13, 9), (len(c3_rank13), len(non_c3_rank9)))
        self.assertFalse(describe_escape(non_c3_rank9, 2)["c3"])
        with tempfile.TemporaryDirectory() as run_dir:
            first = Fleet(run_dir, 1, 0, n=2, m=2, p=2, record=8,
                          initial_terms=c3_rank13, escape_kind="orbit-split")
            write_dump(sorted(non_c3_rank9),
                       os.path.join(first.record, "rank9_non_c3_lower.txt"))
            resumed = Fleet(run_dir, 1, 0, n=2, m=2, p=2, record=8,
                            initial_terms=c3_rank13, escape_kind="orbit-split")
            requested, recovered, path = resumed.recover_frontier()
            self.assertEqual((13, 9), (requested, recovered))
            self.assertTrue(path.endswith("rank9_non_c3_lower.txt"))
            self.assertFalse(describe_escape(set(resumed.initial), 2)["c3"])

    def test_fake_startup_run_keeps_frontier_at_base_rank(self):
        record = parse_scheme(RECORD_SEEDS[3])
        launches = []
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, escape_kind="split",
                          escape_at="startup", escape_every=1)
            fleet.build_walker = lambda: setattr(fleet, "bin", "/unused")

            def fake_launch(index, salt, seed, source=None):
                launches.append(list(seed))
                fleet.request_stop()

            fleet.launch = fake_launch
            fleet.run()
            self.assertEqual(24, len(launches[0]))
            self.assertEqual(23, fleet.best[0])
            self.assertEqual({23}, {len(terms) for terms in fleet.archive.values()})
            rank, best = read_dump(os.path.join(run_dir, "best.txt"))
            self.assertEqual((23, sorted(record)), (rank, best))
            with open(fleet.status_path) as stream:
                status = json.load(stream)
            self.assertEqual(1, status["escape"]["applied"])


class GpuEscapeScoutTest(unittest.TestCase):
    def test_generated_5x5_kernel_uses_full_factor_width_and_seed_portfolio(self):
        record = parse_scheme(RECORD_SEEDS[5])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=5, m=5, p=5, record=93,
                          initial_terms=record, gpu=True, gpu_escapes=64)
            with mock.patch("flipfleet.subprocess.run") as compile_run:
                compile_run.return_value = subprocess_result = mock.Mock(returncode=0)
                subprocess_result.stdout = subprocess_result.stderr = ""
                fleet.build_gpu_relay()
            with open(os.path.join(run_dir, "gpu_relay.w")) as stream:
                source = stream.read()
            self.assertIn("state % 33554431", source)
            self.assertIn("seedid = tid % nseeds", source)
            self.assertIn("ESCAPE_SEEDS = 256", source)
            with open(fleet.events_path) as stream:
                self.assertIn("GPU relay compiled", stream.read())

    def test_generated_6x6_kernel_is_native_i64_and_fits_shared_memory(self):
        record = parse_scheme(RECORD_SEEDS[6])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=6, m=6, p=6, record=153,
                          initial_terms=record, gpu=True, gpu_escapes=64)
            with mock.patch("flipfleet.subprocess.run") as compile_run:
                result = mock.Mock(returncode=0, stdout="", stderr="")
                compile_run.return_value = result
                fleet.build_gpu_relay()
            with open(os.path.join(run_dir, "gpu_relay.w")) as stream:
                source = stream.read()
            self.assertIn("## i64[]: work_us", source)
            self.assertIn("gpu.shared_i64", source)
            self.assertIn("68719476735", source)
            self.assertIn("metal_buffer_write_i64(seed_us", source)
            self.assertEqual(0, fleet.gpu_walkers % 4)

    def test_gpu_candidates_pass_the_same_exact_gate_as_cpu_candidates(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, gpu=True)
            path = os.path.join(run_dir, "gpu_best.txt")
            with open(path, "w") as stream:
                stream.write(f"23 999\n")
                for u, v, w in record:
                    stream.write(f"{u} {v} {w}\n")
            self.assertEqual((23, 0, record, "gpu"), fleet.gpu_candidate(23))
            broken = list(record)
            u, v, w = broken[0]
            broken[0] = (u ^ 1, v, w)
            write_dump(broken, path)
            self.assertIsNone(fleet.gpu_candidate(23))
            self.assertEqual(1, fleet.invalid_candidates)


class MixedDefaultsTest(unittest.TestCase):
    def test_cli_defaults_to_mixed_adaptive_gpu_and_no_gpu_is_explicit(self):
        parser = build_arg_parser()
        defaults = parser.parse_args([])
        self.assertTrue(defaults.gpu)
        self.assertEqual("adaptive", defaults.gpu_policy)
        self.assertEqual("mixed", defaults.escape_profile)
        self.assertEqual(1, defaults.escape_every)
        disabled = parser.parse_args(["--tensor", "7x7", "--no-gpu"])
        self.assertFalse(disabled.gpu)
        self.assertEqual((7, 7, 7), disabled.tensor.dimensions)

    def test_7x7_cli_uses_the_saved_exact_rank247_composition(self):
        with tempfile.TemporaryDirectory() as run_dir, \
                mock.patch("flipfleet.Fleet") as fleet_class, \
                mock.patch("builtins.print"):
            flipfleet_main([
                "--tensor", "7x7", "--no-gpu", "--secs", "1",
                "--dir", run_dir,
            ])
        kwargs = fleet_class.call_args.kwargs
        self.assertEqual((7, 7, 7), (kwargs["n"], kwargs["m"], kwargs["p"]))
        self.assertEqual(247, kwargs["record"])
        self.assertEqual(247, len(kwargs["initial_terms"]))
        self.assertTrue(kwargs["record_known"])
        with tempfile.TemporaryDirectory() as run_dir, \
                mock.patch("flipfleet.Fleet") as explicit_fleet, \
                mock.patch("builtins.print"):
            flipfleet_main([
                "--tensor", "7x7", "--record", "248", "--no-gpu",
                "--secs", "1", "--dir", run_dir,
            ])
        self.assertEqual(248, explicit_fleet.call_args.kwargs["record"])
        self.assertTrue(explicit_fleet.call_args.kwargs["record_known"])

    def test_mixed_cpu_restarts_cycle_exact_variable_rank_slots(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, escape_profile="mixed",
                escape_at="both", escape_every=1, escape_bank_count=13)
            launches = [fleet.prepare_launch_seed(record, "startup")
                        for _ in range(13)]
            ranks = {len(terms) for terms, _ in launches}
            recipes = {metadata["recipe_name"] for _, metadata in launches}
            self.assertEqual({23, 24, 25}, ranks)
            self.assertEqual({"base", "split", "split+split"}, recipes)
            self.assertTrue(all(verify(terms, 3, 3, 3) for terms, _ in launches))

    def test_tensor_profile_builds_rotating_role_specific_gpu_banks(self):
        n = 5
        record = parse_scheme(RECORD_SEEDS[n])
        c3 = parse_scheme(C3_RECORD_SEEDS[n])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=n, m=n, p=n, record=93,
                initial_terms=record, c3_terms=c3, gpu=True,
                gpu_policy="adaptive", tensor_profile=profile_for_tensor(n),
                escape_profile="mixed", escape_bank_count=24)
            fleet.best = (93, record)
            fleet.refresh_gpu_role_seeds(preserve_novelty=False)
            self.assertEqual(set(fleet.gpu_roles), set(fleet.gpu_role_seed_banks))
            self.assertGreater(len(fleet.gpu_role_seed_banks["compose"]), 1)
            self.assertGreater(len(fleet.gpu_role_seed_banks["symmetry"]), 1)
            self.assertGreater(
                len({len(entry["terms"])
                     for entry in fleet.gpu_role_seed_banks["symmetry"]}), 1)
            for entry in fleet.gpu_role_seed_banks["symmetry"]:
                self.assertTrue(describe_escape(set(entry["terms"]), n)["c3"])
            allocation = fleet._initial_gpu_role_allocation()
            self.assertEqual(fleet.gpu_walkers, sum(allocation.values()))
            self.assertTrue(all(lanes >= 32 and lanes % 32 == 0
                                for lanes in allocation.values()))

    def test_c3_branch_rejects_sparser_non_c3_ordinary_leader(self):
        n = 5
        ordinary = parse_scheme(RECORD_SEEDS[n])
        symmetric = parse_scheme(C3_RECORD_SEEDS[n])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=n, m=n, p=n, record=93,
                initial_terms=ordinary, c3_terms=symmetric,
                gpu=True, gpu_policy="adaptive")
            fleet.best = (93, ordinary)
            self.assertFalse(fleet._consider_c3_leader(93, ordinary, refresh=False))
            self.assertTrue(describe_escape(set(fleet.c3_best[1]), n)["c3"])
            self.assertNotEqual(ordinary, fleet.c3_best[1])
            self.assertEqual(1155, fleet.score(*fleet.c3_best)["bits"])

    def test_c3_compile_capacity_covers_every_rotating_symmetric_slot(self):
        n = 5
        record = parse_scheme(RECORD_SEEDS[n])
        c3 = parse_scheme(C3_RECORD_SEEDS[n])
        profile = profile_for_tensor(n)
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=n, m=n, p=n, record=93,
                initial_terms=record, c3_terms=c3, gpu=True,
                gpu_policy="adaptive", tensor_profile=profile,
                escape_profile="mixed")
            compiled = mock.Mock(returncode=0, stdout="", stderr="")
            with mock.patch("flipfleet.subprocess.run", return_value=compiled), \
                    mock.patch("flipfleet.CooperativeSimdRelay"), \
                    mock.patch("flipfleet.C3GpuRelay") as c3_relay, \
                    mock.patch("flipfleet.GpuMitmFleetAdapter"):
                fleet.build_gpu_relay()
            config = c3_relay.call_args.args[1]
            max_rank = max(
                len(entry.scheme) for entry in fleet._mixed_portfolio(c3)
                if entry.profile["c3"])
            self.assertGreaterEqual(config.cap, max_rank + config.band + 6)

    def test_single_gpu_policy_does_not_build_unused_adapters(self):
        n = 5
        record = parse_scheme(RECORD_SEEDS[n])
        c3_terms = parse_scheme(C3_RECORD_SEEDS[n])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=n, m=n, p=n, record=93,
                initial_terms=record, c3_terms=c3_terms, gpu=True,
                gpu_policy="single", tensor_profile=profile_for_tensor(n))
            compiled = mock.Mock(returncode=0, stdout="", stderr="")
            with mock.patch("flipfleet.subprocess.run", return_value=compiled), \
                    mock.patch("flipfleet.CooperativeSimdRelay") as simd, \
                    mock.patch("flipfleet.C3GpuRelay") as c3, \
                    mock.patch("flipfleet.GpuMitmFleetAdapter") as mitm:
                fleet.build_gpu_relay()
            simd.assert_not_called()
            c3.assert_not_called()
            mitm.assert_not_called()

    def test_missing_adaptive_role_is_repaired_even_without_reallocation(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 1, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, gpu=True, gpu_policy="adaptive",
                gpu_walkers=128)
            fleet.best = (23, record)
            fleet.refresh_gpu_role_seeds(preserve_novelty=False)
            fleet.gpu_role_allocations = fleet._initial_gpu_role_allocation()
            alive = mock.Mock()
            alive.poll.return_value = None
            fleet.gpu_procs = {role: alive for role in fleet.gpu_roles
                               if role != "rank"}
            with mock.patch.object(fleet, "_launch_gpu_role") as launch:
                fleet.repair_gpu_roles(now=time.time())
            launch.assert_called_once_with(
                "rank", fleet.gpu_role_allocations["rank"])
            fleet.gpu_procs.pop("density", None)
            fleet.request_stop()
            with mock.patch.object(fleet, "_launch_gpu_role") as stopped_launch:
                fleet.repair_gpu_roles(now=time.time())
            stopped_launch.assert_not_called()
            with mock.patch.object(fleet, "_launch_gpu_role") as drain_launch:
                self.assertEqual([], fleet.gpu_candidates(23))
            drain_launch.assert_not_called()


class AdaptiveGpuPolicyTest(unittest.TestCase):
    @staticmethod
    def _permuted_records(count):
        base = parse_scheme(RECORD_SEEDS[3])

        def permute_mask(mask, permutation):
            out = 0
            for bit in range(9):
                if mask >> bit & 1:
                    row, col = divmod(bit, 3)
                    out |= 1 << (permutation[row] * 3 + col)
            return out

        variants = []
        for permutation in itertools.permutations(range(3)):
            terms = sorted((permute_mask(u, permutation), v,
                            permute_mask(w, permutation))
                           for u, v, w in base)
            if terms not in variants:
                variants.append(terms)
        return variants[:count]

    def test_adaptive_roles_partition_lanes_and_specialize_parameters(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, gpu=True, gpu_walkers=128,
                          gpu_policy="adaptive")
            fleet.best = (23, record)
            fleet.gpu_bin = os.path.join(run_dir, "fake_gpu")
            fleet.gpu_wpg = 16
            processes = []
            for _ in range(4):
                process = mock.Mock(returncode=0)
                process.poll.return_value = 0
                processes.append(process)
            with mock.patch("flipfleet.subprocess.Popen", side_effect=processes) as popen:
                fleet.launch_gpu_relay()
            self.assertEqual(4, popen.call_count)
            self.assertEqual(128, sum(fleet.gpu_role_allocations.values()))
            self.assertEqual({0}, {lanes % 32
                                   for lanes in fleet.gpu_role_allocations.values()})
            calls = {call.args[0][2].split("gpu_")[1].split("_best")[0]:
                     call.args[0] for call in popen.call_args_list}
            self.assertEqual("1", calls["density"][16])
            self.assertEqual("1", calls["novelty"][16])
            self.assertEqual("1", calls["rank"][16])
            self.assertEqual(str(fleet.gpu_escapes), calls["split"][16])
            self.assertLess(int(calls["split"][9]), int(calls["density"][9]))
            for role in list(fleet.gpu_procs):
                fleet._stop_gpu_role(role)

    def test_ucb_feedback_gives_productive_role_more_lanes_but_keeps_floors(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, gpu=True, gpu_walkers=160,
                          gpu_policy="adaptive")
            fleet.gpu_wpg = 16
            for stats in fleet.gpu_role_stats.values():
                stats["epochs"] = 10
                stats["lane_epochs"] = 10
                stats["reward"] = 1.0
            fleet.gpu_role_stats["rank"]["reward"] = 100.0
            allocation = fleet.gpu_lane_allocation()
            self.assertEqual(160, sum(allocation.values()))
            self.assertGreater(allocation["rank"], allocation["density"])
            self.assertTrue(all(lanes >= 32 for lanes in allocation.values()))

    def test_exact_gate_precedes_pareto_and_role_reward(self):
        record, variant = self._permuted_records(2)
        self.assertNotEqual(record, variant)
        self.assertTrue(verify(variant, 3, 3, 3))
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, gpu=True, gpu_policy="adaptive")
            fleet.best = (23, record)
            write_dump(variant, os.path.join(run_dir, "gpu_rank_best.txt"))
            candidates = fleet.gpu_candidates(23)
            self.assertEqual([(23, 0, variant, "gpu/rank")], candidates)
            self.assertEqual(1, len(fleet.gpu_pareto))
            self.assertEqual(1, fleet.gpu_role_stats["rank"]["candidates"])
            self.assertGreater(fleet.gpu_role_stats["rank"]["reward"], 0)

            broken = list(variant)
            u, v, w = broken[0]
            broken[0] = (u ^ 1, v, w)
            write_dump(broken, os.path.join(run_dir, "gpu_split_best.txt"))
            self.assertEqual([], fleet.gpu_candidates(23))
            self.assertEqual(1, len(fleet.gpu_pareto))
            self.assertEqual(0, fleet.gpu_role_stats["split"]["candidates"])
            self.assertEqual(1, fleet.invalid_candidates)

    def test_pareto_discards_dominated_candidate_and_keeps_tradeoff(self):
        variants = self._permuted_records(3)
        self.assertEqual(3, len(variants))
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=variants[0], gpu=True,
                          gpu_policy="adaptive", gpu_novelty_size=4)
            fleet.best = None
            metrics = [
                {"bits": 100, "flip_pairs": 3, "novelty": 10},
                {"bits": 90, "flip_pairs": 4, "novelty": 12},
                {"bits": 80, "flip_pairs": 2, "novelty": 20},
            ]
            with mock.patch.object(fleet, "_gpu_metrics", side_effect=metrics):
                self.assertTrue(fleet.gpu_pareto_admit(23, variants[0], "rank")[0])
                self.assertTrue(fleet.gpu_pareto_admit(23, variants[1], "density")[0])
                self.assertTrue(fleet.gpu_pareto_admit(23, variants[2], "novelty")[0])
            self.assertEqual(2, len(fleet.gpu_pareto))
            self.assertNotIn(fleet.canonical(variants[0]), fleet.gpu_pareto)
            self.assertIn(fleet.canonical(variants[1]), fleet.gpu_pareto)
            self.assertIn(fleet.canonical(variants[2]), fleet.gpu_pareto)

    def test_bounded_engine_returning_its_seed_gets_no_productivity_reward(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, gpu=True, gpu_policy="adaptive")
            fleet.best = (23, record)
            admitted, entry = fleet.gpu_pareto_admit(23, record, "rank")
            self.assertFalse(admitted)
            fleet._reward_gpu_role("rank", 23, entry, admitted)
            self.assertEqual(0.0, fleet.gpu_role_stats["rank"]["reward"])


class CpuDiversityPolicyTest(unittest.TestCase):
    def test_tensor_specific_zone_arms_and_sticky_doors(self):
        record = parse_scheme(RECORD_SEEDS[5])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 12, 0, n=5, m=5, p=5, record=93,
                          initial_terms=record)
            self.assertEqual(
                (100_000_000, 500_000_000, 2_500_000_000, 10_000_000_000),
                fleet.work_zone_moves)
            self.assertEqual(
                (25_000_000, 100_000_000, 500_000_000, 1_000_000_000),
                fleet.wander_zone_moves)
            self.assertEqual(1, fleet.migrate)
            self.assertEqual(1, fleet.cpu_door_roles.count("leader"))
            self.assertEqual(3, fleet.cpu_door_roles.count("symmetry"))
            self.assertEqual(2, fleet.cpu_door_roles.count("near1"))
            self.assertEqual(2, fleet.cpu_door_roles.count("near2"))

    def test_launch_passes_distinct_work_wander_and_near_spool(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record)
            fleet.best = (23, record)
            fleet.bin = "/unused/walker"
            process = mock.Mock(returncode=0)
            process.poll.return_value = 0
            with mock.patch("flipfleet.subprocess.Popen", return_value=process) as popen:
                fleet.launch(1, 0, record)
                first_argv = popen.call_args.args[0]
                # A sticky leader can relaunch without moving any global
                # frontier counter; launch_id must still select a fresh stream.
                fleet.launch(1, 0, record)
                second_argv = popen.call_args.args[0]
            argv = first_argv
            # Walker one is the balanced arm in the stable schedule order.
            self.assertEqual("125000000", argv[7])
            self.assertEqual("25000000", argv[8])
            self.assertIn("near1l1", argv[9])
            self.assertEqual("23", argv[10])
            self.assertNotEqual(first_argv[1], second_argv[1])
            fleet.logs[1].close()

    def test_migration_only_uses_known_leader_frontier_lanes(self):
        record = parse_scheme(RECORD_SEEDS[5])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 12, 0, n=5, m=5, p=5, record=93,
                          initial_terms=record, migrate=2)
            ranks = {index: 93 + index for index in range(1, 13)}
            targets = fleet.migration_targets(12, ranks)
            self.assertEqual(2, len(targets))
            self.assertTrue(all(fleet.cpu_door_roles[index] in
                                ("leader", "frontier") for index in targets))
            # An unreadable leader is preserved rather than treated as worst.
            ranks.pop(1)
            self.assertNotIn(1, fleet.migration_targets(12, ranks))

    def test_generated_worker_has_bounded_near_frontier_spool(self):
        source = gen(3, 3, 3, 22, world_record=23,
                     record_bandq=100, runtime_seed=True,
                     adaptive_esc="cal2zone2")
        self.assertIn("if av0.size() > 8", source)
        self.assertIn("nearbase = av0[9].to_i()", source)
        self.assertIn("if rank <= nearbase + 2", source)
        self.assertIn("if nearhit < 8", source)

    def test_exact_near_banks_feed_sticky_rank_specific_doors(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 7, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, escape_profile="mixed",
                escape_every=1, escape_bank_count=24)
            fleet.best = (23, record)
            fleet.initialize_cpu_seed_banks()

            self.assertEqual((23, record), fleet.best)
            self.assertEqual(23, fleet.cpu_near_bank.best_rank)
            self.assertGreater(len(fleet.cpu_near_bank.entries(1)), 0)
            self.assertGreater(len(fleet.cpu_near_bank.entries(2)), 0)
            for delta in (1, 2):
                for entry in fleet.cpu_near_bank.entries(delta):
                    self.assertEqual(23 + delta, entry.rank)
                    self.assertTrue(verify(entry.terms, 3, 3, 3))

            near1, source1, escape1 = fleet.cpu_launch_seed(3, "startup")
            near2, source2, escape2 = fleet.cpu_launch_seed(7, "startup")
            self.assertEqual(("near1", "near2"),
                             (fleet.cpu_door_roles[3], fleet.cpu_door_roles[7]))
            self.assertEqual(("near1", "near2"), (source1, source2))
            self.assertEqual((24, 25), (len(near1), len(near2)))
            self.assertTrue(verify(near1, 3, 3, 3))
            self.assertTrue(verify(near2, 3, 3, 3))
            self.assertIsNone(escape1)
            self.assertIsNone(escape2)
            self.assertEqual(fleet.canonical(near1),
                             fleet.cpu_active_near_seed[3].terms)
            self.assertEqual(fleet.canonical(near2),
                             fleet.cpu_active_near_seed[7].terms)

            fleet.write_status(time.time())
            with open(fleet.status_path) as stream:
                status = json.load(stream)
            self.assertEqual(23, status["cpu"]["near"]["best_rank"])
            self.assertGreater(status["cpu"]["near"]["tiers"]["+1"]["size"], 0)
            self.assertGreater(status["cpu"]["near"]["tiers"]["+2"]["size"], 0)
            self.assertEqual("near1", status["walkers"][2]["door"])
            self.assertEqual("near2", status["walkers"][6]["door"])

            # A direct convergence launch must not leave stale productivity
            # credit attached to the shoulder process it replaces.
            fleet.bin = "/unused/walker"
            process = mock.Mock(returncode=0)
            process.poll.return_value = 0
            with mock.patch("flipfleet.subprocess.Popen", return_value=process):
                fleet.launch(3, 0, record)
            self.assertIsNone(fleet.cpu_active_near_seed[3])
            fleet.logs[3].close()

    def test_none_profile_keeps_shoulder_doors_unescaped(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 3, 0, n=3, m=3, p=3, record=23,
                          initial_terms=record, archive_reseed=1.0)
            fleet.best = (23, record)
            fleet.archive_candidate(23, record, source="fixture")
            fleet.initialize_cpu_seed_banks()
            seed, source, escape = fleet.cpu_launch_seed(3, "startup")
            self.assertEqual(23, len(seed))
            self.assertTrue(source.startswith("near1-fallback/"))
            self.assertIsNone(escape)
            self.assertEqual(0, fleet.cpu_near_bank.status()["size"])

    def test_shoulder_doors_honor_one_sided_escape_triggers(self):
        record = parse_scheme(RECORD_SEEDS[3])
        for escape_at, startup_rank, cycleout_rank in (
                ("cycleout", 23, 24), ("startup", 24, 23)):
            with self.subTest(escape_at=escape_at), tempfile.TemporaryDirectory() as run_dir:
                fleet = Fleet(
                    run_dir, 3, 0, n=3, m=3, p=3, record=23,
                    initial_terms=record, archive_reseed=1.0,
                    escape_profile="mixed", escape_at=escape_at,
                    escape_every=1)
                fleet.best = (23, record)
                fleet.archive_candidate(23, record, source="fixture")
                fleet.initialize_cpu_seed_banks()
                startup, _, _ = fleet.cpu_launch_seed(3, "startup")
                cycleout, _, _ = fleet.cpu_launch_seed(3, "cycleout")
                self.assertEqual(startup_rank, len(startup))
                self.assertEqual(cycleout_rank, len(cycleout))

    def test_shoulder_doors_honor_per_walker_escape_cadence(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 3, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, archive_reseed=1.0,
                escape_profile="mixed", escape_every=2)
            fleet.best = (23, record)
            fleet.archive_candidate(23, record, source="fixture")
            fleet.initialize_cpu_seed_banks()
            scheduled, _, _ = fleet.cpu_launch_seed(3, "startup")
            skipped, _, _ = fleet.cpu_launch_seed(3, "cycleout")
            self.assertEqual(24, len(scheduled))
            self.assertEqual(23, len(skipped))

    def test_mixed_door_cadence_is_not_double_applied(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 10, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, escape_profile="mixed",
                escape_every=2)
            fleet.best = (23, record)
            fleet.initialize_cpu_seed_banks()
            first = fleet.cpu_launch_seed(10, "startup")
            second = fleet.cpu_launch_seed(10, "cycleout")
            third = fleet.cpu_launch_seed(10, "cycleout")
            self.assertEqual("mixed", fleet.cpu_door_roles[10])
            self.assertIsNotNone(first[2])
            self.assertIsNone(second[2])
            self.assertIsNotNone(third[2])
            self.assertEqual(3, fleet.escape_considered)

    def test_symmetry_door_uses_exact_one_move_c3_provenance(self):
        record = parse_scheme(RECORD_SEEDS[5])
        c3 = parse_scheme(C3_RECORD_SEEDS[5])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 7, 0, n=5, m=5, p=5, record=93,
                initial_terms=record, c3_terms=c3,
                escape_profile="mixed", escape_every=1, escape_bank_count=4,
                cpu_symmetry_seeds=2)
            fleet.best = (93, record)
            fleet.initialize_cpu_seed_banks()

            seed, source, escape = fleet.cpu_launch_seed(7, "startup")
            key = fleet.canonical(seed)
            entry = next(entry for entry in fleet.cpu_symmetry_bank
                         if entry.scheme == key)
            self.assertEqual("symmetry", fleet.cpu_door_roles[7])
            self.assertEqual("symmetry:" + "+".join(entry.recipe), source)
            self.assertIn(entry.recipe, (("orbit-split",), ("polarize",)))
            self.assertEqual(1, len(entry.moves))
            self.assertEqual(entry.recipe[0], entry.moves[0].kind)
            self.assertTrue(entry.profile["c3"])
            self.assertTrue(check_c3(seed, 5))
            self.assertTrue(verify(seed, 5, 5, 5))
            self.assertIsNone(escape)

    def test_note_best_rebases_old_frontier_into_near_tier(self):
        record = parse_scheme(RECORD_SEEDS[3])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(
                run_dir, 7, 0, n=3, m=3, p=3, record=23,
                initial_terms=record, escape_profile="mixed",
                escape_every=1, escape_bank_count=6)
            old_frontier = next(
                list(entry.scheme) for entry in fleet._mixed_portfolio(record)
                if len(entry.scheme) == 24)
            fleet.best = (24, old_frontier)
            self.assertTrue(fleet.archive_candidate(
                24, old_frontier, source="old-frontier-fixture"))
            fleet.initialize_cpu_seed_banks()

            self.assertTrue(fleet.note_best(23, record, 0.1))
            self.assertEqual(23, fleet.best[0])
            self.assertEqual(23, fleet.cpu_near_bank.best_rank)
            self.assertEqual(1, fleet.cpu_near_rebases)
            carried = next(
                entry for entry in fleet.cpu_near_bank.entries(1)
                if entry.terms == fleet.canonical(old_frontier))
            self.assertEqual("old-frontier", carried.source)
            self.assertEqual(24, carried.metadata["frontier_rank"])
            self.assertNotIn(fleet.canonical(old_frontier), fleet.archive)

    def test_cpu_near_cli_knobs_parse_independently(self):
        args = build_arg_parser().parse_args([
            "--cpu-near-size", "10",
            "--cpu-near-signature-quota", "3",
            "--cpu-symmetry-seeds", "5",
        ])
        self.assertEqual(10, args.cpu_near_size)
        self.assertEqual(3, args.cpu_near_signature_quota)
        self.assertEqual(5, args.cpu_symmetry_seeds)
        self.assertEqual(1.0, args.archive_reseed)


class DiversityArchiveTest(unittest.TestCase):
    @staticmethod
    def _permute_mask(mask, rows, cols, row_perm, col_perm):
        out = 0
        for bit in range(rows * cols):
            if mask >> bit & 1:
                row, col = divmod(bit, cols)
                out |= 1 << (row_perm[row] * cols + col_perm[col])
        return out

    @classmethod
    def _permute_scheme(cls, terms, n, ip, jp, kp):
        return sorted((cls._permute_mask(u, n, n, ip, jp),
                       cls._permute_mask(v, n, n, jp, kp),
                       cls._permute_mask(w, n, n, ip, kp))
                      for u, v, w in terms)

    @staticmethod
    def _minimum_distance(fleet):
        schemes = list(fleet.archive_sets.values())
        return min(fleet.scheme_distance(a, b)
                   for a, b in itertools.combinations(schemes, 2))

    def test_bounded_max_min_archive_and_balanced_reseeding(self):
        base = parse_scheme(RECORD_SEEDS[3])
        perms = list(itertools.permutations(range(3)))
        variants = []
        for ip, jp, kp in itertools.product(perms, repeat=3):
            variant = self._permute_scheme(base, 3, ip, jp, kp)
            if variant not in variants:
                variants.append(variant)
            if len(variants) == 12:
                break
        self.assertEqual(12, len(variants))

        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=base, archive_reseed=1.0, archive_size=4)
            fleet.best = (23, base)
            for terms in variants[:4]:
                self.assertTrue(fleet.archive_candidate(23, terms, source="test"))
            initial_distance = self._minimum_distance(fleet)
            for terms in variants[4:]:
                self.assertTrue(fleet.archive_candidate(23, terms, source="test"))
            self.assertEqual(4, len(fleet.archive))
            final_distance = self._minimum_distance(fleet)
            self.assertGreaterEqual(final_distance, initial_distance)
            self.assertEqual(final_distance, fleet.archive_min_distance)
            self.assertGreater(fleet.archive_evictions + fleet.archive_rejections, 0)
            for _ in range(4):
                terms, source = fleet.frontier_seed()
                self.assertEqual("frontier", source)
                self.assertTrue(fleet.exact_valid(23, terms))
            self.assertEqual({1}, set(fleet.archive_uses.values()))

        with tempfile.TemporaryDirectory() as run_dir:
            first = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=base, archive_size=4)
            write_dump(variants[1], os.path.join(first.record, "rank23_old1.txt"))
            write_dump(variants[2], os.path.join(first.record, "rank23_old2.txt"))
            resumed = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                            initial_terms=base, archive_size=4)
            resumed.best = (23, base)
            resumed.archive_candidate(23, base, source="initial")
            self.assertEqual(2, resumed.hydrate_archive(23))
            self.assertEqual(3, len(resumed.archive))

    def test_same_rank_sparser_candidate_becomes_status_leader(self):
        tied = parse_scheme(RECORD_SEEDS[3])
        base = density_increasing_flip(tied, 3)
        self.assertTrue(verify(tied, 3, 3, 3))
        self.assertLess(cost(tied, 3, 3, 3)["bits"], cost(base, 3, 3, 3)["bits"])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=base, archive_size=4,
                          escape_profile="mixed", escape_every=1)
            open(fleet.curve_path, "w").close()
            fleet.best = (23, base)
            fleet.archive_candidate(23, base, source="initial")
            fleet.initialize_cpu_seed_banks()
            old_admissions = fleet.cpu_near_admissions
            self.assertTrue(fleet.note_tie_leader(23, tied, 1.0))
            self.assertEqual(cost(tied, 3, 3, 3)["bits"],
                             fleet.score(*fleet.best)["bits"])
            self.assertEqual(1, fleet.tie_improvements)
            self.assertIn(fleet.canonical(tied), fleet.archive)
            self.assertGreater(fleet.cpu_near_admissions, old_admissions)
            self.assertIn("tie-frontier",
                          {entry.source for entry in fleet.cpu_near_bank.entries()})


class SchedulePortfolioTest(unittest.TestCase):
    def test_move_budget_parser(self):
        self.assertEqual((250_000_000, 1_000_000_000, 10_000_000_000),
                         parse_move_budgets("250m,1b,10_000m"))
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_move_budgets("0,1b")


if __name__ == "__main__":
    unittest.main()
