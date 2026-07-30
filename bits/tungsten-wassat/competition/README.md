# Wassat competition packaging

These wrappers turn a Tungsten source checkout into the two execution shapes
used by the SAT Competition. They do not change solver policy.

The contracts are pinned to the published 2026 infrastructure, which is the
best available preflight target for a future competition:

- [NHR submission instructions](https://satcompetition.github.io/2026/nhr.html)
  require top-level `build.sh` and `run.sh`; `run.sh` receives the CNF as `$1`
  and a proof directory as `$2`.
- [Competition output](https://satcompetition.github.io/2026/output.html)
  requires exactly one `s` line, SAT value lines of at most 4096 characters,
  a final model terminator `0`, and Main-track `proof.out`.
- [AWS submission instructions](https://satcompetition.github.io/2026/aws.html)
  use a Dockerfile plus `solver_cmd.py`; the official package runs local and
  AWS acceptance tests against the same image.

## Entry points

`build.sh` takes no arguments. It bootstraps Tungsten from source when needed
and builds a release/LTO `wassat` binary beside the script. It needs clang,
LLD, and make, but no Ruby or zstd development package: the bootstrap and final
solver use raw string slabs, with optional zstd support deterministically
disabled. No dependency is downloaded.

`run-main.sh INSTANCE PROOF_DIRECTORY` runs the proof-covered sequential
solver and writes ASCII DRAT to `PROOF_DIRECTORY/proof.out`.

`run-parallel.sh INSTANCE` runs the trusted adaptive fast path. Formula
inspection selects among cheap scouts, preprocessing, exact recognizers,
local search, and shared-memory CDCL races. Keeping this policy inside Wassat
also preserves fast structure-specific solutions that an unconditional
preprocess-then-portfolio wrapper can erase.

Both entry points preserve SAT Competition exit codes: 10 for SAT, 20 for
UNSAT, and 0 for UNKNOWN. The solver itself verifies every winning SAT model
against the original CNF and renders value lines within the 4096-character
limit.

## Local preflight

The default preflight generates a 1500-variable SAT formula (large enough to
exercise split value lines) and a small pigeonhole UNSAT formula. It builds the
binary, runs both entry points on both formulas, checks status lines, exit
codes, model syntax and semantics, and verifies Main's ASCII DRAT:

```sh
DRAT_TRIM=/path/to/drat-trim \
CAKE_LPR=/path/to/cake_lpr \
bits/tungsten-wassat/competition/preflight.sh
```

`drat-trim` is mandatory. When `cake_lpr` is available, the preflight also
uses the official `drat-trim -L` conversion followed by the formally verified
checker. To spot-check downloaded official instances instead:

```sh
bits/tungsten-wassat/competition/preflight.sh \
  --sat /path/to/known-sat.cnf \
  --unsat /path/to/known-unsat.cnf
```

This is a host-local check. It must not be described as Linux, NHR-container,
or AWS validation unless those environments were actually run.

## Corpora and benchmark contribution

The complete published SC2026 Main corpus is external test data. The local
developer copy normally lives at
`/Users/erik/benchmarks/satcompetition/2026-main`; it is neither staged nor
submitted with Wassat. Fetch and verify all 400 hash-identified instances with:

```sh
python3 bits/tungsten-wassat/benchmarks/sc2026.py fetch --all \
  --dir /Users/erik/benchmarks/satcompetition/2026-main
python3 bits/tungsten-wassat/benchmarks/sc2026.py verify \
  --dir /Users/erik/benchmarks/satcompetition/2026-main
```

Add `--deep` to the verification command to stream all 25.9 GB and validate
every DIMACS token, bound, clause terminator, and declared count. The current
local corpus passes that full check: 400 files (191 SAT, 163 UNSAT, and 46
without a single published field verdict).

Future SC2027 evaluation instances are not available before the organizers
select them, so SC2026 is regression evidence rather than a preview of that
test set.

The Main-track benchmark contribution is a separate entry requirement. Under
the [published 2026 benchmark rules](https://satcompetition.github.io/2026/benchmarks.html),
a team supplies 20 CNFs never used in an earlier competition; at least 10 must
take MiniSat more than 60 seconds while Wassat solves them within 3600 seconds.
Each family also needs a 1-2 page IEEE Proceedings-style source/generation
description. Existing public corpora and Wassat's reference CNFs do not meet
this new-benchmark obligation.

## Staging

From a clean, committed checkout:

```sh
bits/tungsten-wassat/competition/stage.sh main /tmp/wassat-main
bits/tungsten-wassat/competition/stage.sh parallel /tmp/wassat-parallel
```

Each destination receives source files only, top-level `build.sh`, the selected
top-level `run.sh`, both named entrypoints, and `SOURCE_STATE.txt`. The
parallel stage also receives the AWS `solver_cmd.py` template. Staging refuses
a dirty source tree by default; `WASSAT_STAGE_ALLOW_DIRTY=1` is reserved for
local packaging tests.

[`aws/Dockerfile`](aws/Dockerfile) is a 2026 infrastructure template. It
requires an explicit immutable `WASSAT_REVISION`, clones that public revision,
stages the Parallel package under `/wassat`, builds it, and installs
`solver_cmd.py`. A current uncommitted worktree cannot supply that revision.
The template has not been built here because the local Docker daemon is down;
do not describe it as accepted. Once a public revision is pinned, run the
official `satcomp.py build`, `test-local`, and `acceptance-test`.
