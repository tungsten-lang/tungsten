import json
import os
import sys
import tempfile
import unittest
from unittest import mock


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import flipfleet  # noqa: E402
from bench_decomp import parse_scheme  # noqa: E402
from flipfleet import Fleet, RECORD_SEEDS  # noqa: E402


class ProducerHealthStatusTest(unittest.TestCase):
    def setUp(self):
        self.record = parse_scheme(RECORD_SEEDS[3])

    @staticmethod
    def read_status(fleet):
        with open(fleet.status_path) as stream:
            return json.load(stream)

    def test_heartbeat_is_timestamped_monotonic_and_names_producer_phase(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=self.record)
            fleet.best = (23, self.record)

            with mock.patch("flipfleet.time.time", return_value=101.25):
                fleet.write_status(100.0, compiling=True)
            compiling = self.read_status(fleet)

            with mock.patch("flipfleet.time.time", return_value=102.5):
                fleet.write_status(100.0)
            live = self.read_status(fleet)

            self.assertEqual(os.getpid(), compiling["coordinator_pid"])
            self.assertEqual("compiling", compiling["producer_state"])
            self.assertEqual("live", live["producer_state"])
            self.assertEqual(101.25, compiling["updated_at"])
            self.assertEqual(102.5, live["updated_at"])
            self.assertGreater(live["sequence"], compiling["sequence"])

    def test_terminal_producer_states_distinguish_done_and_failed(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=self.record)
            fleet.best = (23, self.record)
            fleet.write_status(100.0, done=True)
            self.assertEqual("done", self.read_status(fleet)["producer_state"])

            fleet.error = "RuntimeError: synthetic failure"
            fleet.write_status(100.0, done=True)
            failed = self.read_status(fleet)
            self.assertEqual("failed", failed["producer_state"])
            self.assertEqual("RuntimeError: synthetic failure", failed["error"])

    def test_live_walker_status_reports_progress_provenance_rate_and_process(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=self.record)
            fleet.best = (23, self.record)
            fleet.bin = "/unused/walker"
            process = mock.Mock(pid=4321)
            process.poll.return_value = None

            with mock.patch("flipfleet.time.time", return_value=100.0), \
                    mock.patch("flipfleet.subprocess.Popen", return_value=process):
                fleet.launch(1, 0, self.record, source="near1")

            fleet.logs[1].write(
                "BAND band=3 rank=25 mv=100000000\n"
                "  mv=200000000 best=24 cur=25 v=1\n")
            fleet.logs[1].flush()
            with mock.patch("flipfleet.time.time", return_value=110.0):
                fleet.write_status(100.0)
            status = self.read_status(fleet)
            walker = status["walkers"][0]

            expected = {
                "source", "seed_rank", "seed_digest", "seed_c3",
                "current_rank", "band", "rate_mps", "progress_age",
                "running", "process_state", "pid", "exit_code",
                "launch_count", "work_moves", "wander_moves",
            }
            self.assertTrue(expected.issubset(walker), expected - set(walker))
            self.assertEqual("near1", walker["source"])
            self.assertEqual(23, walker["seed_rank"])
            self.assertEqual(24, int(walker["rank"]))
            self.assertEqual(25, walker["current_rank"])
            self.assertEqual(3, walker["band"])
            self.assertEqual(20_000_000.0, walker["rate_mps"])
            self.assertTrue(walker["running"])
            self.assertEqual("running", walker["process_state"])
            self.assertEqual(4321, walker["pid"])
            self.assertIsNone(walker["exit_code"])
            self.assertEqual(1, walker["launch_count"])
            self.assertEqual(0.0, walker["progress_age"])
            self.assertEqual(12, len(walker["seed_digest"]))
            self.assertIsInstance(walker["seed_c3"], bool)

            cohorts = status["cpu"]["cohorts"]
            self.assertTrue(cohorts)
            cohort = next(iter(cohorts.values()))
            cohort_metrics = {
                "launches", "moves", "cpu_seconds", "completions",
                "cycleouts", "exits", "rank_drops", "tie_improvements",
                "near_admissions", "frontier_returns", "quarantines",
                "migrations",
            }
            self.assertTrue(cohort_metrics.issubset(cohort),
                            cohort_metrics - set(cohort))
            self.assertEqual(1, sum(item["launches"]
                                    for item in cohorts.values()))
            self.assertEqual(200_000_000, sum(item["moves"]
                                              for item in cohorts.values()))
            fleet.logs[1].close()

    def test_exited_walker_keeps_exit_code_and_is_not_reported_running(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=self.record)
            fleet.best = (23, self.record)
            fleet.bin = "/unused/walker"
            process = mock.Mock(pid=9876)
            process.poll.return_value = 17
            with mock.patch("flipfleet.time.time", return_value=100.0), \
                    mock.patch("flipfleet.subprocess.Popen", return_value=process):
                fleet.launch(1, 0, self.record, source="leader")
                fleet.write_status(100.0)
            walker = self.read_status(fleet)["walkers"][0]
            self.assertFalse(walker["running"])
            self.assertEqual("exited", walker["process_state"])
            self.assertEqual(17, walker["exit_code"])
            fleet.logs[1].close()

    def test_gpu_role_status_exposes_dashboard_and_normalized_productivity(self):
        with tempfile.TemporaryDirectory() as run_dir:
            fleet = Fleet(run_dir, 1, 0, n=3, m=3, p=3, record=23,
                          initial_terms=self.record, gpu=True,
                          gpu_policy="adaptive", gpu_walkers=128)
            fleet.best = (23, self.record)
            role = fleet.gpu_roles[0]
            fleet.gpu_role_stats[role].update({
                "epochs": 3, "lane_epochs": 96, "reward": 12.0,
                "candidates": 7, "pareto": 2, "rank_drops": 1,
                "density_improvements": 1,
            })
            fleet.gpu_role_allocations[role] = 32
            fleet.gpu_role_launches[role] = 2
            fleet.write_status(100.0)
            gpu = self.read_status(fleet)["gpu"]
            dashboard = gpu["roles"][role]
            expected = {
                "lanes", "weight", "seed", "launches", "failures",
                "retry_at", "plan", "epochs", "lane_epochs", "reward",
                "reward_per_lane_epoch", "candidates", "pareto",
                "rank_drops", "density_improvements",
            }
            self.assertTrue(expected.issubset(dashboard),
                            expected - set(dashboard))
            self.assertEqual(0.125, dashboard["reward_per_lane_epoch"])
            self.assertEqual(
                {"size", "capacity", "admissions", "rejections", "evictions"},
                set(gpu["pareto"]))


