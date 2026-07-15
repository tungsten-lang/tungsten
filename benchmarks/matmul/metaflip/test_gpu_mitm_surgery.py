import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))

from gpu_mitm_surgery import (  # noqa: E402
    GpuMitmWorker,
    GpuMitmFleetAdapter,
    fingerprint_words,
    generate_worker_source,
    join_fingerprint,
    parse_worker_output,
    plan_lane_budget,
    split_fingerprint,
    table_capacity,
)
from mitm_surgery import tensor_xor  # noqa: E402


class GpuMitmSurgeryTest(unittest.TestCase):
    def test_table_capacity_keeps_at_most_half_load(self):
        for pool in (4, 17, 180, 700):
            capacity = table_capacity(pool)
            pairs = pool * (pool - 1) // 2
            self.assertEqual(0, capacity & (capacity - 1))
            self.assertGreaterEqual(capacity, pairs * 2)
            self.assertLess(capacity, pairs * 4)

    def test_lane_budget_is_strict_and_preserves_subset_diversity(self):
        for budget in (16, 100, 1024, 490_000, 2_000_000):
            plan = plan_lane_budget(budget, max_pool=700, target_subsets=4)
            self.assertLessEqual(plan.dispatched_threads, budget)
            self.assertEqual(plan.dispatched_threads,
                             plan.subsets * plan.pool * plan.pool)
            self.assertLessEqual(plan.pool, 700)
        plan = plan_lane_budget(1024)
        self.assertEqual(4, plan.subsets)
        self.assertEqual(16, plan.pool)

    def test_fingerprint_i64_roundtrip(self):
        values = [
            0, 1, (1 << 63) - 1, 1 << 63, (1 << 64) - 1,
            1 << 64, (1 << 127), (1 << 128) - 1,
        ]
        for value in values:
            self.assertEqual(value, join_fingerprint(*split_fingerprint(value)))

    def test_generator_specializes_all_supported_square_dimensions(self):
        for n in range(3, 8):
            source = generate_worker_source(n, 180, Path(f"/tmp/mitm-{n}.metal"))
            self.assertIn(f"DIM = {n}", source)
            self.assertIn("POOL_MAX = 180", source)
            self.assertIn("TABLE_CAP = 32768", source)
            self.assertIn(f'msl = read_file("/tmp/mitm-{n}.metal")', source)
            self.assertIn("@gpu fn mitm_enumerate_pairs", source)
            self.assertIn("@gpu fn mitm_probe_pairs", source)
            self.assertIn("## u32[]: fps0", source)

    def test_i32_words_preserve_all_fingerprint_bits(self):
        value = (1 << 127) | (1 << 96) | (1 << 63) | 17
        words = fingerprint_words(value)
        rebuilt = sum((word & 0xFFFFFFFF) << (32 * index)
                      for index, word in enumerate(words))
        self.assertEqual(value, rebuilt)

    def test_generated_tungsten_passes_frontend_check(self):
        with tempfile.TemporaryDirectory() as directory:
            source_path = Path(directory) / "worker.w"
            source_path.write_text(
                generate_worker_source(3, 32, Path(directory) / "worker.metal"),
                encoding="utf-8",
            )
            result = subprocess.run(
                [str(ROOT / "bin" / "tungsten"), "--check", str(source_path)],
                cwd=ROOT, capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_output_protocol(self):
        output = (
            "GPU_MITM_HIT 0 1 2 3\n"
            "GPU_MITM_RESULT dimension=5 candidates=6 pairs=15 table=32 "
            "enum_ms=1 table_ms=2 upload_ms=3 probe_ms=4 fingerprint_hits=1\n"
        )
        hits, metrics = parse_worker_output(output)
        self.assertEqual([(0, 1, 2, 3)], hits)
        self.assertEqual(6, metrics["candidates"])
        self.assertEqual(4, metrics["probe_ms"])

    def test_python_acceptance_gate_checks_complete_tensor(self):
        candidates = (
            (1, 1, 1), (2, 2, 2), (4, 4, 4), (8, 8, 8),
            (3, 1, 1), (1, 3, 1),
        )
        target = tensor_xor(candidates[:4], 4, 4, 4)
        protocol = (
            "GPU_MITM_HIT 0 1 2 3\n"
            "GPU_MITM_HIT 0 1 4 5\n"
            "GPU_MITM_RESULT dimension=3 candidates=6 pairs=15 table=32 "
            "enum_ms=1 table_ms=1 upload_ms=1 probe_ms=1 fingerprint_hits=2\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            worker = GpuMitmWorker(3, pool=16, workdir=directory)
            with mock.patch.object(worker, "build", return_value=worker.binary), \
                    mock.patch(
                        "gpu_mitm_surgery.subprocess.run",
                        return_value=SimpleNamespace(
                            returncode=0, stdout=protocol, stderr=""
                        ),
                    ):
                result = worker.search(target, candidates, 4, 4, 4)
        self.assertEqual(candidates[:4], result.replacement)
        self.assertEqual(2, result.fingerprint_hits)
        self.assertEqual(1, result.exact_hits)

    def test_fleet_adapter_launch_poll_and_exact_output_contract(self):
        class FakeProcess:
            def __init__(self):
                self.returncode = None

            def poll(self):
                return self.returncode

            def terminate(self):
                self.returncode = -15

            def wait(self, timeout=None):
                return self.returncode

            def kill(self):
                self.returncode = -9

        fake = FakeProcess()
        with tempfile.TemporaryDirectory() as directory:
            seed = Path(directory) / "seed.txt"
            output = Path(directory) / "hit.txt"
            seed.write_text("placeholder\n", encoding="utf-8")
            output.write_text("stale\n", encoding="utf-8")
            adapter = GpuMitmFleetAdapter(4, max_pool=64, workdir=directory)
            with mock.patch.object(adapter, "build", return_value=Path("worker")), \
                    mock.patch("gpu_mitm_surgery.subprocess.Popen",
                               return_value=fake) as popen:
                plan = adapter.launch(seed, output, 4096)
            self.assertFalse(output.exists())
            self.assertEqual(4, plan.subsets)
            command = popen.call_args.args[0]
            self.assertIn("--worker-pool", command)
            self.assertIn("64", command)
            adapter._log_stream.write(
                '{"hit": true, "rank": 46, "output": "hit.txt"}\n'
            )
            output.write_text("46\n", encoding="utf-8")
            fake.returncode = 0
            status = adapter.poll()
            self.assertFalse(status["running"])
            self.assertTrue(status["hit"])
            self.assertTrue(status["result"]["hit"])
            second = FakeProcess()
            with mock.patch.object(adapter, "build", return_value=Path("worker")), \
                    mock.patch("gpu_mitm_surgery.subprocess.Popen",
                               return_value=second) as second_popen:
                adapter.launch(seed, output, 4096)
            second_command = second_popen.call_args.args[0]
            offset_index = second_command.index("--subset-offset") + 1
            self.assertEqual(plan.subsets, int(second_command[offset_index]))
            adapter.terminate()


if __name__ == "__main__":
    unittest.main()
