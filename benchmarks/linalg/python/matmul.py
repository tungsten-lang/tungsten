#!/usr/bin/env python3
"""Numpy matmul benchmark. On macOS this uses vecLib (Accelerate);
elsewhere typically OpenBLAS or MKL."""

import argparse
import json
import time
import numpy as np

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--N", type=int, default=256)
    p.add_argument("--K", type=int, default=100)
    args = p.parse_args()

    N, K = args.N, args.K

    rng = np.arange(N * N, dtype=np.float32)
    A = ((rng * 31 + 7) % 17).astype(np.float32) / 17.0
    B = ((rng * 13 + 3) % 19).astype(np.float32) / 19.0
    A = A.reshape(N, N)
    B = B.reshape(N, N)

    # Warm up.
    C = A @ B

    times: list[float] = []
    for _ in range(K):
        t0 = time.perf_counter()
        C = A @ B
        times.append((time.perf_counter() - t0) * 1000.0)
    times.sort()
    median_ms = times[K // 2]
    gflops = (2.0 * N * N * N) / (median_ms * 1e6)

    # Anti-DCE.
    _ = float(C[0, 0])

    print(json.dumps({
        "impl": "python-numpy",
        "N": N,
        "K": K,
        "median_ms": round(median_ms, 4),
        "gflops": round(gflops, 2),
        "blas": np.show_config_used() if hasattr(np, "show_config_used") else "unknown",
    }))

if __name__ == "__main__":
    main()
