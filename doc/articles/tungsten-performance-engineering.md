# Making a search fast in Tungsten: a codegen bug, a leak, and an 18× speedup

Writing a tight inner-loop search in Tungsten surfaced three problems in
succession — a compiler codegen bug, a memory leak that OOM'd the machine in
seconds, and a 10–18× performance gap. Each had a clean root cause, and the last
one produced a rule that applies to *any* performance-critical Tungsten code.

## 1. The codegen bug: boxed values in raw `i64[]` slots

The search stores schemes in `i64[]` arrays. Storing a value computed by an
expression (`a[i] = a[j] ^ a[k]`) worked, but storing a **function return** or a
**plain variable** (`a[i] = f(x)`, `a[i] = local`) wrote a NaN-box-tagged
`0xFFFA…` value into the raw slot — silently corrupting it. (This is what
originally forced prototyping the algorithm in Python.)

Root cause, in `compiler/lib/lowering/calls.w` (the typed-array `[]=` handler): it
unboxed a polymorphic `:int` RHS before the store, but a `:i64` RHS — the
emitter's tag for a *boxed WValue* from a function return or a variable — fell
through to the boxed path. Direct arithmetic was already raw, which is why only
those two RHS shapes corrupted.

The fix was one token — extend the unbox case from `:int` to `:int :i64`:

```
elsif val_expr[:type] in (:int :i64) && recv_type != :typed_array_w64
  val_reg = nanunbox_int_emit(wfn, ensure_i64_value(wfn, val_expr))
```

Verified: a characterization probe (all RHS shapes store raw), the two-stage
bootstrap **byte-identical (stage 1 .ll == stage 2 .ll)**, and no regression in the
GPU flip-graph or specs. With it, integer-array search code reads the same in
Tungsten as in any other language.

## 2. The leak: a bignum on every RNG multiply

With 18 walkers the machine OOM'd in ~20 seconds. RSS grew a perfectly linear
**~375 MB/second** per walker. The arrays are a fixed ~22 KB, so this was a
per-move heap leak of ~107 bytes/move.

The profiler and a bisecting set of micro-benchmarks pinned it to the RNG:

```
rng = (rng * 1103515245 + 12345) % 2147483648
```

Tungsten's default `Int` is arbitrary-precision. Small ints are NaN-boxed (no
heap), but the **intermediate `rng * 1103515245` reaches ~2.4×10¹⁸**, far above the
~2⁴⁸ small-int ceiling — so it allocates a **heap bignum every multiply**, which
escape analysis doesn't free. Three RNG draws per move × ~35 bytes ≈ the measured
375 MB/s.

Two fixes work. Park–Miller `(rng * 16807) % 2147483647` keeps the intermediate
under 2⁴⁸ so it stays NaN-boxed — but that's a *workaround*: it still allocates
and frees. The real fix is to type `rng` as a fixed-width integer:

```
rng = base * 1009 + 12345 ## i64
```

Now the multiply is a single hardware 64-bit op that wraps — **no allocation, no
2⁴⁸ constraint, and ~3× faster** than the boxed Park–Miller (1.36 s → 0.46 s for
200M iterations). Confirmed flat at 8 MB RSS.

## 3. The 18× speedup: stop guessing, profile

The search ran at 0.55 Mmoves/s on 5×5. Five hand-guesses — wrapping the loop in a
function (to make variables local), gating an O(rank) duplicate-scan to every 8th
move, adding an early-exit to the partner search — *each changed nothing*. They
optimized operation **count**; the real cost was per-operation.

`sample <pid> 4` on the running binary found it in seconds:

```
351  w_eq   → bigint_compare
187  w_add
 63  w_mod
 59  w_lt
```

Every `us[jj] == ui`, every `scan < rank`, every `(st+scan) % rank` in the hot
loop was a **function call into arbitrary-precision integer helpers** — because the
loop variables were default `Int`. The `i64[]` *reads* are raw, but the moment a
value lands in an un-typed variable (`ui`, `scan`, `rank`, `au`…), arithmetic on it
boxes.

The fix: type the hot-path variables `## i64`, so the loop compiles to raw
`icmp`/`add`/`urem`:

```
ui = us[ti] ## i64
scan = 0 ## i64
rank = 0 ## i64
```

Result — **18× on 5×5 (0.55 → 10.0 Mmoves/s) and 10.5× on 3×3 (2.7 → 28.5)**, with
correctness intact. Re-profiling confirmed `w_eq`/`bigint_compare` *gone*; time now
sits in `main` (the raw loop) where it belongs.

## The rule

For performance-critical compiled Tungsten:

1. **Type hot-loop scalar variables `## i64`** (or `## u64`). The default `Int`
   boxes, and every compare/add/mod on a boxed value is a bignum function call.
2. **Profile, don't guess.** `sample` on the native binary tells you in seconds
   whether you're CPU-bound on `bigint_*`/`w_*` helpers. Five intuition-driven
   edits missed what one profile showed immediately.
3. Things that were *already* fine and didn't need touching: `i64[]` array reads
   are raw; `[]`/`[]=` are bounds-free (inline GEP, no checks); fixed-size arrays
   allocate once. And `break` exists (`KIND_BREAK`) — no need to emulate it with
   `scan = rank`.

The same root cause — default-`Int` boxing — produced all three problems: the
codegen bug (a boxed value in a raw slot), the leak (a bignum per multiply), and
the slowdown (bignum helpers per compare). Fixed-width typing is the through-line.
