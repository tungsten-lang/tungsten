#!/usr/bin/env python3
"""Exercise the opt-in numeric-leaf prefix cache against ordinary lowering.

Artifacts and timing evidence are retained under build/reports/library-prefix.
Timing is a synthetic edit workload, not a whole-project speedup claim.
"""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/reports/library-prefix"
OUT.mkdir(parents=True, exist_ok=True)
source = OUT / "src"
source.mkdir(exist_ok=True)
cache = OUT / f"cache-{time.time_ns()}"
cache.mkdir()
compiler = Path(os.environ.get("TUNGSTEN", ROOT / "bin/tungsten-compiler"))
env = dict(os.environ, TUNGSTEN_ROOT=str(ROOT), BIT_HOME=str(ROOT / "bits"),
           TUNGSTEN_INCREMENTAL="0", TUNGSTEN_FUNCTION_EMIT_CACHE="0",
           TUNGSTEN_CACHE_DIR=str(cache), TUNGSTEN_LIBRARY_PREFIX_CACHE="1")
leaves = "\n".join(
    f"-> prefix_kernel_{i}(x) (i64) i64\n  (x * {i + 2} + {i + 1}) * x\n"
    for i in range(100))
(source / "leaves.w").write_text(leaves)
(source / "operation.w").write_text("-> prefix_operation(x)\n  prefix_kernel_0(x) + 1\n")
entry = source / "entry.w"
entry.write_text("use leaves\nuse operation\n\nTungsten.PROTECT_THE_CORE!\n"
                 "Tungsten.LOCK_THE_DOORS!\n\n<< prefix_operation(7)\n")


def compile_case(name, mode="1", link=False, prefix="1"):
    output = OUT / name
    run_env = dict(env, TUNGSTEN_LIBRARY_WIRE_CACHE=mode,
                   TUNGSTEN_LIBRARY_PREFIX_CACHE=prefix,
                   TUNGSTEN_LL_PATH=str(output.with_suffix(".ll")))
    args = [str(compiler), "compile", str(entry), "--out", str(output),
            "--release", "--native", "--fast", "--verbose"]
    args += ["--no-lto"] if link else ["--emit-ll"]
    started = time.perf_counter()
    result = subprocess.run(args, cwd=ROOT, env=run_env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    elapsed = time.perf_counter() - started
    output.with_suffix(".log").write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"{name} failed: {output.with_suffix('.log')}\n{result.stdout[-4000:]}")
    return result.stdout, elapsed


def identical(a, b):
    for ext in (".ll", ".sidemap"):
        assert (OUT / (a + ext)).read_bytes() == (OUT / (b + ext)).read_bytes(), (a, b, ext)


compile_case("prime")
store, _ = compile_case("store")
hit, _ = compile_case("hit")
assert re.search(r"library WIRE cache: hit .*100 functions, 1 files", hit), hit[-5000:]
compile_case("off", "0")
identical("store", "hit")
identical("off", "hit")

# Change a downstream source body without changing its signature or type facts.
(source / "operation.w").write_text("-> prefix_operation(x)\n  prefix_kernel_0(x) + 2\n")
edited, on_time = compile_case("edited-hit")
assert "library WIRE cache: hit " in edited, edited[-4000:]
_, off_time = compile_case("edited-off", "0")
identical("edited-hit", "edited-off")
compile_case("edited-run", link=True)
assert subprocess.check_output([str(OUT / "edited-run")], text=True).strip() == "107"

# Editing a cached helper invalidates it even when its type is unchanged.
(source / "leaves.w").write_text(leaves.replace("x * 2 + 1", "x * 3 + 1", 1))
invalidated, _ = compile_case("invalidated")
assert "library WIRE cache: miss " in invalidated, invalidated[-4000:]
compile_case("invalidated-off", "0")
identical("invalidated", "invalidated-off")

# Adding a forward dependency makes the first file ineligible for the shortcut.
(source / "leaves.w").write_text(leaves.replace("(x * 2 + 1) * x", "prefix_operation(x)", 1))
unsafe, _ = compile_case("dependent")
assert "100 functions, 1 files" not in unsafe
compile_case("dependent-off", "0")
identical("dependent", "dependent-off")

# Restore the leaf graph and compare successive edits with the existing whole
# library cache. Alternate order, use the same source and flags in each pair,
# link and execute both binaries, and preserve the actual result checksum.
(source / "leaves.w").write_text(leaves)
compile_case("bench-prime-prefix", link=True)
compile_case("bench-prime-whole", link=True, prefix="0")
pairs = []
for pair in range(6):
    offset = pair + 20
    (source / "operation.w").write_text(
        f"-> prefix_operation(x)\n  prefix_kernel_0(x) + {offset}\n")
    times = {}
    order = ("prefix", "whole") if pair % 2 == 0 else ("whole", "prefix")
    for label in order:
        name = f"bench-{pair}-{label}"
        log, wall = compile_case(name, link=True, prefix="1" if label == "prefix" else "0")
        assert ("library WIRE cache: hit " if label == "prefix" else "library WIRE cache: miss ") in log
        assert subprocess.check_output([str(OUT / name)], text=True).strip() == str(105 + offset)
        times[label] = wall
    identical(f"bench-{pair}-prefix", f"bench-{pair}-whole")
    pairs.append(times)

summary = {"checks": "passed", "fixture": "100 raw scalar polynomial helpers",
           "edited_cached_wall_seconds": on_time, "edited_uncached_wall_seconds": off_time,
           "linked_edit_pairs": pairs,
           "linked_prefix_median_seconds": statistics.median(p["prefix"] for p in pairs),
           "linked_whole_median_seconds": statistics.median(p["whole"] for p in pairs),
           "timing_status": "synthetic edit workload; not a whole-project speedup claim"}
(OUT / "result.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
