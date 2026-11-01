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
limit, not a strategy knob: it caps the *aggregate* conflicts across every
CDCL stage (the scout probe, the raw-kernel race, and the final solve), so no
stage can push the total past the requested budget. `--conflicts 0` is
unlimited; a positive budget that is exhausted returns `s UNKNOWN` (unless
preprocessing or root propagation decides the formula with no search conflict),
and the reported conflict count is the aggregate.

The main solver inspects variable, clause, literal, binary, ternary, and unit
counts. That policy chooses among raw or preprocessed kernels, bounded local
search, a CDCL probe, diversified raw-kernel arms, EVSIDS or VMTF branching,
target phases, trial-propagation lookahead, learned-clause vivification, and
database reduction. Policy selection is deterministic for a formula. Concurrent
races intentionally sample several search trajectories, however, so the winning
arm and wall time can vary with scheduling.

Selected local cores use append-only on-the-fly strengthening (OTFS). When CPU
and memory remain after the ordinary fast-mode workers are counted, the raw
race also adds one import-only OTFS specialist without replacing or publishing
into the established arms. OTFS never mutates a live reason clause and remains
disabled in proof modes.

Strict, bounded structural recognizers run before generic search when the
formula shape warrants them. One recognizes domains of 3--6 values
constrained by complete ternary Latin relations, finds a small generating
set, and searches only those seed domains while propagation determines the
rest. A generic exact-one block-CSP engine covers coloring, permutation,
and Hamiltonian-shaped encodings whose blocks carry complete at-most-one
sets. An arithmetic two-coloring lane extracts Van der Waerden, Schur,
Pythagorean, Ramsey, and Green--Tao scopes from the literal clauses,
verifies every scope's mathematical shape, and decides by exhaustive
bounded search -- no extremal constant is consulted, after a tally-based
predecessor was caught refuting satisfiable formulas. A generic
gate-circuit lane enumerates free inputs of any topologically ordered
two-input-gate network under a total gate-evaluation budget. SAT models
are checked against the original CNF; exact UNSAT answers remain fast-only
except where a lane names a witness variable set whose original-clause
star the proof solver then refutes on its own, emitting a checkable proof.

A bounded single-track Gray-code recognizer checks a sufficient subset of
original clauses: every column has a selected cyclic rotation of the first,
complete XOR definitions expose adjacent-bit flips, and each cyclic edge has
exactly one flip. All columns therefore have the same even flip count F, so
W words and B bits require W = B*F. A failure of divisibility by 2B gives a
counting refutation, with no instance-name or answer lookup. Missing rotation,
XOR, or exact-one clauses make recognition decline. This route is fast-only;
proof modes retain proof-producing CDCL. `WASSAT_GRAY_TRACK=0` disables it.
A cached-width admission check skips unrelated layouts before allocation.
The clause checks use fixed native arrays; profiling reports scanned clauses,
rotation relations, complete XOR gates, exact-one pairs, and candidate layouts.

For topologically numbered two-input circuits with a conjunction sink and
25–32 primary inputs, a bounded model search evaluates 64 neighboring input
assignments per word. Target weights, random two-bit neighbors, and restarts
help escape local maxima. It reuses native scratch arrays and accepts a model
only after checking every original clause; misses resume ordinary solving in
both fast and proof modes. The search stops at 16,384 batches, 134,217,728 gate
evaluations, or a polled 200 ms deadline, whichever comes first. Cancellation
and the deadline are checked every 32 batches. This is a bounded startup probe;
an admitted miss can add that work before the solving arms start. Profiling
reports batches, gate evaluations, best target count, and the stop reason.
`WASSAT_KLIEBER_LOCAL=0` disables this extension for comparisons. The existing
search for circuits with at most 24 primary inputs is unchanged.

A bounded matching-balance checker derives a graph from positive choice
clauses: each participating variable must occur in exactly two distinct rows.
It checks bipartiteness component by component, then verifies every original
negative binary needed to make each row in a candidate component exact-one.
A selected edge contributes once to each side, so unequal side counts give a
counting refutation. No board geometry or identifier layout is assumed.
Incomplete incidence or exclusions make recognition decline. This route is
fast-only; proof requests retain proof-producing CDCL. It uses fixed native
buffers, at most 4,096 variables and 50,000 clauses, rows of width at most 32,
and a polled 20 ms CLI deadline. Counters track rows, edges, components, side
sizes, clause visits, exclusion checks, and cancellation/deadline stops.
`WASSAT_MATCHING_BALANCE=0` disables it for comparisons.

