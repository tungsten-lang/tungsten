# FlipFleet offline Metal cache

FlipFleet no longer compiles MSL in every GPU epoch. At worker-build time,
`flipfleet_metallib_cache.w` resolves the downloaded Apple Metal tools, compiles
the compiler-emitted `.metal` source, and atomically publishes
`worker.metallib` next to the native executable. Every launch receives that
path and loads it through `metal_load_library`.

The cached path covers:

- square and rectangular cal2zone workers;
- C3 and D3 quotient workers;
- cooperative SIMD-group workers;
- MITM, k-XOR/circuit, and constraint-pool workers.

Source compilation remains an explicit fallback for standalone developer
launches that omit the final cache argument. Cache freshness is the emitted
Metal source mtime; a missing or older library causes a rebuild before the
campaign marks that engine ready. `TUNGSTEN_METAL_PATH` directs compiler output
beside the worker executable, so campaign builds do not rewrite checked-in
sidecars.

Square and rectangular cal2zone workers additionally support an optional
persistent mailbox mode. `flipfleet_persistent_gpu.w` launches one child and
atomically publishes commands of the form:

```text
generation action steps reseed margin workq wanderq wthr escapes
```

The coordinator calls `ffpg_prepare_mailboxes` before each launch so an old
session cannot replay a command. The worker then creates its Metal device,
library, pipeline, queue, and buffers once.
Action `1` runs exactly one bounded dispatch and acknowledges only after its
candidate output is complete; action `0` acknowledges a clean stop. Generation
numbers reject stale commands after a restart. A changed lane allocation or
engine identity still restarts the process, and the coordinator can fall back
to the ordinary bounded-child path after a timeout. This keeps adaptive
rotation, exact host gates, failure backoff, and TUI accounting intact while a
stable generic lane avoids process and pipeline setup.

Each worker also carries a ten-minute idle mailbox lease. Normal shutdown uses
the explicit stop/ack path above; if a coordinator is killed before it can
publish that command, the child writes an `expired` acknowledgement and exits
on its own instead of retaining an orphaned Metal device indefinitely.

Focused checks:

```sh
bin/tungsten --release --native --fast --lto \
  -o /tmp/ff-metallib-cache-test \
  benchmarks/matmul/metaflip/flipfleet_metallib_cache_test.w
/tmp/ff-metallib-cache-test "$PWD"
```

On the development M4 Max, six isolated 16-lane one-step 3x3 launches averaged
0.182 seconds with runtime source compilation and 0.150 seconds from the cached
library. Three simultaneous eight-worker launch batches averaged 0.500 seconds
from source and 0.383 seconds cached, removing 23% of the rotation gap. After
adding the persistent path, a same-session five-launch check averaged 122 ms
from source and 64 ms from the cached child; eight commands through one
persistent child averaged 15 ms apiece, while the latest integrated reuse
sample averaged 19 ms. Thus the focused persistent samples remove roughly
70–77% of the remaining cached-child gap (84–88% versus source compilation).
These are intentionally tiny, startup-dominated measurements that can run
beside a campaign; they do not claim a change in kernel move throughput.
