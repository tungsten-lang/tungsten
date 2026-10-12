# Satori

A concise proof language with a small, auditable kernel. Satori is to Lean what
Tungsten is to C++: the same mathematics in far fewer lines. It gets there through
Unicode notation, auto-bound variables, a powerful evaluator, and automation whose
every step is re-checked by the kernel.

```satori
-> fact : ℕ → ℕ
  | 0 => 1
  | n + 1 => (n + 1) * fact n

+ fact5 : fact 5 = 120 := by decide

+ len_app (xs ys : list α) : length (xs ++ ys) = length xs + length ys
  induction xs with x xs ih
  · simp [append, length]
  · simp [append, length, ih]
    ring

+ php32 (p : ℕ → ℕ → Prop) (h1 : ∀ i < 3, ∃ j < 2, p i j)
    (h2 : ∀ j < 2, ∀ i < 3, ∀ k < 3, i < k → ¬ (p i j ∧ p k j)) : False := by sat
```

Run it from the Tungsten root (it needs the prelude and the SAT solver):

```sh
bin/tungsten bits/tungsten-satori/bin/satori.w -- file.sat
bits/tungsten-satori/bin/satori file.sat            # prebuilt release binary
bits/tungsten-satori/bin/satori check -j 4 file.sat # split mode
```

**Split mode** (`-j N`). Tungsten has no garbage collector, so a single process
that checks many heavy theorems (large `decide`, `sat`) keeps all of their memory.
With `-j N` every theorem is checked in its own process (`satori --only K`), N at a
time, each under a memory and time watchdog (`SATORI_JOB_MEM_MB`, default 6144;
`SATORI_JOB_SECONDS`, default 3600). A process admits the other theorems with a
`split:NAME` tag. The driver replaces each such tag by the transitive tags of
NAME's own check, so the verdict and trust tags match a single-process run. If
a theorem fails, every theorem that used it is marked `uses-failed:NAME`.

## Logic and trust

Classical higher-order logic (simple types with polymorphism), presented as natural
deduction, LCF-style: only `lib/kernel.w` can create a theorem. The trusted base is

| component | file | role |
|---|---|---|
| inference rules | `kernel.w` | ND rules for → ∧ ∨ ¬ ∀ ∃, equality and congruence, β, η, choice, excluded middle |
| definitions | `kernel.w` | closed definitions; inductive types with recursors, injectivity, distinctness, induction |
| evaluator | `eval.w` | `⊢ t = v`: β, unfolding, literal arithmetic on ℕ ℤ ℚ ℝ, ι-reduction, finite expansion of bounded quantifiers |
| checkers | `checkers.w` | LRAT (tag `oracle:sat`), ring normal form (`oracle:ring`), Farkas certificates (`oracle:arith`) |
| foundational axioms | `prelude/core.sat` (generated) | ordered-semiring/ring/field facts for ℕ ℤ ℚ ℝ; consistent with the evaluator's literal semantics |

Every theorem carries a tag list. Using a non-prelude `axiom` adds `axiom:name`,
using `sorry` adds `sorry`, and each checker adds its oracle tag. `#axioms name`
prints them. A file that states imported deep results as axioms is therefore honest
by construction.

## Declarations

| form | meaning |
|---|---|
| `-> f (x : ℕ) : ℕ := body` | definition (`def` also accepted) |
| `-> f : list α → ℕ` then `\| [] => 0` / `\| x :: xs => …` | structural recursion: patterns on one argument (ℕ: `0`, `n + 1`; lists: `[]`, `x :: xs`; constructors) |
| `+ name (binders) : stmt` then an indented tactic block | theorem (`theorem`/`lemma` also accepted) |
| `+ name : stmt := by tac; tac` | one-line theorem |
| `+ name : stmt := proof-term` | term proof |
| `@[simp] + name : …` | add to the simp set |
| `axiom name (binders) : stmt` | axiom (tagged on use) |
| `opaque c : τ` | declare an uninterpreted constant |
| `inductive t (α) \| c1 \| c2 (x : α) (r : t α)` | inductive type |
| `structure p := (x : ℚ) (y : ℚ)` | one-constructor type `p.mk` with projections `p.x`, `p.y` (also `v.x` on a variable) |
| `import name` | load `prelude/name.sat` or `./name.sat` |
| `#check e`, `#eval e`, `#print n`, `#axioms n` | queries |

