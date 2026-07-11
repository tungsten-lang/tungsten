#!/usr/bin/env python3
"""Python / NumPy / Numba / JAX baselines for fusion chain y=sin(a*x+b)+c."""
import time
import math
import numpy as np

n = 200_000
a, b, c = 2.0, 0.5, 0.1
x = np.arange(n, dtype=np.float64) * 1e-5


def py_loop():
    return [math.sin(a * float(xi) + b) + c for xi in x]


def numpy_ufunc():
    return np.sin(a * x + b) + c


# warmup + time helper
def bench(name, fn, iters=10):
    fn()
    t0 = time.perf_counter()
    y = None
    for _ in range(iters):
        y = fn()
    t1 = time.perf_counter()
    s = float(np.sum(y)) if not isinstance(y, list) else sum(y)
    print(f"{name} n={n} avg_ms={(t1 - t0) * 1000 / iters:.4f} sum={s:.6f}")


bench("python_loop", py_loop, iters=3)
bench("numpy_ufunc", numpy_ufunc, iters=50)

try:
    from numba import njit

    @njit
    def numba_chain(x, a, b, c):
        out = np.empty_like(x)
        for i in range(x.shape[0]):
            out[i] = math.sin(a * x[i] + b) + c
        return out

    numba_chain(x, a, b, c)  # compile
    bench("numba_njit", lambda: numba_chain(x, a, b, c), iters=50)
except Exception as e:
    print(f"numba skipped: {e}")

try:
    import jax
    import jax.numpy as jnp

    # JAX defaults to float32 — without this the jax_jit line is computing
    # a different (32-bit) problem than every other row.
    jax.config.update("jax_enable_x64", True)

    jx = jnp.asarray(x)

    @jax.jit
    def jax_chain(x):
        return jnp.sin(a * x + b) + c

    jax_chain(jx).block_until_ready()
    def run():
        return jax_chain(jx).block_until_ready()

    bench("jax_jit", run, iters=50)
except Exception as e:
    print(f"jax skipped: {e}")
