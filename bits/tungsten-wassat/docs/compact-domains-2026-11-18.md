# Recovering the finite-domain structure of frb35-17-5

The SC2025 input has 175 Boolean variables and 14,577 clauses. Its 140 binary
clauses split the variables into 35 connected components of five bits each.
Within a component a distinguished bit, when set, forces the other four
clear. That leaves 17 assignments. Each remaining clause mentions at most
two components. It excludes precisely the product of the assignments on
which its literals in each component are false. The full translation has
23,461 distinct forbidden pairs.

Wassat recovers the components by variable incidence and enumerates their
legal assignments. The same table representation supports signed one-hot
choices. The existing minimum-remaining-values search took 2,907 nodes on
the original input. Three variable-renamed and sign-flipped versions reached
the 10,000-node budget. Applying Wassat's existing tabu search to their
decoded tables recovered a model in each case. The original competition
model checker accepted every model, including a signed one-hot re-encoding.

| Input | Previous Wassat | New Wassat | Verification |
|---|---:|---:|---|
| SC2025 original, seven alternating fast-mode pairs | 0.4214 s median | 0.0126 s median | All 14 complete models |
| Original, LRAT mode | — | 0.0148 s | Complete model |
| Three sign-flipped and renamed inputs | — | 0.018–0.057 s | Three complete models |
| Signed one-hot re-encoding | — | 0.050 s | Complete model |

Both fast-mode binaries solved the original. Measurements include model
printing and exclude independent replay. Absolute wall time varied with
host load. The existing ordinary one-hot and subgraph-isomorphism solvers
remain relevant on the other inspected inputs. In particular, the original
SGI instance has twenty signed rows of width 30 and already receives a
trusted UNSAT result from Wassat's graph specialist. The new model path
handles at most 24 values per group.
[Paired observations](../../../build/wassat-pattern-domains-20261118/final-pairs.json) ·
[Variants](../../../build/wassat-pattern-domains-20261118/final-variants.json) ·
[Translation study](../../../build/wassat-pattern-domains-20261118/pilot.log)

## Signed competition inputs

Of 800 SC2025 and SC2026 entries, 252 passed the broad input-size filter.
Eight reached the initial finite-domain search. Five of those entries have
binary exclusions that match colors across shuffled rows. Aligning those
colors gives a short, independently checkable capacity refutation. The other
three have satisfying assignments.
[Admission survey](../../../build/wassat-pattern-domains-20261118/all-admissions.json) ·
[Capacity certificates](polynomial-clique-capacity-certificate-2026-11-17.md)

SC2025 `case20.normalised` and SC2026 `rbsat-v945c61409gyes9` each have 45
signed domains of 21 values. A single tabu trajectory found the latter after
10,043 moves but spent 300,000 moves on the former with one conflict remaining
at its best point. A bounded exact repair around incumbent assignments missed
both in the tested configurations. A second tabu trajectory found the SC2025
model after 40,356 moves. On one core Wassat allocates 25,000 moves to the
first start and 75,000 to the second. On multiple cores their read-only tables
are shared, each start has private search state and up to 100,000 moves, and
the first model cancels the other search. Both policies use a 150 ms wall
deadline. The seeds were selected using the two competition inputs and a
signed re-encoding.
[Seed measurements](../../../build/wassat-pattern-domains-20261118/actual-seeds.log) ·
[Repair experiment](../../../build/wassat-pattern-domains-20261118/repair-series.log)

In five alternating pairs, SC2025 `case20` took 0.118 s median with the
qualified release and 1.151 s on the pre-domain release. All ten complete models passed
the original checker. The initial single-trajectory candidate had regressed
from 0.326 to 0.485 s in a separate series. On SC2026 `rbsat` the final
candidate returned five checked models with a 0.050 s median. The second
baseline attempt exceeded four seconds, at which point baseline timing stopped.
[Initial pairs](../../../build/wassat-pattern-domains-20261118/wassat-capacity-signed-pairs.json) ·
[Final pairs](../../../build/wassat-sc2025-qualified-20261118/wassat-signed-pairs.json)

Eight permutations per source changed variable names, polarities, clause order
and literal order. The single-start prototype and the final specialist found
2 and 3 models on the eight `case20` permutations, 0 and 2 on `rbsat`, and
7 and 7 on `frb35`. The final specialist retained all nine earlier hits. Each
count is a first-stage result before fallback to CDCL. A serial two-start
prototype lost two `case20` hits by cutting the first run short. The multicore
release subsequently solved both using the ordinary CLI, three times each.
[Permutation study](../../../build/wassat-specialists-parallel-20261118/holdout.json) ·
[CLI replay and sequential controls](../../../build/wassat-specialists-parallel-20261118/direct.json)
