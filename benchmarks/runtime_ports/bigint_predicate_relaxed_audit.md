# BigInt predicate relaxed-gate audit

Status: completed on 2026-07-15. The full matched-root correctness campaign and
two independently rebuilt timing campaigns passed. All five source migrations
are retained; all five corresponding C ICs may be removed.

Integration status: retained in the shared tree after the separate
`BigInt#to_i` identity port. The combined production shape has six BigInt ICs
removed, now uses loader epoch `v16` after the later Float leaf integration,
and preserves the predicate autoload and
native-field bridges described below. The runner's static audit was rebased to
that combined shape; the recorded campaign binaries and 52 timing rows remain
the isolated predicate-only evidence.

Isolated roots (both at `f62869bff0fc22fdc0a3179c82fb5da158d987d6`):

- baseline: `/tmp/tungsten-bigint-predicate-relaxed-baseline`
- candidate: `/tmp/tungsten-bigint-predicate-relaxed-candidate`

## Why the old result is not dispositive

`run_bigint_leaf.sh` was a useful semantic/direct-load probe, but it did not
measure the production transition. Its C leg called an ordinary benchmark
method wrapping a C reference, whereas the installed public native IC uses the
cached handler ABI with arity `-1`. Under the earlier strict 0.97 policy, direct
`negative?` sometimes passed (about 0.954) and direct `even?` passed once then
failed its repeat (about 0.961 then 1.085). Those noisy/ABI-mismatched results
justify a true public revisit under the requested 1.10 ceiling; they do not
justify retaining or removing any handler by themselves.

## Candidate representation bodies

`WBigint.size` is a signed `int32_t`: its sign is the number sign and its
absolute value is the logical limb count. The declared view therefore retains
`i32 length`, and every method explicitly binds `$length ## i64`. The compiler
must emit an offset-4 `load i32` followed by `sext i32`, not zero extension.

Only parity needs limb storage. The first word of C's flexible `limbs[]` tail is
declared as the view field `u64 limb0` at offset 16. This is intentionally not
an Array facade. Compiled `even?`/`odd?` branch on zero before loading it, then
perform one raw `and 1`; the interpreter bridge exposes the same word as an
unsigned arbitrary-precision Integer. LLVM gates require the offset-16 i64 load
and reject numeric/method calls.

The source truth table is exactly the native representation truth table:

- `zero?`: signed size equals zero;
- `even?`: size zero, or low limb is even;
- `odd?`: size nonzero, and low limb is odd;
- `negative?`: signed size is negative;
- `positive?`: signed size is positive.

There is no representable “negative zero”: two's-complement `int32_t` has only
one zero bit pattern. A heap BigInt with `size == 0` is nevertheless possible
through synthetic/native construction even though arithmetic normally demotes
zero to an immediate Integer. The fixture set includes both a size-zero object
with `cap == 0` (proving parity never touches absent limb storage) and zero
objects with garbage spare limbs. It also includes spare capacity, leading-zero
noncanonical nonzero headers, both signs/parities, and one through four limbs.
`INT32_MIN` size is excluded: it violates `abs(size) <= cap` and the old C
`-size` expression itself has signed-overflow undefined behavior there.

## Autoload and baseline contamination

A BigInt can arrive through a large literal, arithmetic promotion, a parameter,
or an untyped C factory, so receiver-shape inference cannot soundly schedule its
source class. The candidate uses a one-shot predicate-name trigger and bumps the
loader cache epoch. The self-host explicitly imports `core/numeric/big_int` so
an older bootstrap can build the first no-IC stage.

One subtle constraint changes the benchmark design: compiling the *baseline*
with the candidate loader would schedule baseline `BigInt < Int`; inherited
`Int`/`Real` predicate bodies could then win type-class dispatch and contaminate
the supposedly native leg. The runner therefore builds a fresh baseline and a
fresh candidate compiler from the same bootstrap and starting commit, compiles
the exact shared driver with its matching compiler, and requires the five hot
caller WIRE bodies to be identical. Baseline WIRE must contain no BigInt
predicate body; candidate and no-import autoload WIRE must contain all five.

The tree walker receives only two new allowlisted fields, `BigInt.length` and
`BigInt.limb0`, through `w_native_data_field`. Natural one-/multi-limb values,
both signs/parities, and ignored surplus arguments are covered. The tree
walker's historical behavior is also pinned: source dispatch binds but does not
implicitly iterate an attached block, so the block remains uncalled and the
predicate result is returned. The compiled baseline and candidate separately
must retain the same `undefined method 'each'` Bool-result error. Synthetic
zero/no-storage remains a compiled C-fixture gate because ordinary interpreter
arithmetic normalizes it away.

