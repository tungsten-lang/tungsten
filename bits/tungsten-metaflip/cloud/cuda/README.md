# NVIDIA CUDA 7x7 relay

This is a narrow cloud harness for Metaflip's cooperative 7x7 GF(2) walker.
It is separate from `bin/metaflip`: the production fleet currently dispatches
Metal, while this relay launches one exact scheme per 32-lane CUDA warp.

The CUDA kernel is not a hand-maintained fork. `build_777.sh` extracts the
`@gpu` section from the packaged
`lib/metaflip/kernels/simd/simdgroup_777.w` source and asks Tungsten to emit a
temporary CUDA sidecar. The C++ host supplies the buffer protocol, NVIDIA warp
reductions, multiple restart doors, seeded term-order diversification,
an exhaustive 7^6 coefficient gate, and atomic checkpoints. A device claim
that fails the host tensor or density gate is preserved as `.reject...` and
terminates the process nonzero.

## Provision and build

Use an x86-64 CUDA-devel image with a working remote entrypoint. A bare
`nvidia/cuda:*` image contains CUDA but does not configure Runpod SSH merely
because `runpodctl pod create --ssh` is present. Prefer Runpod's official,
SSH-ready PyTorch template:

```sh
runpodctl pod create \
  --name metaflip-4090-gate \
  --template-id runpod-torch-v240 \
  --gpu-id 'NVIDIA GeForce RTX 4090' --gpu-count 1 \
  --cloud-type SECURE --data-center-ids EU-RO-1 \
  --container-disk-in-gb 40 \
  --volume-in-gb 20 --volume-mount-path /workspace \
  --ssh
runpodctl ssh info POD_ID
```

The official Ubuntu 22.04 template has CUDA installed, but its default
`clang` is 14 and `/usr/local/cuda/bin/nvcc` is not necessarily on `PATH`.
Clang 15 also cannot consume this checkout's current LLVM IR; the helper pins
the proven Clang 18 toolchain. The native compiler link
also needs `libopenblas-dev`, which was absent from the former ad-hoc package
list. After transferring or cloning the source, run the checked setup helper
as the container's root user:

```sh
cd /workspace/tungsten
bits/tungsten-metaflip/cloud/cuda/setup_runpod.sh
bits/tungsten-metaflip/cloud/cuda/setup_runpod.sh --check
bin/tungsten build --no-bits
bits/tungsten-metaflip/cloud/cuda/test_777_host.sh
METAFLIP_CUDA_ARCH=sm_89 \
  bits/tungsten-metaflip/cloud/cuda/build_777.sh \
  --out /workspace/metaflip-cuda-777
```

The helper pins LLVM 18 from the signed apt.llvm.org repository, installs the
complete Tungsten/OpenBLAS self-host dependencies (including Ruby), exposes
the image's existing CUDA compiler through an `/usr/local/bin/nvcc` exec
wrapper, and functionally
probes clang/lld, zstd, Oniguruma, OpenBLAS, Ruby, and `nvcc`. It is
idempotent. Use `--dry-run` to inspect its package/link plan without changing
the image. The wrapper is intentional: NVIDIA's driver derives its toolkit
root from `argv[0]`, so a raw symlink outside `/usr/local/cuda/bin` can make a
healthy CUDA image fail to locate `cuda_runtime.h`.

Use the full stage-one/stage-two `build --no-bits` above, not only
`bootstrap`: the CUDA source exercises compiler paths that need the installed
self-hosted stage-two compiler. The resulting pod emission is checked against
the canonical Tungsten kernel before `nvcc` runs.

`METAFLIP_TUNGSTEN` selects another compiler. `NVCC` selects another CUDA
compiler. `METAFLIP_CUDA_ARCH` defaults to `native`; set it to a concrete
architecture when cross-compiling.  An RTX 4090 is Ada (`sm_89`), so the
recommended reproducible 4090 build is:

```sh
METAFLIP_CUDA_ARCH=sm_89 \
  bits/tungsten-metaflip/cloud/cuda/build_777.sh \
  --out /workspace/metaflip-cuda-777
```

The host gate has a CPU-only regression that can run before provisioning a
GPU:

```sh
bits/tungsten-metaflip/cloud/cuda/test_setup_runpod.sh
bits/tungsten-metaflip/cloud/cuda/test_777_host.sh
```

