# Python/NumPy bridge proof of concept

Python orchestrates; a compiled Tungsten kernel computes on native f64 storage.
The example evaluates `x*x + 2*x + 1` and returns an ndarray of the same shape.

```python
import numpy as np
from tungsten_numpy import Kernel

transform = Kernel("build/reports/numpy-kernel")
x = np.linspace(-3, 3, 1_000_000).reshape(1000, 1000)
y = transform(x)
print(y.shape, transform.last_run)
```

## Contract

- Native-endian, C-contiguous float64 ndarrays, including zero-dimensional
  arrays. Dtype conversion and layout copying are explicit caller choices.
- At most 2^31-1 elements; empty arrays return empty output without a worker.
- Python serializes the input once to a private temporary file. Tungsten maps
  it read-only, borrows an ordinary f64 array header through `bridge.c`, and
  computes into independent output storage. The mapping remains open until
  computation finishes; its view is never returned to Python.
- Python reads the output into owned NumPy storage before removing temporary
  files. Returned arrays survive worker exit and deletion of the inputs.
- Every call checks worker exit status, protocol acknowledgment, and exact
  output length. Subprocess arguments are passed without a shell; timeouts
  raise `KernelError` and terminate the worker.
- This is a process/file bridge with explicit copies, not an in-process
  extension or an end-to-end zero-copy API. The optional adapter is isolated
  from Core. The prototype was tested on little-endian macOS ARM64.

The adapter exists because `Mmap.as_f64` returns a BigArray, while a raw
`f64[]` kernel requires a WArray header. It checks the size bound and borrows
the same pages. It performs no array payload copy.

## Build and test

```sh
python3 -m venv build/venv-science
build/venv-science/bin/python -m pip install numpy==2.0.2
TUNGSTEN_C_INCLUDES=experiments/numpy-bridge/bridge.c \
  bin/tungsten-compiler compile experiments/numpy-bridge/kernel.w \
  --out build/reports/numpy-kernel --release --no-lto
build/venv-science/bin/python experiments/numpy-bridge/test_bridge.py
```

Tests exercise 1-D, N-D, scalar, empty, read-only input behavior, independent
result lifetime, invalid dtype/endianness/layout, NaN/infinities, and a malformed
worker. Six alternating matched pairs check one million elements against NumPy.

On the local M5 host, Python 3.9.6 / NumPy 2.0.2, median whole-call time was
8.612 ms through the bridge versus 1.001 ms in NumPy. `result.json` retains the
individual measurements, including input, worker, and output costs. These are
local diagnostic results. This cheap polynomial does not justify crossing the
process boundary for speed.

The next useful experiment is a substantial existing Tungsten solver or exact
arithmetic workload. A persistent worker can amortize process launch; an
in-process extension would additionally need a supported embedding ABI,
runtime/thread lifetime contract, Python exception translation, and explicit
buffer ownership. Those are separate implementation projects.

NumPy's [extension documentation](https://numpy.org/doc/stable/user/c-info.how-to-extend.html)
describes the in-process C API that a later extension could use.
