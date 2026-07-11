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
from flipfleet import (C3_RECORD_SEEDS, Fleet, RECORD_SEEDS, parse_move_budgets, read_dump,
                       write_dump)  # noqa: E402
from metaflip_proto2 import recon  # noqa: E402
from sym_start import (  # noqa: E402
    check_c3,
    check_reversal,
    diagonal_partition_scheme,
    parse_partition,
)
from sym_escape import best_bridge, describe as describe_escape  # noqa: E402


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
        self.assertIn("q = recordqv", runtime_budget)
        self.assertIn("if best_rank <= 23\n  nextesc = recordqv", runtime_budget)
        self.assertIn("    if cycleout == 0\n      aband = nb", runtime_budget)
        self.assertIn("    wraps = 0\n    nextesc = mv + 2500000000", runtime_budget)

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
            write_dump(record, resumed.dump_file(1))
            left, right = record[11], record[2]
            sparser = [term for index, term in enumerate(record)
                       if index not in (2, 11)]
            sparser.extend(((left[0], left[1] ^ right[1], left[2]),
                            (right[0], right[1], left[2] ^ right[2])))
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

            def fake_launch(index, salt, seed):
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
        base = parse_scheme(RECORD_SEEDS[3])
        left, right = base[11], base[2]
        self.assertEqual(left[0], right[0])
        replacement = [(left[0], left[1] ^ right[1], left[2]),
                       (right[0], right[1], left[2] ^ right[2])]
        tied = [term for index, term in enumerate(base) if index not in (2, 11)]
        tied.extend(replacement)
        self.assertTrue(verify(tied, 3, 3, 3))
        self.assertLess(cost(tied, 3, 3, 3)["bits"], cost(base, 3, 3, 3)["bits"])
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=base, archive_size=4)
            open(fleet.curve_path, "w").close()
            fleet.best = (23, base)
            fleet.archive_candidate(23, base, source="initial")
            self.assertTrue(fleet.note_tie_leader(23, tied, 1.0))
            self.assertEqual(cost(tied, 3, 3, 3)["bits"],
                             fleet.score(*fleet.best)["bits"])
            self.assertEqual(1, fleet.tie_improvements)
            self.assertIn(fleet.canonical(tied), fleet.archive)


class SchedulePortfolioTest(unittest.TestCase):
    def test_move_budget_parser(self):
        self.assertEqual((250_000_000, 1_000_000_000, 10_000_000_000),
                         parse_move_budgets("250m,1b,10_000m"))
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_move_budgets("0,1b")


if __name__ == "__main__":
    unittest.main()
