# Does DETOUR have anything to give wassat?

**Reviewed:** 2026-07-26. **Sources:** `~/math/DETOUR_ALGORITHM.md` (authoritative),
`~/math/detour/`. **Verdict:** mostly negative, with exactly one open
transposition worth costing (§4).

This closes the DETOUR half of the "what about DETOUR / metaflip ideas?"
question. The metaflip half was answered earlier and was a measured null.

## 0. First, a correction to the question

The question as posed was whether DETOUR's *escape / reconfiguration structure*
maps onto wassat's restart policy, phase reconfiguration, or the SLS walker.

DETOUR has no escape structure. It is an **exact event-time label-setting
search** — a uniform-cost/Dijkstra wavefront over solve-state labels, with a
priority queue keyed on literal accumulated cost `g`, and the first settled
goal label is optimal. It never occupies a local minimum, so it never needs to
escape one, and it never reconfigures itself because there is no configuration
to change. Every mechanism it carries is either a *completeness* device
(branching, event ordering) or a *pruning/compression* device (dominance,
macros, bounds).

So the restart/SLS framing is answered negatively at the root, and not because
the mapping was tried and failed: there is nothing on DETOUR's side of that
particular mapping to try. The useful question is the one about its pruning and
learning devices, which is what the rest of this reviews.

(Per `feedback_detour_not_textbook_algos`, DETOUR is Erik's own algorithm and is
not a textbook local-search method. Nothing below identifies DETOUR *as* a known
method. §4 does observe that one DETOUR mechanism, when transposed into SAT,
lands on ground a known SAT technique also occupies — that is a statement about
the destination, not about DETOUR.)

## 1. The one structural constraint that decides everything

DETOUR's characteristic mechanism — the live detour matrix — is indexed by
**pairs drawn from a small, reusable ground set**: `D(A,B)` over vertices. That
is what makes online path learning pay. A witness learned once is reusable by
every future traveler that ever stands at `A`, and there are only `n²` cells to
learn.

Ask of each wassat component: *is there a small, reusable index set?*

| component | candidate ground set | size | verdict |
|---|---|---|---|
| CDCL trail / search states | assignments | 2ⁿ | no reusable index — a state is visited once |
| SLS walker (`lib/sls.w`) | assignments | 2ⁿ | same; a `(from,to)` macro would never hit twice |
| binary implication graph | literals | 2n | **yes** — this is the one |
| race arms (`lib/portfolio.w`) | arms | 8 | yes, but trivially small |

This single test disposes of most of the mapping, and it is the reason the SLS
answer is negative on stronger grounds than "we tried it and it did not help".
A detour matrix over SLS states cannot amortise: the walker essentially never
returns to a state it has seen, so every learned witness is dead on arrival. To
make it amortise you would have to key macros on something coarser than the
state — and then the recorded cost is no longer the cost of the move you will
actually make, which is precisely the property DETOUR's strictness rule relies
on.

## 2. Mechanisms that map onto something wassat already has

**Parallel travelers, first-settled-wins → the raw race.** DETOUR's wavefront
launches many travelers, runs them concurrently, and takes the first to settle.
Wassat's raw race launches N diversified arms plus up to two preprocessing arms
and takes the first to finish (`lib/wassat.w`, `wassat_race_build` /
`wassat_race_run`). Structurally the same. Nothing to import.

**Travelers teaching each other → clause sharing.** In DETOUR an arrival
updates `D`/`P` for the benefit of *future* launches; the learning is shared,
immutable, and never retroactively rewrites an in-flight traveler. Wassat's
arms export learned clauses into a seqlock ring and import them mid-flight
(`Wassat#enable_sharing` / `share_export` / `share_import`). Wassat is actually
the more aggressive of the two here — it *does* perturb in-flight travelers,
which DETOUR forbids for optimality reasons that a decision problem does not
have. Nothing to import.

**Superset-coverage dominance → subsumption.** `(v,S₁,g₁)` dominates
`(v,S₂,g₂)` when `S₁ ⊇ S₂` and `g₁ ≤ g₂`. The clause analogue is
`C₁ ⊆ C₂ ⟹ C₂ redundant`, present as `run_subsumption` and strengthened by the
interruptible subsumption landed in `bf60637`. Already there.

**Exact cluster factors / quotient → variable elimination.** DETOUR's
proof-safe clustering solves a cluster exactly, replaces it by its *boundary
interface* `F_C(p,q)`, and declines the contraction when no useful reduction
was certified. The SAT analogue is eliminating a set of interior variables and
keeping only the projection onto the boundary — bounded variable elimination,
present as `run_bve` / `try_eliminate`, complete with the "decline when it does
not shrink" growth bound. Gate extraction and the congruence pass
(`extract_and_gates`, `extract_xor_gates`, `congruence_rounds`) are the same
idea applied to definitional structure. Already there, and per
`project_wassat_rival_recon` BVE is explicitly *not* where the gap is.

