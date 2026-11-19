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
  auto

+ php32 (p : ℕ → ℕ → Prop) (h1 : ∀ i < 3, ∃ j < 2, p i j)
    (h2 : ∀ j < 2, ∀ i < 3, ∀ k < 3, i < k → ¬ (p i j ∧ p k j)) : False := by sat
```

Start with `auto` for routine proofs. Supply a useful identity or bound with
`auto [lemma]`; keep explicit cases and induction when they clarify the argument.
If a strict numeric bound stays open, `auto` tries the non-strict bound with
the same assumptions and hints. When that succeeds, the diagnostic reads:

```text
  proved b ^ 2 ≤ d
  need b ^ 2 ≠ d
```

For `(m : ℝ) < (n : ℝ)` with naturals `m ≤ n`, the missing condition simplifies
to `m ≠ n`. Adding that hypothesis closes the goal with `by auto`.
If the missing fact comes from a library lemma, `auto [lemma]` can infer
its arguments and prove its guards. For example, from `f i ≤ g i` and
a lemma `apart : ∀ j, f j ≠ g j`, `by auto [apart]` proves `f i < g i`.

If an explicit hint or an `@[auto]` rule matches the goal and one premise stays open, `auto`
shows what it proved and which premise would finish that application. With
`import arith`, scaling `a ≤ b` to `a*c ≤ b*c` with plain `auto`
reports `proved a ≤ b` and `need 0 ≤ c`. With `a ≠ b` and the goal `a < b`, `auto`
finds the registered order rule and reports `need a ≤ b`. For `a/c ≤ b`,
if the hypotheses imply `a ≤ b*c`, a loaded division rule can report
`proved a ≤ b * c` and `need 0 < c`.

For `a*c < b*c`, if `a < b` and `0 ≤ c`, the remaining condition is
`c ≠ 0`. If `c = 0` is known, the diagnostic reads `proved a * c = b * c`.
The same check can reduce `f i ≠ f j` to `i ≠ j` when the hypotheses establish
injectivity.

For an existential goal, `auto` can report a concrete witness and the
conditions still needed for that choice. For example, given `active k`
and `k < n`, a failed proof of `∃ j ≤ n, active j ∧ ready j` produces
the following diagnostic.

```text
  witness k
  proved k ≤ n ∧ active k
  need ready k
```

Over ℚ and ℝ, `auto` can construct a witness for simultaneous linear bounds.
For example, `a < b` suffices for `∃ x : ℚ, a < 3*x ∧ 3*x < b`.
Given only `a ≤ b`, the diagnostic reports `proved a ≤ b` and `need a ≠ b`.
Satori checks that every witness forces a strict gap and replays the original
goal with the proposed condition.
The arithmetic checker verifies each bound at the chosen value.
See the [interval proofs](examples/compact_interval_witnesses.sat).
With `arith` loaded, a strict margin at one endpoint also lets `auto`
step inside the interval while preserving several bounds with variable slopes.
See the [affine step proofs](examples/compact_affine_steps.sat).

Run it from the Tungsten root (it needs the prelude and the SAT solver):

```sh
bin/tungsten bits/tungsten-satori/bin/satori.w -- file.sat
bits/tungsten-satori/bin/satori file.sat            # prebuilt release binary
bits/tungsten-satori/bin/satori check -j 4 file.sat # split mode
```

Basic finite-sum rules are included by `arith` and `realx`.
[Compact sum examples](examples/compact_sums.sat) show how library rules replace
common inductions with plain `auto`: splitting and scaling a sum, nonnegativity,
constant bounds, monotonicity, and separating the first term. Local function definitions and bounds over
larger index ranges are handled automatically. These examples run in the
compiled and interpreted test suites.
[Zero-sum examples](examples/compact_zero_sums.sat) use `auto` for constant
or pointwise zero terms, including bounds on a larger range.
[Sum-congruence examples](examples/compact_sum_congruence.sat) use `auto`
when corresponding terms agree, including nested sums and pointwise arithmetic.
[Sum-interchange examples](examples/compact_sum_swap.sat) swap rectangular
summation ranges with `auto`, including local row/column definitions.
[Weighted exchange examples](examples/compact_sum_exchange.sat) cover matrix
bilinear identities and termwise equality assumptions with the same `auto`.
[Termwise linearity examples](examples/compact_sum_linearity.sat) lift local
scaling, addition and subtraction identities through a sum, including rearranged products.
[Compact inequality examples](examples/compact_inequalities.sat) replace manual
product bounds and case splits with `nlinarith`, including a chord comparison.

**Split mode** (`-j N`). Tungsten has no garbage collector, so a single process
that checks many heavy theorems (large `decide`, `sat`) keeps all of their memory.
With `-j N` every theorem is checked in its own process (`satori --only K`), N at a
time, each under a memory and time watchdog (`SATORI_JOB_MEM_MB`, default 6144;
`SATORI_JOB_SECONDS`, default 3600). A process admits the other theorems with a
`split:INDEX` tag identifying its declaration. The driver replaces each such tag by
the transitive tags of that declaration's own check, including in `#axioms` output,
and rechecks `@[auto]` registrations against those resolved tags. If
a theorem fails, every theorem that used it is marked `uses-failed:NAME`.
The driver starts workers from its own executable; `SATORI_BIN` may override it
with a matching Satori binary. Incompatible worker protocols are rejected.

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
`simp only […]` · `simpa [lemmas] using e` · `unfold f` · `decide` · `norm_num` · `ring` · `linarith [extra]` ·
`nlinarith [extra]` · `linear_combination 2 * h₁ - x * h₂` · `positivity` · `omega` · `t1 <;> t2` · `all_goals t` ·
`sat` · `auto` · `specialize h a` · `symm` · `calc` · `funext x` · `subst h` ·
`revert h` · `sorry` · `·` focuses a goal.

An ordinary tactic can own an indented proof of the subgoals it opens:

```satori
+ pair (p q : Prop) (hp : p) (hq : q) : p ∧ q
  constructor
    hp
    hq
```

Known proof terms can stand alone: `h`, `h.2`, `bound x h`, or `⟨x, h⟩`.
They close the current goal just as `exact` does. `exact` remains available,
and tactic names keep their existing meaning. See the
[compact logic examples](examples/compact_logic.sat).

Dedenting resumes the surrounding proof only when those subgoals are closed.
Nested blocks stay within their parent's goal; they cannot consume a sibling
outside that block. Bullets remain available for explicit focus. `have h : P`
and `calc` retain their existing proof blocks.

* `induction x` introduces `x` from the statement's leading quantifiers when
  it is not already local, along with any preceding parameters and guards.
  Case names are optional when automation can finish the branches; the
  [compact induction example](examples/compact_induction.sat) needs three proof lines.
  `induction x with n₁ n₂ …` introduces, case by case, every binder of each case:
  constructor arguments, induction hypotheses, then the goal's own ∀/→ binders
  (including hypotheses reverted because they mention x). The names are spent in that
  order across all cases, so a base case's hypotheses are named first:
  `induction cs with m h c cs ih m h` for a goal `∀ m, P cs m → Q cs m`. Unnamed binders
  get default names.
* `decide` evaluates a closed proposition in the kernel. Bounded quantifiers over
  literal ranges, literal lists, `Prop` and enumeration types expand finitely.
