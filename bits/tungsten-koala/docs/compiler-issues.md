# Compiler / runtime issues that hurt koala

These are **upstream** bugs and gaps. Koala is full of workarounds; fixing
them here shrinks the bit and removes silent footguns for every Tungsten
program, not just ML.

## P0 — correctness (fix or keep forever-workarounds)

### 1. Float literal argument poison — FIXED / use `~1.0`

Fixtures under `spec/fixtures/repros/float_literal_poison/` are green.
Prefer **`~0.1`** for float literals (language form). Decimal `0.1` also
works on current engines; koala’s `1.to_f / 10.to_f` style remains fine.

### 2. `@ivar` invisible inside block bodies — mostly OK

Simple `@items.each` works on both engines with `-> new(@items)`. Prefer
the `@param` constructor form. Koala may still hoist defensively.

### 3. Sibling-closure local counter miscompile — **FIXED**

WIRE `dead_store_elim` no longer kills capture flushes when a later
reassignment stores to the same escaped slot. Always-flush in
`lower_block_closure` keeps the live value in the frame slot. See
`docs/compiler-answers.md`.

### 4. Bare tail array-literal parse bug — **FIXED**

Parser treats call-with-block as a block node; next-line `[` starts a new
statement.

## P1 — portability / dual-engine

### 5. `type(instance)` is `"Hash"` on the interpreter — **FIXED**

`type` / `class` use `w_type_name` → real class name on both engines.

### 6. Trait composition (`with OtherTrait`) does not run interpreted

**Symptom:** Flat traits only; `Estimable` restates `Tunable` methods.

**Fix:** Interpreter support for trait composition, or codegen that flattens
at parse time consistently on both engines.

### 7. `File` / `IO` missing on the interpreter

**Symptom:** `Persist.save(path)` cannot be dual-engine; CSV path helpers
must be compiled-only or string-based.

**Fix:** Either stub File on the interpreter (read/write temp + cwd) or
document compiled-only I/O as a language rule and give koala dual APIs
(`from_csv_string` always; `read_csv` compiled).

### 8. Hash key iteration order differs by engine

**Symptom:** `.keys` order is unstable across engines → non-deterministic
payloads and CV folds if used for enumeration order.

**Koala workaround:** Sort keys by `to_s`; never enumerate hash keys for
ordering-sensitive work; first-appearance scans for class labels.

**Fix:** Document deterministic insertion order (or require sorted
enumeration in the language spec) and enforce on both engines.

### 9. `Float#to_s` is only ~6 significant digits — **FIXED**

`w_to_s` uses `%.17g` (f64 round-trip).

## P2 — API / performance (not blockers, but koala needs them)

### 10. Class-side factories on interpreter — **FIXED** (Tensor ccalls)

Interpreter registers `w_array_new_aligned` and Tensor/BLAS ccalls.
`Tensor.zeros([2, 3])` works interpreted.

### 11. Top-level `fn` memoization vs impure ccall

`core/blas.w` documents `fn` bodies being memoized incorrectly for
allocating ccalls (`w_array_new_aligned`). Worked around with `->` form.
Worth fixing the purity allowlist so `fn` is safe for allocators.

### 12. Array `+` / some Array APIs unavailable

Koala builds arrays with `push` only. Completing Array surface reduces
noise.

### 13. `return` inside closure-bearing methods

Koala avoids early `return` in methods that contain closures (see
`stats.w` notes). Either fix control-flow lowering or keep the rule in the
style guide.

## Suggested fix order (compiler team)

1. Float literal poison (P0) — unlocks readable defaults in every estimator.
2. Ivar-in-block (P0) — drops half the “hoist locals” boilerplate.
3. Sibling-closure capture (P0) — safety for weighted loops.
4. Bare tail array literal (P0).
5. `type` for instances (P1).
6. Trait composition (P1).
7. File on interpreter **or** formal dual-engine I/O story (P1).
8. Deterministic hash order + full float printing (P1).

Until (1)–(3) land, **do not** “clean up” koala by reintroducing float
literals or bare `@` inside blocks — the specs will flake by engine.