**Auto-bound variables.** Free lowercase names in a theorem statement are universally
quantified, so `+ comm : a + b = b + a` is fine. Binders before the colon may be
variables `(x : ℝ)` or hypotheses `(h : x > 0)`. The proof starts with all of them
introduced.

## Terms

`fun x => e`, `∀ x y : τ, P`, `∃ x, P`, `∃! x, P`, bounded forms `∀ x ∈ S, P`,
`∀ i < n, P`, `∃ i ≤ n, P`; `¬ ∧ ∨ → ↔ = ≠ < ≤ > ≥ ∈ ∉ ⊆ ∣`, `+ - * / % ^`, chains
`a < b < c`; `if c then a else b`; `let x := v; e`; lists `[a, b]`, `x :: xs`,
`xs ++ ys`; tuples `(a, b)`; sets `{x | P x}`, `{a, b}`; `|x|`; `(e : τ)`, which
inserts the coercions ℕ→ℤ→ℚ→ℝ; `∑ i < n, f i`, `∑ x ∈ l, f x`, `∏`; projections
`h.1 h.2 h.mp h.mpr h.symm`; `(by tac)` inside proof terms. Types: `ℕ ℤ ℚ ℝ Prop`,
`α → β`, `α × β`, `list α`, `set α`, with Greek letters as type variables. Numerals
default to ℕ (decimals to ℚ).

## Tactics

`intro x h` · `intros` · `exact e` · `apply thm args` · `assumption` · `rfl` ·
`trivial` · `constructor` · `left` · `right` · `use t` · `exfalso` · `by_contra h` · `by_cases h : P` ·
`contradiction` · `have h : P := proof` / `have h : P` + block · `show P` ·
`obtain ⟨x, hx⟩ := h` · `obtain a | b := h` · `cases h with …` ·
`induction n with x xs ih` · `rw [h, ← g] at h'` · `simp [lemmas, *] at h` ·
`simp only […]` · `unfold f` · `decide` · `norm_num` · `ring` · `linarith [extra]` ·
`sat` · `auto` · `specialize h a` · `symm` · `calc` · `funext x` · `subst h` ·
`revert h` · `sorry` · `·` focuses a goal.

* `induction x with n₁ n₂ …` introduces, case by case, every binder of each case:
  constructor arguments, induction hypotheses, then the goal's own ∀/→ binders
  (including hypotheses reverted because they mention x). The names are spent in that
  order across all cases, so a base case's hypotheses are named first:
  `induction cs with m h c cs ih m h` for a goal `∀ m, P cs m → Q cs m`. Unnamed binders
  get default names.
* `decide` evaluates a closed proposition in the kernel. Bounded quantifiers over
  literal ranges, literal lists, `Prop` and enumeration types expand finitely.
* `sat` expands the hypotheses → goal implication to a propositional formula,
  Tseitin-encodes it in the kernel, runs the external solver
  (`bits/tungsten-wassat/bin/wassat`, or `$SATORI_SOLVER`), and re-checks the LRAT
  refutation. Proofs are cached in `.satori-cache/` by CNF hash.
* `linarith` runs Fourier–Motzkin and hands the kernel a Farkas certificate. For ℕ
  and ℤ it uses nonnegativity and `a < b ↔ a + 1 ≤ b`.
* `ring` proves commutative-ring identities over ℕ ℤ ℚ ℝ.
* `by_cases h : P` splits on excluded middle: one goal with `h : P`, one with `h : ¬P`.

