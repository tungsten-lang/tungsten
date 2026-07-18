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
