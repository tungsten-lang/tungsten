#!/usr/bin/env python3
import gc
import json
from pathlib import Path
import statistics
import sys
import tempfile
import time
import numpy as np
from tungsten_numpy import Kernel, KernelError

ROOT = Path(__file__).resolve().parents[2]
kernel = Kernel(sys.argv[1] if len(sys.argv) > 1 else ROOT / "build/reports/numpy-kernel")
for shape in ((1,), (31,), (3, 7), (2, 3, 5), (0,), (2, 0), ()):
    values = np.asarray(np.arange(np.prod(shape), dtype=np.float64).reshape(shape) / 7)
    before = values.copy()
    output = kernel(values)
    np.testing.assert_allclose(output, values * values + 2 * values + 1, rtol=1e-14)
    np.testing.assert_array_equal(values, before)
    assert output.shape == values.shape
    assert not np.shares_memory(values, output)
    del values
    gc.collect()
    assert output.shape == shape  # no temporary-file/worker-backed result

for value, error in ((np.ones(3, dtype=np.float32), TypeError),
                     (np.ones(3, dtype=">f8"), TypeError),
                     (np.arange(8, dtype=np.float64)[::2], ValueError),
                     ([1.0], TypeError)):
    try:
        kernel(value)
    except error:
        pass
    else:
        raise AssertionError("invalid buffer was silently converted")

special = np.array([np.nan, np.inf, -np.inf, -0.0, 1e-300, 1e150])
with np.errstate(invalid="ignore", over="ignore"):
    np.testing.assert_allclose(kernel(special), special * special + 2 * special + 1, equal_nan=True)

with tempfile.TemporaryDirectory() as directory:
    broken = Path(directory) / "broken"
    broken.write_text("#!/bin/sh\necho wrong-protocol\n")
    broken.chmod(0o700)
    try:
        Kernel(broken)(np.ones(2))
    except KernelError:
        pass
    else:
        raise AssertionError("malformed worker response was accepted")

values = np.linspace(-3, 3, 1_000_000)
kernel(values)  # warm executable launch and filesystem paths
pairs = []
for pair in range(6):
    times = {}
    for mode in (("tungsten", "numpy") if pair % 2 == 0 else ("numpy", "tungsten")):
        started = time.perf_counter()
        if mode == "tungsten":
            actual = kernel(values)
            times["transfer"] = kernel.last_run
        else:
            expected = values * values + 2 * values + 1
        times[mode] = time.perf_counter() - started
    np.testing.assert_allclose(actual, expected, rtol=1e-14, atol=1e-14)
    pairs.append(times)
summary = {"checks": "passed", "numpy": np.__version__, "python": sys.version,
           "elements": len(values), "pairs": pairs,
           "tungsten_median_seconds": statistics.median(p["tungsten"] for p in pairs),
           "numpy_median_seconds": statistics.median(p["numpy"] for p in pairs),
           "scope": "whole-call cost, including process launch and file transfers; not kernel-only timing"}
path = ROOT / "build/reports/numpy-bridge.json"
path.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps({k: v for k, v in summary.items() if k != "pairs"}, indent=2))