## 3. Mechanisms that do not map at all

**Incumbent bounding, reduced-cost arc fixing, forced-edge 1-trees.** All of
DETOUR's strongest exact pruning is of the form "compute a lower bound `L`,
compare against an incumbent `U`, delete what cannot beat it". Every one of
these needs an objective function and a feasible incumbent. SAT as wassat
solves it is a decision problem: there is no `U`, so there is nothing to prune
against. This is a hard structural negative, not a tuning question. (It would
become live if wassat ever grew a MaxSAT mode, where `U` is the incumbent cost
and reduced-cost fixing has a real analogue in hardening.)

**Macro-transition contraction of forced paths.** DETOUR contracts a forced
consecutive path into one macro traveler queued at the summed literal cost. The
CDCL analogue of "a forced sequence of moves collapsed into one step" is unit
propagation, which is not an optimisation wassat could add — it is the thing
the solver is already built out of.

**Event-time ordering / first-settled optimality.** Requires nonnegative
weights and a cost to be monotone in. CDCL has no such measure over its search;
conflicts are not a cost being minimised along a path.

## 4. The one open transposition: probe arrivals are discarded

This is the only place where DETOUR says something wassat is not already doing.

DETOUR's rule is: **every settled arrival teaches.** When a traveler arrives
with history `H = (v₀…v_k)` and costs `G`, *every* newly completed contiguous
subpath is checked — for each `i<j`, if `Gⱼ - Gᵢ < D(vᵢ,vⱼ)` the shorter route
is recorded with its witness. The traveler does not have to reach the goal to
be useful. Only strict improvements are recorded, and the first witness is kept.

Wassat's probing does the opposite. `WassatPreprocess#probe(lit)` assumes `lit`,
propagates, and:

- if a conflict arises, it learns the unit `¬lit` — the goal case;
- **otherwise it calls `undo_to` and returns `false`, discarding the entire
  trail.**

That discarded trail is a set of arrivals. If propagating `l` implies `m`, then
`F ∧ l ⊨ m`, so `F ⊨ (¬l ∨ m)` — a valid binary clause, and RUP-checkable
(assume `l ∧ ¬m`, propagate, conflict), so it is proof-loggable with the
existing `conflict_chain` machinery. Today every one of those is thrown away
unless the probe happens to fail. On a probe with a trail of depth *k*, wassat
banks 1 fact when it fails and 0 when it does not; DETOUR's rule banks up to *k*
either way.

**The strictness filter is the part actually worth importing.** Adding every
implied binary would flood the clause database — this is the known failure mode
of the technique, and it is exactly what DETOUR's `c < D(A,B)` guard prevents.
The transposition is direct: the "known route" from `l` to `m` is a path in the
binary implication graph, so record `(¬l ∨ m)` only when `m` is *not* already
BIG-reachable from `l`. The cheap implementation is DETOUR's comparison done
once per probe rather than per pair: propagate `l` using binary watches only,
then propagate fully; the set difference is precisely the set of
non-transitively-redundant new arcs. Two propagations per probe, the second
already being paid for.

**Why it is plausibly worth something here specifically.** Per
`project_wassat_rival_recon`, wassat's gap to kissat is ELS plus congruence
inprocessing, not BVE. ELS is `tarjan` over the binary implication graph
(`build_binary_graph` / `run_substitution`) and its yield is bounded by how many
arcs that graph has. Feeding it arcs it currently never sees is the most direct
lever on the technique that recon named as the gap. That is a mechanism-level
argument, not a measurement.

**Why it is not being landed in this pass.** It is a new inprocessing
technique, not a tuning change: it needs proof-log hints per added binary, a
budget (the probe pass is already tick- and deadline-bounded), a cap on added
binaries, and the full gate — including the 200-case differential in both
default and `WASSAT_RAW_AT=0` modes and a `wrat`-verified php87. It should be
scoped as its own item, and it must be measured against the survey geomean
rather than the families it obviously helps.

## 5. Summary

| DETOUR mechanism | wassat | outcome |
|---|---|---|
| parallel travelers, first settled wins | raw race | already present |
| shared immutable learning across travelers | clause-sharing ring | already present |
| superset-coverage dominance | subsumption | already present |
| exact cluster factor → boundary interface | BVE, gate/congruence | already present |
| incumbent + reduced-cost fixing | — | no objective in a decision problem |
| forced-path macro contraction | unit propagation | not an addition |
| escape / reconfiguration | — | DETOUR has none; question mis-framed |
| detour matrix over SLS states | — | no reusable index; cannot amortise |
| **every arrival teaches, strictly** | **probing discards non-failing trails** | **open — §4** |

The load-bearing observation is §1: DETOUR's online learning needs a small
reusable index set, and wassat has exactly one, the 2n literals of the binary
implication graph. That is why the answer is negative everywhere except at
probing, and it is why the negative on the SLS walker is structural rather than
empirical.
