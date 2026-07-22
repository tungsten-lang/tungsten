# Tungsten Wassat

Wassat is a compact CDCL SAT solver written in pure Tungsten. It can emit a
raw DRAT refutation during search or a hinted WRAT refutation for independent
checking by [`tungsten-wrat`](../tungsten-wrat). The checker deliberately
shares no parser or solver code with Wassat.

Wassat is currently an experimental solver and proof-portfolio member, not a
replacement for CaDiCaL or Metaflip's specialized `ffcdcl` backend.

## Build and use

From this directory:

```sh
../../bin/tungsten compile bin/wassat.w --out bin/wassat --release --lto --fast

bin/wassat problem.cnf
bin/wassat problem.cnf --conflicts 100000
bin/wassat problem.cnf --drat out.drat
bin/wassat problem.cnf --proof out.wrat
bin/wassat problem.cnf --proof out.wrat --drat out.drat
```

`--conflicts n` returns `s UNKNOWN` if the bounded search has not finished.
`--lookahead n` scores up to `n` candidate variables by trial propagation
before each decision. Lookahead is useful on some random and pigeonhole
instances but has hurt the structured tensor encodings tested so far, so the
default is zero.

The command accepts strict DIMACS CNF only. It validates the header, variable
bounds, clause count, clause terminators, and all tokens. Native XNF/XOR input
is rejected explicitly rather than interpreted as CNF. Certificate files are
cleared before a run, so SAT, UNKNOWN, malformed input, or interruption cannot
leave a stale proof masquerading as the current result.

## Proof modes

- `--drat` is the inexpensive search mode. It records learned RUP clauses
  directly and can be checked by `tungsten-wrat`, `drat-trim`, and compatible
  DRAT tools.
- `--proof` emits WRAT with explicit unit-propagation hint chains. The hints
  make checking predictable, but generating them replays propagation for each
  learned clause and is much more expensive on large searches.
- Requesting both performs the hinted search and derives DRAT from the same
  proof. Use raw DRAT alone for large campaigns.

On the open ψ-quotient tensor cells, a 1,000-conflict trial took about 0.07 s
with proof logging off or raw DRAT enabled, versus 7.3 s with hinted WRAT.
Hinted mode is therefore intended for small instances and final offline work,
not routine search.

## Library API

```tungsten
use wassat

result = wassat_solve_mode_limited(
  read_file("problem.cnf"), WASSAT_PROOF_DRAT, 0, 100000
)

if result["status"] == 1
  << "SAT"
elsif result["status"] == -1
  write_file("out.drat", wassat_drat_text(result))
else
  << "UNKNOWN"
```

`status` is `1` for SAT, `-1` for UNSAT, and `0` for UNKNOWN. Results also
contain `sat`, `unsat`, `complete`, `model`, `proof`, `drat`, `proof_mode`,
`conflicts`, and `decisions`.

The one-shot wrappers parse and construct a new solver each time. For genuine
continuation, parse once, construct `Wassat`, and call `solve_budget` repeatedly:

```tungsten
formula = wassat_parse_cnf(read_file("problem.cnf"))
solver = Wassat.new(
  formula["nvars"], formula["clauses"], WASSAT_PROOF_DRAT, 0
)

result = solver.solve_budget(10000) # up to 10,000 additional conflicts
result = solver.solve_budget(10000) if result["status"] == 0
result = solver.solve_budget(0) if result["status"] == 0 # finish without a cap
```

A positive budget is additional work for that call. UNKNOWN retains the trail,
learned database, restart/reduction cadence, branching state, and hidden proof
prefix. Terminal calls are idempotent, and returned result arrays are detached
from later continuation.

## Search engine

The core uses flat typed `i64[]` storage, an arena clause database, intrusive
two-watched-literal lists with blockers, first-UIP learning, non-chronological
backjumping, phase saving, integer EVSIDS in a max heap, LBD-based learned
clause reduction, and scheduled restarts. Every variable newly encountered in
the conflict graph is bumped; the former implementation accidentally left all
activities at zero and silently used variable order as its branching policy.

## Current Metaflip standing

The native solver was tested against the four still-open rank-17
ψ-symmetric `<2,5,2>` cells with 20,000-conflict caps:

| cell `(pairs,fixed)` | Wassat decisions | Wassat wall | `ffcdcl` decisions | `ffcdcl` solve |
|---|---:|---:|---:|---:|
| `(7,3)` | 37,807 | 0.74–0.78 s | 35,130 | 0.53–0.54 s |
| `(6,5)` | 38,418 | 0.68 s | 36,323 | 0.52–0.55 s |
| `(5,7)` | 37,069 | 0.60–0.62 s | 34,878 | 0.42–0.43 s |
| `(4,9)` | 37,933 | 0.64–0.65 s | 36,496 | 0.41–0.42 s |

The Wassat number includes process startup and DIMACS parsing; the `ffcdcl`
measurement is solve-only, so the table is useful but not perfectly
like-for-like. Wassat is roughly 1.2–1.6× slower here and makes 4–7% more
decisions. It is close enough to provide independent solver diversity, while
`ffcdcl` remains the correct default.

Wassat also independently re-solved the already-known `(3,11)` cell as UNSAT
in 568,284 conflicts and 751,899 decisions (27.5 s without logging, 29.4 s
with raw DRAT). `drat-trim` verified the complete proof and a trimmed proof.
This is an independent certificate and performance result, not a new tensor
rank bound: that ψ cell had already been closed by CryptoMiniSat.

The new EVSIDS policy improves the intended ψ workload materially, but it
regresses the unusually favorable static ordering on pigeonhole formulas.
For example, PHP(9,8) now takes about 35,872 conflicts rather than 7,133 under
the accidental near-static policy. `--lookahead 16` reduces that to about
1,151 conflicts, but remains opt-in because its trial propagations hurt the ψ
encodings.

## Correctness and reproduction

```sh
../../bin/tungsten spec/solver_spec.w
../../bin/tungsten spec/cli_spec.w

# Requires CaDiCaL; verifies each UNSAT proof when tungsten-wrat is built.
CASES=300 python3 benchmarks/differential.py

python3 benchmarks/gen_instances.py /tmp/satbench
BENCH=/tmp/satbench python3 benchmarks/bench.py
```

Current coverage includes 36 solver specs, six CLI specs, a
300-instance differential run with zero disagreement and 152 independently
checked UNSAT proofs, a separate 1,200-formula brute-force audit, and proof
checks after learned-clause deletion and resumed conflict budgets. SAT models
are evaluated against their original clauses.

## Limitations

Wassat does not yet provide assumptions, failed-assumption cores, incremental
formula mutation, native XOR/XNF reasoning, or a tensor-specific branching
interface. Those are the main prerequisites before considering it as more than
an independent Metaflip proof lane. Contiguous per-literal watcher vectors are
also a likely performance improvement over the current intrusive lists.

Version 0.0.1.
