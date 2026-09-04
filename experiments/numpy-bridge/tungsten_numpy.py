"""Small, explicit Python -> compiled Tungsten ndarray bridge proof of concept.

There is one input serialization and one output read/allocation per call.
Tungsten maps the input without another full-array allocation. Returned arrays
own their memory; they never refer to deleted temporary files or dead workers.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import numpy as np


class KernelError(RuntimeError):
    pass


class Kernel:
    def __init__(self, executable, timeout=30):
        self.executable = Path(executable).resolve(strict=True)
        self.timeout = timeout
        self.last_run = None

    def __call__(self, values):
        if not isinstance(values, np.ndarray):
            raise TypeError("pass an ndarray; conversion must be explicit")
        if values.dtype != np.dtype("float64") or not values.dtype.isnative:
            raise TypeError("kernel requires native-endian float64")
        if not values.flags.c_contiguous:
            raise ValueError("kernel requires C-contiguous storage; use np.ascontiguousarray explicitly")
        if values.size > 2**31 - 1:
            raise ValueError("element count exceeds Tungsten's ordinary Array limit")
        if sys.byteorder != "little":
            raise RuntimeError("this proof of concept has only been validated on little-endian hosts")
        if values.size == 0:
            self.last_run = {"elements": 0, "input_bytes": 0, "output_bytes": 0,
                             "worker_started": False, "total_seconds": 0.0}
            return np.empty(values.shape, dtype=np.float64)
        started = time.perf_counter()
        with tempfile.TemporaryDirectory(prefix="tungsten-numpy-") as directory:
            input_path = Path(directory) / "input.f64"
            output_path = Path(directory) / "output.f64"
            values.tofile(input_path)
            transferred = time.perf_counter()
            try:
                result = subprocess.run([str(self.executable), str(input_path), str(output_path), str(values.size)],
                                        capture_output=True, text=True, timeout=self.timeout, check=False)
            except subprocess.TimeoutExpired as exc:
                raise KernelError("Tungsten worker exceeded its deadline") from exc
            completed = time.perf_counter()
            if result.returncode:
                raise KernelError(f"Tungsten worker exited {result.returncode}: {result.stderr.strip()}")
            if result.stdout.strip() != f"tungsten-numpy-v1 {values.size}":
                raise KernelError("worker did not acknowledge the expected protocol and element count")
            if not output_path.is_file() or output_path.stat().st_size != values.nbytes:
                raise KernelError("worker output has the wrong byte length")
            output = np.fromfile(output_path, dtype=np.float64).reshape(values.shape)
            finished = time.perf_counter()
        self.last_run = {"elements": int(values.size), "input_bytes": int(values.nbytes),
                         "output_bytes": int(output.nbytes), "worker_started": True,
                         "input_seconds": transferred - started,
                         "worker_seconds": completed - transferred,
                         "output_seconds": finished - completed,
                         "total_seconds": time.perf_counter() - started}
        return output
