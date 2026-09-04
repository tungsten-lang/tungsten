# Item 22: a run manifest, not another package manager

Proposal. Give every experiment a self-contained run directory containing the
manifest, outputs and verification evidence. Notes opens that directory and
renders its manifest; CLI/headless users can inspect the same files.

Suggested surface:

```w
run = Experiment.start("heat-diffusion", seed: 42)
run.input("grid", "input/grid.h5")
run.context("units", lab)
run.measure("solver_seconds", elapsed, unit: "s")
run.artifact("temperature", "result.h5")
run.finish(status: :succeeded)
```

These methods are proposed, not existing APIs. Start with an external recorder
around an argv-only command before introducing the W facade. It captures a
manifest even for nonzero exit, signal, timeout, or missing outputs. A run that
exits successfully but fails an output verifier must not be marked verified.

Manifest version 1 fields:

- run ID, label, start/end timestamps, status and command argv/cwd;
- compiler binary SHA-256, runtime archive hash, target, CPU flags, math mode,
  source revision plus dirty-diff hash and the actual source/input file hashes;
- dependency lock digest, optional-library versions, declared environment
  allowlist and explicitly configured seed/PRNG algorithm;
- machine/OS/backend/device identity and thread count;
- units/calibration contexts by digest, precision/tolerances and stopping rules;
- output paths, media types, sizes/hashes, measurements with units;
- verifier command/version, exact evidence hashes, result and stated scope.

A seed does not prove determinism. Distinguish bitwise replay, tolerance-based
numerical replay and an unreproducible/unknown run. Record all paired benchmark
samples, warmups, input corpus and comparison baseline; do not publish a ratio
without the comparator's manifest. Timing and verification remain separate.

Only include explicitly declared environment variables; never dump the whole
environment. Relative paths are resolved inside the run directory, with external
inputs copied or identified by hash and a documented retrieval requirement.
`finish` writes the terminal manifest atomically. A missing terminal record is
interrupted/unknown, never silently successful.

Reuse the existing `gpu-bench` reproducibility fields and the experiment JSON
records in this branch. First delivery should wrap the Notes numerical example,
with a local bundle that another clean checkout can verify. Package publishing,
remote uploads and canonical research ledgers remain separate user actions.