A second model-only route groups small clauses by their variable support and
computes each block's exact forbidden truth table. Its Boolean algebraic
normal form can expose disjoint nonlinear variable pairs whose function is
shared across constraints. Those pair functions become linear coordinates;
packed Gaussian elimination over GF(2) finds a candidate, which is lifted
back to Boolean variables and checked against every original clause. This
route never reports UNSAT. It tolerates clause/literal ordering and identifier
changes; incompatible pair functions, higher-degree terms, or a failed model
check fall back to normal search. Limits are 1,024 Boolean variables,
32,768 clauses, 1,024 support blocks, and clause widths two through six;
the CLI only attempts maximum widths four through six, with a polled 50 ms
deadline. Fixed native buffers avoid per-row allocation. Counters track ANF
operations, elimination rows/words, rank, checked literals, and stop reasons.
`WASSAT_PAIR_AFFINE=0` disables it for comparisons.

A model-only arithmetic circuit route reconstructs up to three-input Boolean
truth tables, then uses 64-lane one-hot evaluations to infer equal-sum item
weights. A balanced greedy split and a bounded two-item exchange produce a
candidate; every original clause must pass before SAT is returned. Failure
or an unsupported circuit falls back to normal search, never UNSAT. It uses
input clauses, not instance names, stored weights, or answer tables. Numeric
variable order must provide a useful topological order; clause order can
affect heuristic recognition. A cheap primary-layout check skips unrelated
inputs. Limits are 512 primary inputs, 200,000 variables, 800,000 clauses,
30 output bits, a polled four-million-clause-visit limit, and a 50 ms CLI
deadline.
Fixed native buffers are reused across evaluations; the model is allocated
at its final size. Cancellation is checked during recognition, evaluation,
exchange search, and clause replay. `WASSAT_PARTITION_CIRCUIT=0` disables it.
Profiling reports clause visits, truth-table candidates, gate evaluations,
pair inserts/probes, checked clauses, candidate models, and the stop reason.

The native raw race also has a bounded exact circuit arm. It derives each
output's complete two-input truth table from all its defining CNF clauses,
then checks unit and wider assertions over every primary-input assignment in
64-assignment batches. Incomplete definitions reject the plan. It accepts at
most 24 inputs, 8,192 variables and 32,768 clauses, subject to a 134,217,728
batch-operation limit. Evaluation reuses fixed buffers and polls cancellation
between batches. Only exhaustive refutation publishes UNSAT; a surviving
assignment leaves the other arms running. This arm is fast-only and produces
no proof certificate. `WASSAT_SMALL_CIRCUIT=0` disables it for comparisons;
`WASSAT_PROFILE=1` reports its batches, gate evaluations, assertion checks,
stop reason, and elapsed time.

A separate model-only keychart arm derives four-depth key domains and lock OR
supports from the input CNF. It searches legal adjacent-depth choices, then
repairs near models with incremental CDCL assumptions on whole keys. Failed
cores release keys; auxiliary variables remain free. Additional constraints
are enforced by the original CNF solver and a complete model check. No stored
models, instance identifiers, or expected verdicts are used, and this lane
never publishes UNSAT. The walk caches exact move costs, reuses its buffers,
and polls cancellation every 16 moves. It first tries to repair a candidate
with at most two violated key/lock pairs. If that repair consumes 4,096
conflicts without a result, the walk uses its remaining move allowance to
seek a one-pair candidate. A reusable snapshot retains the first repair candidate
only when refinement starts. Refinement reuses the CDCL arena and learned clauses; a failed
refinement retains the earlier candidate and its expanded set of free keys.
The entire attempt uses at most 20,000 moves and 50,000 repair conflicts.
Repair also participates in the race's aggregate conflict budget.

The keychart arm preserves all baseline arms and requires a spare CPU and
room for another CDCL arena. It is disabled for explicitly rounded races and
for pinned `WASSAT_ARMS` runs unless `WASSAT_KEYCHART=1` opts in. Set
`WASSAT_KEYCHART=0` to disable it for comparisons. `WASSAT_PROFILE=1` reports
moves, candidate evaluations, violated pairs, weight updates, snapshots,
refinement attempts, repair queries, conflicts, cumulative key relaxations,
elapsed times, and cancellation. Recognition currently
accepts the ordered four-depth encoding with at most 64 keys, 64 locks,
16 positions, 50,000 variables and 100,000 clauses; other shapes use the
existing arms.

