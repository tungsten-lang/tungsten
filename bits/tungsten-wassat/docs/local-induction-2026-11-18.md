# Certifying local induction on pairs of literals

Some CNFs represent an object at a vertex by a conjunction of two literals.
For a two-literal guard clause `G`, suppose the input contains
`G ∨ p ∨ r` and `G ∨ p ∨ s`, and a previously established clause forbids
`r ∧ s`. Assuming that both `G` and `p` are false forces `r` and `s`
simultaneously. This gives the reverse-unit-propagation step `G ∨ p`. Two
incompatible consequences under the same guard prove the guard itself.

Wassat starts from original binary exclusions, accumulates these steps to
a fixed point, and checks whether the original target now propagates a
contradiction. It can also close by splitting on one target literal. Cyclic
dependencies require an established base before they can yield a fact.
The public entry point is `wassat certify input.cnf --veripb proof.pbp`.

VeriPB independently accepted all six generated refutations across four
signed grids and two paired-target grids. The largest, a 14 × 17 grid, took
a 21,707-byte proof. Removing one required transition clause from each input yielded six
satisfiable controls according to CaDiCaL, and the exporter returned UNKNOWN
on each. The initial shape filter admitted 25 SC2025 and 58 SC2026 competition
entries. None produced a new local-induction proof. This lane is confined to
the explicit certificate command.
[Generated controls](../../../build/wassat-induction-20261118/native-controls.json) ·
[Competition survey](../../../build/wassat-induction-20261118/native-competition.json)
