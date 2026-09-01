# Perf30 dense / Tensor / LinAlg campaign

Baseline revision: `43642a9de2dca0ab455cef7e49deb69b70d86066`

Branch: `codex/perf30-dense`

Host: Apple Silicon macOS; release builds; wall-clock samples are matched within each item.

This journal is append-only by campaign item. Each retained change has a focused correctness oracle, alternating or multi-sample timings, and its own commit. Millisecond-resolution results are reported as directional when the measured interval is too short for a reliable ratio.

## Item 9 — CPU Tensor result allocation

Source finding: CPU-capable `scale`, unary, axis-reduction, and softmax methods allocated with the three-argument Metal constructor. A CPU receiver therefore passed `:cpu` where an MTLDevice was required.

Oracle and command:

```sh
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" \
  /Users/erik/tungsten/bin/tungsten-compiler compile \
  benchmarks/linalg/tungsten/dense_tensor_campaign.w \
  --out /tmp/perf30_dense --release
/tmp/perf30_dense cpu-ops
```

- Baseline `43642a9d`: fails immediately with `Metal.buffer_new: first arg must be a Metal device`.
- Candidate: `CPU_OPS_OK`; five process timings were at or below the shell timer's 10 ms resolution after one 50 ms cold launch.
- Focused regression `spec/core/tensor_cpu_ops_spec.w`: 10/10 checks pass.
- Existing `spec/sci/tensor_cpu_spec.w`: `TENSOR_CPU_OK`.

Retained as a correctness fix. It changes result construction to the existing backend-aware `Tensor.zeros_like` path; no performance ratio is claimed because the baseline operation cannot complete.
