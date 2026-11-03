# Deadline frontier benchmark

Status: measured, uncommitted prototype on `codex/event-deadline-waits`.
Not an across-the-board no-regression result and not ready to land as such.

## Scope and method

Measured on 2026-09-05 UTC, Apple M5 Max, macOS 26.6.2 (25G83), Apple clang
21.0.0, `-O2`. Baseline runtime: `189ed930f8b21b59a51020d78efb8d7105799ba0`.
Main advanced to `43cf6497` during the experiment, but its runtime tree was
unchanged; the baseline binary was not replaced during measurement.

Both binaries compile the **same C harness** against their respective runtime
sources. The idle and ready cells drive actual native runtime goroutines,
socket parking, event polling, wakeup, and completion. This is a runtime
workload, not a compiled Tungsten application benchmark. Goroutine/pipe
creation is outside timing; registration and scheduler work are inside.

The final run uses six serial ABBA/BAAB blocks, rotating cell order, with
12 samples per lane per cell and an excluded warmup. Each child has a 20 s
alarm and the runner has a 25 s parent watchdog. No builds or other test jobs
were run concurrently with the timed cells. This was a local measurement,
not an exclusive-machine or thermally controlled campaign.

Raw samples, binary hashes, harness hash and runner hash:
[`event_deadlines_abba.json`](../../benchmarks/runtime/event_deadlines_abba.json).
All reported numbers below are medians. Lateness is the median of each
batch's within-batch p99, **not** a statistically established service-level
p99; for a single waiter it is simply that waiter's lateness.

## Retained experiment: heap and precise deadline clamp

The candidate replaces cooperative socket deadline list scans with an indexed
per-event-loop heap, adds sticky cross-thread wakeups, and clamps kqueue's
final deadline wait at nanosecond precision. Batch mode retains its existing
64 hot polls followed by 1 ms polling. M:P retains the legacy cross-worker
expiry list. Core Timer, channels/select and mutex waiting are unchanged.

Each idle cell parks its waiters until one common deadline 200 ms away.

| Pending waits | Baseline CPU | Candidate CPU | CPU change | Baseline lateness | Candidate lateness |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.569 ms | 0.581 ms | +2.1% | 764 us | 46 us |
| 100 | 1.040 ms | 0.855 ms | -17.8% | 999 us | 131 us |
| 1,000 | 4.062 ms | 2.936 ms | -27.7% | 1,404 us | 790 us |

Ready cells perform 32 park/read/re-arm rounds per goroutine on prefilled
pipes. The timed variant exercises eager cancellation and deadline re-arm;
the untimed variant is a control for general scheduler/event-loop overhead.

| Ready workload | Baseline wall time | Candidate wall time | Change |
| --- | ---: | ---: | ---: |
| 1 waiter, deadline | 0.046 ms | 0.048 ms | +3.1% |
| 100 waiters, deadline | 1.971 ms | 2.014 ms | +2.2% |
| 1,000 waiters, deadline | 20.842 ms | 20.202 ms | -3.1% |
| 1 waiter, no deadline | 0.047 ms | 0.050 ms | +5.4% |
| 1,000 waiters, no deadline | 19.217 ms | 19.212 ms | -0.02% |

The smallest cells are short and noisy, but their regressions are not grounds
for a no-regression claim. They need a longer steady-state workload and
profiling before promotion. Single-wait idle CPU also did not improve.

The separate frontier microbenchmark performs 10,000 nearest-deadline and
expiry probes with no deadlines due. At 10,000 pending records it falls from
405.018 ms to 0.238 ms. This demonstrates removal of the list-scan scaling
cost; it is **not** an application-level speedup of that magnitude.

## Rejected experiment: remove the batch-mode polling

An intermediate binary let the otherwise idle cooperative scheduler block
until its next deadline, using the new wakeup source for an earlier arrival.
It also used the nanosecond kqueue clamp. Three ABBA/BAAB blocks, six samples
per lane per cell, produced:

| Pending waits | Baseline CPU | Blocking CPU | Baseline lateness | Blocking lateness |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.693 ms | 0.093 ms | 691 us | 1,013 us |
| 100 | 1.196 ms | 0.417 ms | 1,005 us | 1,152 us |
| 1,000 | 5.672 ms | 2.858 ms | 1,785 us | 2,223 us |

Raw data: [`event_deadlines_blocking_ns_abba.json`](../../benchmarks/runtime/event_deadlines_blocking_ns_abba.json).
This was an intermediate build, before restoring the M:P compatibility path;
the measured cells exercise only the cooperative scheduler. Its binary hash
and raw data are preserved, but the blocking policy is no longer in source.

The CPU saving is real in this corpus, but latency worsens. Nanosecond
precision reduced the regression seen with a millisecond-rounded timeout;
it did not eliminate it. This tradeoff is not retained as the default.
The recorded rusage context-switch counts are **not syscall counts**.

## Validation and remaining gates

- Deadline frontier randomized insert/update/cancel/pop oracle, equal-deadline
  preservation, eager detach/reuse, cross-thread wake, earlier-leader changes,
  wake-before-poll, timeout clamp and small output-buffer tests: passed with
  AddressSanitizer and UndefinedBehaviorSanitizer (over 142,000 checks).
  Leak detection was disabled; this is not a leak-free-runtime claim.
- Existing event-loop checks: 25/25; goroutine/channel checks: 19/19.
- Final epoll source cross-compiled for aarch64 Linux with Zig.
- No Linux execution or io_uring build was available on this host. Those
  backend gates, M:P workload measurements, and a compiled Tungsten application
  check remain before landing. The full rake suite was not run, per AGENTS.md.

Next: resolve or establish neutrality for the small ready-I/O cells; validate
Linux backends; design safe M:P expiry ownership and park-commit/generation
tokens before moving M:P deadlines. Timer thread identity/TLS compatibility
must be resolved separately before changing Timer callback dispatch.

## Reproduce

From the candidate checkout (outputs go into a fresh temporary directory):

```sh
deadline_bench_dir=$(mktemp -d /tmp/tungsten-deadlines.XXXXXX)
git worktree add --detach "$deadline_bench_dir/baseline-tree" 189ed930f8b21b59a51020d78efb8d7105799ba0
make -C runtime bench-event-deadlines-build \
  DEADLINE_RUNTIME_DIR="$deadline_bench_dir/baseline-tree/runtime" \
  DEADLINE_BENCH_OUT="$deadline_bench_dir/baseline"
make -C runtime bench-event-deadlines-build \
  DEADLINE_BENCH_OUT="$deadline_bench_dir/candidate"
ruby scripts/bench/event_deadlines.rb \
  "$deadline_bench_dir/baseline" "$deadline_bench_dir/candidate" \
  "$deadline_bench_dir/results.json" 6

make -C runtime tests/test_event_deadlines tests/test_event_loop tests/test_goroutines
runtime/tests/test_event_deadlines
runtime/tests/test_event_loop
runtime/tests/test_goroutines
```
