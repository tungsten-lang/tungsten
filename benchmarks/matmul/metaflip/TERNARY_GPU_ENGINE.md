# Strict-ternary GPU breadth engine

`flipfleet_ternary_gpu_bench.w` is the pure-Tungsten source for a Metal engine
over the same six-mask `{-1,0,1}` representation as
`flipfleet_ternary_worker.w`.  It does not import, call, or alter the GF(2)
coordinator or TUI.  `flipfleet_ternary_gpu_lib.w` is the production host
wrapper used by `flipfleet_ternary.w`.

## Move and safety contract

Each Metal lane owns a fixed-rank signed scheme and applies exact 2x2 basis
changes.  It rejects an endpoint addition that would create `+2`, `-2`, or a
zero factor, and gauge-canonicalizes the two touched terms.  Three lane
temperatures run together:

- unrestricted wander;
- density increase at most two on the touched pair;
- downhill/equal density only.

At rank 250, two lanes interleave six 256-entry `i64` arrays in 24 KiB of
threadgroup memory.  This stays below Metal's 32 KiB limit while retaining the
full 49-bit 7x7 factor masks.

The host upload deliberately crosses the generic seed portfolio through a
statically typed `i64[]` helper. Without that boundary, 49-bit 7x7 masks that
use boxed host integers can be copied into a raw Metal view as runtime pointer
bits after nested-array type erasure; smaller masks concealed the issue. The
GPU-library regression now exercises two real rank-250 seeds through this
production wrapper and requires two exact returns with zero rejects. This was
fixed in fleet code and did not require a language or compiler extension.

The GPU is never an exactness oracle.  Every endpoint returned to the fleet is
copied into ordinary Tungsten arrays and passed through `fft_init_terms`, which
reconstructs every integer coefficient of all `n^6` tensor cells.  Archive and
best-file publication repeat the integer gate.  A deterministic planted test
also applies the same selected move on CPU and GPU, compares all six masks of
every term, and then runs the exhaustive integer gate.

The public 4x4/r49 support contains no shared factor on any axis.  Rather than
launch inert lanes, the wrapper deterministically searches exact donor splits,
gates a +1 door, and holds the GPU walk at rank 50.  Such an endpoint is only a
restart door; it can never replace the rank-49 objective.  The checked-in
5x5/r93, 6x6/r153, and 7x7/r250 seeds have direct fixed-rank doors.

## Fleet policy

The strict-ternary CLI runs the bounded GPU scout by default while CPU islands
remain live.  Use `--no-gpu` for a CPU-only campaign.  The tuning controls are
`--gpu-lanes`, `--gpu-steps`, and `--gpu-rounds`; defaults are 1024 lanes,
4096 moves of depth, and four rounds.

Lanes rotate across every same-rank catalogue/continuation seed instead of
cloning one presentation. The portfolio retains each raw seed and also adds
each fingerprint-distinct deterministic CPU index-normalization endpoint;
this lets custom seeds follow the same shear-then-GPU compound path without
sacrificing their original basin. Every round restarts independent RNG streams,
rotates the lane-to-seed mapping, and returns at most one exhaustively gated
candidate.  Density improvements use the lane's best endpoint; otherwise a
changed unrestricted-wander endpoint supplies basin diversity.  A missing
Metal device, sidecar, or pipeline is caught by the optional GPU thread and
reported as `gpu=degraded`; CPU islands continue and the process still gates
its durable winner.

The production wrapper has a dedicated rank-250 regression. It caught a host
upload bug that the standalone kernel harness could not expose: indexing an
`Array` of seed states erased the nested `i64[]` type, so 49-bit 7x7 masks
outside the nanboxed immediate range were copied to raw Metal views as boxed
WValue pointer bits. This was neither a mask-width nor a dispatch-geometry
failure. Seed upload now crosses the generic portfolio through an explicitly
typed `i64[]` helper. The regression rotates two independent 7x7 seeds through
the real wrapper and requires two exhaustively gated outputs with zero rejects;
an 8,388,608-attempt integrated follow-up also gated both returns with zero
rejects.

## Results

The engine produced six independently replayed density improvements.  These
are equal-rank sparse presentations and tunnel seeds, not lower-rank records.

| tensor | input | GPU attempts | result | certificate SHA-256 |
|---|---:|---:|---:|---|
| 5x5 | r93/d1249 | 8,388,608 | r93/d1245 | `2b068340b0ffd07eaa47e05669a3ab18c5f47906840ceaeb8d2c7936b3faad89` |
| 5x5 | r93/d997 index shear | 8,388,608 | r93/d967 | `d63c756fef192ea7b0fe78bdc5378f2eb3af0f8cf63e6d3fb7b9f8110701c407` |
| 6x6 | r153/d1938 index shear | 8,388,608 | r153/d1931 | `f58820f4b3c4f71f4a7fd5b2303e30fda382c352d3b059fed74a678072186c37` |
| 6x6 | r153/d2208 Kauers index shear | 8,388,608 | r153/d2148 | `6fb699952b4325c9b224852fdff76dd5d9d7631448fe2d9dd4038a609b5e977a` |
| 6x6 | r153/d2208 Kauers-r153 index shear | 8,388,608 | r153/d2148 | `921627eee48fba62105c46e80f82567d8a47d8371c66ca626f63ada1371aaeec` |
| 6x6 | r153/d1937 shallow symmetry door | at most 4,194,304 | r153/d1935 | `78df6b6f0b08c82d737b3f1940f6442f85ab48e2f0a8550435cd0fe4aa05ef82` |

