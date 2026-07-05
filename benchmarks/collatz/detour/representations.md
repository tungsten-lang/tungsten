# Representations of the Collatz map — eight changes of coordinate, one conserved obstruction

## What this is — and is not

A record of a systematic exploration of one question: *can a change of representation
make the Collatz conjecture tractable?* The answer here is **no**, but the value is in
*how* it fails. Eight natural re-encodings are each carried far enough to see what
structure they reveal and exactly where they stop. **Every one finds real structure;
every one leaves behind the same residue** — convergence ("every positive integer
reaches 1").

This is a survey/synthesis with reproducible computations (`representations.py`), **not a
new result.** It locates the difficulty precisely; it does not move it. It complements
`reduction.md` (the two hard kernels) and `proof.md` (the bounded result) by showing the
obstruction is *invariant* under re-encoding.

The conserved obstruction has two faces that recur in every representation:
- **`2^a ≠ 3^d`** — the multiplicative incommensurability (`log₂3` irrational), and
- **no descent function** — nothing provably decreases along every trajectory.

## The eight representations

**1. Forward trajectory → the affine merged map (DETOUR).** A run of operations composes
to `x → (3^a·x + c)/2^d`. A cycle closes iff `x = c/(2^d − 3^a)` is a positive integer.
Clean and exact; the difficulty is now "can `2^d − 3^a` divide `c`" — a Baker-strength
question. (See `collatz_detour.w`, `proof.md` Lemma 1.)

**2. The backward tree.** The dual: the tree rooted at 1 covers all of ℕ ⟺ Collatz. The
level at which `m` appears **equals `m`'s forward stopping time**, so "the tree covers
everything" is identically "every number has finite stopping time." No easier — the same
problem mirrored.

**3. Symbolic affine forms.** Reachable forms from a free `x` are `(2^a/3^b)·x + c`. The
coefficient equals `1` only at the identity (`2^a = 3^b ⟺ a=b=0`), so **`x+1` is not a
reachable form** — there is no universal "successor" operation, and no `x → x+1`
induction. (Same `2^a` vs `3^b` fact.)

**4. Deferred accumulation of the `+1`.** Perform `×3`/`÷2` on a running coefficient and
let every `+1` accumulate: `value = (3^a/2^d)·x + c`. A cycle is `x·(2^d − 3^a) = c·2^d`
— **the deferred accumulator *is* the cycle-equation constant.** This is the correct
normal form (the engine of every bounded result); it makes the equation exact without
making `2^d − 3^a` controllable, and says nothing about divergence (no finite cash-out).

**5. The large starting set.** Backward-closure of `{1..N}` = closure of `{1}` (the seed
size is irrelevant; the reachable set is fixed by the dynamics). A counterexample is a
**disjoint component** — a second cycle or a divergent ray — and growth never crosses a
component boundary. The **negative** integers exhibit this concretely: three disjoint
cycles (`−1`, `−5`, `−17`), and `−5` is unreachable from `−1`'s tree no matter how large
you grow it. Collatz ⟺ "ℕ⁺ is a single connected component," which the negatives show is
*not* automatic. (See `cycle_search.w`.)

**6. The complex plane ℂ.** The map extends to an entire function
`f(z) = z/2·cos²(πz/2) + (3z+1)/2·sin²(πz/2)`. Three obstructions: the extension is
**non-canonical** (add `sin(πz)·g(z)` for any entire `g`); the integers are an
**unstable, measure-zero skeleton** (perturbing `7.0→7.01` drifts away; `7+0.2i`
escapes to ∞); and it reframes convergence into intractable Fatou/Julia-membership
questions. The canonical completion is `p`-adic, not complex — but see (8).

**7. Multiplicative / prime structure.** Collatz respects **exactly one prime — 2** (the
parity test / halving): `steps(2n) = steps(n)+1` always. Every odd prime scrambles it
(`steps(21)=7, 35=13, 49=24, 77=22` — no pattern), and `a→1, b→1` gives nothing about
`ab→1` (`steps(5)=5, steps(11)=14, steps(55)=112`). **Unique factorization is dynamically
inert.** The classical multiplicative toolkit is attached to the wrong group.

**8. Binary → residue tower → 2-adic ℤ₂ → Syracuse.** The deepest lens.
- *Run-length / parity:* the symbolic dynamics is the **golden-mean subshift** — no two
  consecutive odd-steps (because `3n+1` is always even), so the number of realizable
  `k`-step behaviors is `F(k+2)` (Fibonacci), not `2^k`. A finite *local* law that says
  nothing about convergence.
- *Residue tower:* `n mod 2^k ↔ first k parities` is a **bijection** (Terras), consistent
  at every level, with inverse limit the **2-adic integers ℤ₂** — where the map is a clean,
  measure-preserving system. But the bijection means the tower is a faithful *relabeling*:
  knowing all residues just reconstructs the number. The maximal climber `2^k−1 ≡ −1`
  survives at every level; its limit is `−1 = …1111`, a divergent 2-adic point that is not
  a positive integer.
- *Odd-part (Syracuse):* factoring out the power of two concentrates **everything** into
  one number, `v = v₂(3m+1)`. Each step is `m → 3m/2^v`, so descent ⟺ **average `v >
  log₂3 ≈ 1.585`**. The valuations are geometric (`P(v=j)=2^{-j}`) with **`E[v] = 2`** —
  comfortably above the threshold. That gap is the entire heuristic for truth; "almost
  all" is provable (Tao 2019); "all" is the conjecture. And `v` is a residue-tower
  quantity, so it is steered by the convergence-blind 2-adic structure.

## The synthesis

**Convergence is orthogonal to all faithful structure.** It is not a parity rule, a
residue, a subshift constraint, an analytic continuation, a multiplicative law, or a
limit of finite-residue conditions. It survives every *faithful* re-encoding precisely
*because* the encodings are faithful — they relabel the integers without changing what
must be proven.

The sharpest form (representation 8, Syracuse) reduces the entire conjecture to one line:

> the 2-adic valuations `v₂(3m+1)` average more than `log₂3` along **every** trajectory.

The average (`E[v] = 2`) beats the threshold (`1.585`) by `0.4` — which is why the
conjecture is believed and why density-1 is provable. The worst case (a trajectory riding
the minimal `v=1`) is what no method rules out, because it would be a measure-zero
exception invisible to the residue tower — exactly the disjoint component of (5) and the
measure-zero needle of (6) and (8). That `log₂3` is the same `2^a` vs `3^d` wall from
representation 1, in its most honest face: the break-even point of a valuation race the
average wins and the worst case might not.

The lesson is not that some representation we haven't tried will work. It is that the
difficulty is **conserved** — it is the residue every faithful coordinate change leaves
behind — so progress requires not a re-encoding but new mathematics that controls the
*worst case* of the valuation race (cycles) and rules out *divergence* (the two kernels of
`reduction.md`).