The host regression exact-gates all five campaign roots, proves that objective
ordering retains the final d3094 affine certificate over its equal-density
incumbent, and checks the 25% leader
floor, adaptive role and original-root allocation, productive-role preference,
deterministic replay, bounded no-starvation exploration, descendant rotation,
source-aware density-chain admission, deterministic top-K group selection,
the K=1 compatibility path, transfer bounds, and harvest-counter lifecycle. It
also pins the observed saturated-novelty trace (155 archive admissions in 208
visits with no objective gain): the saturated source must no longer monopolize
reward slots, while the fixed exploration gaps and productive-source preference
remain unchanged. The pinned result allocates the next 256 source slots as
`65,64,63,64` (the saturated source is third) and the 4,096-slot horizon as
`854,854,1534,854`, keeping its bounded discovery bonus below twice any neutral
source instead of winning every exploitation slot.

The relay launch is deliberately one 32-thread warp per CUDA block.  During
the cloud build, the script fail-closed checks the emitted barrier inventory
and specializes Tungsten's conservative block barriers to warp barriers.
This preserves all shared-memory ordering while avoiding full-block barrier
machinery in the hot walk loop.

To inspect the generated CUDA without requiring `nvcc` or a device:

```sh
bits/tungsten-metaflip/cloud/cuda/build_777.sh --emit-only
```

## RTX 4090 smoke

Run two deliberately tiny epochs before spending a two-hour allocation.  The
two epochs exercise scan and hash mode respectively, and reuse the same exact
checkpoint/archive paths as the long run.

```bash
cd /workspace/tungsten
mkdir -p /workspace/results
set -o pipefail
/workspace/metaflip-cuda-777 \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt \
  --out /workspace/results/best.txt \
  --status /workspace/results/status.txt \
  --archive-dir /workspace/results/archive \
  --epochs 2 --seconds 60 --groups 256 --steps 100 --dispatches 1 \
  --mode alternate --stop-rank 246 --device 0 \
  2>&1 | tee /workspace/results/smoke.log
rc=${PIPESTATUS[0]}
printf '%s\n' "$rc" > /workspace/results/smoke.exit.code
if [ "$rc" -ne 0 ]; then exit "$rc"; fi
grep -qx 'phase=done' /workspace/results/status.txt || exit 2
grep -qx 'exact_rejects=0' /workspace/results/status.txt || exit 2
```

## Two-hour RTX 4090 campaign

Use structurally different exact rank-247 doors. One epoch in every four
unconditionally grinds the current fleet-best checkpoint. The other three
slots adapt across the leader, other command-line roots, and diversity-admitted
descendants. Every available nonleader role is tried before reward selection;
thereafter one in every four adaptive slots explores the least-recently used
nonleader role. Reward slots select the best exact-gated useful-yield rate. This
keeps a 25% leader floor while reallocating the remaining 75% according to the
yield of the original and descendant families. Within the original role, every
eligible root is likewise tried once, then one in every four original slots is
oldest-first exploration. At both levels, the first raw exact-novel artifact
contributes one bounded discovery point. Raw archive diversity
therefore cannot accumulate an unbounded advantage or monopolize a portfolio.
An exact-novel endpoint at lower rank, or at the fleet-best rank
within `max(8, best_density/50)` density bits of the leader, earns four
unbounded objective-useful points. A same-source rank/density chain replacement
earns the same credit as measured continuation fertility. A fleet-best earns
sixteen additional unbounded points. A unit scheduling prior lets finite historical credit
be compared fairly with less-visited neutral sources; it is used only when at
least one compared source has credit, preserving the exact neutral oldest-first schedule.
Deterministic age and source ties make a fixed run reproducible. The relay
permutes term order on every visit so CUDA RNG streams do not repeat. Production
uses the faster scan specialization; explicit
`--mode alternate` remains useful in the smoke test because it exercises both
kernels independently within every scheduling role. In alternate mode, the
leader role, every original source, and every descendant slot own independent
scan/hash visit parity rather than inheriting the global epoch. Adaptive
preference and even-sized door rotation therefore cannot pin a fertile source
to only one kernel.