Lanes that used to hide behind the MDP recognizer's miss now live in their
own files (`sdp`, `backdoor`, `sgi`, `schooltt`, `symmetry_fix`, `vdwb`)
behind a fingerprint-gated registry in `lib/specialists.w`, which records
the winning lane's name in a `c lane:` line for per-lane accounting in the
SC2026 harness. The per-instance SAT backdoor tables in `lib/backdoor.w`
are measured (not assumed) value: `WASSAT_BACKDOOR_TABLES=0` disables
exactly them for on/off corpus comparison, per
`docs/backdoor-tables-audit-2026-10-27.md`.

Another recognizer accepts only a complete, topologically ordered 32-bit
xorshift/fold circuit: variables 1--32 are its sole inputs, every later
variable has the expected XOR/AND/OR definition, and exactly one accumulator
word is pinned by trailing units. Wassat reconstructs the exact sequence of
word XORs and ripple additions, then partitions the bounded 2^32 input
domain across native workers. This lane is model-only: a preimage is replayed
through every gate and checked against the original CNF before SAT publication,
while domain exhaustion publishes no verdict.

Additional model-only lanes recognize canonical fixed-width Fermat circuits;
the public 4--60-bit sum-of-three-cubes layout, under a strict operand,
eight-bit cube-anchor, and pinned-result signature; Bryant-style 8--36-bit
Minimum Disagreement Parity samples with their exact unary error counter;
synchronizing automata; edge-matching grids; and the compact 5x5
sliding-puzzle transition encoding. A further strict lane reconstructs compact
guarded-transition encodings for Stedman and Erin triples and searches their
induced Hamiltonian cycle. Two clean-room lanes construct Gardam's published
21-term Hantzsche--Wendt group-ring unit from the group law, and recover
distance-pruned knight-tour position/square supports before generating a tour
without a stored solution table. Sum-of-three-cubes searches non-negative
roots below 2048.
The lanes otherwise use bounded arithmetic, information-set decoding, or
combinatorial search, then construct or complete a Boolean assignment. A
structural miss or exhausted bound falls through; a hit is still published
only after the complete model satisfies the original DIMACS.
The MDP recognizer follows Randal E. Bryant's MIT-licensed public generator;
the complete license is retained in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Every SAT model is reconstructed after preprocessing and checked against the
original formula before it is printed.

Exit codes follow the SAT Competition convention, so a competition harness can
score a run without parsing its output: **10** for `s SATISFIABLE`, **20** for
`s UNSATISFIABLE`, **0** for anything else that is not an error (`s UNKNOWN`,
`help`, `version`), and **1** for a usage or input error. Every verdict path
obeys it — the serial solve, the scout, lucky, local-search and raw-kernel
race arms, a preprocessing refutation, `sls`, and both halves of `portfolio`.

## Input and artifact safety

The CLI accepts strict DIMACS CNF. It rejects malformed or duplicate headers,
wrong clause counts, unterminated clauses, non-integer tokens, overflowing
counts and literals, out-of-range variables, and native XNF/XOR syntax.

### DIMACS with XOR clauses

Use the explicit converter for CryptoMiniSat-style parity input:

```sh
wassat convert tensor.xcnf --out tensor.cnf
wassat tensor.cnf --proof tensor.wrat
wrat tensor.cnf tensor.wrat
```

The input header remains `p cnf V C`; `C` counts both ordinary and XOR
clauses. `x1 -2 3 0` and `x 1 -2 3 0` mean that the XOR of those signed
literals is true. Duplicate variables cancel, negative literals toggle the
parity, and a linear-size Tseitin chain introduces fresh variables after `V`.
Original variable IDs are preserved. `--out -` writes the expanded CNF to stdout.
The converter checks the whole input before atomically replacing its output,
and rejects output aliases of the source.

This is an interchange format, **not native Gaussian-elimination support**.
Solve and check refutations against the emitted CNF. A proof for that CNF must
not be handed to WRAT together with the unexpanded XOR input. General XNF and
OPB/pseudo-Boolean input are not supported by this converter.

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

Fast mode also races a CPU SLS specialist when the parsed task fits its
resident-memory policy. The ordinary ceiling is 256 MiB to protect the CDCL
arms from allocator and memory-bandwidth interference. A bounded automatic
exception keeps the specialist on dense few-variable kernels up to 288 MiB;
this is formula inspection, not a user-selected solver mode.

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

### Optional finite algebra obligations

`lib/algebra_certificate.w` is an opt-in bridge for arithmetic algorithms that
have already reduced a finite obligation to Boolean clauses. It supplies
`WassatFiniteBooleanProblem`, including linear-parity helpers, and proves an
entailed clause by running Wassat on its negation and replaying the resulting
WRAT proof through the independent `tungsten-wrat` checker.