class HealthDerivationTest(unittest.TestCase):
    def status(self, **changes):
        status = {
            "updated_at": 100.0,
            "sequence": 8,
            "producer_state": "live",
            "done": False,
            "compiling": False,
            "error": None,
            "walkers": [{"id": 1, "running": True,
                         "process_state": "running"}],
            "gpu": {"enabled": False, "running": False},
        }
        status.update(changes)
        return status

    def assert_state(self, expected, status, now=102.0):
        health = flipfleet.derive_health_state(status, now=now, stale_after=5.0)
        self.assertIsInstance(health, dict)
        self.assertEqual(expected, health["state"])

    def test_all_six_health_states(self):
        self.assert_state("LIVE", self.status())
        self.assert_state("COMPILING", self.status(
            compiling=True, producer_state="compiling"))
        self.assert_state("DEGRADED", self.status(walkers=[{
            "id": 1, "running": False, "process_state": "exited",
            "exit_code": 9,
        }]))
        self.assert_state("STALE", self.status(), now=105.01)
        self.assert_state("DONE", self.status(done=True, producer_state="done"),
                          now=1_000.0)
        self.assert_state("FAILED", self.status(
            done=True, producer_state="failed", error="boom"), now=1_000.0)

    def test_health_precedence_is_failed_done_compiling_stale_degraded_live(self):
        dead = [{"id": 1, "running": False, "process_state": "exited"}]
        self.assert_state("FAILED", self.status(
            done=True, compiling=True, error="boom", walkers=dead), now=999.0)
        self.assert_state("DONE", self.status(
            done=True, compiling=True, walkers=dead), now=999.0)
        self.assert_state("COMPILING", self.status(
            compiling=True, walkers=dead), now=999.0)
        self.assert_state("STALE", self.status(walkers=dead), now=999.0)
        self.assert_state("DEGRADED", self.status(walkers=dead))