The active beam-far root is the exact rank-247/d3096 child harvested at epoch
1849 of Runpod campaign `7h2j3f0tfwjv0p` from source commit `fd25c71`; its
SHA-256 is
`6b308083887f1bab57ddf476afdf4e6ec6f5fca28cc477e6e62e89b413cb3e64`.
That campaign's epoch-3306 d3096 affine-code child, SHA-256
`b8af658635eae896fe7111666925bbd4c6bb65ac1b64a47db8ff3bbb65387b92`,
is now the explicit parent of the active d3094 descendant described below.
Independent support-major and coefficient-major Tungsten gates accept the
complete lineage. Both d3096 children were three-term exchanges from their
d3098 roots; the active beam child and final affine d3094 child remain mutually
disjoint (distance 494), preserving the independent basins.

The exact three-for-three support exchanges are recorded here so the density
steps can be replayed without relying on archive term order:

```text
epoch 1849 removes
  (16777216, 21994569474368, 4330618880)
  (2164294658, 41951488, 4294967360)
  (2203335008257, 21994527522880, 4294967360)
and adds
  (16777216, 21994569474368, 35651648)
  (2147517442, 41951488, 4294967360)
  (2203318231041, 21994527522880, 4294967360)

epoch 3306 removes
  (67108864, 22578644156672, 41945088)
  (1099578806276, 584116633600, 2050)
  (2216270235650, 21994527523072, 2050)
and adds
  (67108864, 22578644156672, 41943042)
  (1099511697412, 584116633600, 2050)
  (2216203126786, 21994527523072, 2050)

epoch 257 of the final campaign removes
  (16777216, 87961234317378, 34370224128)
  (274894701569, 35651650, 34360786944)
  (566952501248, 87961198665728, 34360786944)
and adds
  (16777216, 87961234317378, 11534336)
  (274877924353, 35651650, 34360786944)
  (566935724032, 87961198665728, 34360786944)
```

The last exchange is the active source-4 replacement. Runpod pod
`aack78ni07p1uh`, campaign source commit
`1dfc4321f964a0ca4eca75e8c0870f8692d565b0`, produced it at epoch 257,
group 8177. The packaged raw bytes have SHA-256
`ddf710feced82ece388d9e368f9ad4bcf4da08d0583c4b17ab34a8a5e1accb71`;
the order-independent numeric term-multiset SHA-256 is
`d71bbeb41d5da88264475eb412baca85d099764fa3a1fce9474cffc78b7cfee8`.
It is rank 247/d3094, support distance six from the epoch-3306 d3096
affine-code parent and distance 396 from the hot d3094 incumbent. Across 48
canonicalized matched four-million-move continuations it tied the incumbent
48 times and beat its parent 48/0/0. It therefore replaces the parent only in
source 4 and the active frontier slot; the incumbent stays source 0/hot
default, while the d3096 parent remains packaged for explicit replay.

Final Runpod triage promotes two independently exact C013 artifacts. Epoch
1965/group 6417 produced rank 247/d3542; in 24 canonical matched 4M-move
continuations it beat the old d3538 low-quota source 24/0/0 and the former
active d3492 endpoint 23/0/1. It replaces source 3 in the CUDA recipe and the
single low-quota slot, while the d3554 C013 root remains in the CPU frontier.
The same trials reached an identical rank-247/d3486 endpoint in trials 4, 15,
and 21 (seeds `718917`, `1870936`, and `2499310`). That endpoint is distance 42
from d3542 and 20 from d3492; direct continuation was locally terminal, so it
replaces d3492 in the active C013 frontier slot. The old d3538, d3492, and d3496
certificates remain packaged for explicit replay. Raw, term-multiset, and
D3/reversal hashes are respectively
`bc0d913f34d0b733436059e16775bbff3c8f29e3306bd5b8e29de4f05a05b676`,
`6a54c3e5388784485afa3a10814a9e41658ff7456c339c3e01e1c487fe6e4f6c`,
`dbd111c632e27812ddddac7300e6d4842a68340248842dce65c825f8eb7c9a24`
for d3542 and
`dfab762a6150c274b670f67f6169d3635c32974c0be106482717b94fae149b05`,
`52284f28e3886fe20b848ddd81d57993dbd1566de11c13cce8875c4729ffbef3`,
`4873e956b1f3df815c250ab99fceb4ee9f3dd18c230fea8b5985e9f4817952ec`
for d3486. The d3094 scheme remains the hot leader.

