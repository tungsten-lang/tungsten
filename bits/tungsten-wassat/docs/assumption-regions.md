# Caching small regions for repeated assumption queries

For a proof-free incremental workload, a caller can identify variables that frequently occur in assumptions. Preparing a solver once can make subsequent queries cheaper when ordinary unit propagation misses implications at that interface.

```tungsten
use ../lib/assumption_regions

formula = wassat_parse_cnf_native("p cnf 4 4\n-1 2 3 4 0\n-1 2 3 -4 0\n-1 2 -3 4 0\n-1 2 -3 -4 0\n")
solver = wassat_region_query_solver(formula, [1])
conflict = solver.solve_assuming([1, -2])
model = solver.solve_assuming([-1, 3, -4])
```

Here, setting variable 1 true forces variable 2 true for every assignment to 3 and 4. The summary installs the clause `[-1, 2]`. A later query can assume any original variable, including 3 or 4. The same solver supports `solve_assuming_budget`, returns original-variable models and failed-assumption cores, and retains learned clauses across calls.

## What gets cached

Remove the caller's boundary from the formula's variable co-occurrence graph. Build the remaining connected components directly from the clause buffers using union-find. Each candidate region contains an entire interior component and every clause touching that component. A clause involving only boundary variables stays with the ordinary solver. Preparation considers interiors of up to six variables, local boundaries of up to four variables and up to 64 local clauses.

For each complete local boundary assignment, a 64-bit word records which assignments to the interior satisfy *all* the region's clauses. An empty word rules out the joint boundary assignment. A nonempty word can still force an interior variable if every surviving bit agrees on its value. Taking the union of two rows that differ on one boundary variable gives the exact witnesses with that variable unspecified.

The builder emits short clauses for minimal impossible boundary assignments and minimal conditions that force an interior literal. It tests local unit propagation to skip redundant work. CDCL keeps the original clauses and attaches the additional facts to its existing clause and watch storage. The tables are scratch space used during preparation. Subsequent queries use ordinary propagation and conflict analysis. Only the explicit factory enables this proof-free option.

## Local release measurements

The baseline was the raw `Wassat.from_flat` solver at local main `c64f49ee`. Both programs ran full `solve_assuming` queries on one persistent solver per batch. Each of 20 paired repetitions built a fresh solver, alternated arm order and used the same ordered query trace in both arms. End-to-end times include solver setup, summarization, clause attachment and all queries. Both programs read the CNF and trace before timing. Ratios below are medians of paired elapsed-time ratios. A ratio below 1 favors caching. Measurements are from a shared arm64 macOS host.

| Formula and query trace | Queries | Plain, ms | Cache, ms | Cache / plain |
|---|---:|---:|---:|---:|
| Hidden equality chain, 72 edges | 768 | 6.81 | 4.66 | 0.67 |
| Hidden equality chain, 48 edges, fresh seed | 768 | 4.65 | 3.31 | 0.70 |
| Hidden XOR gates, 96 gates | 512 | 11.97 | 9.85 | 0.85 |
| Hidden XOR gates, 48 gates, fresh seed | 512 | 6.67 | 5.86 | 0.90 |
| Hidden XOR gates, 29 gates | 512 | 4.45 | 4.19 | 0.93 |
| Direct equality / direct XOR controls | 768 / 512 | 1.82 / 3.30 | 1.84 / 3.35 | 0.99 / 1.02 |
| Standard ripple adder, 32 / 64 / 96 bits, mixed queries | 1,024 each | 7.85 / 11.95 / 16.07 | 7.71 / 11.89 / 16.06 | 0.98 / 1.00 / 0.97 |
| Standard ripple adder, 32 / 96 bits, carry queries | 384 / 1,152 | 1.92 / 12.64 | 2.17 / 12.84 | 1.10 / 1.04 |
| Public 15-bit multiplier miter, 30 / 25 signed operand bits | 256 each | 72.22 / 262.99 | 74.89 / 275.43 | 1.05 / 1.02 |

The hidden fixtures expand each relation clause across all four polarities of two free interior variables. Their direct controls expose the same relation immediately. On hidden equality and XOR, preparation paid for itself within eight queries in every tested size. In a second comparison using one binary for both modes, summarization plus attachment took a median 47 µs for the 72-edge chain (144 facts), 87 µs for 96 XOR gates (384 facts), and about 1.8–1.9 ms for the public multiplier (386 facts). The two direct controls produced zero facts. So did random500, factorize-1022117 and clique_n2_k10. Time differences on those three varied between runs.

The multiplier used `multiplier_15bits__miter_23--539a1f4e4f7a.cnf`, with the top third of variables by occurrence as its cut and generated queries on the primary operands. The adder tests used conventional XOR, AND and OR gate clauses. All query traces were generated. No production traffic or competition solve scores were measured.

For each arm, every SAT model was checked against the original clauses and assumptions. CaDiCaL checked all 10,240 query verdicts and independently replayed all 4,138 failed cores per arm. Separately, exhaustive enumeration checked the emitted clauses on 500 additional small formulas over 97,208 complete assignments.

## Reproducing a comparison

From the repository root, build the benchmark once and supply the same trace to both modes.

```sh
bench=bits/tungsten-wassat/benchmarks
bin/tungsten -o /tmp/region-bench --release "$bench/assumption_regions.w"
python3 "$bench/assumption_region_fixture.py" /tmp/region-chain --hidden
/tmp/region-bench plain /tmp/region-chain/formula.cnf /tmp/region-chain/queries.txt
/tmp/region-bench regions /tmp/region-chain/formula.cnf /tmp/region-chain/queries.txt
```

Omit `--hidden` for the direct control. For the 96-gate XOR case, add `--family xor --size 96 --queries 512 --seed 41`. The held-out chain used size 48 and seed 812. The held-out XOR used size 48 and seed 457 with 512 queries. The first line of a trace contains the boundary variable IDs. Each subsequent line contains the signed assumptions for one query. Terminate each line with `0`. The driver reports setup, summary and attachment time separately, plus setup-inclusive totals at 1, 8, 64, 256 and the final query count.