The final five demonstrate the intended CPU/GPU composition: the global
matrix-index shear creates a much sparser exact door, then GPU breadth finds a
better fixed-rank basin than the one CPU reference trajectory at the same
depth.  The two d2148 files are particularly useful as diversity doors: they
share only two of 153 canonical terms with each other and no terms with the
d1931 objective leader. Independent Python integer reconstructions and a
fresh `flipfleet_ternary --seed ... --moves 1 --no-gpu` replay accepted all
six files.

Each d2148 return reopens deterministic index descent: three exact shears
reduce it to a distinct d1953 fixed point. The integrated portfolio constructs
those normalized clones automatically and feeds them back to GPU lanes, so
the CPU/GPU composition is iterative rather than a one-time preprocessing
pass. The retained d1953 certificate hashes are
`f0f06c9812ecdec7ca79ebd07a65f296dc044a32a433e0f845f0d60837aa760c`
and `a38623255e9e7269b0d1ab681a2a0b39a48f91d94b4c741d1a3bdda6a6f7fcdd`.
Dedicated 134,217,728-attempt continuations from each d1953 door retained
d1953, gated 32 changed exact basins per seed, and had zero exact rejects.
Thus these are live diversity components, but this bounded run did not beat
the d1931 objective.

A structurally distinct 5x5 d1245 basin normalized to d994, then reached the
same canonical d967 term multiset in 8,388,608 GPU attempts.  This is direct
evidence that the two normalized doors are connected by the signed basis-flip
graph, rather than merely sharing a density score.

The bounded symmetry escape also showed value. From each normalized seed the
fleet may construct at most one exact, shallow positive-density index shear
with debt at most eight. It is admitted only to the GPU portfolio, never as
the objective. For 5x5 this constructs d967 -> d974; 134,217,728 GPU attempts
returned changed exact basins but did not close below d974. For 6x6 it
constructs d1931 -> d1937, GPU breadth reached d1935 in the first 4,194,304
attempts, and strict CPU index descent then closed to a different exact d1931
basin. The new certificate is
`matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt`, SHA-256
`39d8782dffd33b988447982bb13632553734da4c5c70b36148670645eeda3801`.
It shares 147 of 153 canonical terms with the previous d1931 leader, so the
compound uphill-shear -> local GPU -> descent path is a verified tunnel rather
than a serialization change.

Longer 134,217,728-attempt continuations from d967 and d1931 found four changed
exact basins each but no further density decrease.  An 8,388,608-attempt 7x7
run found a changed exact r250 basin but did not beat d2966.  There were zero
integer-gate rejects in these campaigns. Each of the two new d1953 compound
doors also received 134,217,728 attempts: all 32 sampled returns per door were
changed and exact, but neither reduced density. This bounds the immediate
basis-flip continuation without treating the new doors as exhausted by other
move families. The tunneled d1931 then received another 134,217,728 mixed and
134,217,728 downhill-only attempts; both campaigns had zero exact rejects and
neither reduced density below 1931.

On the development M-series host, a concurrent four-second 5x5 comparison
gave:

| mode | CPU attempts | GPU attempts | total accepted exact moves |
|---|---:|---:|---:|
| one CPU island, `--no-gpu` | 8,085,504 | 0 | 364,713 |
| one CPU island + GPU | 7,995,392 | 33,554,432 | 919,734 |

The hybrid retained 99% of CPU attempt throughput while raising aggregate
attempt throughput from about 2.02M/s to 10.37M/s and aggregate accepted-move
throughput from about 91k/s to 229k/s.  These are machine-local scheduling
measurements, not portable performance claims.

## Reproduction

The commands below are the exact compiler form used during development.  The
standalone compile emits a fresh generated Metal file in `/tmp`; the checked-in
`.msl` sidecar is the reviewed runtime source.

```sh
TUNGSTEN_LL_PATH=/tmp/flipfleet-ternary-gpu.ll \
TUNGSTEN_METAL_PATH=/tmp/flipfleet-ternary-gpu.metal \
  bin/tungsten-compiler compile \
  benchmarks/matmul/metaflip/flipfleet_ternary_gpu_bench.w \
  --out /tmp/flipfleet-ternary-gpu --release --lto

/tmp/flipfleet-ternary-gpu --tensor 5x5 --lanes 1024 \
  --steps 4096 --rounds 2 --gate-every 1 --cpu-steps 200000 \
  --policy mixed

bin/tungsten-compiler compile \
  benchmarks/matmul/metaflip/flipfleet_ternary_gpu_lib_test.w \
  --out /tmp/flipfleet-ternary-gpu-lib-test --release --lto
/tmp/flipfleet-ternary-gpu-lib-test

bin/tungsten-compiler compile \
  benchmarks/matmul/metaflip/flipfleet_ternary.w \
  --out /tmp/flipfleet-ternary --release --lto
/tmp/flipfleet-ternary --tensor 5x5 --secs 60 -J1
/tmp/flipfleet-ternary --tensor 5x5 --secs 60 -J1 --no-gpu
```

No syntax extension was needed.  The existing `gpu.shared_i64` support handles
all six signed masks.  The generated MSL needs no hand-written move logic; the
checked-in sidecar adds only a diagnostic suppression for redundant comparison
parentheses emitted by the current compiler. The boxed-mask upload issue is a
compiler type-flow/ABI sharp edge rather than missing syntax; the typed helper
is correct and regression-tested, while preserving nested typed-array
information across generic containers remains worthwhile compiler work.