```bash
cd /workspace/tungsten
mkdir -p /workspace/results
set -o pipefail
/workspace/metaflip-cuda-777 \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt \
  --seed bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt \
  --out /workspace/results/best.txt \
  --status /workspace/results/status.txt \
  --archive-dir /workspace/results/archive \
  --seconds 7200 --groups 8192 --steps 20000 --dispatches 5 \
  --mode scan --stop-rank 246 --device 0 \
  2>&1 | tee /workspace/results/run.log
rc=${PIPESTATUS[0]}
printf '%s\n' "$rc" > /workspace/results/exit.code
exit "$rc"
```

Each process chooses a fresh diversification seed, so restarting a neutral
campaign does not replay the same term permutations. Add `--run-seed N` to
reproduce a run exactly; the selected value is printed and included in every
status snapshot. An existing exact `--out` checkpoint is re-gated and admitted
as the leader role. Exact entries in the archive are all re-gated after an
interruption; raw support distance then rebuilds the bounded descendant bank
farthest-first instead of accepting files by pathname order. Live descendants
must have support distance at least 12 from every retained door, and a full
bank changes only when a replacement strictly raises its exact max-min score.
There is one narrow density-chain fallback after normal admission rejects: an
objectively better candidate launched from descendant slot `s` may replace
that same slot while ignoring only its distance to its own parent. It must
still meet the configured distance floor against every original root and every
other descendant. Normal append/replacement always takes precedence, and
`epoch_door_source_replacement=1` distinguishes this fallback from an ordinary
`epoch_door_action=2+s` replacement. Archive replay first performs the normal
farthest-first/max-min rebuild, then deterministically advances objective-better
parent/child chains under the same one-parent exception. Thus a retained child
does not regress to its worse archived parent after restart.
Use `--door-min-distance N` to override that measured default. The checkpoint
is preserved unless a strictly better result appears.

`--harvest-top-k N` (1 through 8, default 8) preserves more of the
independent group work already completed by an epoch. After the one fixed
group-state download, the host orders valid completed endpoints by rank,
density, then ascending group ID. It transfers only the first `N` endpoints
that strictly improve the launch door. `N=1` is the original path: it selects
the same absolute group, performs the same factor transfer, and makes the same
archive, door, reward, and fleet-best decisions. For `N>1`, every selected
scheme passes the exhaustive tensor gate and the published rank/density check
before any scheme from that epoch is archived or admitted. Canonical scheme
keys then remove duplicates—the compact device state intentionally identifies
groups, not full scheme equality.

The absolute objective winner alone may improve the fleet best, use the
source-aware one-parent density-chain exception, or score adaptive-role
reward. Auxiliary exact-novel schemes are archived and offered to the live
descendant bank through the ordinary all-door distance gate. They cannot waive
distance to their launch source. This turns independently discovered basins
into future GPU doors without allowing top-K multiplicity to distort reward.
`harvest_epoch_auxiliary_door_admissions` and its cumulative `harvest_total_*`
counter report how often that strict gate retained an auxiliary. K=1 remains
behaviorally identical to the original winner-only path. At rank 247, K=8
transfers at most 47,424 factor bytes total per productive epoch; the
capacity-wide hard bound is 69,120 bytes. Neutral epochs transfer none, and
neither setting adds device buffers or changes the kernel.

The first deterministic RTX 4090 K=8/K=1 validation used the distant d3554
root, run seed 778, and identical three-epoch GPU work (2.4576B attempts and
186.7246M partners). K=1 exact-gated three candidates, all novel, in 9.535s;
K=8 exact-gated 24 candidates and retained 18 novel schemes in 9.772s. That is
six times the novel evidence for 237ms (2.5%) added wall time, with zero exact
rejects and the same d3522 objective endpoint. Under the distance-12 production
gate, all seven auxiliary novel artifacts from the first epoch formed valid
doors in objective order, while its absolute density winner was too close to
the root. Production therefore defaults to `--harvest-top-k 8`; pass
`--harvest-top-k 1` only for winner-only trajectory controls or direct legacy
comparisons.

The 8192-group launch allocates 141,828,572 bytes (135.3 MiB) of explicit
device buffers.  CUDA context and driver allocations make the process total
shown by `nvidia-smi` larger, but it should remain comfortably below 1 GiB on
a 24 GiB RTX 4090.  The relay also refuses a launch whose explicit buffers
would consume more than 80% of currently free VRAM.

The status file is replaced atomically after every completed CUDA dispatch,
not merely at epoch end.  While the first long dispatch is running, inspect
the GPU and then use its measured completion time as the heartbeat baseline:

```sh
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,power.draw \
  --format=csv,noheader
cat /workspace/results/status.txt
tail -n 5 /workspace/results/run.log
```

