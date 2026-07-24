# Tungsten Wassat

Wassat is a native CDCL SAT solver written in Tungsten. It can return fast
trusted answers or emit independently checkable WRAT, LRAT, and DRAT
refutations. [`tungsten-wrat`](../tungsten-wrat) deliberately has its own
DIMACS parser and proof checker, so it does not share Wassat's trust boundary.

Wassat 0.1 selects its search policy automatically from the parsed formula.
There are no environment-variable or command-line switches for choosing
branching, restart, probing, vivification, or portfolio-arm strategies.

## Build

From the repository root:

```sh
bin/tungsten compile bits/tungsten-wassat/bin/wassat.w \
  --out bits/tungsten-wassat/bin/wassat --release --lto --fast
```

The binary's complete command reference is available through:

```sh
bits/tungsten-wassat/bin/wassat help
```

## Solve

An explicit answer contract is required:

```sh
wassat problem.cnf --fast
wassat problem.cnf --fast --conflicts 100000
wassat problem.cnf --proof out.wrat
wassat problem.cnf --lrat out.lrat
wassat problem.cnf --drat out.drat
wassat problem.cnf --proof out.wrat --drat out.drat
```

`--fast` enables the full trusted engine. Proof modes use only transformations
whose certificate obligations are implemented. `--conflicts` is a resource
limit, not a strategy knob; exhaustion returns `s UNKNOWN`.

The main solver inspects variable, clause, literal, binary, ternary, and unit
counts. That policy chooses among raw or preprocessed kernels, bounded local
search, a CDCL probe, diversified raw-kernel arms, EVSIDS or VMTF branching,
target phases, trial-propagation lookahead, learned-clause vivification, and
database reduction. The choice is deterministic for a formula, so repeated
runs remain reproducible.

Every SAT model is reconstructed after preprocessing and checked against the
original formula before it is printed.

## Input and artifact safety

The CLI accepts strict DIMACS CNF. It rejects malformed or duplicate headers,
wrong clause counts, unterminated clauses, non-integer tokens, overflowing
counts and literals, out-of-range variables, and native XNF/XOR syntax.

Certificate destinations never alias the input or each other, including
symlink and hardlink aliases. A stale final certificate is removed before a
run. Search writes to a unique temporary file beside the destination; only a
completed UNSAT proof is flushed, renamed into place, and followed by a parent
directory flush. SAT, UNKNOWN, and malformed input leave no final proof.

Proofs written to `-` go to stdout; status and model text then go to stderr so
the proof stream stays standalone.

## Proofs

- `--proof` emits WRAT with a `wrat 1` header.
- `--lrat` emits the same hinted body without the WRAT header.
- `--drat` emits plain DRAT.
- Requesting WRAT/LRAT and DRAT together emits both streams in lockstep.

Hinted search steps record antecedents from the first-UIP conflict cone in
dependency order. Preprocessing additions carry their own RUP chains.
Deletions use clause IDs in the hinted stream and literal content in DRAT.

The trimmer validates the entire hinted grammar before pruning:

```sh
wassat trim full.wrat --out core.wrat
wassat trim full.wrat --out core.wrat --drat core.drat
```

It rejects malformed headers, IDs, terminators, duplicate additions, and
forward derived-step citations. Its output is still untrusted and should be
checked independently.

Clause-label sidecars can narrate a trimmed core:

```sh
wassat explain core.wrat --labels problem.labels
```

Each nonblank labels line must be `<positive-clause-id><tab><label>`. Missing,
zero, malformed, and duplicate IDs are errors.

## Portfolio

Proof mode preprocesses once, starts isolated worker processes over one reduced
artifact, and atomically stream-splices the winning proof onto the
preprocessing prefix:

```sh
wassat portfolio problem.cnf --proof out.wrat
wassat portfolio problem.cnf --proof out.wrat --timeout-ms 60000
wassat portfolio problem.cnf --proof out.wrat --dir /path/to/work-parent
```

The default deadline is 300,000 ms. A deadline returns `s UNKNOWN`, terminates
workers, removes partial proofs, and cleans the unique run directory.

Trusted portfolio mode uses in-process CDCL arms with learned-clause sharing:

```sh
wassat portfolio problem.cnf --fast --threads 4
wassat portfolio problem.cnf --fast --threads 4 --no-share
wassat portfolio problem.cnf --fast --threads 4 --gpu
```

The GPU arm returns models only and is therefore available only with `--fast`.

## Stochastic local search

The standalone CCAnr-family engine returns SAT or UNKNOWN, never UNSAT:

```sh
wassat sls problem.cnf --flips 10000000 --seed 1
wassat sls problem.cnf --flips 10000000 --seed 1 --pre
wassat sls problem.cnf --gpu --flips 10000000 --seed 1 \
  --walkers 256 --noise 48
```

`--walkers` and `--noise` are rejected without `--gpu`. The GPU executes the
exact requested flip bound, including a final partial dispatch and zero flips.
Every reported model passes the original-formula check.

## Library API

```tungsten
use wassat

formula = wassat_parse_cnf(read_file("problem.cnf"))
solver = Wassat.new(
  formula["nvars"], formula["clauses"], WASSAT_PROOF_DRAT
)

result = solver.solve_budget(10000)
result = solver.solve_budget(10000) if result["status"] == 0
result = solver.solve_budget(0) if result["status"] == 0
```

Status is `1` for SAT, `-1` for UNSAT, and `0` for UNKNOWN. A positive budget
means additional conflicts for that call. Continuation preserves learned
clauses, activities, restarts, reductions, and the hidden proof prefix.

`solve_assuming` and `solve_assuming_budget` implement fresh MiniSat-style
queries over one learned database. UNSAT-under-assumptions includes a failed
assumption core. Zero and out-of-range literals are rejected before solver
arrays are accessed. When preprocessing is used, assumed variables must be
frozen before preprocessing or survive it unchanged:

```tungsten
pre = WassatPreprocess.new(nvars, clauses, WASSAT_PROOF_NONE)
pre.freeze(variable)
artifact = pre.run
wassat_check_assumptions(artifact, assumptions)
```

Internal typed-array access in hot propagation and analysis loops remains
unchecked for performance; public assumption and phase-seeding boundaries
validate their literals.

## Verification and benchmarks

The default repository spec gate builds a fresh Wassat CLI and runs all Wassat
specs, including the native parser, process portfolio, deadlines, atomic proof
publishing, randomized continuation agreement, and independent proof replay:

```sh
scripts/test-specs.sh
```

For randomized comparison with CaDiCaL, every generated UNSAT case must also
pass the separately built `tungsten-wrat` checker:

```sh
CASES=300 WASSAT=/path/to/wassat WRAT=/path/to/wrat \
  CADICAL=/path/to/cadical python3 bits/tungsten-wassat/benchmarks/differential.py
```

The portable performance corpus is generated locally:

```sh
python3 bits/tungsten-wassat/benchmarks/gen_instances.py /tmp/satbench
BENCH=/tmp/satbench WASSAT=/path/to/wassat \
  python3 bits/tungsten-wassat/benchmarks/reference.py
```

Set `SATLIB_ROOT` to add the optional SATLIB parity families. Set `LR5_37`
and/or `LR5_41` to add frontier instances. No benchmark script assumes a
specific checkout path.

## Current limits

Wassat does not support incremental clause addition/removal or native XOR/XNF
reasoning. Proof portfolio workers do not share learned clauses, by design;
the shared threaded portfolio is trusted-only. GPU local search currently
uses Metal and is model-only.
