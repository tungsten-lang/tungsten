# Scheduler ownership / evented-idle validation

Measured candidate: worktree changes on `codex/scheduler-fifo-park`, based on
`22a2da361efae0d879e0c2c7ba41d4ec67f16737`.
Baseline: main at the same commit. Measurements were taken before integration;
unrelated work in the main checkout was excluded and left untouched.
Implementation and remaining work: [design](../../doc/design/scheduler-ownership.md).

The user approved landing this correctness/evented-idle tranche with the
limitations recorded below: noisy-host timings, a 2–5% forced-ready-park cost,
and Linux execution validation still outstanding. Landing is not a claim that
all scheduler polling has been removed or that every workload is faster.

## Validation

Focused native C checks passed:

| Target | Result |
| --- | --- |
| `test-scheduler-fifo-park` | 602,081 checks: FIFO, 100k last-item races, concurrent ring reuse, park/wake transitions, eager deadline unlink, global fairness, MP deadline churn |
| `test-scheduler-sync-migration` | 3,210 checks: controlled mutex/channel migration and native receiver cancellation cleanup |
| `test-scheduler-evented-idle` | 40 checks: no completion poll, exactly one blocking deadline/readiness wait; no timing thresholds |
| `test-event-deadlines` | Over 160k checks: heap oracle, equal keys, update/cancel/reuse, sticky wake before/during poll, earlier-frontier notification, small output capacity |
| `test-goroutines` | 19/19 |
| `test-event-loop` | 25/25, including two independent scheduler threads with socket deadlines |

`test_scheduler_fifo_park --queues-only` passed 601,591 checks under both
ThreadSanitizer and AddressSanitizer/UndefinedBehaviorSanitizer. The raw
event-deadline test also passed under both sanitizer builds. Sanitizer runs
exclude custom-stack goroutine execution; they are not a claim that arbitrary
migrating stacks or the whole runtime are sanitizer-clean.

Native compiled Tungsten specs passed: `channel_unbuffered_spec`,
`channel_timeout_spec`, `mutex_spec`, and `mutex_thread_spec`. They were run with
the candidate runtime through `scripts/test-specs.sh --job-compiled SPEC`.
The aggregate `--compiled-slice` entry was blocked by unrelated unclassified
tracked bignum specs; its single-job worker entry bypassed that discovery gate
without changing classifications. Full `rake` was not run, per AGENTS.md.

Candidate public MP stress completed exactly 1,048,576 iterations with checksum
8,623,489,024 at each of 1, 4 and 8 workers. This was a correctness check, not a
matched MP performance claim. Quiescent stop/restart is covered; arbitrary
shutdown with live waiters is not.

Execution validation is on macOS ARM64. Linux epoll/io_uring changes received
source review but have not been built or executed on Linux in this task.
`git diff --check` passed.

## Provisional matched measurements

Apple M5 Max, ARM64. Same public-API C harness and runtime build flags, warmup
then five ABBA blocks (10 timed samples per lane), fresh processes, per-cell
timeouts, and exact counts/checksums throughout. Source and executable hashes
were checked against the final build log before measurement.

**The machine was not quiet:** unrelated CPU-heavy Python and flip-search jobs
were active. These numbers are directional, not a clean promotion gate or a
no-regression guarantee. None of those jobs was interrupted. No builds or
other benchmarks from this task ran during the timed phases.

Times below are total timed run divided by iteration count. They include lazy
event-loop initialization and terminal scheduler return, not just yield cost.
The ratio is the median candidate/baseline ratio within each ABBA block; it is
not necessarily the ratio of the two lane medians.

| Cell | Baseline ns/iteration | Candidate ns/iteration | Paired ratio |
| --- | ---: | ---: | ---: |
| coop, 1 task × 1M | 17.762 | 16.873 | 0.934 |
| coop, 64 × 16,384 | 18.178 | 17.101 | 0.955 |
| four independent workers, 128 × 8,192 total | 11.046 | 6.924 | 0.640 |
| ready read, 64 × 1,024 | 297.981 | 306.496 | 1.009 |
| forced ready park, 64 × 128 | 841.431 | 880.066 | 1.047 |
| 1 ms deadline, 64 × 32 | 21,526.855 | 18,359.375 | 0.800 |
| coop, 1 task × 10M | 19.215 | 18.128 | 0.939 |
| forced ready park, 64 × 4,096 | 756.075 | 775.200 | 1.020 |
| forced ready park, 256 × 1,024 | 774.460 | 811.584 | 1.047 |
| 1 ms deadline, 1 task × 32 | 1,946,500 | 1,134,578 | 0.581 |

The tiny `coop:1:1:1` fixed-cost control had median total wall times of 29 us
baseline and 9.5 us candidate, but it is particularly exposed to host noise.
The long one-task control is the relevant throughput check. The old terminal
event poll is normally nonblocking; its removal is **not** a 1 ms batch saving.

Waiting CPU time provides the clearest directional benefit:

| Quiet deadline workload | Baseline CPU ms/run | Candidate CPU ms/run | Reduction |
| --- | ---: | ---: | ---: |
| 64 tasks × 32 waits | 6.3755 | 2.6290 | 58.8% |
| 1 task × 32 waits | 2.9715 | 0.2185 | 92.6% |

Forced timed parking of already-readable sockets remains 2–5% slower in these
samples. That path includes the stronger publication/lifetime protocol and
heap cancellation. It is deliberately different from normal read-before-park
I/O, which screens approximately flat. Do not hide this cost behind the large
idle-wait or sharded numbers, and do not attribute the whole observed difference
to a particular instruction without a controlled follow-up.

## Reproduction and artifacts

Commands and cell descriptions are in [README](README.md). Final local raw
artifacts are retained in `/tmp/tungsten-scheduler-validation.ux4oFz/bench/`:

- `final-builds.jsonl`: build commands, source and executable hashes.
- `final-measurements.jsonl`: six default cells, raw samples and summaries.
- `extended-measurements.jsonl`: fixed-cost, long-run, larger cancellation and
  single-deadline controls.

Follow-up validation: repeat matched timings on a quiet host, investigate the
forced-park cost, and run Linux backend tests. Then use the wake source
to replace MP idle ticks with an arm/recheck notification protocol; migrate
Core Timer and channel/mutex waits separately under their existing contracts.
