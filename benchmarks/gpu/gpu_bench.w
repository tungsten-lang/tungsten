# Reproducible baseline used by `bin/tungsten gpu-bench`.
#
# The host prepares zero-copy f32 arrays, compiles the sibling MSL emitted from
# this source, verifies the result, and records both synchronous round-trip
# latency and one-command-buffer batched throughput. The command wrapper owns
# configuration and supplies provenance through TUNGSTEN_GPU_BENCH_*.

use core/metal
use core/json

## f32[]: x
## f32[]: y
## i32: n
@gpu fn gpu_bench_saxpy(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    y[i] = 1.0001 * x[i] + 0.5

-> positive_env(name, fallback)
  raw = env(name)
  if raw == nil || raw == ""
    return fallback
  value = raw.to_i
  if value <= 0
    raise name + " must be positive"
  value

-> nonnegative_env(name, fallback)
  raw = env(name)
  if raw == nil || raw == ""
    return fallback
  value = raw.to_i
  if value < 0
    raise name + " must be non-negative"
  value

-> absolute(value)
  if value < 0.0
    return 0.0 - value
  value

n = positive_env("TUNGSTEN_GPU_BENCH_ELEMENTS", 1048576)
runs = positive_env("TUNGSTEN_GPU_BENCH_RUNS", 50)
warmup = nonnegative_env("TUNGSTEN_GPU_BENCH_WARMUP", 5)
strict = env("TUNGSTEN_GPU_BENCH_STRICT") == "1"
metal_path = env("TUNGSTEN_GPU_BENCH_METAL")
result_path = env("TUNGSTEN_GPU_BENCH_RESULT")
if metal_path == nil || result_path == nil
  raise "run this benchmark through bin/tungsten gpu-bench"

t0 = clock()
device = metal_device()
device_seconds = clock() - t0

source = read_file(metal_path)
t0 = clock()
library = metal_compile_source(device, source, strict)
source_compile_seconds = clock() - t0

t0 = clock()
pipeline = metal_pipeline(library, "gpu_bench_saxpy")
queue = metal_queue(device)
pipeline_seconds = clock() - t0

x = metal_array(-32, n)
y = metal_array(-32, n)
i = 0 ## i64
while i < n
  x[i] = (i + ~0.0) * ~0.000001
  i += 1

xb = metal_buffer_for(device, x)
yb = metal_buffer_for(device, y)
nb = metal_buffer(device, 4)
metal_buffer_write_i32(nb, 0, n)
bufs = [xb, yb, nb]

k = 0
while k < warmup
  metal_dispatch_n(queue, pipeline, bufs, n)
  k += 1

t0 = clock()
k = 0
while k < runs
  metal_dispatch_n(queue, pipeline, bufs, n)
  k += 1
sync_seconds = clock() - t0

t0 = clock()
metal_batch_begin(queue)
k = 0
while k < runs
  metal_dispatch_n(queue, pipeline, bufs, n)
  k += 1
metal_batch_commit(queue)
batch_seconds = clock() - t0

first = y[0]
last = y[n - 1]
expected_first = ~0.5
expected_last = ~1.0001 * ((n - 1 + ~0.0) * ~0.000001) + ~0.5
max_error = absolute(first - expected_first)
last_error = absolute(last - expected_last)
if last_error > max_error
  max_error = last_error
verified = max_error < ~0.001

bytes_total = (n + ~0.0) * ~8.0 * (runs + ~0.0)
sync_avg_ms = sync_seconds * ~1000.0 / (runs + ~0.0)
batch_avg_ms = batch_seconds * ~1000.0 / (runs + ~0.0)
sync_gbps = bytes_total / sync_seconds / ~1000000000.0
batch_gbps = bytes_total / batch_seconds / ~1000000000.0

result = {
  "schema": "tungsten-gpu-bench-v1",
  "timestamp_utc": env("TUNGSTEN_GPU_BENCH_TIMESTAMP"),
  "backend": "metal",
  "kernel": "gpu_bench_saxpy",
  "elements": n,
  "runs": runs,
  "warmup_runs": warmup,
  "strict_math": strict,
  "timing": {
    "device_create_ms": device_seconds * ~1000.0,
    "source_compile_ms": source_compile_seconds * ~1000.0,
    "pipeline_create_ms": pipeline_seconds * ~1000.0,
    "sync_total_seconds": sync_seconds,
    "sync_avg_ms": sync_avg_ms,
    "batch_total_seconds": batch_seconds,
    "batch_avg_ms": batch_avg_ms
  },
  "throughput": {
    "bytes_per_dispatch": n * 8,
    "sync_gb_per_second": sync_gbps,
    "batch_gb_per_second": batch_gbps
  },
  "verification": {
    "passed": verified,
    "first": first,
    "last": last,
    "max_error": max_error
  },
  "device": env("TUNGSTEN_GPU_BENCH_DEVICE"),
  "host": env("TUNGSTEN_GPU_BENCH_HOST"),
  "toolchain": env("TUNGSTEN_GPU_BENCH_TOOLCHAIN"),
  "compiler_version": env("TUNGSTEN_GPU_BENCH_COMPILER_VERSION"),
  "git_commit": env("TUNGSTEN_GPU_BENCH_GIT_COMMIT"),
  "git_dirty": env("TUNGSTEN_GPU_BENCH_GIT_DIRTY") == "true",
  "source_sha256": env("TUNGSTEN_GPU_BENCH_SOURCE_SHA256"),
  "sidecar_sha256": env("TUNGSTEN_GPU_BENCH_SIDECAR_SHA256"),
  "compiler_sha256": env("TUNGSTEN_GPU_BENCH_COMPILER_SHA256"),
  "binary": env("TUNGSTEN_GPU_BENCH_BINARY")
}

encoded = JSON.encode(result)
if !write_file(result_path, encoded + "\n")
  raise "could not write GPU benchmark result to " + result_path
<< encoded
if !verified
  exit(1)
