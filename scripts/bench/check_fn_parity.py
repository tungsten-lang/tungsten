#!/usr/bin/env python3
"""Compare the Tungsten engine's per-layer hidden streams and logits against
the numpy reference for the parity fixture.

  python3 scripts/bench/flash_next_ref.py --tokens 1 --dump /tmp/fn_ref
  bin/tungsten run scripts/bench/qwen38fn_mlx.w baseline 1 5 "" /tmp/fn_eng
  python3 scripts/bench/check_fn_parity.py /tmp/fn_ref.npz /tmp/fn_eng
"""

import sys

import numpy as np

N_LAYERS, HC_HIDDEN, N_VOCAB = 48, 10240, 248320
LAST_POS = 4   # last prompt position of the 5-token fixture


def rel(a, b):
    return np.max(np.abs(a - b)) / (np.max(np.abs(a)) + 1e-9)


def main():
    ref_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fn_ref.npz"
    eng_prefix = sys.argv[2] if len(sys.argv) > 2 else "/tmp/fn_eng"
    ref = np.load(ref_path)
    h = np.fromfile(f"{eng_prefix}_h.f32", dtype=np.float32).reshape(N_LAYERS, HC_HIDDEN)
    logits = np.fromfile(f"{eng_prefix}_logits.f32", dtype=np.float32)

    worst = 0.0
    first_bad = None
    for li in range(N_LAYERS):
        r = ref[f"h_pos{LAST_POS}_layer{li}"]
        d = rel(r, h[li])
        worst = max(worst, d)
        flag = "" if d < 2e-3 else "  <-- DIVERGES"
        if d >= 2e-3 and first_bad is None:
            first_bad = li
        print(f"layer {li:2d}: rel {d:.2e}{flag}")
    rl = ref[f"logits_pos{LAST_POS}"]
    dl = rel(rl, logits)
    print(f"logits : rel {dl:.2e}  ref argmax {np.argmax(rl)}  eng argmax {np.argmax(logits)}")
    ok = dl < 2e-3 and np.argmax(rl) == np.argmax(logits)
    if first_bad is not None:
        print(f"first diverging layer: {first_bad}")
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()