## Timing protocol and retention rule

`run_bigint_predicate_relaxed.sh` defaults to `STATIC_ONLY=1`. Once the shared
benchmark lane is free:

1. set `STATIC_ONLY=0 CHECK_ONLY=1` for fresh compiler-pair, public release/LTO,
   exact behavior, WIRE/LLVM, block, autoload, and interpreter gates;
2. set `STATIC_ONLY=0 CHECK_ONLY=0` for timing. The runner performs two complete
   independent rebuild campaigns, not two passes over the same binaries;
3. each campaign uses 10 alternating ABBA/BAAB observations and
   `CLOCK_THREAD_CPUTIME_ID` inside the workload;
4. the 26 independently gated strata separate no-storage/spare zero, one- and
   multi-limb sign, and parity outcomes as relevant to each method;
5. every stratum for a method must have median source/native `<= 1.10` in both
   campaigns. A failure retains that method's C handler. `max_pair` is reported
   only as a noise diagnostic.

Predicate checksums consume the returned Bool's exact WValue bits directly.
They never assign a heap-Integer-typed predicate result: the concurrent
Float#to_f/BigInt#to_i audit found a compiler bug in which assigned heap BigInt
results and implicit-result iteration can be mis-nanunboxed.

## Executed gates and timing results

`STATIC_ONLY=0 CHECK_ONLY=1` passed first. It established matched-root compiler
pairs, an uncontaminated native baseline, identical hot-caller WIRE, direct
signed offset-4 `i32`/`sext` and offset-16 `u64` LLVM loads, all 32 exact layout
fixtures and Bool bits, ignored surplus arguments, receiver stability, compiled
block-error parity, no-import autoload, and the tree-walker bridge including its
historical ignored-block behavior.

The first timed invocation completed its first observation set but exposed a
BSD-awk ambiguity in the reporting-only ternary; those temporary samples were
discarded automatically. After parenthesizing it, the complete two-campaign
protocol was rerun from fresh compiler builds and exited zero. Compiler hashes:

- C1 baseline `fc12f10547dd7a666793534fc7115f9fb4595fb953586662a7343fb16ad55781`, candidate `59cf4918e3658c04d7f01479bc9b35d9d66dfcbe028c60fde6b3450473e6bd37`;
- C2 baseline `0baaa672499c551449e7aa2dac4abb77b3b680419e4b06d8008c0a3ae3a79e82`, candidate `d6c921eb13975593555dc8959ca697e170eff1506b8d53bf2e6229bbbe6ac392`.

`native`/`source` are median thread-CPU ns/public call. `paired` is the
10-sample balanced median source/native ratio and the declared gate; `max` is
the largest paired-sample ratio and only a noise diagnostic.