Layout: a statement may continue on indented lines that start with an infix
operator (`=`, `→`, `∧`, `≤`, `:=`, …), and binder groups of a `+`/`->`/`axiom`
header may continue on indented lines until the header's `:`. A parse or lexer
error fails only its own command; the rest of the file is still checked.
Pattern definitions accept constructor patterns in several argument positions
(`| x :: xs, 0 => …`), nested patterns (`x :: y :: ys`, `(a, b) :: rest`, `n + 2`,
literal numbers and list literals) and uppercase pattern variables; the first
matching equation wins. Recursive calls must be on a direct constructor argument.

## Prelude

Always loaded: `core` (axioms, generated) · `logic` (de Morgan, quantifier duality,
`not_not`, pairs `(a, b)` with `fst snd`) · `nat` (`nat.induct` in `n + 1` form,
`dvd even odd prime gcd min max`) · `list` (`length append map sum range iota filter all`,
`sum_below prod_below sum_list prod_list`).

Optional:
* `import real`: `is_sup` with `sup_exists`, `sqrt exp log sin cos pi` with their
  basic laws, `tends_to converges continuous_at continuous summable bounded_seq
  monotone_seq` (ε–δ definitions).
* `import graph`: graphs as adjacency predicates on `0..n-1`; `simple
  edge_list_adj proper_coloring colorable color_assignment clique independent
  degree regular consecutive distinct_list hamiltonian_cycle`.
  `color_assignment` is the sat-friendly colouring form, e.g.
  `+ k4 (x : ℕ → ℕ → Prop) : ¬ color_assignment 4 3 k4 x := by intro h; sat`.
* `import poly`: Laurent polynomials as `(exponent, coefficient)` lists; `poly_at1 poly_at_neg1
  poly_d1 poly_d2 poly_d3 poly_mirror poly_neg_var poly_within`. Conditions on knot polynomials and generating
  functions then close by `decide` (e.g. the purely-cosmetic-surgery sieve in `~/math/openai/families/306-cosmetic-surgery`).

## Design notes

* `+` for theorems and `->` for definitions mirror Tungsten's `+ Class` / `-> method`.
  Theorems are the most frequent declaration, so they get the shortest token.
* The solver is an untrusted oracle with an independent checker, matching the
  original reason Wassat and Wrat are separate bits. Satori depends on the solver
  bit through its Bitfile only.

## Use: the OpenAI math families

**Provenance.** Satori was designed and implemented for this project, in response to the owner's request (session
3039114e, 2026-10-10 19:35 EDT) to "implement the general idea in a LEAN-like language … with a better, more concise syntax" and to
"put the new proving language in bits/tungsten-satori". Its first commit (996b71c7e, 2026-10-10 20:16) added the
kernel, evaluator and tactics, together with `core/svg` and `core/raster` for the families' figures. The owner's `+` / `->`
declaration syntax and the symbolic `sat` tactic followed at 20:44 (f28267e2b). The first family (156, Borsuk) was committed at 20:49
(`~/math` af0994ef). Everything since (26 commits: big operators, opaque constants, split mode, nested patterns, the prelude modules,
soundness fixes) was driven by the families.

Satori was written for one project: to restate the 372 result families of OpenAI's math release
(`~/code/edge/openai/math`) in a language far more concise than Lean. Each family's rebuild in `~/math/openai/families/`
has a `.sat` file that checks with `satori check -j 1`. `~/math/openai/SATORI_VS_LEAN.md` lists every family's line counts.

* **All 372 files:** 26,473 non-blank, non-comment Satori lines in total (median 58 per family, 90th percentile 123).
* **The 138 families with a Lean development in the release:** 11,640 Satori lines against 8,594,590 Lean lines. This aggregate is
  *not* a like-for-like ratio. A Satori file imports the paper's deep analytic steps as named axioms (`axiom:` tags make that visible
  in every theorem), while the Lean developments prove them.
