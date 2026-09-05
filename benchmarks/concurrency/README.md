# Matched scheduler microbenchmarks

`scheduler_public.c` uses exported runtime entry points and compiles unchanged
against either runtime checkout. It does not include private scheduler code.
Run it through `scheduler_compare.rb`, which builds both binaries serially,
records checkout commits, runtime hashes and compile commands, checks exact
counts/checksums, and runs warmups followed by repeated ABBA blocks. Each sample
gets a fresh subprocess with a process-group timeout; the harness also has a
30-second alarm. A failed cell is recorded and never produces a speed ratio.

From the candidate checkout:

```sh
ruby benchmarks/concurrency/scheduler_compare.rb \
  --baseline /path/to/baseline/runtime \
  --candidate /path/to/candidate/runtime \
  --build-dir /tmp/scheduler-bench-build --build-only

ruby benchmarks/concurrency/scheduler_compare.rb \
  --baseline /path/to/baseline/runtime \
  --candidate /path/to/candidate/runtime \
  --build-dir /tmp/scheduler-bench-build --skip-build \
  --output /tmp/scheduler-bench-build/measurements.jsonl --pairs 5
```

The build directory is retained. Existing output logs are never overwritten.
`--cell MODE:TASKS:ROUNDS:WORKERS` is repeatable and replaces the default cells.
`--mp` adds a multi-worker stress cell; an unsafe baseline may fail or time out.
Do not run builds or other benchmarks alongside the timed phase.

| Mode | Timed work | What it measures |
| --- | --- | --- |
| `coop` | One yield per iteration | Cooperative scheduling at one or many runnable tasks |
| `sharded` | Independent cooperative schedulers on native threads | Forge/Hammer-style ownership, with disjoint task groups and exact per-worker checksums |
| `ready` | Read an already-readable socket, then yield | Normal read-before-park control; includes read syscall cost |
| `ready-park` | Force a timed park on readable socket, read, yield | Readiness publication and deadline cancellation; deliberately not normal ready-I/O behavior |
| `deadline` | Park a quiet socket for 1 ms, then yield | Deadline churn and wakeup delivery; wall time includes requested sleeps |
| `mp` | Submit tasks to already-started workers and yield repeatedly | Multi-worker correctness and throughput, including per-task atomic progress checks and completion notification |

Cooperative timing excludes socket/task construction and initial submission.
The MP interval includes submission, excludes worker startup/shutdown, and uses
a 100-us native completion poll; it should not be compared directly with coop
costs. Every task must finish exactly its requested iterations with its own
expected checksum. Public ready reads must also return the exact byte stream.
The sharded interval starts after every worker has submitted its own tasks and
ends after joining all workers; native thread startup and task submission are
excluded, while the final joins are included. `TASKS` is the aggregate count
and must divide evenly by `WORKERS`.

Default cells are `coop:1:1000000:1`, `coop:64:16384:1`,
`sharded:128:8192:4` (four independent workers, 32 tasks each),
`ready:64:1024:1`, `ready-park:64:128:1`, and `deadline:64:32:1`.
For tail-cancellation pressure, add larger ready-park shapes explicitly.
The report prints lane medians and the median of per-ABBA-block candidate /
baseline ratios. Lower ratios indicate less time for this workload, not a
general application-speed claim. Raw wall/CPU times and context-switch counts
remain in the JSONL log.

Cooperative/sharded timing includes lazy event-loop creation and scheduler
drain/return. The baseline's terminal check is normally one nonblocking poll,
not a 1 ms sleep. These are full-run times amortized per iteration, not isolated
context-switch costs. Add `coop:1:1:1` (report total wall time) and
`coop:1:10000000:1` alongside the million-iteration cell to distinguish fixed
cost from the long-run slope. `ready-park:64:4096:1` and
`ready-park:256:1024:1` exercise longer cancellation workloads;
`deadline:1:32:1` exposes the CPU cost of waiting on a single quiet timer.
Concurrent CPU-heavy work makes timings provisional even with ABBA pairing.
