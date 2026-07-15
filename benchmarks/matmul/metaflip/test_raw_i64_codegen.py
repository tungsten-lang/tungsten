import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
ZOO = os.path.abspath(os.path.join(HERE, "..", "zoo"))
for directory in (HERE, ZOO):
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bucket_gen import gen as bucket_gen, gen_worker  # noqa: E402
from gpu_cal2zone_gen import gen as gpu_cal2zone_gen  # noqa: E402


class RawI64CodegenTest(unittest.TestCase):
    def test_cal2zone_7x7_uses_chunked_parse_and_typed_buffer_views(self):
        source, shared = gpu_cal2zone_gen(
            7, 7, 7, cap=375, wpg=2, seedcap=375,
            metal_ll_path="/tmp/cal2zone_7.ll", nw=64, steps=10, rounds=1,
        )
        self.assertEqual(18_000, shared)
        for prefix, axis in (("u", "u"), ("v", "v"), ("w", "w")):
            self.assertIn(f"{prefix}text = parts", source)
            self.assertIn(f"{prefix}mask = {prefix}hi * 10000000 + {prefix}lo",
                          source)
            self.assertIn(f"base{axis}[ti2] = {prefix}mask", source)
            self.assertIn(
                f"seed_{axis}s_view[soff + ii] = seed{axis}[soff + ii]", source)
            self.assertIn(
                f"best_{axis}s_view[bestthread * CAP + di]", source)
        self.assertNotIn("baseu[ti2] = parts[0].to_i()", source)
        self.assertIn(
            "seed_us_view = metal_buffer_view(seed_us, 66, "
            "375 * ESCAPE_SEEDS) ## i64[]", source)
        self.assertIn(
            "best_us_view = metal_buffer_view(best_us, 66, NW * CAP) ## i64[]",
            source)
        self.assertIn("cus[t] = bufu[baseoff + t]", source)
        self.assertIn("cvs[t] = bufv[baseoff + t]", source)
        self.assertIn("cws[t] = bufw[baseoff + t]", source)
        self.assertNotIn("metal_buffer_read_i64(bufw, baseoff + t)", source)
        self.assertIn("while ai < ab", source)
        self.assertIn("while bi < bb", source)
        self.assertIn("while ci < cb", source)
        self.assertNotIn("while trial < 40", source)
        self.assertIn("vok = verify_buf(best_us_view, best_vs_view, best_ws_view",
                      source)

    def test_cal2zone_6x6_source_keeps_existing_host_access_path(self):
        source, _ = gpu_cal2zone_gen(
            6, 6, 6, cap=185, wpg=4, seedcap=185,
            metal_ll_path="/tmp/cal2zone_6.ll", nw=64, steps=10, rounds=1,
        )
        self.assertIn("baseu[ti2] = parts[field_base].to_i()", source)
        self.assertIn('first_parts[0] == "R"', source)
        self.assertIn("metal_buffer_write_i64(seed_us", source)
        self.assertIn("metal_buffer_read_i64(bufw, baseoff + t)", source)
        self.assertNotIn("seed_us_view = metal_buffer_view", source)

    def test_bucket_7x7_runtime_seed_uses_chunked_raw_locals(self):
        source = bucket_gen(7, 7, 7, 342, runtime_seed=True)
        for name, field in (("rsu", 0), ("rsv", 1), ("rsw", 2)):
            self.assertIn(f"{name}text = rsp[{field}]", source)
            self.assertIn(f"{name}mask = {name}hi * 10000000 + {name}lo", source)
            self.assertIn(f"{name} = {name}mask ## i64", source)
        self.assertNotIn("rsu = rsp[0].to_i() ## i64", source)
        self.assertIn("rank = ins_term(st, rsu, rsv, rsw, rank)", source)

    def test_bucket_worker_7x7_load_scheme_uses_chunked_raw_locals(self):
        source = gen_worker(7, 7, 7, 342)
        for name, field in (("lsu", 0), ("lsv", 1), ("lsw", 2)):
            self.assertIn(f"{name}text = parts[{field}]", source)
            self.assertIn(f"{name}mask = {name}hi * 10000000 + {name}lo", source)
        self.assertIn("rank = ins_term(st, lsu, lsv, lsw, rank)", source)
        self.assertNotIn("rank = ins_term(st, parts[0].to_i()", source)

    def test_bucket_6x6_generated_sources_remain_on_existing_parse_path(self):
        standalone = bucket_gen(6, 6, 6, 215, runtime_seed=True)
        worker = gen_worker(6, 6, 6, 215)
        self.assertIn("rsu = rsp[0].to_i() ## i64", standalone)
        self.assertNotIn("rsutext = rsp[0]", standalone)
        self.assertIn(
            "rank = ins_term(st, parts[0].to_i(), parts[1].to_i(), "
            "parts[2].to_i(), rank)", worker)
        self.assertNotIn("lsutext = parts[0]", worker)


if __name__ == "__main__":
    unittest.main()