* **Like for like:** where both prove the same statement, the difference comes from the evaluator, the checked oracles and the
  notation, not from omitted mathematics.

  | statement | Lean (OpenAI) | Satori |
  |---|---|---|
  | Borsuk in dimension 9, finite core: no ten-system exists | `FiniteCases/`, 66,297 lines | 3 lines (`intro`, `obtain`, `sat`; LRAT re-checked by the kernel) |
  | Catalan's constant, mod-101 matrix certificate | `FiniteMatrices/`, 395,415 lines | 72 `decide` theorems (plus a 201-line data file) |
  | Jacobsthal's function, the statement | `Model.lean`, 20 lines | 8 lines |
  | Ostmann's inverse Goldbach, main theorem from Lemma 2.2 and Theorem 2.3 | inside 609,199 lines | 3 tactic lines |

  These are the rows in the families' READMEs (`156-borsuk-nine`, `005-catalan-irrational`, `021-jacobsthal-quadratic`,
  `013-ostmann-goldbach`).
* **What carries the concision:**
  - The evaluator decides bounded quantifiers and literal arithmetic, so finite checks are one `decide`.
  - `sat` turns combinatorial cores into a kernel-checked LRAT refutation.
  - `ring` and `arith` (`linarith`) check certificates instead of replaying proofs.
  - Higher-level predicate modules (`graph`, `real`, `poly`, `nat`) let statements say what the paper says.
  - Tungsten programs compute the certificates (inverse matrices, coset tables, Steenrod-algebra data, braid invariants) that Satori
    re-checks, so the heavy computation stays in Tungsten and only the check enters the kernel.

## Soundness checks

Satori's claims are only as good as its kernel. Two spec files exercise the rejection side:

* `spec/ring_soundness.sat`: `ring` must reject an identity that is false as polynomials.
* `spec/must_fail.sat`: nine false statements. Each must be refused:
  - `decide` on false arithmetic, divisibility and bounded quantifiers;
  - `ring` on (x + y)² = x² + y²;
  - `linarith` on contradictory orderings and on x² ≥ x;
  - `sat` on a satisfiable claim ("the formula is satisfiable").

  The ninth statement is derived from a deliberately false `axiom`. It checks, but it carries the tag `axiom:a_false`, which is how
  imported assumptions stay visible.

Run them with `satori check -j 1 spec/must_fail.sat`. The expected verdict is `FAILED (8)`, with f9 checked and tagged. As of
2026-10-12 all eight are refused for the stated reason. All 372 family files check, and every theorem in them carries its
trust tags (`axiom:…`, `oracle:sat`, `oracle:ring`, `oracle:arith`).

## The SAT solver: decision

The question was whether Satori should incorporate the SAT solver (the `tungsten-wassat` bit). The decision is to **incorporate it as
an untrusted oracle, not into the trusted base**. Concretely:

* `by sat` (`lib/satbridge.w`) expands the goal's bounded quantifiers into a propositional formula and Tseitin-encodes it. It calls
  the solver (`$SATORI_SOLVER`, else `bits/tungsten-wassat/bin/wassat --lrat`) under a memory and time watchdog, and caches proofs by
  content hash. **The kernel re-checks the LRAT refutation** (`checkers.w`), and the theorem carries the tag `oracle:sat`.
* The solver stays a separate bit, referenced only from the Bitfile. A bug in the solver can make `sat` fail, but never makes a false
  theorem check. The solver can also be optimized or replaced (any LRAT-producing solver works through `$SATORI_SOLVER`) without
  touching the kernel. This is the same split as the original Wassat/Wrat pair.
* Merging the solver's source into Satori was rejected: it would add a CDCL engine to the code that has to be trusted, for no gain in
  what can be proved.
* **Name.** Decided by the owner on 2026-10-12: **keep "wassat" for now**. The rename proposal (koan, lantern, spar) was declined at
  this time. For reference: the suggested replacement was **koan**: a short puzzle whose answer is checked, next to
  Satori. Alternatives: *lantern*, *spar*. The rename is the owner's call and is not done here, because the bit's name is referenced
  by other active projects (`~/math` SAT campaigns, DETOUR's SAT rollout, Lonely Runner certificates, the `.wrat` format). Satori itself
  depends on the name in exactly two places, the Bitfile line and the default path in `satbridge.w`. After a rename, set
  `SATORI_SOLVER` or update those two lines.
