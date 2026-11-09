# SSA normalization/recomposition experiment

Base: f764abbd3906457b38dd6cfa9f64ddf0470d261b. Isolated branch codex/ssa-normalize-recompose-20261109. Shared dirty checkout is preserved. The draft combines coefficient normalization and recomposition, skips discarded padding, and retains the previous body at BN_SSA_NORMALIZE_RECOMPOSE_FUSED=0 for same-source A/B builds. The default on this experimental branch is 1; no main promotion is authorized by this experiment.

- [x] Create clean isolated worktree and apply the draft.
- [x] Preserve the exact old SSA tail as the baseline knob.
- [x] Prepare the focused GMP harness and start the reserve-waiting supervisor.
- [x] Replace the narrow free-page policy with conservative reclaim credit and pressure/swap vetoes, at the user's request. Eleven policy checks and actual cap/timeout controls pass.
- [x] Admit launch only after three normal-pressure samples with at least 18 GiB estimated headroom.
- [x] Build focused release correctness harness for baseline and candidate serially.
- [x] Compare direct SSA and boxed multiply/square results against GMP, with zero, one, max, alternating, sparse and random limbs; ragged sizes; transform boundaries; output canaries and unchanged input checks.
- [x] Run existing boxed GMP differential fuzz on both variants.
- [x] Run release alternating baseline/candidate whole-operation benchmark, at least nine rounds x 110 ms; include Toom controls and SSA boundaries. Keep production worker policy.
- [x] Record dispatch eligibility, compiler/CPU/flags, binary/source hashes, raw samples, spread, memory guards, and any stopped jobs.
- [x] Summarize the outcome; leave the experiment isolated.

Every build/test/benchmark uses the identity-safe process-tree guard: unchanged 1 GiB sampled RSS cap, .1-second process sampling and 600-second timeout. The user authorized pressure-aware reclaim accounting: immediate free/speculative/purgeable pages plus half a bounded file-backed candidate pool, never anonymous inactive or compressed pages. Require kernel pressure normal, at least 512 MiB immediate pages, at least 16 GiB estimated headroom, less than 256 MiB new swap use and less than 64 MiB new swap writes per workload. System telemetry is checked every .5 seconds and fails closed. The shared preflight requires three samples above 18 GiB estimated headroom; reserve stops do not count as mathematical failures and do not authorize killing unrelated jobs. No compiler/core source changes or full bootstrap are required for this runtime-only experiment. No OOM absence, stage-identity or performance claim is made before results exist.

The old waiting supervisor (session 91570, PID 27393, exact start-time/command checked) was stopped while idle. Its log and state are preserved under `/private/tmp/tungsten-ssa-normalize-20261109/legacy-wait/`. The revised supervisor is unified exec session 50227; state/receipts remain `/private/tmp/tungsten-ssa-normalize-20261109/STATUS.json`, log `/private/tmp/tungsten-ssa-normalize-20261109-supervisor-pressure-v1.log`. It retries only system headroom/pressure/swap stops, then waits for recovery; telemetry failures, process-cap stops, timeouts and ordinary failures remain terminal. Do not start another copy while it is live.

Pressure values are userspace dispatch constants 1=normal, 2=warning, 4=critical, not the internal XNU enum: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event_private.h and https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c . Cache credit is our deliberately discounted estimate, not an Apple MemAvailable guarantee. The guard remains sampled, not an OS hard resident-memory limit.

Completed both trials and source-bound evidence at `RESULTS.md`. Sessions 14534 (initial pipeline) and 48015 (replication) completed successfully. The prior 50227 setup attempt failed on optional package discovery and is retained. No supervisor remains live; the earlier live-session paragraph is historical context.