class TuiFormattingHelpersTest(unittest.TestCase):
    def test_objective_describes_known_record_with_a_signed_human_gap(self):
        common = {"record": 23, "configured_record": 23, "record_known": True}
        above = flipfleet.format_objective({**common, "best": {"rank": 26}})
        match = flipfleet.format_objective({**common, "best": {"rank": 23}})
        beat = flipfleet.format_objective({**common, "best": {"rank": 22}})
        self.assertIn("3 above known record", above)
        self.assertIn("matches known record", match)
        self.assertIn("beats known record", beat)
        self.assertIn("1", beat)
        self.assertNotIn("+-", above + match + beat)

    def test_objective_does_not_call_an_unknown_baseline_a_record(self):
        status = {
            "record": 250,
            "configured_record": 250,
            "record_known": False,
            "best": {"rank": 249},
        }
        objective = flipfleet.format_objective(status)
        self.assertIn("beats baseline", objective)
        self.assertIn("1", objective)
        self.assertNotIn("record", objective.lower())

    def test_cpu_island_row_contains_search_identity_and_fits_width(self):
        walker = {
            "id": 3, "door": "near1", "zone": "balanced",
            "rank": 24, "current_rank": 25, "band": 3,
            "mv": 200_000_000, "rate_mps": 2_500_000.0,
            "progress_age": 7.0, "since_reseed": 11.0,
            "source": "near1/mixed-bank", "seed_rank": 24,
            "running": True, "process_state": "running",
        }
        row = flipfleet.format_cpu_island_row(walker, best_rank=23, width=72)
        self.assertLessEqual(len(row), 72)
        for token in ("w03", "near1", "balanced", "+1", "b3", "2.5M/s"):
            self.assertIn(token, row)

        compact = flipfleet.format_cpu_island_row(walker, best_rank=23, width=32)
        self.assertLessEqual(len(compact), 32)
        self.assertTrue(compact.strip())

    def test_cpu_island_row_tolerates_unstarted_legacy_walker(self):
        legacy = {
            "id": 1, "rank": "?", "mv": 0, "since_reseed": 0,
            "door": "leader", "zone": "balanced",
        }
        row = flipfleet.format_cpu_island_row(legacy, best_rank=23, width=24)
        self.assertLessEqual(len(row), 24)
        self.assertIn("w01", row)
        self.assertIn("?", row)


