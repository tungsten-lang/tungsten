# AWS 7x7 sharded CPU campaign

`supervise_7x7.sh` runs a fail-closed, NUMA-local portfolio of independent
Metaflip coordinators. Its defaults target a six-NUMA-node `m8i.96xlarge` and
use the upper half of the machine:

- nodes `3,4,5`;
- one full-NUMA shard per node (three independent fleets total);
- `-J 64` walkers per shard;
- every curated exact rank-247 seed rotated across shards;
- node-specific `--steps` (`48000011`, `50000021`, `52000031`) so repeated seeds do
  not replay the same square walk while square `--seed-nonce` is unavailable.
  Once both the runtime and native binary expose that option, the supervisor
  automatically switches to unique shard nonces and a common 500,000 steps.

This topology follows the large-host sweep: one J64 fleet reached about 294,
416, and 492 million moves/s at 25M, 50M, and 100M-step coordinator cadences,
respectively. The coordinator now adapts the nominal 500,000-step budget toward
roughly three-second worker epochs, capped at 128x, so a single full-node fleet
avoids the coordination bottleneck without hard-coding a long epoch forever.

Each child gets independent `state`, `best`, `status`, `near`, and log paths.
The supervisor atomically publishes an aggregate status, including summed
moves, the best rank/density, counts of live/healthy shards, and OOM counters.
An early child exit, stale status, or observable kernel/cgroup OOM drains the
whole campaign. `INT`, `TERM`, `HUP`, and the wall deadline first request a
clean epoch-boundary stop, then use `KILL` only after the drain grace expires.
Any rank at most 246 is copied immediately to `winner/` before the other shards
are drained.

## Launch on the large host

From the Tungsten checkout, using the already-built native release binary:

```sh
bits/tungsten-metaflip/cloud/aws/supervise_7x7.sh \
  --binary /home/ubuntu/tungsten/build/cloud/metaflip-next \
  --runtime-root /home/ubuntu/tungsten/bits/tungsten-metaflip \
  --state-root /var/lib/metaflip/7x7-sharded \
  --log-root /var/log/metaflip/7x7-sharded \
  --seconds 7200
```

Run it in `tmux` or as a systemd service. The aggregate heartbeat is:

```text
/var/lib/metaflip/7x7-sharded/supervisor/status.txt
```

The PID/path manifest is beside it. Durable shard checkpoints survive a clean
restart; old statuses and logs are timestamped before reuse. Use a fresh
`--state-root` when a completely independent campaign is desired.
If the supervisor itself was killed but a manifested shard survived, a restart
refuses to duplicate that live process and points at the manifest for cleanup.

Before spending compute, inspect all three commands without writing anything:

```sh
bits/tungsten-metaflip/cloud/aws/supervise_7x7.sh \
  --dry-run \
  --binary /home/ubuntu/tungsten/build/cloud/metaflip-next \
  --runtime-root /home/ubuntu/tungsten/bits/tungsten-metaflip \
  --state-root /var/lib/metaflip/7x7-sharded \
  --log-root /var/log/metaflip/7x7-sharded
```

The current binary exact-verifies every explicit seed while loading it. A bad
seed therefore exits its child and triggers the fail-closed drain rather than
silently entering the portfolio.

## Local contract test

```sh
bits/tungsten-metaflip/cloud/aws/test_supervise_7x7.sh
```

The test uses synthetic structural fixtures and dry-run mode; it launches no
fleet and performs no cloud action.

## Rectangular leased campaigns

`supervise_rect_leaves.sh` maps one independent, single-shape rectangular
portfolio parent to each listed NUMA node. Its defaults preserve the six-node
AWS retarget:

```text
shape    3x3x4  3x4x4  2x3x5  3x4x5  4x5x5  5x6x7
node         0      1      2      3      4      5
walkers     64     64     64     64     64     64
```

This launcher is specifically a strict-record campaign. It rejects `2x3x4`,
whose GF(2) rank is already proven optimal at 20; use an explicit standalone
density/basin run for that profile instead.

