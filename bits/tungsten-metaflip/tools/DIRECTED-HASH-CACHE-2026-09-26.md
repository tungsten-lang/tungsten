# Exact-replay directed-walk fingerprint cache

The large projected-basis queue timeout was in an automatically scheduled
30-million-move directed walk, not the matrix basis rewrite. On the native
20×19×25 fixture, the first such four-task batch took 36.48 seconds before
this change, exceeding the harness's 30-second subprocess limit.

A five-second macOS sample of that worker placed 55% of leaf samples in the
inlined `ffxt_walk` body, 18% in `ffws_toggle`, 13% in `ffwd_touch`, 9% in
`ffws_remove`, and 5% in `ffws_partner`. The local `tungsten flame --pid`
command failed with `expected string or symbol` before profiling; the sample
and compiler sidemap were used instead. No profiler source was changed.

## Change

Directed contexts now cache both legacy term fingerprints by stable live
slot. Existing terms need no rehashing. New terms compute both hashes in one
limb traversal; insertion installs their cached values. Removal leaves an
inactive cache slot unused, and every rollback insertion refreshes its slot.
This covers cancellation against a third term as well as zero factors and
split escapes. Incremental global hashes retain their original XOR meaning.

The two caches add 16 bytes per term-capacity slot. Random draws, sampling,
history guards, rank acceptance, and density-as-archive-only behavior are
unchanged. The optimization is automatic in existing directed workers,
including the native background refinement walks; it does not speed the
ordinary undirected packed worker and adds no strategy flag.

## Matched evidence

The replay driver ran 20,000 fixed moves on 13 exact sources in all three
directed modes: all packaged squares 8–16, naive 2×2×2 and 3×5×7, the
maximum-width 2×2×512 case, and the 20×19×25/r5439 projected parent.
All 39 comparisons matched **byte-for-byte canonical current and best
tensors**, RNG state, and every reported search counter/fingerprint.
Both native and independent Python full-coefficient checks passed. The new
driver additionally checks every active slot cache after each 1,000 moves.

Three counterbalanced 10-million-move nonbacktracking runs of the projected
parent gave work-loop timings:

| Version | Timings (ms) | Median (ms) |
| --- | --- | --- |
| Before | 11,819; 11,859; 11,351 | 11,819 |
| Cached | 8,570; 8,507; 8,873 | 8,570 |

That is 1.379× directed-move throughput, or 27.5% less work-loop time, on
this workload. Concurrent development workloads were present; this is not a
whole-fleet or record-finding-yield claim. All three long paired runs also
matched their exact endpoints and counters. Neither version found a new
record in this test.

A second counterbalanced pass with no other MetaFlip tests/builds running
reproduced the rectangular gain: median 10,042→7,103 ms (1.414×) for 10M
moves. On the packaged 16×16/r2401 tensor, 5M identical moves took median
2,616→2,175 ms (1.203×). Individual timings were 10,841/9,870/10,042 vs
7,103/7,232/6,995 ms, and 2,616/2,570/2,735 vs 2,150/2,293/2,175 ms.
Endpoints and counters matched in every pair. Other non-MetaFlip workloads
still existed; the result remains workload-specific, not a full-machine
throughput qualification.

Focused state-cache, rectangular-walk, density-neutral, public CLI/deadline,
shape-cycle, and live packed-refinement feedback tests passed. The density
fixture needed its context allocated from the actual initialized trial
capacity, rather than a different-capacity source; production callers already
use their own initialized states. The previously timing-out
`productive_postbasis` control also passed its unmodified 30-second
subprocess limits and complete FIFO handoff: r5439 → r5422 → r5418. The full
wide queue suite is not certified by these focused checks.

## Reproduce

Compile `spec/wide_directed_replay_test.w` at the before revision and the
current revision with identical `--release --native` settings, then run:

```sh
python3 bits/tungsten-metaflip/spec/wide_directed_replay_test.py \
  /tmp/replay-before /tmp/replay-after /tmp/replay-results \
  --benchmark-source /tmp/projected.mfw
```

The projected source is the existing `productive_postbasis` control:
`replay_structured_parent_portfolio.rb --only 20x20x25`, remove middle
coordinate 18, then exact shared-factor compression to r5439. Result files
and profiling data belong in temporary/campaign storage, not runtime assets.