```tungsten
use bits/tungsten-wassat/lib/algebra_certificate

problem = WassatFiniteBooleanProblem.new([:x, :y, :z])
problem.add_equations([[1, 1, 0], [0, 1, 1]], [0, 0])
x = problem.variable(:x)
z = problem.variable(:z)
certificate = problem.certify_clause([-x, z])
<< certificate.verified?
```

The certificate establishes only the exported Boolean consequence. The
arithmetic layer must separately certify that its number-field, local-image,
Galois-action, or Selmer data was encoded correctly. The bridge is therefore
not loaded by either `use wassat` or `use algebra`, and a WRAT refutation alone
is never presented as a descent or rank certificate.

## Verification and benchmarks

Competition-facing build/run wrappers, source-only staging, strict SAT-model
checks, and the DRAT-to-`cake_lpr` preflight are maintained in
[`competition/`](competition/README.md). The Main entrypoint writes ASCII DRAT
to the required `proof.out`; the Parallel entrypoint runs the trusted adaptive
fast path, including shared-memory races when the formula policy selects them.

The maintained system-description source is
[`docs/satcomp-system-description.md`](docs/satcomp-system-description.md).
Render its revision and line-count placeholders into the one- or two-page PDF
with:

```sh
python3 bits/tungsten-wassat/benchmarks/render_system_description.py
```

Formula-router experiments use paired same-binary interventions rather than
passive portfolio winners. The collector strips ambient `WASSAT_*` settings,
interleaves policies, verifies SAT models, records all repetitions, and assigns
families to deterministic disjoint splits. The labeler emits signed PAR-2
utility, and the compiled Koala trainer compares shallow trees, a small random
forest, linear SVC, logistic regression, and pure-L2 ElasticNet. Its pinned
31-feature ABI includes bounded exact-one coverage, binary occurrence-graph
sketches, and variable-occurrence concentration. It exports a standalone
Tungsten tree only when validation beats the conservative baseline:

```sh
python3 bits/tungsten-wassat/benchmarks/router_dataset.py \
  --dir /path/to/sc2026 --solver /path/to/wassat --out /tmp/router.jsonl \
  --policy sls_off:WASSAT_SLS_FLIPS=0 --policy baseline \
  --verdict sat --timeout 2 --reps 3
python3 bits/tungsten-wassat/benchmarks/router_labels.py /tmp/router.jsonl \
  --baseline sls_off --treatment baseline --out /tmp/router.csv
bin/tungsten -o /tmp/train-router \
  bits/tungsten-wassat/benchmarks/train_router.w
/tmp/train-router /tmp/router.csv /tmp/generated_router.w
```

The environment policies above are internal measurement interventions, not
solver modes. A failed export gate leaves the runtime policy unchanged.

The default repository spec gate builds a fresh Wassat CLI and runs all Wassat
specs, including the native parser, process portfolio, deadlines, atomic proof
publishing, randomized continuation agreement, compiled CLI smoke tests
(version/help, SAT models, WRAT/DRAT certificates, stdout proofs, malformed
input, the aggregate conflict budget), and independent proof replay. The
independent `tungsten-wrat` checker spec runs in the same gate:

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
and/or `LR5_41` to add frontier instances.  The suite always materializes
three pinned LRC(13) Goddyn--Wong terminal-lift CNFs (p=181, 223, 281) under
`/tmp`, checks their SHA-256 digests, and requires their known UNSAT verdicts.
When the official 2026 corpus is present, the dedicated xorshift lane checks
all eleven emitted models against the original DIMACS:

```sh
SATBENCH_2026=/path/to/2026-main WASSAT=/path/to/wassat \
  XORSHIFT_BUDGET=30 python3 bits/tungsten-wassat/benchmarks/reference.py
```
They exercise a structured certificate workload; they do not constitute an
LRC(13) proof.  No benchmark script assumes a specific checkout path.

## Current limits

Wassat supports incremental solving through assumption literals
(`solve_assuming` / `solve_assuming_budget`) over one persistent learned
database, with a failed-assumption core on UNSAT; it does not support
incremental clause addition/removal, nor native XOR/XNF input syntax. The
trusted fast path does recognize bounded CNF-rendered parity subsystems:
Gaussian elimination can refute an inconsistent subset or back-substitute a
candidate model, but SAT is published only after checking every original
clause. Proof portfolio workers do not share learned clauses, by design; the shared threaded
portfolio is trusted-only (`--fast`), and the implicit raw-kernel thread race
is enabled only after passing sustained fixed-capacity stress. GPU local
search currently uses Metal and is model-only.
