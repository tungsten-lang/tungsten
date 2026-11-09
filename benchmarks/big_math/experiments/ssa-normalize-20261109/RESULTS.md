# SSA normalization/recomposition: completed isolated trial

The patch passed the focused exact arithmetic checks and produced a **small repeatable timing benefit** on the sampled Apple M5 Max SSA cells. It remains on `codex/ssa-normalize-recompose-20261109`; the shared Tungsten checkout was not edited or merged. Base is `f764abbd3906457b38dd6cfa9f64ddf0470d261b`. The experimental switch retains the exact old tail at zero and uses fusion at one. The runtime bytes were unchanged between both trials.

## Results

Ratios are geometric means of per-cell paired median candidate/baseline time. SSA and Toom groups use actual dispatch observations from the correctness binary; 12288 is below the dispatcher's unconditional 16384-limb transform gate. Smaller is better. Both multiply and square are included.

| Run | Timing | SSA cells | SSA time change | Toom controls | Control time change |
|---|---|---:|---:|---:|---:|
| Initial | 9 alternating rounds, 110 ms | 10 | -1.75485% | 10 | -0.60983% |
| Replication | 15 alternating rounds, 200 ms | 10 | -1.03222% | 4 | +0.21627% |

Each trial has nine of ten SSA cell medians below baseline. Neither trial has a cell-median regression above five percent. The strongest repeated pair is 24576 limbs (1572864 bits): multiply time falls 2.813% then 2.657%; square falls 3.300% then 3.216%. Other cells vary: multiply at 65536 limbs goes from -3.055% to +0.946%. These are same-host samples under normal background activity, not a universal gain, cross-machine qualification or reason to retune dispatch thresholds.

Full replication ratios (candidate/baseline):

| Limbs | Route | Multiply | Square |
|---:|---|---:|---:|
| 8192 | Toom | 1.002676 | 1.000733 |
| 16384 | SSA | 0.987150 | 0.995941 |
| 24576 | SSA | 0.973430 | 0.967837 |
| 32768 | SSA | 0.998347 | 0.992636 |
| 32769 | Toom | 0.995474 | 1.009820 |
| 65536 | SSA | 1.009456 | 0.988944 |
| 131072 | SSA | 0.995069 | 0.988624 |

Both runs rebuilt **byte-identical corresponding binaries**, despite using distinct temporary output directories:

- baseline: `e7925e7b932c4201719ecd4511639a478c2309713e163cdcbff2824256b26ad5`
- candidate: `72a69ddd833053326cf2894b3d05401c862959bc95be931eb7f518899e4e8c7c`

Compiler: Homebrew Clang 23.1.5; Apple M5 Max, 18 logical CPUs, AC power. Shared release flags: `-O3 -flto -ffast-math -DNDEBUG -mcpu=apple-m5 -falign-functions=64 -Wno-deprecated-declarations`. Only `BN_SSA_NORMALIZE_RECOMPOSE_FUSED=0/1` differs. Production worker settings are retained. The established `run_variant_ab.py` harness measures full boxed immutable C/runtime operations, includes GMP correctness and within-build timings, alternates variant order, and retains all samples and IQRs. This is not a language-driver/whole-application benchmark.

## Correctness and guard validation

Each version passed 556 direct SSA multiply/square cases against GMP and 96 boxed multiply/square fuzz cases (192 products per fuzz run), up to 131073 direct limbs and 65537 boxed limbs. Coverage includes zero/one/max/alternating/sparse/random limbs, ragged operands, transform boundaries, output canaries, preserved distinct inputs and in-place outputs. A complete product oracle is used, not just a forward/inverse round trip. No compiler or Core sources were changed; no bootstrap stage-identity claim is made.

Eleven memory-policy tests pass, including no launch under a simulated warning and rejection of unknown pressure or missing counters. Controlled child tests actually trip the RSS cap and timeout; their reports are separate from successful workload reports. A first build-helper attempt incorrectly required optional Oniguruma together with GMP; the helper now mirrors the established benchmark's optional Oniguruma handling and requires GMP. Its failed receipt is retained and was not a memory stop. All required builds, arithmetic checks and both benchmarks then pass.

## Revised memory policy

The process-tree cap remains **1 GiB sampled RSS**, with .1-second process sampling, 600-second timeouts, and the original PID/start-time/group ownership checks before termination. Only owned job processes may be terminated. The new shared system policy checks kernel pressure and swap at .5-second intervals and fails closed if telemetry is unavailable.

Estimated headroom equals immediate free + speculative + purgeable bytes, plus **half** of `max(0, min(inactive,file_backed) - speculative - purgeable)` pages. This is a discounted heuristic for reclaimable file-backed cache, not a claim that all inactive memory or every file page is immediately reclaimable. Anonymous inactive and compressed memory receive no independent credit. Subtracting speculative and purgeable pages from the candidate avoids adding their credit twice. The policy vetoes non-normal pressure, less than 512 MiB immediate headroom, less than 16 GiB estimated headroom, at least 256 MiB swap-use growth, or at least 64 MiB new swap writes since workload launch. Preflight requires three healthy samples above 18 GiB estimated headroom.

Userspace pressure constants 1/2/4 and the sysctl dispatch mapping were checked against Apple's XNU sources: [constants](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event_private.h), [mapping](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c). The earlier free-page-only guard remains preserved in commit `e72ead43c`; its idle wait was stopped after exact supervisor identity and absence of children were checked.

The initial benchmark peaked at **916.31 MiB** sampled tree RSS; replication at **913.34 MiB**, both below 1024 MiB. Lowest estimated headroom was about 20.66 GiB in the initial run and 27.59 GiB in replication. Kernel pressure stayed normal at sampled checks; swap-used and swapout counters remained zero. No workload resource stop occurred. These are sampled guard observations, not a hard OS resident-memory limit or a claim about historical system OOMs.

## Reproduce and disposition

`SOURCE.json` pins the runtime, checker, policy, guard and runner. `evidence/MANIFEST.json` authenticates exact saved receipts, timings, raw samples and failed attempts. `check-0`/`check-1` binaries remain outside Git under `/private/tmp/tungsten-ssa-normalize-20261109`; the A/B harness removes its temporary benchmark binaries after hashing them. There are no live experiment jobs left at completion.

From this isolated worktree, `/opt/homebrew/bin/python3.14 -B benchmarks/big_math/experiments/ssa-normalize-20261109/experiment.py` runs the first pipeline, and the same command with `--replicate` runs the longer trial. Each command authenticates the runtime, guard and memory-policy hashes and uses the shared preflight and guard; all checker/runner hashes were also matched when these results were frozen. Outputs are experiment-specific under `/private/tmp/tungsten-ssa-normalize-20261109`; attempt counters preserve earlier logs. The standalone focused policy/control commands and exact workload commands are retained in their guard reports. No parallel heavy run, Lean, Docker or full-history suite is required.

Disposition: retain the candidate and measured evidence on the isolated branch. The result supports a modest SSA-tail improvement on this host, strongest at the padded 24576-limb shape. Any production merge is a separate action; no automatic merge, install or threshold change occurred. Broader platform qualification is the next useful step if this is chosen for production, rather than another local microbenchmark round. New code/report prepared with OpenAI Codex assistance; original runtime/benchmark attribution remains intact.