The additive `policy_leader_epochs`, `policy_original_epochs`, and
`policy_descendant_epochs` status fields count selected epoch roles;
`selected_role` and `selected_source` identify the active launch. At every
completed prefix, leader epochs must be at least one quarter of their sum.
`policy_adaptive_role_slots`, `policy_role_explore_every`, and `role_stats`
make the outer reward schedule auditable. Epoch log lines repeat the selected
role/source, cumulative `policy=L/O/D` counts, and role statistics. In
`role_stats`, `lastA` is the role's last adaptive slot; fixed leader-floor
visits do not change it.
`original_source_stats` serializes each source as
`INDEX:vVISITS,nNOVEL,uUSEFUL,bBEST,pPOINTS,lastSLOT`; `role_stats` and
`descendant_source_stats` expose the same `uUSEFUL` field. `pPOINTS` is the
bounded novelty plus objective-useful and fleet-best reward described above;
it deliberately excludes the unit scheduling prior. `policy_original_slots` and
`policy_original_explore_every` make the exploration cadence auditable.
`epoch_door_action`, `epoch_door_score`, and
`epoch_door_source_replacement` report the current epoch's archive decision;
they reset while the next epoch is in flight. The epoch log mirrors them as
`epoch_door_action`, `epoch_door_score`, and `epoch_door_source_replace`.
Those singular fields describe the absolute endpoint; auxiliary top-K door
changes are counted separately by `harvest_epoch_auxiliary_door_admissions`.

The relay also reports the breadth available to candidate harvesting.
`harvest_epoch_completed_groups` counts completed cooperative groups in the
most recently downloaded epoch, while `harvest_epoch_improved_groups` counts
the groups whose retained rank/density strictly beats that epoch's launch
door. `harvest_epoch_capture_groups` and `harvest_epoch_capture_sum` count
groups with at least one strict device capture and all such captures,
respectively. These are device telemetry, not substitutes for the host exact
gate. The corresponding `harvest_total_*` fields add completed epochs from
this process only; they reset on process restart and are not reconstructed
from the archive. Epoch fields are zero in `ready` and while a new epoch is in
flight (the relay publishes a pre-launch `dispatch=0` status), become final
after its state download, and remain visible in `done` if no later epoch starts.
`harvest_top_k` reports the configured cap. The
`harvest_epoch_selected_groups`, `harvest_epoch_downloaded_schemes`,
`harvest_epoch_exact_schemes`, `harvest_epoch_novel_schemes`,
`harvest_epoch_auxiliary_door_admissions`, and
`harvest_epoch_transfer_bytes` fields audit the opt-in host path; matching
`harvest_total_*` fields accumulate them for the process. The epoch log emits
the same values in compact form. Candidate epoch counters reset alongside the
group counters before the next dispatch, and totals remain additive. Group
breadth counters do not affect selection. Candidate counters observe work
already performed; auxiliary door admission changes only future restart
selection, while the exact-gated absolute winner alone affects fleet best and
adaptive-role reward.

The build mechanically emits constant scan and hash specializations from the
same canonical Tungsten kernel. Structural guards reject changed mode geometry,
and startup refuses to search unless compiled static shared memory is exactly
8,688 bytes for scan and 19,152 bytes for hash. This lets scan avoid reserving
the 10,464 bytes of hash tables it never touches without maintaining a second
hand-written walker.

With the campaign's CUDA 11.8 `nvcc -O3 -arch=sm_86` toolchain, `ptxas`
reports scan at 82 registers/thread and 8,688 bytes shared, and hash at 78
registers/thread and 19,152 bytes shared; both use zero stack and zero spills.
On the 84-SM A40 the runtime occupancy calculation reports 10 versus 5
one-warp blocks per SM (840 versus 420 resident groups), reducing an
8,192-group scan launch from 20 backlog waves to 10. Treat register counts as toolchain measurements,
not portable constants; static shared-byte checks remain fail-closed.

A deterministic A40 ABBA check (8,192 groups, four 10,000-step epochs,
327.68M attempts/run) reproduced every per-epoch partner count exactly between
the old combined kernel and these specializations. Scan fell from a 5.980s
mean to 3.034s (54.8M to 108.0M attempts/s, 1.97x); hash fell from 4.715s to a
4.456s mean (69.5M to 73.5M attempts/s, 1.06x). This is a trajectory-preserving
resource optimization, not a changed move distribution.