* `auto` derives consequences of local hypotheses, including conjunction projections,
  implication chains and contradictions, with bounded forward reasoning. It specializes
  universal facts at in-scope variables and terms already present in the goal or hypotheses.
  It also chains equalities, applies congruence and substitutes in propositions,
  including when matching implication premises and contradictory facts, and handles bounded case splits
  on disjunctions. It can choose a witness already in scope or extract one from an
  existential hypothesis. A witness can also refute a negated existential when
  its guards hold. The search works backwards through implications to construct their premises,
  introducing variables and assumptions where needed. A bounded classical case search
  handles patterns such as excluded middle and double negation.
  On ℕ and ℤ, `auto` reduces a known remainder to any positive literal divisor
  of its positive literal modulus. For example, `n % 4 = 1 ∨ n % 4 = 3`
  proves `odd n` in one `auto`: both branches give remainder 1 modulo 2.
  Sums and products use the modulus in the goal. From `n % 5 = 2`, bare
  `auto` proves `(2*n + 1) % 5 = 0`. A factor with remainder zero also
  determines the remainder of a product with an unknown factor.
  Common loaded arithmetic and analysis rules also work with plain `by auto`,
  including square bounds, exponential/logarithmic Jensen, square-root
  comparisons, geometric-mean bounds, Cauchy–Schwarz, Euclidean triangle
  inequalities and entropy bounds. Finite-sum splitting, linearity, nonnegativity, bounds and monotonicity
  work over ℕ, ℤ, ℚ and ℝ. Local quantified bounds can supply premises whose
  guards follow by arithmetic; their consequences can be combined to prove
  weaker bounds or discharge further guards, without intermediate `have` lines.
  For arithmetic equalities, it also tries rules against the reversed equation.
  Candidates are indexed by the goal's shape and numeric type. Lookup also
  follows bounded chains of outer definitions, so a user-defined `norm` can
  select the underlying square-root bound without an `unfold` step. This does
  not import additional modules or search every theorem in scope.
  See [`examples/compact_auto.sat`](examples/compact_auto.sat) for six proofs
  requiring no lemma names, and [compact norm bounds](examples/compact_norms.sat)
  for Cauchy–Schwarz and triangle inequalities. With `realx` loaded, `auto`
  handles exponential/logarithmic signs and order, proving the required
  positivity conditions; see [compact analysis proofs](examples/compact_analysis.sat).
  Square-root signs, order, strict bounds, and square/product identities also
  work with `auto`, including through definitions of norms. Squaring a root
  comparison still requires the appropriate domain and sign conditions.
  With `arith` loaded, absolute-value signs, interval bounds, triangle
  inequalities and squared bounds work across integers, rationals and reals.
  Local absolute-value bounds supply their endpoints to later arithmetic;
  see [compact absolute-value proofs](examples/compact_abs.sat).
  For widening casts along ℕ → ℤ → ℚ → ℝ, `simp` distributes casts over
  sums and products, and `auto` carries nonnegativity into arithmetic.
  From `h : m ≤ n` over naturals, `by auto` proves `(m : ℝ) ≤ (n : ℝ)`.
  `simpa using h` transports equality and strict or weak order in either
  direction. For bounds involving literals or arithmetic in several domains,
  `linarith` can widen the hypotheses and combine them in a common domain.
  See [numeric cast proofs](examples/compact_numeric_casts.sat).
  Rational and real quotient bounds, reciprocal order and cancellation also
  use loaded `arith` rules. `auto` proves the denominator conditions before
  cross multiplying. It can use a quotient in a hypothesis too. Given
  `0 < c`, `a/c ≤ b` and `b*c < t`, it proves `a < t`.
  When the denominator may be zero, `auto` checks that case too. For
  example, `0 ≤ r` and `r ≤ a` suffice for `r^2/a ≤ r`.
  See [compact division proofs](examples/compact_division.sat).
  Minimum/maximum bounds, clamps and nonnegative scaling work over ℕ, ℤ, ℚ
  and ℝ. Their endpoint bounds feed arithmetic automatically, including after
  specializing a local quantified hypothesis; see [compact min/max proofs](examples/compact_minmax.sat).
  Natural-exponent powers use their base-sign and exponent-order conditions
  automatically. Small natural-subtraction guards need no separate `omega`
  step; see [compact power proofs](examples/compact_powers.sat).
  In an algebraic identity, `auto` can check that two exponents differ by one
  and apply the power recurrence. For a predecessor such as `n - 1`, it can
  prove the zero case separately when a factor vanishes.
  See the [power step examples](examples/compact_power_steps.sat).
  A local bound can also guide a missing comparison: from `c ≤ b^n`, `auto`
  can prove `b^n ≤ x^n` and conclude `c ≤ x^n`, without an intermediate `have`.
  This works with strict bounds and local monotonicity rules too; see
  [compact bound chains](examples/compact_bound_chains.sat). Arithmetic margins also chain:
  from `c + 1 ≤ b^n` and `0 ≤ b ≤ x`, `auto` proves `c < x^n`;
  a positive variable margin works the same way. See
  [compact affine chains](examples/compact_affine_chains.sat).
  Matching offsets and numeric factors need no normalization step either:
  `c + d ≤ b^n + d` and `2*c ≤ 2*b^n` can both guide the same power bound.
  See [compact normalized bounds](examples/compact_normalized_chains.sat).
  Symbolic factors work when their sign is known: `0 < d` and `d*c ≤ d*b^n`
  yield `c ≤ b^n`, which can then chain through power monotonicity. Small
  product and sign arguments also close directly; see
  [compact symbolic-factor proofs](examples/compact_symbolic_factors.sat).
  Squared comparisons can supply intermediate order bounds for a later product
  estimate, including two weighted bounds in one goal. See
  [compact square-bound proofs](examples/compact_square_bounds.sat).
  Affine equalities also feed product estimates: from `x + y = z`, `auto`
  proves `a*x + a*y = a*z` without an explicit multiplied equality. See
  [compact equality-product proofs](examples/compact_equality_products.sat).
  Local implications can have universal, conditional or conjunctive premises.
  For induction, `auto` restricts `∀ i < n+1, 0 ≤ f i` to the range needed
  by the induction hypothesis; see
  [compact induction proofs](examples/compact_induction_guards.sat).
  `simp [definitions] at *` simplifies all local hypotheses and the goal,
  so unfolding needs no generated hypothesis names. See
  [compact simplification](examples/compact_simp_locations.sat).
  Equal indices also feed arithmetic: `i = k` lets `auto` combine bounds
  on `f i` and `f k` without a separate rewrite. Nested applications and
  several arguments work too. Linear index calculations such as
  `f (s+(i+1)) = f ((s+1)+i)` need only `auto`, with no intermediate
  equality; see [compact arithmetic with equalities](examples/compact_arithmetic_congruence.sat).
  Quantified arithmetic hints infer arguments from applications already in
  the proof: `auto [total_nonneg]` can replace `auto [total_nonneg f n]`.
  Their premises still have to be proved; see
  [compact quantified hints](examples/compact_quantified_hints.sat).
  Implicit order rules reduce comparisons of these functions to their inputs.
  Explicit hints also support the inverse directions. Matching reduces record fields
  on constructors using their checked projection equations; the
  [complex-norm example](examples/compact_complex.sat) needs no explicit
  unfolding or projection lemmas. The same matching works with `apply`,
  `exact` and bare proof terms. Repeated products such as `x*x` match squares
  written `x^2`, including in supplied premises and under functions or binders.
  Local assumptions use the same conversion. These conversions preserve
  assumptions and carry checked equality proofs.

  Use `auto [lemma1, lemma2]` for additional patterns. Arguments are inferred,
  routine premises are proved, and short rule chains are supported. Small
  quadratic side conditions use the existing nonlinear checker, including
  squares and products of known signs, with four shared attempts per call.
  Explicit hints can also supply facts: quantified and conjunctive facts are
  specialized and combined by arithmetic, without intermediate `have` lines.
  Types and arguments are inferred for polymorphic hints, so
  `auto [measure_nonneg]` can supply facts at several argument types. Local
  quantified hypotheses work the same way with plain `auto`; see the
  [compact hint examples](examples/compact_hints.sat). Partially applied hints
  keep the types of their supplied arguments. Equivalences work in both
  directions with their guards retained. Automatic selection excludes named-axiom dependencies; explicit
  hints preserve those dependencies in the result. Search has a shared limit
  of 24 rule attempts and detects cycles. Failed candidates contribute neither
  assumptions nor trust tags. `aesop` and `tauto` support the same behavior.

  Bare `auto` also tries up to eight previously proved lemmas that share a
  distinctive constant with the goal. Rare constants rank higher, and symbols
  from local hypotheses help choose between candidates. Satori instantiates
  each lemma and proves its premises. For example, after `import arith`,
  `+ parity (n : ℤ) : even n ∨ odd n := by auto` finds the library's parity
  theorem. The [premise selection example](examples/premise_selection.sat)
  also uses an ordinary user lemma proved by induction.

  Library authors can write `@[auto] + lemma ...` to register a proved rule.
  Subsequent proofs use ordinary `auto`, including after an import. Selection
  uses the conclusion's structure and type; theorem names have no special
  meaning. Conjunctions supply their components, and equivalences supply both
  directions. Arguments and guards are checked as for explicit hints. For
  example, `import quadratic` registers the proved quadratic-form bounds:

  ```text
  + discriminant (a b c : ℚ)
      (q : ∀ x y : ℚ, 0 ≤ x^2*a - 2*x*y*b + y^2*c) : b^2 ≤ a*c
    auto
  ```

  Registration requires a closed theorem and permits the checked arithmetic,
  ring and SAT dependencies. It rejects `sorry` and named-axiom dependencies;
  use an explicit hint when such a dependency is intentional. Replacing a
  theorem does not transfer its registration. Registered search runs after
  existing automation, with its own shared limit of 24 rule attempts and cycle
  checks. Registration makes a lemma available; bounded search may still need
  an explicit hint. See [quadratic-form rules](prelude/quadratic.sat) and
  [compact registered proofs](examples/compact_registered_rules.sat).
  Registered comparisons also contribute intermediate arithmetic facts. For
  example, the quadratic-form bound together with `a*c ≤ d` proves
  `2*b^2 ≤ 2*d` with `auto`. Selection uses expressions already in the goal
  or hypotheses, with at most 32 candidate rules and eight instantiated facts.
  Guards remain obligations; explicit hints can prove quantified guards and
  retain their dependencies. See [registered arithmetic chains](examples/compact_registered_chains.sat).
