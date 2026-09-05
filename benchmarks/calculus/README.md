# Calculus scaling probes

`scaling.w` checks Differential addition and finite-budget oscillatory GK15
integration. `measure.py` alternates baseline/candidate order for 30 paired
runs after one warm-up, verifies deterministic equal checksums, and prints
raw process elapsed time, median and median absolute deviation (MAD).
These are local workload measurements, including process startup; they do not
measure end-to-end application performance or prove quadrature accuracy.

Compile the same `scaling.w` with the same compiler and flags against each
checkout's Core, using `TUNGSTEN_ROOT` and `BIT_HOME` to select it. Use explicit
output paths to preserve both binaries:

```sh
TUNGSTEN_ROOT=/absolute/baseline BIT_HOME=/absolute/baseline/bits \
  /absolute/compiler compile /absolute/scaling.w --no-lto --out /tmp/calculus-before
TUNGSTEN_ROOT=/absolute/candidate BIT_HOME=/absolute/candidate/bits \
  /absolute/compiler compile /absolute/scaling.w --no-lto --out /tmp/calculus-after
python3 benchmarks/calculus/measure.py /tmp/calculus-before /tmp/calculus-after
```

## Measurement on 2026-09-05

Host: Apple M5 Max, arm64, macOS 26.6.2. Baseline: `cdf7875f54f78425307cb1de3a96181c09e4a43a`.
Candidate: the pre-rebase calculus improvement snapshot; no fast-math flags. Compiler:
`/Users/erik/.codex/worktrees/ae39/tungsten/bin/tungsten-compiler`, SHA-256
`29bf18ef7ce24396ab34dd62ecff379b59d4acd5a931bc550c0124bbba32371a`.
Thermal/power state was not locked. Retain these as host-specific evidence.
These numbers compare historical snapshots, not incremental gains over current
main: main independently hoisted the Differential copies in `3d7e8208`.
The rebased integration preserves that existing optimization.

| Workload | Calls per process | Baseline median ± MAD (ms) | Candidate median ± MAD (ms) | Speedup |
|---|---:|---:|---:|---:|
| Differential addition, dimension 16 | 10 | 16.97 ± 0.15 | 3.36 ± 0.08 | 5.05× |
| Differential addition, dimension 32 | 10 | 205.49 ± 1.66 | 5.43 ± 0.24 | 37.86× |
| GK15, 64 panels | 4 | 40.19 ± 0.16 | 31.02 ± 0.10 | 1.30× |
| GK15, 256 panels | 4 | 301.80 ± 0.40 | 117.25 ± 0.26 | 2.57× |
| GK15, 512 panels | 4 | 1002.13 ± 3.39 | 235.19 ± 1.01 | 4.26× |

Raw data for these five cases are in `results-2026-09-05.jsonl`. The addition
checksum is 60; GK checksums also match bit-for-bit. An independent replay of
the old scan controller versus the new heap controller additionally matched
all sampled coordinates, final value, companion value, estimated error,
evaluation counts and status on oscillatory 64/256-panel and kink 32-panel
cases. These integrations stop at the interval budget; the timing is a
controller benchmark, not a convergence or accuracy claim.

Reproduce the trace comparison with
`ruby benchmarks/calculus/trace_parity.rb /absolute/compiler`; it reads the
pinned pre-heap controller from Git (`e7d019a7`, the rebased introduction)
and compiles a temporary replay against current Core.

Measured executables:

- baseline SHA-256: `7ab28b771db2d3eb7604acb5ae5692010152b4251176fb11d3acafb91ea2d6b6`
- candidate SHA-256: `a754b16386398b8d42b4bf5104f6900854a49b3c29af1a9d1bbce57ff66d7551`

The algebraic changes explain the scaling: addition copies the RHS gradient
and Hessian once (quadratic instead of quartic work); GK15 uses a stable
binary max-heap, compensated delta updates and geometric/full-final rebuilds.
All arithmetic checks and the conservative subnormal policy remain active.

## Regression validation

Run focused checks from the candidate checkout with a compiler compatible with
its Core/runtime snapshot:

```sh
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" /absolute/compiler \
  run spec/core/calculus_improvements_spec.w
TUNGSTEN_ROOT="$PWD" BIT_HOME="$PWD/bits" /absolute/compiler \
  compile spec/core/calculus_improvements_spec.w --no-lto --out /tmp/calculus-spec
/tmp/calculus-spec
ruby scripts/gen_core_doc.rb --check
```

The new regression suite covers rounded abscissae, quantization, bounded domain
retries, stale errors, overflow-safe tolerances, cached callback counts,
breakpoints, heap tie ordering, finite/status guards, numerical vector results,
AD shape/domain validation, JVP/VJP transpose and primitive cross-checks, and
optimizer failure propagation. It is registered in both interpreted and native
Core test manifests.

On the original pre-rebase checkout, focused numerical, improvements, autoload
and legacy calculus specs passed interpreted and native execution. The broader interpreted calculus
family (including complex, certified transcendentals, Laurent/Puiseux, radial
Mellin and expression calculus) also passes. This is not a root-green claim:
`rake` stops at the pre-existing missing `WUUIDBytes` runtime layout, and the
native complex suite still fails its unrelated `complex.to_s` assertion.
That checkout lacked its own compiler binary; the sibling compiler identified
above was used instead. Its numerical-spec build emits a nonfatal return-type
inference warning.

### Landing revalidation

Rebased onto current main, preserving its existing `Autodiff.grad`, damped
least-squares implementation, Differential copy optimization and Physics work.
The current compiler (`/Users/erik/tungsten/bin/tungsten-compiler`, SHA-256
`0705327ca4a22d3e05d5eaebebe20a1da1ab215231b34a8a35c0116b8159620d`)
passes all 71 new checks plus the numerical, autoload, legacy calculus, complex,
autodiff, optim and expression-calculus suites in interpreted and native modes.
The earlier native `complex.to_s` failure no longer reproduces. The exact
controller trace replay also passes with this compiler. Modern compiler
interpretation is selected explicitly with `--interpret run`.

The standard focused-slice wrapper stops before compilation on three existing
unclassified BigInt specs (`bigint_add3_equal_reopen_source_seam_spec`,
`bigint_add3_equal_source_c_differential_spec`, and
`bigint_add3_equal_source_spec`). The above checks were therefore run directly
through the compiler, including `compile-batch`, without changing those specs
or their classification. Generated Core documentation and shell syntax checks
pass. The full `rake` suite is left to CI per repository guidance.