Every NUMA process is a long-lived `--rect --rect-shapes SHAPE` parent, not an
eternal private child. By default the parent gives its node to one finite
64-round child lease, exact-gates and checkpoints the result, then starts a new
lease with the portfolio scheduler's fresh high-entropy restart nonce and
low-discrepancy door ticket. The checkpoint and eight exact side-door files are
reloaded at each boundary, so a restart changes the walk without throwing away
useful basins. `--lease-rounds N` exposes the runtime's `1..64` range; 64 is the
production default. A matched 5x6x7/J12/500k benchmark over 1.92 billion moves
measured 6.18 seconds at 16 rounds per lease, 5.46 seconds at 32, and 4.95
seconds at 64 (4.61 seconds without lease boundaries). The 64-round default
therefore recovered 25% throughput over 16 while still loading/saving all eight
doors and seeding 32 saved-door lanes in the five-lease sample.

The launcher rejects unsupported/square shapes, duplicates, unequal
shape/node counts, absent NUMA nodes, and a native binary/runtime mismatch
before starting a fleet. Parents and their leased children are CPU-only and
headless; the supervisor owns the wall deadline so all NUMA groups drain
together. At the default `J64` width, each lease keeps 32 independently salted
streams on the current best and balances the other 32 across its checked-in
and durable side doors.

The normal two-hour launch is:

```sh
bits/tungsten-metaflip/cloud/aws/supervise_rect_leaves.sh \
  --binary /home/ubuntu/tungsten/build/cloud/metaflip-next \
  --runtime-root /home/ubuntu/tungsten/bits/tungsten-metaflip \
  --state-root /var/lib/metaflip/rect-leaves \
  --log-root /var/log/metaflip/rect-leaves \
  --seconds 7200
```

The supervisor atomically updates
`STATE_ROOT/supervisor/status.txt`. `best_by_shape` keeps the heterogeneous
rank/density objectives separate; `total_moves` sums each parent's cumulative
portfolio counter. `lease_rounds`, `lease_failure_count`, and
`protocol_error_count` make the new boundary explicit alongside stale-
heartbeat and kernel/cgroup OOM counters. `progress_stale_count` separately
tracks a fresh parent heartbeat whose cumulative `total_moves` has not advanced
for `--status-timeout`; a responsive parent therefore cannot mask a wedged
private lease, and a counter that moves backward is a protocol error. A failed
private lease remains fail-closed even though the portfolio coordinator could
retry it: any cumulative `cpu_failures`, frozen work, unexpected parent exit,
malformed parent status, stale heartbeat, or OOM drains the entire campaign.

A parent exiting zero after `--stop-on-record` is successful only when its
fresh final one-shape portfolio status and durable checkpoint agree on a rank
at or below the independently curated target. The aggregate reason becomes
`record-SHAPE`, sibling parents drain, and the supervisor exits zero after
preserving the shape's durable best.

Mutable state now uses the normal live-state layout below each shape:

```text
STATE_ROOT/SHAPE/checkpoints/gf2/SHAPE/best.txt
STATE_ROOT/SHAPE/checkpoints/gf2/SHAPE/best.txt.side-door-{0..7}.txt
```

On first launch, an older `STATE_ROOT/SHAPE/best.txt` and any adjacent side
doors are atomically copied into that layout if the destination does not
already exist. Existing portfolio state always wins.

This AWS launcher requests `sudo shutdown -h now` after every terminal result,
including a failed campaign, so an instance configured to terminate on guest
shutdown stops accruing Spot compute charges. Pass `--no-shutdown` for
an interactive host. `--shutdown-command` exists for test harnesses and must
name one executable; it is never evaluated as shell text.

Inspect a custom topology without writes or shutdown:

```sh
bits/tungsten-metaflip/cloud/aws/supervise_rect_leaves.sh \
  --dry-run \
  --binary /home/ubuntu/tungsten/build/cloud/metaflip-next \
  --runtime-root /home/ubuntu/tungsten/bits/tungsten-metaflip \
  --shapes 3x4x6,4x5x7 \
  --nodes 0,1 \
  -J 64
```

The fast local contract test replaces `setsid`, `numactl`, `flock`, Metaflip,
the OOM counters, and shutdown with fixtures. It covers the clean deadline,
legacy archive migration, verified record stop, a failed private lease, an
active lease hidden behind a responsive parent, a regressed cumulative counter,
an unexpected parent exit, and OOM drains and can never invoke the host
shutdown tool:

```sh
bits/tungsten-metaflip/cloud/aws/test_supervise_rect_leaves.sh
```