```text
campaign 1                         native  source  paired    max  gate
zero.zero_nostorage                 8.415   8.480   0.994  1.032  PASS
zero.zero_spare                     8.452   8.379   0.979  1.012  PASS
zero.one                            8.580   8.271   0.966  1.022  PASS
zero.multi                          8.383   8.239   0.974  1.020  PASS
even.zero_nostorage                 8.605   8.460   0.990  1.095  PASS
even.zero_spare                     8.599   8.518   0.992  1.035  PASS
even.one_even                       8.515   8.350   0.966  0.996  PASS
even.one_odd                        8.715   8.281   0.959  1.013  PASS
even.multi_even                     8.538   8.400   0.972  1.267  PASS
even.multi_odd                      8.645   8.388   0.972  1.006  PASS
odd.zero_nostorage                  9.031   8.453   0.944  1.008  PASS
odd.zero_spare                      8.863   8.475   0.969  1.008  PASS
odd.one_even                        8.717   8.420   0.955  0.970  PASS
odd.one_odd                         8.892   8.345   0.930  0.991  PASS
odd.multi_even                      8.819   8.409   0.949  0.981  PASS
odd.multi_odd                       8.900   8.345   0.925  0.962  PASS
negative.zero                       8.427   8.257   0.983  1.077  PASS
negative.one_positive               8.426   8.227   0.973  1.012  PASS
negative.one_negative               8.423   8.279   0.990  1.017  PASS
negative.multi_positive             8.567   8.389   0.976  1.004  PASS
negative.multi_negative             8.501   8.432   0.981  1.028  PASS
positive.zero                       8.453   8.328   0.975  1.016  PASS
positive.one_positive               8.611   8.432   0.975  0.989  PASS
positive.one_negative               8.522   8.437   0.984  1.018  PASS
positive.multi_positive             8.569   8.334   0.989  1.064  PASS
positive.multi_negative             8.511   8.355   0.972  1.007  PASS

campaign 2                         native  source  paired    max  gate
zero.zero_nostorage                 8.491   8.234   0.967  1.003  PASS
zero.zero_spare                     8.451   8.320   1.001  1.018  PASS
zero.one                            8.507   8.246   0.970  1.014  PASS
zero.multi                          8.477   8.373   0.990  1.012  PASS
even.zero_nostorage                 8.581   8.439   0.997  1.037  PASS
even.zero_spare                     8.469   8.436   0.985  0.999  PASS
even.one_even                       8.489   8.356   0.969  1.006  PASS
even.one_odd                        8.595   8.306   0.962  1.220  PASS
even.multi_even                     8.474   8.295   0.975  1.004  PASS
even.multi_odd                      8.472   8.273   0.974  1.003  PASS
odd.zero_nostorage                  8.767   8.428   0.956  0.975  PASS
odd.zero_spare                      8.764   8.506   0.969  1.057  PASS
odd.one_even                        8.708   8.430   0.960  0.995  PASS
odd.one_odd                         8.953   8.380   0.934  0.954  PASS
odd.multi_even                      8.682   8.364   0.950  0.980  PASS
odd.multi_odd                       8.905   8.350   0.933  0.974  PASS
negative.zero                       8.449   8.305   0.976  1.032  PASS
negative.one_positive               8.477   8.386   0.977  1.108  PASS
negative.one_negative               8.513   8.301   0.980  1.017  PASS
negative.multi_positive             8.610   8.420   0.968  1.029  PASS
negative.multi_negative             8.456   8.322   0.979  1.012  PASS
positive.zero                       8.339   8.317   0.994  1.013  PASS
positive.one_positive               8.615   8.320   0.977  0.993  PASS
positive.one_negative               8.311   8.287   0.981  1.022  PASS
positive.multi_positive             8.469   8.352   0.984  1.014  PASS
positive.multi_negative             8.550   8.429   0.975  1.028  PASS
```

Independent decisions—“retain” means retain the Tungsten source port and
remove its C IC:

- `BigInt#zero?`: **RETAIN source** (worst paired C1/C2 0.994/1.001);
- `BigInt#even?`: **RETAIN source** (0.992/0.997);
- `BigInt#odd?`: **RETAIN source** (0.969/0.969);
- `BigInt#negative?`: **RETAIN source** (0.990/0.980);
- `BigInt#positive?`: **RETAIN source** (0.989/0.994).

## Integration and artifacts

Merge the five direct-view bodies plus `limb0` declaration from
`core/numeric/big_int.w`; the BigInt predicate-name loader trigger/cache epoch;
the old-bootstrap `compiler/tungsten.w` import; the two-field interpreter
allowlist and `w_native_data_field` bridge; and removal/reindexing of exactly the
five BigInt C IC handlers/rows. Keep the separate active `BigInt#to_i` trial and
any newer loader epoch/IC edits, resolving those files manually.

Reproducibility artifacts in `benchmarks/runtime_ports/` are:

- `run_bigint_predicate_relaxed.sh` — static, correctness, code-shape, and two-campaign timing gate;
- `bigint_predicate_relaxed_ref.c` — ABI assertions, 32 fixtures, reference mask, and thread clock;
- `bigint_predicate_relaxed_public.w` — public correctness/block/timing driver;
- `bigint_predicate_relaxed_autoload.w` — no-import compiled autoload gate;
- `bigint_predicate_relaxed_interpreter.w` — tree-walker compatibility gate;
- `bigint_predicate_relaxed_audit.md` — rationale and complete results.

## Merge warning

This candidate deliberately does **not** include BigInt#to_i. If both trials
pass, merge method bodies, loader guards/cache version, `compiler/tungsten.w`,
and the BigInt IC table/reindex manually against the then-current production
tree. Do not copy the isolated files wholesale: the identity trial and other
runtime ports touch the same class, loader epoch, bootstrap imports, and IC
indices.

If only a subset of predicates passes, failed methods must lose their source
bodies as well as keep their native rows: once BigInt is registered, a
type-class method wins before the native IC. Restrict the one-shot autoload
name set to retained source predicates, then reindex the table around only the
removed rows.
