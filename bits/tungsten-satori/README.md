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
`trivial` · `constructor` · `left` · `right` · `use t` · `exfalso` · `by_contra h` ·
`contradiction` · `have h : P := proof` / `have h : P` + block · `show P` ·
`obtain ⟨x, hx⟩ := h` · `obtain a | b := h` · `cases h with …` ·
`induction n with x xs ih` · `rw [h, ← g] at h'` · `simp [lemmas, *] at h` ·
`simp only […]` · `unfold f` · `decide` · `norm_num` · `ring` · `linarith [extra]` ·
`sat` · `auto` · `specialize h a` · `symm` · `calc` · `funext x` · `subst h` ·
`revert h` · `sorry` · `·` focuses a goal.

* `decide` evaluates a closed proposition in the kernel. Bounded quantifiers over
  literal ranges, literal lists, `Prop` and enumeration types expand finitely.
* `sat` expands the hypotheses → goal implication to a propositional formula,
  Tseitin-encodes it in the kernel, runs the external solver
  (`bits/tungsten-wassat/bin/wassat`, or `$SATORI_SOLVER`), and re-checks the LRAT
  refutation. Proofs are cached in `.satori-cache/` by CNF hash.
* `linarith` runs Fourier–Motzkin and hands the kernel a Farkas certificate. For ℕ
  and ℤ it uses nonnegativity and `a < b ↔ a + 1 ≤ b`.
* `ring` proves commutative-ring identities over ℕ ℤ ℚ ℝ.

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

## Design notes

* `+` for theorems and `->` for definitions mirror Tungsten's `+ Class` / `-> method`.
  Theorems are the most frequent declaration, so they get the shortest token.
* The solver is an untrusted oracle with an independent checker, matching the
  original reason Wassat and Wrat are separate bits. Satori depends on the solver
  bit through its Bitfile only.