* `sat` expands the hypotheses → goal implication to a propositional formula,
  Tseitin-encodes it in the kernel, runs the external solver
  (`bits/tungsten-wassat/bin/wassat`, or `$SATORI_SOLVER`), and re-checks the LRAT
  refutation. Proofs are cached in `.satori-cache/` by CNF hash.
* Arithmetic treats `succ n` and `n + 1` consistently, including inside function
  applications. Induction steps do not need a `show` line just to restate the
  generated successor goal. See [the compact induction example](examples/compact_induction.sat),
  which uses indentation and `auto` without helper lemmas or imports.
* `linarith` runs Fourier–Motzkin and hands the kernel a Farkas certificate. When elimination gets large (more than 12
  rounds or 600 constraints), an exact two-phase simplex over the Farkas multipliers takes over, which is complete for linear
  arithmetic. For ℕ and ℤ it uses nonnegativity (of variables and of products of non-literal factors) and
  `a < b ↔ a + 1 ≤ b`. For `x / k` and `x % k` with a literal k > 0 it adds `k * (x / k) + x % k = x` and `0 ≤ x % k < k`.
* `nlinarith` is `linarith` plus, for every pair of hypotheses `a ≤ b`, `c ≤ d` (including the negated goal), the product
  fact `0 ≤ (b - a) * (d - c)` (`0 <` for strict pairs), each proved with `mul_nonneg` / `mul_pos`. Over ℕ, where `b - a`
  truncates, it uses `a * d + b * c ≤ a * c + b * d` instead (the prelude lemma `nl_cross.nat`).
  Natural factors' nonnegativity is included automatically: from `h : a ≤ b`,
  `by nlinarith` proves `c * a ≤ c * b` for `c : ℕ`, including function-valued
  weights such as `w x`. Signed factors still need a sign hypothesis. `linarith` also knows that the
  monomials of an expanded ℕ power such as `(k + 1) ^ 2` are ≥ 0.
  If the signed search fails, a bounded fallback substitutes equal local
  variables and combines up to eight affine sign bounds in triples. These
  extra facts use the same checked multiplication rules and arithmetic
  certificates; they add no oracle or axiom.
  The fallback also recognizes up to twelve distinct squares written as
  `x * x` or `x ^ 2`, including squares of expressions and function values.
  Their nonnegativity is proved by a checked sign split, so `by nlinarith`
  needs no sign premise or explicit square lemma.
  A final bounded search uses up to six linear or mixed terms in quadratics
  to suggest squares of sums, differences, and coefficient-scaled combinations.
  This proves AM–GM, midpoint bounds, and shifted quadratic bounds such as
  `12*x ≤ 4*x*x+9` directly with `nlinarith`.
* `positivity` collects sign facts of the goal's subterms (`|x|`, `exp x`, `√x`, even powers) and runs `nlinarith`.
* `omega` is `linarith` with case splits on truncated ℕ subtraction `a - b` (`b ≤ a` with `a - b + b = a`, or `a ≤ b`
  with `a - b = 0`), at most 3 deep.
* `t1 <;> t2` runs `t2` on every goal `t1` leaves (a line ending in `<;>` continues on the next indented line);
  `all_goals t` runs `t`, which may contain `<;>`, on every open goal; `(t)` groups a tactic sequence. `at h1 h2 ⊢` lists may
  include the goal.
* `simpa [rules] using e` simplifies an existing proof or theorem application and the goal, then closes by checked
  conversion. `only` restricts the simp rules; `← rule` and `*` work as in `simp`. Quantified term arguments may be
  inferred after simplification. Omit `using e` when simplification and a local assumption suffice. `simpa` must
  close the goal; use `simp … at h` to simplify a hypothesis. Function equalities rewrite both bare functions and
  call heads, so `simpa [f_eq] using h` also handles occurrences such as `f x` under quantifiers.