The distant d3554 outer root confirms the choice of scan as the production
default: the same deterministic four-epoch test produced identical partners,
four identical exact candidates, and the same d3520 endpoint, while scan took
1.375s versus hash's 1.955s (1.42x). Hash remains an explicit diagnostic and
performance fallback, not a diversity role—the two kernels intentionally
choose the same first matching partner.

The initial `CUDA777_CONFIG` line preserves the original hash-compatible
resource fields and also reports `scan_*` and `hash_*` shared bytes, registers,
local bytes, active warps per SM, resident groups, and backlog waves. Preserve
that line with the smoke log. The build enables the `ptxas` resource report for
both kernels; preserve each function's register, spill, and shared-memory lines,
or save an Nsight Compute launch summary, before changing capacity or hash
geometry. In particular, do not lower the 360-term capacity merely from the
static shared-memory estimate: register allocation or the lane-zero serial hash
path may be the actual limiter.

Do not classify a status file as stale while the CUDA process exists and GPU
utilization remains nonzero: a heartbeat cannot be written from inside a
kernel dispatch.  A campaign has failed if the process disappears before
`phase=done`, `exit.code` is nonzero, the log contains `CUDA_OOM`,
`CUDA_ERROR`, or `CUDA777_FATAL`, status says `phase=exact-reject` or reports a
nonzero `exact_rejects`, or the status mtime exceeds three times the longest
observed dispatch while GPU utilization is zero on three consecutive checks.
Also treat a kernel-log OOM kill or NVIDIA Xid as fatal.  Preserve `best.txt`,
`archive/`, `status.txt`, `run.log`, any `best.txt.reject.*`, and the exit-code
files before deleting the pod.

Treat 8192 groups as the breadth setting, not a knob to keep increasing.  It
already leaves a deep backlog of independent one-warp schemes on a 4090.  Use
the first completed long dispatch to tune only `--steps`: target roughly
10--60 seconds between status updates; halve 20000 if a dispatch takes more
than two minutes, or double it if dispatches take only a few seconds.  Keep
five dispatches when possible so each door receives a 100000-step trajectory
before rotation.

For any alternate unattended wrapper, save the real pipeline exit code:

```bash
set -o pipefail
/workspace/metaflip-cuda-777 ... 2>&1 | tee /workspace/results/run.log
printf '%s\n' "${PIPESTATUS[0]}" > /workspace/results/exit.code
```

An exit code of 2, a `CUDA_OOM`/`CUDA_ERROR`/`CUDA777_FATAL` line, an
`exact-reject` status, or a stale status combined with zero GPU utilization is
a failed campaign. Copy `/workspace/results` off the pod before terminating
it. A normal wall-limit or signal drain writes `phase=done`.

## Unattended harvest before stop

Use the host-side guard when a pod should stop billing as soon as a campaign
reaches `phase=done` or a terminal failure. List every result-bearing tree;
the mixed 7x7/rectangular campaign has two:

```sh
bits/tungsten-metaflip/cloud/cuda/harvest_then_stop.sh \
  --pod-id POD_ID \
  --ssh-host SSH_HOST --ssh-port SSH_PORT \
  --ssh-key ~/.ssh/runpod_tungsten \
  --remote-workspace /workspace \
  --local-destination ~/.tungsten/metaflip/cloud/POD_ID/final-UTC \
  --result-path results \
  --result-path cpu-results-445
```

The destination must not already exist. The guard polls the atomically written
status and checks the campaign process. At a terminal state it generates a
SHA-256 manifest on the pod, copies each configured tree into a fresh staging
directory, regenerates the remote manifest, requires both manifests to match,
and verifies every listed hash locally. Only after the verified staging tree
is published does it run exactly `runpodctl pod stop POD_ID`. It never deletes
or terminates a pod. An SSH, manifest, copy, stability, local-hash, or final
status error exits without invoking Runpod, leaving the pod and persistent disk
untouched. A still-running terminal process is permitted only when the two
source manifests prove a stable snapshot around the transfer.

Use `--dry-run` to validate and print the plan without contacting the pod, or
`--once` from an external scheduler to return 3 while a campaign remains
active. The mock regression exercises clean completion, terminal failure,
transfer corruption, an active campaign, and dry-run without cloud access:

```sh
bits/tungsten-metaflip/cloud/cuda/test_harvest_then_stop.sh
```