class DashboardSummaryTest(unittest.TestCase):
    def test_gpu_role_summary_shows_seed_exposure_reward_and_outcomes(self):
        status = {
            "gpu": {
                "enabled": True,
                "roles": {
                    "split": {
                        "lanes": 64,
                        "seed": {"rank": 94, "recipe": ["split", "break"]},
                        "lane_epochs": 256,
                        "reward": 32.0,
                        "candidates": 1234,
                        "pareto": 7,
                        "rank_drops": 2,
                        "density_improvements": 5,
                        "failures": 1,
                        "retry_at": 321.0,
                    },
                    "novelty": {
                        "lanes": 32,
                        "seed": {"rank": 93, "recipe": "archive"},
                        "lane_epochs": 64,
                        "reward": 16.0,
                        "candidates": 10,
                        "pareto": 4,
                        "rank_drops": 0,
                        "density_improvements": 1,
                    },
                },
            },
        }
        rows = flipfleet.summarize_gpu_roles(status)
        self.assertEqual(2, len(rows))
        self.assertTrue(rows[0].startswith("split 64l r94/split+break"))
        for token in ("cand 1.2K", "P7", "↓2", "d5", "R/le 0.12",
                      "fail 1", "retrying"):
            self.assertIn(token, rows[0])
        self.assertTrue(rows[1].startswith("novelty 32l r93/archive"))
        self.assertIn("R/le 0.25", rows[1])

    def test_gpu_role_summary_has_an_explicit_off_state(self):
        self.assertEqual(
            ["GPU off"],
            flipfleet.summarize_gpu_roles({
                "gpu": {"enabled": False, "roles": {"stale": {"lanes": 99}}},
            }))

    def test_diversity_summary_covers_every_search_archive(self):
        status = {
            "counters": {
                "archive": 42, "archive_capacity": 64,
                "archive_min_distance": 34,
                "archive_evictions": 5, "archive_rejections": 8,
            },
            "cpu": {
                "near": {
                    "tiers": {
                        "+1": {"size": 11, "capacity": 32,
                               "minimum_distance": 9},
                        "+2": {"size": 17, "capacity": 32,
                               "minimum_distance": 12},
                    },
                    "counters": {
                        "selections": 20, "successes": 3,
                        "signature_quota": 4, "novelty": 6,
                    },
                },
                "symmetry": {
                    "size": 24, "least_uses": 1, "most_uses": 7,
                    "ranks": [98, 100],
                },
            },
            "gpu": {
                "enabled": True,
                "pareto": {
                    "size": 13, "capacity": 32, "admissions": 19,
                    "rejections": 41, "evictions": 6,
                },
            },
        }
        lines = flipfleet.summarize_diversity(status)
        rendered = "\n".join(lines)
        for token in (
                "Frontier 42/64", "Δmin 34", "+1 11/32 Δ9",
                "+2 17/32 Δ12", "Near return 3/20",
                "struct reject 4", "novelty reject 6",
                "Symmetry 24 seeds", "uses 1–7", "ranks 98,100",
                "GPU Pareto 13/32", "admit 19", "reject 41", "evict 6"):
            self.assertIn(token, rendered)

    def test_diversity_summary_hides_stale_pareto_when_gpu_is_off(self):
        lines = flipfleet.summarize_diversity({
            "counters": {"archive": 1, "archive_capacity": 8},
            "gpu": {"enabled": False,
                    "pareto": {"size": 7, "capacity": 8}},
        })
        self.assertNotIn("Pareto", "\n".join(lines))

    def test_effectiveness_normalizes_cpu_by_moves_and_gpu_by_lane_epoch(self):
        status = {
            "cpu": {
                "cohorts": {
                    "leader/balanced": {
                        "launches": 2, "moves": 2_000_000_000,
                        "rank_drops": 2, "tie_improvements": 1,
                        "near_admissions": 1,
                    },
                    "near1/short": {
                        "launches": 4, "moves": 500_000_000,
                        "rank_drops": 0, "tie_improvements": 1,
                        "near_admissions": 1,
                    },
                },
            },
            "gpu": {
                "enabled": True,
                "roles": {
                    "rank": {"lane_epochs": 80, "reward": 20},
                    "density": {
                        "lane_epochs": 100, "reward": 1,
                        "reward_per_lane_epoch": 0.5,
                    },
                },
            },
        }
        lines = flipfleet.summarize_effectiveness(status)
        # near1 has fewer total outcomes but twice the exposure-normalized yield.
        self.assertTrue(lines[0].startswith("CPU near1/short 4.00 prod/B"))
        self.assertTrue(lines[1].startswith("CPU leader/balanced 2.00 prod/B"))
        self.assertIn("↓0 tie1 near1 · 500M mv", lines[0])
        gpu = next(line for line in lines if line.startswith("GPU reward/lane-epoch:"))
        self.assertIn("density 0.50", gpu)
        self.assertIn("rank 0.25", gpu)
        self.assertLess(gpu.index("density"), gpu.index("rank"))

    def test_timeline_uses_wall_time_and_places_lower_ranks_above(self):
        points = [
            {"t": 0, "rank": 26, "ops": 100},
            {"t": 10, "rank": 25, "ops": 95},
            {"t": 90, "rank": 24, "ops": 91},
            # A same-rank density improvement should remain visible.
            {"t": 95, "rank": 24, "ops": 88},
        ]
        lines = flipfleet.build_time_timeline(points, elapsed=100, width=50)
        self.assertEqual(4, len(lines))  # one row per rank plus the time axis
        self.assertTrue(lines[0].startswith("r24"))
        self.assertTrue(lines[1].startswith("r25"))
        self.assertTrue(lines[2].startswith("r26"))
        self.assertIn("◆", lines[0])
        self.assertTrue(lines[-1].rstrip().endswith("1m40s"))
        self.assertTrue(all(len(line) <= 50 for line in lines))

        x0 = lines[2].index("●")
        x10 = lines[1].index("●")
        x90 = lines[0].index("●")
        # Equal event-index gaps are deliberately unequal on screen: the
        # 80-second plateau consumes far more space than the first 10 seconds.
        self.assertGreater(x90 - x10, 4 * (x10 - x0))


if __name__ == "__main__":
    unittest.main()