* `have h : P := by t1; t2` runs both tactics on the subgoal. A block indented under `have h : P` (also on a `·` line) is
  its proof. `rw [thm a b]` uses the given arguments (the rule's free variables are fixed, not patterns); `rw … at h1 h2`
  and `unfold f at h1 h2` act on every listed hypothesis. `rw` can replace free subterms inside lambdas and quantifiers,
  keeping replacements distinct from bound variables. Missing rule arguments can also be inferred by matching
  its premises against local hypotheses. Rewriting and arithmetic identify `f` with `fun x => f x`,
  so direct sum applications and `∑` notation work together. A term proof `+ t (a : ℝ) (h : …) : … := thm a h` sees the
  binders. In applications, term arguments may follow proof arguments (Satori hoists ∀ binders to the front), and
  `have k := thm a` with later binders left open is a partial application. Supplied lambda arguments are reduced
  when matching the goal or a proof premise, so remaining arguments can be inferred. Projections such as `h.1`,
  tuples `⟨hp, hq⟩`, and `obtain` also reduce applied predicates to expose their logical form.
  Applications continue through implications, negations and quantifiers exposed by a supplied predicate;
  this also works when the applied predicate was saved with `have`.
  Small literal calculations are reduced as arguments are inferred: a parameter
  inferred as `3` can match `3 + 1` with `4`, including beneath quantifiers.
  `apply` opens any remaining premises. Alias matching also computes beneath quantifiers with fresh binders.
  Fully supplied theorem applications can unfold aliases to match the goal;
  proof arguments and projections also unfold aliases to fit a known premise.
  Projected and partially applied proofs preserve the types of local terms already supplied to them.
  `a⁻¹` is `1 / a`.
* `auto` handles small arithmetic case splits: for example, `x*y = 0`
  gives `x = 0 ∨ y = 0`, or just `x = 0` when `y ≠ 0` is known.
  Nonzero facts can be local hypotheses or explicitly supplied proofs.
  See [compact_arithmetic_cases.sat](examples/compact_arithmetic_cases.sat).
* `auto [formula]` can rewrite small arithmetic goals and their hypotheses
  with the supplied formula before checking the result. Conditional formulas
  require their guards; local formulas and their dependencies are preserved.
  This also handles several arithmetic conclusions together.
  See [compact_rewrite_arithmetic.sat](examples/compact_rewrite_arithmetic.sat).
* `auto` can reuse quadratic reasoning for repeated compound values, such as
  `(a*b)^2+(c*d)^2 = 0`, without expanding every product. This covers zero
  components and signed square-order bounds; over ℕ ℤ ℚ ℝ it also covers AM–GM
  for these values. Natural AM–GM uses the proved default lemma
  `two_mul_le_add_sq.nat`; `auto` also combines matching default bounds with
  arithmetic, including added positive margins.
  See [compact_natural_squares.sat](examples/compact_natural_squares.sat).
  Weighted squares such as `12*x*x` are recognized by
  `nlinarith` even when no explicit `x*x` subexpression appears.
  See [compact_compound_squares.sat](examples/compact_compound_squares.sat).
* `auto` can combine square bounds with supplied inequalities even when
  higher-degree terms cancel between them. This uses proved nonnegative
  squares and a checked linear certificate, with bounded polynomial expansion
  and at most two attempts after the established proof paths.
  Known guards can also determine arguments of supplied conditional lemmas.
  See [compact_square_cancellation.sat](examples/compact_square_cancellation.sat).
* `ring` proves commutative-ring identities over ℕ ℤ ℚ ℝ, including through
  small local definitions and constructor projections. Ordinary polynomial
  identities need no preceding `unfold`; opaque functions remain opaque.
  See [compact_ring_definitions.sat](examples/compact_ring_definitions.sat).
* `linear_combination` closes a numeric equality with an explicit polynomial combination of equality proofs.
  Write `linear_combination 2 * h₂ - 6 * (r - 1) * h₁`; coefficients can be terms, on either side of `*`,
  and proofs can be applications or projections. `+` combines equalities and `-` reverses them;
  for ℕ this reversal does not introduce truncated subtraction. All inputs must have the goal's numeric type.
  Equality congruence and `ring` check the certificate; ℕ also uses checked arithmetic to cancel a common
  additive term. With no arguments it behaves like `ring`.
* `by_cases h : P` splits on excluded middle: one goal with `h : P`, one with `h : ¬P`.

Layout: a statement may continue on indented lines that start with an infix
operator (`=`, `→`, `∧`, `≤`, `:=`, …), and binder groups of a `+`/`->`/`axiom`
header may continue on indented lines until the header's `:`. A parse or lexer
error fails only its own command; the rest of the file is still checked.
Pattern definitions accept constructor patterns in several argument positions
(`| x :: xs, 0 => …`), nested patterns (`x :: y :: ys`, `(a, b) :: rest`, `n + 2`,
literal numbers and list literals) and uppercase pattern variables; the first
matching equation wins. Recursive calls must be on a direct constructor argument.
Generated equations retain the declared type parameters and simplify at every
instance, including sums and products over ℤ, ℚ and ℝ.

## Prelude

Always loaded: `core` (axioms, generated) · `logic` (de Morgan, quantifier duality,
`not_not`, pairs `(a, b)` with `fst snd`) · `nat` (`nat.induct` in `n + 1` form,
strong and bounded reverse induction, least witnesses, infinite descent,
`dvd even odd prime gcd min max`) · `list` (`length append map sum range iota filter all`,
`sum_below prod_below sum_list prod_list`) · `function` (`function.iterate` and
proved fixed-point, composition, preservation and commutation lemmas for repeated application).
`function.iterate_invariant` propagates any property preserved by one step.

`nat.exists_least_of P n hn` turns a witness `hn : P n` into
`∃ m, P m ∧ ∀ k < m, ¬ P k`; `nat.exists_least P h` takes an existential
witness instead. `nat.least_le` bounds a least index by any witness, and
`nat.least_unique` identifies two least indices. The property need not be decidable.
`apply nat.strong_induct P` supplies every smaller case in the induction step.
`nat.reverse_induct P bound base step n hn` descends from `base : P bound`
to `n ≤ bound`, with `step` allowed to use every level strictly above `n`
and at most `bound`. `nat.infinite_descent` rules out a property whose every
witness yields a strictly smaller witness. For sequences, `nat.descent_bound`
needs strict decrease only on a finite prefix and proves `f n + n ≤ f 0`;
`nat.no_infinite_descent` rules out strict decrease at every natural index.
From `f 0 ≤ n`, `nat.exists_nondecreasing_step` gives some `k ≤ n` with
`f k ≤ f (k + 1)`. If the sequence is weakly decreasing through `n`,
`auto [nat.exists_nondecreasing_step]` finds a pair of equal adjacent values.

`list.foldl step xs state` runs an element-first step (`step element state`) from
left to right; `list.foldr` combines from right to left. Both are included by
default, with append, map, invariant, commutation, preservation and fixed-point
lemmas. `list.foldl_invariant step p h xs state hs` lifts a step rule
`h : ∀ x s, p s → p (step x s)` and initial fact `hs : p state` to a whole run.
The `_invariant_on` variants need the step rule only for members of `xs`.
The `_invariants` variants preserve two mutually dependent facts. They infer
both predicates from a step theorem of the form
`∀ x s, p s → q s → p (step x s) ∧ q (step x s)`:
`exact list.foldl_invariants step_rule xs state hp hq`.
`_commutes` transports a run through a map between state types; `_preserves`
lifts an unchanged quantity. The same rules are available for `list.foldr`.

List predicates have reusable proofs: `list.all_mem p xs x hx hp` extracts `p x`
from membership `hx` and `hp : all p xs`; `list.all_of_mem` builds `all` from
memberwise facts. `rw [list.all_iff]` converts `all p xs` to `∀ x ∈ xs, p x`.
`list.all_imp`, `list.all_map` and `list.all_append` transform, map and combine
these predicates without another list induction.

Optional:
* `import geometric`: finite geometric sums over ℤ, ℚ and ℝ, with no
  division or excluded rates. `sum_below.geometric_step r A n` sums
  `(r - 1) * A * r^i` to `A * (r^n - 1)`.
  `sum_below.arithmetic_geometric r n` gives the denominator-cleared identity
  for `Σ (i + 1) r^i`, including `r = 0` and `r = 1`.
  `sum_below.geometric_bound` and `sum_below.geometric_bound_add` bound a
  sum by one or two geometric increments; their pointwise hypotheses only
  cover `i < n`.
  `sum_below.weighted_geometric_bound f w r A B n hw h` sums `w^i * f i`
  from `f i ≤ (w*r - 1)*A*r^i + (w - 1)*B`, yielding
  `A*((w*r)^n - 1) + B*(w^n - 1)`. Only the weight `w` must be
  nonnegative; `r`, `A`, and `B` may be signed. All five rules use
  `.int/.rat/.real` suffixes and permit empty sums.
* `import recurrence`: `recurrence.linear_lower` and `linear_upper` turn
  constant one-step drift into `A + n*d` bounds from an initial bound `A`.
  `geometric_eq` proves `f n = f 0 * r^n` from `f (i+1) = r*f i`, including
  negative rates. `geometric_upper` and `geometric_lower` compare with
  `A*r^n`; they require `0 ≤ r`, but `A` may be signed. These rules have
  `.nat/.int/.rat/.real` variants.
  `recurrence.geometric_forcing` handles
  `f (i+1) ≤ b*f i + c*q^i` with `0 ≤ b ≤ q` and `f 0 ≤ 0`, proving
  `(q-b)*f n ≤ c*(q^n-b^n)`. It has `.int/.rat/.real` variants, permits
  signed `c` and equal rates, and does not divide by `q-b`.
  `recurrence.affine_transform f r c A B balance step n` solves a scaled
  affine recurrence: if `f(i+1) = r*f(i) + c` and `A*c + B = r*B`, then
  `A*f(n) + B = (A*f(0) + B)*r^n`. It has all four numeric variants.
  For ℤ, ℚ and ℝ, `affine_closed` gives `(f(0) + A)*r^n - A` when
  `c = (r - 1)*A`; `affine_zero` uses `f(0) = 0` to give `(r^n - 1)*A`.
  These equalities allow zero, unit and signed rates and introduce no division.
  `recurrence.count` recognizes a natural counter starting at zero and
  increasing by one, using only the kernel. `linear_eq` recognizes constant
  increments and preserves an arbitrary initial value.
  `recurrence.quadratic f a b c base step n` proves `f(n) = a*n*n + b*n + c`
  from `f(0) = c` and `f(i+1) = f(i) + 2*a*i + (a+b)`.
  `recurrence.cubic` similarly recognizes `a*n³ + b*n² + c*n + d` from
  initial value `d` and increments `3*a*i² + (3*a+2*b)*i + (a+b+c)`.
  These three polynomial rules have `.nat/.int/.rat/.real` variants, with
  the index cast to the result type; coefficients may be zero or signed
  where the type permits them.
  With this import, `auto` also recognizes counters and polynomial closed
  forms up to degree three, inferring coefficients from expressions such as
  `n*(n+2)` or `3-(n:ℤ)^3`. It checks the initial value and every recurrence
  step using the existing proved rules. Scaled sums such as `2*s n` work too;
  name auxiliary facts when needed, as in `auto [cr_closed]`.
  See `examples/compact_polynomial_recurrence.sat`.
  `auto` also recognizes shifted geometric formulas such as
  `4*f n+3 = 3*9^n` and, over signed types, `f n = A*r^n+B`.
  It checks the initial value and geometric step without a sign restriction
  on the rate, including zero and one. For natural numbers, put any constant
  offset on the sequence side. See `examples/compact_affine_geometric.sat`.
  Small closed-form identities also use the proved `recurrence.identity`
  induction pattern: `auto` checks the base and one step with the current-index
  equality as its induction hypothesis. This covers index factors such as
  `2*f n = n*2^n`, shifted exponents through `n+3`, and weighted geometric sums.
  The step uses bounded algebra, without another general proof search.
  See `examples/compact_recurrence_identities.sat`.
  Identities may also combine up to four distinct sequence values at the same index;
  their definitions or supplied initial values and step equations must prove
  the base and induction step. See
  [compact_coupled_recurrences.sat](examples/compact_coupled_recurrences.sat).
  When recursion changes a second argument, `auto` can keep that parameter
  universal in the induction hypothesis. Initial values and steps must hold
  for every parameter value; point assumptions are insufficient. See
  [compact_recurrence_families.sat](examples/compact_recurrence_families.sat).
  `geometric_linear f r c step n` recognizes `f(i+1) = r*f(i) + c*r^i`
  and proves `r*f(n) = (r*f(0) + c*n)*r^n` for all four numeric types.
  `geometric_linear_succ` gives `f(n+1) = (r*f(0) + c*(n+1))*r^n`,
  including at rate zero. For ℤ, ℚ and ℝ, `geometric_forcing_eq` handles
  `f(i+1) = r*f(i) + c*q^i` with arbitrary rates and initial value:
  `(q-r)*f(n) = (q-r)*f(0)*r^n + c*(q^n-r^n)`.
  `geometric_sum f r base step n` recognizes a local cumulative sum with
  `f(0) = 0` and `f(i+1) = f(i) + r^i`, proving `(1-r)*f(n) = 1-r^n`.
  With this import, `auto` recognizes geometric sums and proves the
  `geometric_forcing` bound from the initial value, step, and rate assumptions.
  Existing sequence definitions work directly; see
  `examples/compact_geometric_recurrence.sat`.
  These equalities require no division or sign assumptions; use
  `geometric_linear_succ` for an informative formula when the two rates agree.
  For natural sums, `auto` proves `r*s(n) + 1 = (r+1)^n` from zero initial
  value and increments `(r+1)^i`. The equivalent form
  `(r-1)*s(n) + 1 = r^n` requires `1 ≤ r`; subtraction on ℕ is truncated.
  See `examples/compact_natural_geometric.sat`.
* `import progression`: `sum_below.arithmetic a d n` sums `a + d*i` for
  `i < n`; `arithmetic_squares` sums `(a + d*i)²`. For ℚ and ℝ, the
  results are `n*a + d*n*(n-1)/2` and
  `n*a² + a*d*n*(n-1) + d²*n*(n-1)*(2*n-1)/6`.
  The `.int` variants multiply the sum by 2 or 6 to avoid division;
  `.nat` variants move negative terms to the left to avoid truncated
  subtraction. All permit empty sums, constant progressions and signed
  starts/steps where the type permits them.
  `recurrence.arithmetic_shift` and `square_shift` recognize local recursive
  sums: `s 0 a = 0`, and `s (i+1) a = a + s i (a+d)` or
  `a² + s i (a+d)`. The step must hold for every starting value `a`.
  `sum_below.index` and `index_squares` give the familiar sums of `i`
  and `i*i` directly, with `.rat/.real` variants.
* `import sequence_order`: `sequence.monotone` and `sequence.antitone` lift
  adjacent inequalities to any two ordered natural indices.
  Their `_on` variants need the step inequality only for `a ≤ i < b`.
  All four rules have `.nat/.int/.rat/.real` variants. For example,
  `sequence.antitone.rat f step a b hab` proves `f b ≤ f a`.
  `nat.interval_induct P a b hab base step` propagates a property across
  the same finite interval; the base and every step before `b` are required.
  `sequence.descent_on.nat f n step` bounds a natural-valued rank that loses
  at least one per step: `f n + n ≤ f 0`. `descent_length.nat` gives `n ≤ f 0`;
  both require the decrease only before `n`. With this import, `auto` applies
  interval monotonicity and these finite descent bounds directly from the
  step assumptions; see `examples/compact_sequence_order.sat`.
  `descent.nat` accepts a global
  step rule, `no_cyclic_descent.nat` excludes a nonempty decreasing cycle,
  and `no_infinite_descent.nat` excludes an infinite strictly decreasing rank.
* `import comparison`: `recurrence.compare.nat/.int/.rat/.real` compares
  two sequences from `f 0 ≤ g 0`, an upper recurrence for `f`, and a lower
  recurrence for `g`, both using `a i * value + b i`. Coefficients may vary
  with the index; premises are needed only before the requested endpoint.
  Signed multipliers must be nonnegative, while values and offsets may be
  negative. Zero multipliers and empty prefixes are supported.
* `import linear2`: elimination and uniqueness for two linear equations over
  ℤ, ℚ and ℝ. `linear2.eliminate` gives the two determinant identities without
  division, including singular systems. `linear2.unique` proves equal inputs
  from equal outputs when the determinant is nonzero; `linear2.zero` handles
  two homogeneous equations. Use `.int/.rat/.real` to choose the scalar type.
* `import amortized`: `run.final next xs s` executes requests in order;
  `run.total next cost xs s` adds costs evaluated before each transition.
  Both functions take state-first callbacks, `next state request` and
  `cost state request`. `run.potential` lifts a per-step cost/potential bound
  to a whole run while preserving a state invariant. `run.ratio` uses a
  multiplier times another accumulated cost; `run.ratio_bound` drops a
  nonnegative final potential and `run.ratio_zero` also uses zero initial
  potential. These rules have `.rat/.real/.int` variants and only require
  bounds on allowed requests and valid states. For a step theorem shaped as
  `∀ s, P s → ∀ x, Q x → P (next s x) ∧ cost s x + phi (next s x) - phi s ≤ c * opt s x`,
  `exact run.ratio.rat step_rule xs` proves the whole-run invariant and bound.
  `run.total_scale` factors a constant out of accumulated costs. Costs and
  multipliers may be negative; dropping the final potential requires its
  explicit nonnegativity premise.
* `import sequence`: rules for an existing sequence `s` with recurrence
  `rec : ∀ n, s (n + 1) = f (s n)`. `sequence.shift` and `eq_iterate` connect
  it to `function.iterate`; `sequence.invariant` propagates a step invariant.
  `sequence.stable` shows that a fixed state at index `k` persists for `j ≥ k`.
  `forall_of_stable` extends a property from the prefix through `k` to the
  whole sequence; `not_reachable_of_stable` rules out a target property.
  `repeat_after_equal` gives equal futures after equal states.
  For positive periods, `periodic_repeats` finds equal values beyond any bound,
  `periodic_tail` propagates a property from one full period, and
  `periodic_run_bound` bounds a constant run in a nonconstant sequence.
* `import finite_range`: finite pigeonhole and injection rules.
  `nat.inj_bound m n f bound inj` proves `m ≤ n` for an injection from
  `[0, m)` into `[0, n)`. `nat.inj_bound_le` handles inclusive endpoints
  and pairwise-distinct values. `nat.pigeonhole` produces ordered inputs
  `x < y` with equal images when `n < m`; `nat.pigeonhole_le` handles
  inclusive endpoints. `nat.inj_bound_of_missing` strengthens the size bound
  to `m < n` when a value inside the target range is unused.
  `nat.surjective_of_injective` gives preimages for an injection on `[0, n)`,
  and `nat.unique_preimage` also proves uniqueness within that range.
* `import sum_range`: finite-range sum congruence, strict comparisons and
  recurrence recognition over ℕ, ℤ, ℚ and ℝ. Basic splitting, constant bounds
  and partial-sum monotonicity are already included by `arith` (and `realx`).
  `sum_below.lt_of_le_of_exists_lt` needs weak inequalities throughout the
  range and one strict witness inside it. `sum_below.lt` uses strict
  inequalities throughout a nonempty range. `sum_below.le_const` and
  `sum_below.const_le` allow empty ranges and signed bounds; their strict
  counterparts `lt_const` and `const_lt` require a nonempty range.
  `sum_below.split.real f a b` splits the first `a + b` terms into the first
  `a` and the next `b`; all numeric rules have `.nat/.int/.rat/.real` variants.
  `sum_below.single` and `sum_below.single_out` evaluate sums of
  `f i * (if i = j then 1 else 0)` when `j < n` or `n ≤ j`, respectively.
  `sum_below.single_eq` also permits a separately proved selected value;
  `auto` composes these patterns for nested sums and combines evaluated sums
  with arithmetic, including offsets and local bounds. It also distributes
  small weighted summands, so sums of selected entries need no manual
  distributivity rewrites. All four numeric types are included by `arith`;
  subtraction distribution applies to ℤ, ℚ and ℝ.
  `auto` recognizes a cumulative sum from its zero base and additive recurrence
  (`sum_below.eq_of_recurrence`). It also telescopes successive differences over
  ℤ, ℚ and ℝ, and combines the result with endpoint bounds. Definitionally
  equivalent user-defined sums also use these rules, including wrappers and
  reordered arguments; see `running_total` in the compact sum examples.
  Constant summands and pointwise constant functions also sum with `auto`:
  `sum_below.eq_const` gives `n*c`, and `sum_below.eq_one` counts `n` terms
  equal to one (with the appropriate cast for ℤ, ℚ or ℝ).
  `sum_below.succ_front` extracts the first term and shifts the remaining
  indices by one; it is included by `arith` and used by `auto`. `sum_below.congr` is generic in the summands' type and is
  available with `import arith`; `auto` applies it without naming the lemma.
  `arith` also provides `sum_below.swap` for exchanging two rectangular
  summation ranges, used by `auto` across all four numeric types.
  `sum_below.exchange` exchanges weighted sums when the weighted entries agree
  throughout the rectangle; `auto` proves this condition from algebra or local
  assumptions. Weights may be signed. `sum_below.scale` and `sum_below.add`
  similarly lift termwise scaling or addition identities. `sum_below.sub` lifts
  subtraction over ℤ, ℚ and ℝ. `auto` checks their local premises, including
  identities established by arithmetic.
  `sum_below.mono f a b hab nonneg` compares two partial sums when only
  the added terms, `a ≤ i < b`, are nonnegative; it has all four numeric
  variants and permits negative terms before `a`.
  `sum_below.eq_of_recurrence f s base step n` recognizes a local cumulative
  sum: from `s 0 = 0` and `s (i + 1) = s i + f i`, it proves
  `s n = sum_below n f`. It works for any summand type and uses only the kernel.
* `import quadratic` (also included by `arith`): square-order comparisons and
  weighted-product bounds over ℕ, ℤ, ℚ and ℝ. `le_of_mul_self_le_mul_self`
  removes squares with a nonnegative right-hand value; the corresponding
  `mul_self_le_mul_self_iff` compares squares of two nonnegative values.
  Both have strict variants. `le_mul_of_le_mul_self` combines two lower
  bounds on weighted squares into a lower bound on the weighted product;
  `mul_le_of_mul_self_le` does the same for upper bounds. Weights must be
  nonnegative. Lower bounds need a nonnegative product; upper bounds allow
  either sign of the product. Natural variants
  need no sign premises. All variants are proved from the existing axioms.
  `quadratic_form.bound.real a b c q` extracts `b² ≤ a*c` from
  `q : ∀ x y, 0 ≤ x²*a - 2*x*y*b + y²*c`; `.rat` and `.int` also work,
  including zero diagonal coefficients.
* `import list_sum`: comparison, nonnegativity, member bounds and scalar
  multiplication for list-indexed sums over ℕ, ℤ, ℚ and ℝ; addition and
  concatenation identities, plus subtraction and negation over ℤ, ℚ and ℝ.
  `list_sum.congr` uses equality on list members, and `list_sum.map` composes
  the summand with a map. `list_sum.closed`
  lifts any property preserved by zero and addition to a sum. `sum_multiple.nat`
  replaces the induction showing that a list sum of multiples is a multiple;
  `sum_list_multiple.nat/.int` handles indexed summands, including zero or
  negative integer multipliers. `sum_list_dvd.nat` and `sum_dvd.nat` use `∣` notation.
  `sum_list_weighted_le`, `sum_list_weighted_lower` and `sum_list_weighted_upper`
  compare weighted sums or lift a pointwise bound. `sum_list_double_lower` and
  `sum_list_double_upper` lift bounds through two independently indexed sums.
  Each has `.nat/.int/.rat/.real` variants; signed weights need only be nonnegative
  on list members, and the bound may be negative. For example, given nonnegative
  weights and `∀ x ∈ xs, ∀ y ∈ ys, m ≤ f x y`, a double-sum lower bound is
  `by apply sum_list_double_lower.real xs ys w v f m <;> auto`.
* `import sum_support`: vanishing and positivity of bounded and list-indexed sums.
  `sum_below.zero` sums constant zero without an arithmetic oracle.
  It and `sum_below.eq_zero`, which sums pointwise zeros, are included by
  `arith` and used by plain `auto`. `sum_below.eq_zero_iff` says a
  nonnegative sum vanishes exactly when all its terms vanish. `sum_below.pos_iff`
  characterizes positivity by one positive term, and `sum_below.pos` handles a
  nonempty range of strictly positive terms. `list_sum.eq_zero`,
  `list_sum.eq_zero_iff` and `list_sum.pos_iff` use list membership, including
  empty lists and repeated elements. Each has `.nat/.int/.rat/.real` variants;
  the signed `_iff` rules require nonnegativity only within the index set.
  For example, `(sum_below.eq_zero_iff.rat f n nonneg).mp total_zero` replaces
  the induction showing that every summand is zero.
* `import sum_squares`: nonnegativity and zero detection for finite sums of
  squares, with `.nat/.int/.rat/.real` variants. `list_sum.squares_eq_zero_iff`
  says `Σ f(x)² = 0` exactly when every member's value is zero.
  `list_sum.weighted_squares_eq_zero_iff` gives the same result for strictly
  positive weights: `(list_sum.weighted_squares_eq_zero_iff.rat xs w f positive).mp total_zero`.
  `list_sum.squares_nonneg` and `list_sum.weighted_squares_nonneg` prove the
  corresponding lower bounds; the latter only needs nonnegative weights
  (automatic for naturals). Empty lists and repeated members are supported.
* `import cauchy`: weighted and unweighted Cauchy–Schwarz over ℤ, ℚ and ℝ.
  `sum_below.weighted_cauchy.real n w f g nonneg` proves
  `(Σ w*f*g)² ≤ (Σ w*f²)*(Σ w*g²)` when `w i ≥ 0` for `i < n`.
  `list_sum.weighted_cauchy.real xs w f g nonneg` uses list membership
  instead; empty lists, repeated members and zero weights are supported.
  Use `sum_below.cauchy.real n f g` or `list_sum.cauchy.real xs f g` for
  unweighted sums. Both families also provide `weighted_square_expand`
  for expanding `Σ w*(x*f-y*g)²`. The `.rat` and `.int` variants have the
  same arguments.
* `import euclidean`: real norm bounds for lists and bounded sums.
  `sum_below.weighted_cauchy_sqrt.real n w f g nonneg` proves
  `|Σ w*f*g| ≤ √(Σ w*f²)*√(Σ w*g²)`; `weighted_minkowski.real` proves
  `√(Σ w*(f+g)²) ≤ √(Σ w*f²)+√(Σ w*g²)`. Weights only need to be
  nonnegative on the summed domain. The corresponding `list_sum` rules use
  list membership. Omit `w nonneg` with `cauchy_sqrt.real` or `minkowski.real`
  for unweighted sums. `norm2.add_le a b c d` gives the two-coordinate
  triangle inequality; `norm2.sub_le` gives its reverse-triangle bound.
  `abs_le_sqrt_mul x a b ha hb h` (also in `realx`) converts `x² ≤ a*b`
  to `|x| ≤ √a*√b` when `a` and `b` are nonnegative.
* `import entropy`: scalar and finite entropy bounds, including zero masses.
  `mul_log_tangent_le a x ha hx` proves `x*log a+x-a ≤ x*log x` for
  `a > 0`, `x ≥ 0`; `mul_log_tangent_lt` adds `x ≠ a` for strictness.
  `sub_one_le_mul_log x hx` specializes to `x-1 ≤ x*log x`.
  `neg_mul_log_le_scale x c hx hc` gives
  `-x*log x ≤ x*(log c-1)+1/c` for `c > 0`.
  `neg_mul_log_le_of_le x t ht h` gives `-x*log x ≤ x*log(1/t)` when
  `0 < t ≤ x`. Finally, `sum_below.entropy_le_log.real n p hn hp mass`
  proves `Σ -p*log p ≤ log n`, requiring a positive alphabet size,
  nonnegative masses on `i < n` and `Σ p = 1`. No value for `log 0`
  is assumed: its zero coefficient is enough.
* `import log_convex`: positive-domain logarithmic concavity.
  `log_tangent_le x y hx hy` proves `x*log y ≤ x*log x+y-x`;
  `log_tangent_lt` adds `hne : x ≠ y` for a strict bound.
  `log_weighted_jensen x y z a b hx hy hz ha hb mean` proves
  `a*log x+b*log y ≤ (a+b)*log z` from `(a+b)*z = a*x+b*y`,
  positive `x,y,z` and nonnegative weights. For strictness, use
  `log_weighted_jensen_lt x y z a b hx hy ha hb hne mean` with
  positive weights and distinct inputs; positivity of `z` follows from the
  mean. `log_midpoint_le` and `log_midpoint_lt` specialize to equal weights.
  This module imports only `exp_convex` and its real foundations.
* `import square_gap`: `square_gap.le_abs.real a b ha hb` proves
  `(a-b)*(a-b) ≤ |a*a-b*b|` for nonnegative `a` and `b`; `.rat` and `.int`
  have the same arguments.
* `import sqrt_distance`: `sqrt_sub_sq_le_abs x y hx hy` proves
  `(√x-√y)² ≤ |x-y|`; `sqrt_sub_abs_le` gives `|√x-√y| ≤ √|x-y|`.
  Both require `x,y ≥ 0`. `sum_below.weighted_sqrt_distance.real n w f g hw hf hg`
  sums the squared bound: `Σ w*(√f-√g)² ≤ Σ w*|f-g|`, with nonnegative
  weights and values on `i < n`. `list_sum.weighted_sqrt_distance.real`
  uses list membership. Omit `w hw` with `sqrt_distance.real` for unweighted
  sums; zero weights and empty domains are allowed.
* `import geometric_mean`: weighted geometric-mean bounds.
  `sum_below.weighted_sqrt_mul_le.real n w f g hw hf hg` proves
  `Σ w*√(f*g) ≤ √((Σ w*f)*(Σ w*g))`. The three hypotheses require
  `w`, `f` and `g` to be nonnegative only for `i < n`.
  `list_sum.weighted_sqrt_mul_le.real xs w f g hw hf hg` uses list
  membership; empty domains, repeated members and zero weights work too.
  Omit `w hw` with `sqrt_mul_le.real` for unweighted sums.
  `sqrt_mul.weighted_add_le x1 y1 x2 y2 a b h1 h2 h3 h4 ha hb`
  gives `a*√(x1*y1)+b*√(x2*y2) ≤ √((a*x1+b*x2)*(a*y1+b*y2))`.
  `sqrt_mul.add_le x1 y1 x2 y2 h1 h2 h3 h4` sets both weights to one.
* `import convex`: concavity, convexity and finite Jensen on a closed interval,
  over ℚ and ℝ. `concave_interval.real lo hi f` states the two-point
  weighted-mean inequality without division. Its `convex_interval` counterpart
  reverses the inequality. `sum_below.concave_jensen.real lo hi f hf n p m domain mean`
  proves `Σ f(p j) ≤ n*f(m)` from `n*m = Σ p j`; `convex_jensen` reverses
  the bound. Empty sums work too. `concave_jensen_succ` uses `n+1` sites
  and the mean coefficient `(n : ℝ)+1` directly.
  `concave_interval.sub_convex` closes concavity under subtracting a convex
  function; `concave_interval.mono_below_max` compares values below an
  interval maximizer. Replace `.real` with `.rat` for rational functions.
  `convex_interval.affine.real lo hi a b` and `concave_interval.affine.real`
  handle affine functions of either slope; `convex_interval.square.real lo hi`
  handles `x²`. These instances also have rational variants.
* `import exp_convex`: `exp_tangent_le x y`, `exp_weighted_jensen x y z a b ha hb mean`,
  and `exp_midpoint_le x y`. The weighted bound requires nonnegative weights
  and `(a+b)*z = a*x+b*y`; zero weights are allowed. This small module avoids
  the unrelated definitions in `arith`; `realx` also includes it.
  `one_add_lt_exp x hne` makes `1+x ≤ exp x` strict when `x ≠ 0`.
  `exp_tangent_lt x y hne` and `exp_midpoint_lt x y hne` require `x ≠ y`.
  `exp_weighted_jensen_lt x y z a b ha hb hne mean` requires both weights
  positive and the inputs distinct; it uses the same mean equation.
* `import convex_real`: the exponential instance `convex_interval.exp.real lo hi`
  and the unrestricted finite bound `sum_below.exp_jensen.real n p m mean`,
  which proves `n*exp m ≤ Σ exp(p i)` from `n*m = Σ p i`, including `n = 0`.
* `import indicator`: numeric indicators of propositions over ℕ, ℤ, ℚ and ℝ,
  with proved bounds, monotonicity, complement, intersection and union laws. For
  example, `indicator.and.real p q` proves that the indicator of `p ∧ q` is the
  product of their indicators; `indicator.or_le.nat p q` gives the union bound.
* `import list_product`: product congruence, mapping and multiplicative
  invariants, plus nonnegativity, comparison, concatenation and pointwise
  multiplication over ℕ, ℤ, ℚ and ℝ. `one_add_sum_list_le_prod_list` proves
  `1 + Σ f(x) ≤ Π (1 + f(x))` from nonnegative summands; its `.nat` variant
  needs no sign premise. Signed product comparison needs nonnegative lower
  factors, and `prod_list_one_le` needs factors at least one. Empty products
  are one, and repeated members contribute repeatedly.
* `import real`: `is_sup` with `sup_exists`, `sqrt exp log sin cos pi` with their
  basic laws, `tends_to converges continuous_at continuous summable bounded_seq
  monotone_seq` (ε–δ definitions).
* `import graph`: graphs as adjacency predicates on `0..n-1`; `simple
  edge_list_adj proper_coloring colorable color_assignment clique independent
  degree regular consecutive distinct_list hamiltonian_cycle`.
  `color_assignment` is the sat-friendly colouring form, e.g.
  `+ k4 (x : ℕ → ℕ → Prop) : ¬ color_assignment 4 3 k4 x := by intro h; sat`.
* Recursive numeric list identities also work with `auto`: Satori checks the
  empty list and one cons step. Definitions may combine several list totals;
  supply auxiliary identities with `auto [lemma]` when needed. This pattern
  is available in the default prelude.
  See [compact_list_identities.sat](examples/compact_list_identities.sat).
  Small list bounds also use `auto`, including memberwise assumptions,
  recursive nonnegativity conditions, and conditional summands. Both the
  empty case and the step must follow from the supplied assumptions.
  See [compact_list_bounds.sat](examples/compact_list_bounds.sat).
  `simp` splits `∀ y ∈ x :: xs, P y` into the head fact and tail condition.
* Traversal invariants also use `auto`, including several properties preserved
  together. For `list.foldl` and `list.foldr`, the step may depend on membership
  in the traversed list. Satori also checks recursive traversals with a changing
  final state argument, generalizing that state in the induction hypothesis.
  Use `auto [step_inv]` to supply a previously proved preservation rule; the
  initial state must still satisfy the invariant. These patterns are included
  in the default prelude.
  See [compact_fold_invariants.sat](examples/compact_fold_invariants.sat).
  Relations between traversals and formulas also use `auto`, including several
  coordinate equalities together and a state that changes on recursive calls.
  Use `auto [step_act]` when the relation needs a local calculation. Equality
  directions may differ between coordinates, and guards on step facts remain
  proof obligations.
  See [compact_list_relations.sat](examples/compact_list_relations.sat).
* `auto` also checks small enumerations, combining constructor cases with
  algebra and local bounds. It can handle two variables with up to four cases
  each, including conditions that exclude some cases. Every remaining case
  must still be proved.
  See [compact_finite_cases.sat](examples/compact_finite_cases.sat).
  These cases also work inside list identities, including numeric observations
  of structured recursive results. Supply an algebraic rule when needed, as in
  `auto [det_mul]` for a determinant of a matrix product.
  See [compact_enum_lists.sat](examples/compact_enum_lists.sat).
* Small arithmetic goals can use local definitions directly. `auto` also opens
  definitions in hypotheses and supplied facts, so a bound on a named quantity
  need not start with an `unfold` or `simp` step. Conditions on supplied rules
  still have to follow from the assumptions.
  See [compact_defined_arithmetic.sat](examples/compact_defined_arithmetic.sat).
* `import power`: `auto` recognizes `a^(m+n) = a^m*a^n`,
  `a^(m*n) = (a^m)^n`, and `(a*b)^n = a^n*b^n` in either direction,
  over ℕ, ℤ, ℚ, and ℝ. Also included by `arith`.
  See [compact_power_identities.sat](examples/compact_power_identities.sat).
* `import arith`: the elementary library (proved lemmas with no added axioms), stated per type with suffixes
  `.nat .int .rat .real`: abs (`abs_mul`, `abs_add`, `abs_sub_le`, `abs_le`, …), min/max, products and order (`mul_le_mul`,
  `sub_nonneg`, …), powers (`pow_add`, `pow_le_pow_left`, `one_le_pow`, `lt_two_pow`, …), ℕ/ℤ division and remainder
  (`div_mod_unique`, `add_mul_mod`, `mod_two_cases`, …), min/max distance identities and non-expansive clamps, field division (`div_le_iff`, `mul_div_cancel`, …), weighted variance gaps over ℚ and ℝ, casts ℕ→ℤ→ℚ→ℝ
  (`cast_add`, `cast_le`, `int_cast_pow`, …), `fact` and `choose` (Pascal, `choose_two`, `choose_mul_fact`, `choose_symm`),
  sums (`sum_le`, `sum_telescope`, `geom_sum_mul`, `sum_congr`, `sum_below.split`,
  `sum_below.const_le`, `sum_below.le_const`, `sum_below.mono`, …), the binomial theorem (`add_pow.nat`), products
  (`prod_eq_zero_iff`), Euclid's lemma (`prime_dvd_mul`, `prime_dvd_of_dvd_pow` on ℕ and ℤ), `Int.toNat` facts
  (`nat_of_int_le`) and integer sign/parity cases with natural witnesses, Bernoulli's inequality. It costs about 1 s per theorem process to load.
  `div_le_div_iff.real a b c d hc hd` turns `a/c ≤ b/d` into
  `a*d ≤ b*c` for positive denominators `c,d`, with arbitrary signed numerators.
  `div_lt_div_iff` handles strict comparisons; both also have `.rat` variants.
* `import realx`: `real` + `arith` + exp/log/sqrt facts (`exp_le_exp`, `exp_le_inv_one_sub`, `log_le_sub_one`, `sqrt_mul`, …)
  including reciprocal-root certificates. `(one_div_sqrt_le_div_iff B m c hB hm hc).mpr h`
  proves `1/√B ≤ m/c` from `h : c*c ≤ m*m*B`, given `B > 0`, `m ≥ 0`, `c > 0`.
  `div_le_one_div_sqrt_iff` handles the opposite bound; replacing `le` with
  `lt` handles strict bounds. Use `.mp` to recover the polynomial certificate.
  The module also provides the Archimedean property of ℝ (`exists_nat_gt.real`, from `sup_exists`); Taylor-type bounds `quadratic_le_exp_of_nonneg`
  and `abs_exp_sub_one_sub_id_le`; `-x` forms `exp_neg'`, `exp_neg_mul'`.
* `import hyperbolic`: `realx` + `sinh cosh` (Mathlib's definitions) with `sinh_neg cosh_neg cosh_add sinh_add
  cosh_sq_sub_sinh_sq sinh_pos_iff sinh_ne_zero cosh_pos one_le_cosh self_lt_sinh_iff …`. A separate module, so files that
  define their own sinh / cosh can still import `realx`.
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

**A new result, kernel-checked.** `~/math/openai/families/156-borsuk-nine/borsuk_eleven.sat` proves
`borsuk_number_eleven`: the Borsuk number of OpenAI's nine-dimensional projector set is exactly 11. OpenAI's paper leaves that
value open. The file has 83 theorems, checks in 55 s, and its trust base is
`[oracle:arith, oracle:ring, oracle:sat, axiom:minkowski_weyl, axiom:openai_cover_to_ten_system]`:
- the 11-cell certificate is checked by `decide`;
- the Voronoi and convexity argument is proved;
- the textbook representation theorem enters as one generic axiom;
- the lower bound uses OpenAI's own Lean reduction and the 3-line `no_ten_system`.

The same certificate check on ten centres fails, as it must.

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
* **Every like-for-like row in the family READMEs.** Each row below has the same statement proved, or the same object defined,
  on both sides, collected from the "Satori vs Lean" sections of all 372 READMEs. Rows where Satori checks instances and Lean proves
  the general case are excluded.

  | family | statement or object | Lean | Satori |
  |---|---|---|---|
  | 005 | mod-101 matrix certificate, all 3·48² cells | 395,415 lines (`FiniteMatrices/`) | 72 one-line `decide` theorems |
  | 156 | no ten-system exists | 66,297 lines (`FiniteCases/`) | 3 lines |
  | 156 | the ten-system definition | ≈ 20 lines | 15 lines |
  | 173 | Seymour's second-neighbourhood theorem from its two halves | 22 lines (`Main.lean`) | 12 lines |
  | 173 | the model: oriented graph, first and second neighbourhoods, images | 313 lines | ≈ 20 lines |
  | 050 | the ampleness inequalities | 384 lines (for the paper's b) | 25 lines (for every b ≥ 6) |
  | 162 | hypergraph, cover, intersecting | 48 lines | 6 lines |
  | 028 | the Gaussian-moat model (graph, endpoints) | 38 lines | ≈ 10 lines |
  | 021 | the Jacobsthal statement | 20 lines | 8 lines |

  On these rows Satori is never longer. The ratio runs from about 1.3× (small definitions) to more than 20,000× (finite
  certificates, where the evaluator and `sat` replace step-by-step kernel proofs). These rows are computation-heavy, though, and
  the systematic benchmark below shows they are not representative.
* **Systematic benchmark, two rounds.** In `~/math/openai/benchmarks/like_for_like/`, 339 fully proved Lean lemmas from
  107 families were re-proved in Satori with the same statement and generality. All of them check, with no axiom tags.
  - **Round 1** used the original Satori: no library, no `nlinarith`/`positivity`/`omega`. Satori came out **2.0× longer**.
    Files re-proved abs, min/max, pow, cast and div/mod facts by hand.
  - **Round 2** (`like_for_like_v2/`) re-proved the same 339 statements after `import arith` (561 proved lemmas) and the
    new tactics were added. The coordinator checked the statements identical, all files checking, and no axioms.

  | | Lean + Mathlib | Satori round 1 | Satori round 2 |
  |---|---|---|---|
  | statement + proof lines | 2,306 | 4,642 | **1,293** |
  | aggregate / median line ratio Satori/Lean | | 2.00 / 1.71 | **0.57 / 0.55** |
  | non-whitespace characters (layout-independent) | 69,973 | 89,593 | **58,336** (0.83×) |
  | Satori shorter / equal / longer (lines) | | 61 / 25 / 253 | **266 / 51 / 22** |

  **Round 3** (`like_for_like_v3/`) closed the remaining losses with `nlinarith` over ℕ and 102 more Mathlib-backed library lemmas
  (`import hyperbolic` for sinh/cosh). On 343 pairs Satori is **0.54× Lean in lines and 0.82× in characters**: shorter in 280
  pairs, equal in 62, and longer only in 027, whose short proof needs a 3-line `iter` definition that Mathlib supplies.

  The remaining 22 losses need library lemmas Satori lacks (`zero_pow`, prime divisibility, sinh/cosh, ℕ division) or
  `field_simp`, `split_ifs` and `nlinarith` over ℕ. The round-2 README lists each loss and its cause.
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

The file also holds four parser-trap cases (TUNGSTEN_ISSUES #98, #100, #105). In those, a proof block is dropped or misread, and
the check fails closed with "unsolved goals" or an unknown name. A false goal is never admitted.

Two more cases (`leak4`, `leak5`) record a tactic bug found on 2026-10-12. `obtain ⟨a, b⟩ | ⟨c, d⟩` continued the second
alternative's tuple on the globally first open goal, so `d` appeared in the first branch. Even before the fix
(`destruct_rest` in `lib/tactics.w`), the kernel refused both false theorems: "proof leaves assumptions: 1 < 0 ∧ 1 < 0" and
"x is free in hypothesis". The tactic layer is untrusted, and the kernel's assumption tracking caught the bug.

`spec/auto_truth_table.py` independently evaluates 2,704 two-variable propositional
formulas and checks both that `auto` proves each valid case and rejects each invalid
one. Run `sh bits/tungsten-satori/spec/cli_spec.sh /path/to/satori` from the
Tungsten root to run this audit and the focused CLI and automation regressions against
a freshly built binary.

Run an interpreted proof spec with `python3 scripts/run-satori-spec.py SPEC.w`
from the Tungsten root. The runner serializes Satori interpreters across test
invocations and applies a 2048 MiB footprint limit. Set `SATORI_TEST_MEMORY_MB`
to a value from 1 to 4096 to adjust it.

Run the whole file with `satori check -j 1 spec/must_fail.sat`. The expected verdict is `FAILED (20)`, with f9 checked and
tagged. Split workers use the executable running the driver; rebuild the installed
`bits/tungsten-satori/bin/satori` to test source changes through that binary.
`spec/core_axioms_spec.w` evaluates the 194 foundational axioms on 4,575 random instances: 0 contradictions.
`spec/kernel_smoke.w` exercises the inference rules. As of
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
* **Name and packaging.** Decided by the owner on 2026-10-12, and confirmed after considering the alternatives: **keep "wassat" as
  is, as its own bit**. The alternatives were renaming it (koan, lantern, spar, saturn, satellite) and rolling it into Satori as a
  second binary. Satori keeps calling it as a separate, watchdog-guarded process whose LRAT proofs the kernel re-checks. For reference: the suggested replacement was **koan**: a short puzzle whose answer is checked, next to
  Satori. Alternatives: *lantern*, *spar*. The rename is the owner's call and is not done here, because the bit's name is referenced
  by other active projects (`~/math` SAT campaigns, DETOUR's SAT rollout, Lonely Runner certificates, the `.wrat` format). Satori itself
  depends on the name in exactly two places, the Bitfile line and the default path in `satbridge.w`. After a rename, set
  `SATORI_SOLVER` or update those two lines.
