#!/usr/bin/env python3
"""Numpy twin of test_fn_moe_gather.w — compares the Metal gather matvec
output against a direct dequant-and-matmul from the checkpoint."""

import numpy as np

from flash_next_ckpt import Experts

HIDDEN, MOE_FFN, LAYER = 2560, 640, 0
test_experts = [0, 1, 2, 10, 100, 127, 128, 300, 500, 511]

x = ((np.arange(HIDDEN, dtype=np.int64) * 1103515245 + 12345) % 1000 - 500)
x = (x / 500.0).astype(np.float32)

got = np.fromfile("/tmp/fn_moe_gather_y.f32", dtype=np.float32).reshape(len(test_experts), MOE_FFN)
ex = Experts()
worst = 0.0
for i, e in enumerate(test_experts):
    ref = ex.weight(LAYER, e, "gate_proj") @ x
    d = np.max(np.abs(ref - got[i]))
    rel = d / (np.max(np.abs(ref)) + 1e-9)
    worst = max(worst, rel)
    print(f"expert {e:3d}: max abs diff {d:.6f}  rel {rel:.2e}"
          f"  ref[0]={ref[0]:.6f} got[0]={got[i][0]:.6f}")
print("PASS" if worst < 1e-3 else "FAIL", f"worst rel {worst:.2e}")
