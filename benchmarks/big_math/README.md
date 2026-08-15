# Big Math Benchmark

Compares Tungsten runtime BigInt kernels against GMP when GMP is installed:

```sh
benchmarks/big_math/run.sh
```

The benchmark includes:

- balanced BigInt multiply and square
- single-limb modulus, including an A/B against the former 128/64 division
  loop and GMP checks across the 32-bit fast-path boundary
- fixed-modulus BigInt multiply-mod
- Mersenne square reduction, `s^2 mod (2^p - 1)`

For the language/runtime-wide bignum matrix, use the public CLI:

```sh
bin/tungsten bench bignum --quick
bin/tungsten bench bignum --all --quick --no-capacity
bin/tungsten bench bignum --all --accurate --json --no-capacity
bin/tungsten bench bignum --full --output results/bignum-full.json
bin/tungsten bench bignum --worker-sweep --output results/bignum-workers.json
```

The default lanes are the direct Tungsten C/runtime harness, Tungsten native,
and GMP. The Tungsten native lane lives in `tungsten/`, builds with
`--release --native --fast`, and times ordinary Tungsten operators and methods;
Core reaches retained C kernels through its production `ccall` seams. After
declaring the harness, it executes `Tungsten.PROTECT_THE_CORE!` and
`Tungsten.LOCK_THE_DOORS!`, so the measured program has validated Core
provenance and irreversibly locked instance/static method tables. The table's
`C/native` and `C/GMP` ratios remain anchored to the established direct C lane.
The gcd, lcm, and integer-square-root timed bodies call their retained runtime
kernel boundaries explicitly with `ccall`; the arithmetic, bitwise, shift,
comparison, sign, power, and conversion rows use their ordinary source forms.

`--python`, `--rust`, `--odin`, `--go`, `--node`, and `--boost` additionally
enable CPython `int`, Rust `num-bigint` 0.5.1, Odin `core:math/big`, Go
`math/big`, JavaScript `BigInt` under Node's V8, and Boost.Multiprecision
`cpp_int`; `--all` enables all six optional lanes. Their persistent harnesses
live in `rust/`, `odin/`, `go/`, `node/`, and `boost/`, built with release
optimization and the native CPU target only when selected (the Node lane has
no compile step; its script is self-tested once per change instead).
Dependencies and compiler versions are recorded in JSON metadata. The V8 lane
reports gcd/lcm/isqrt/powmod as unsupported: V8 ships no BigInt builtin for
them, and a hand-written JS algorithm would measure the harness author rather
than the engine.

The default matrix remains the fast 1..8192-limb development sweep. `--full`
is the reproducible threshold/FFT-band preset: it implies `--accurate` and
`--no-capacity`, uses at least nine 110 ms timing repetitions, brackets the
multiply/square and recycler cutoffs, and takes selected operations through
1,048,576 limbs. It does not form a wasteful Cartesian product of every cheap
operation and every huge size. Every repeated native row records its
interquartile spread so host noise and power throttling remain visible in JSON
artifacts. Above 8192 limbs, rows report the median; smaller rows retain the
normal best-of-N statistic. On macOS, artifacts also record AC/battery state
and charge level.
`--full` cannot be combined with `--quick`. `--operations` selects a subset of
the preset, and `--sizes` replaces its per-operation sizes (and is required if
an operation outside the preset is requested). `--output FILE` writes the full
JSON artifact while leaving the human-readable table on stdout; `--json` still
prints that same document. Artifacts record the exact command, commit and dirty
state, CPU and target, compiler flags, dependency versions, selected matrix,
and timing methodology.

`--worker-sweep` is a separate, deliberately narrow large-multiply experiment.
It builds isolated native harnesses with each compile-time parallel-worker cap
from one through the host's logical CPU count minus one, then measures `mul`
and `sqr` at the SSA/FFT and recycler boundaries through 1,048,576 limbs. It
records the worker cap, host logical-CPU count, per-row median/IQR variability
above 8192 limbs, and the winner for every operation/size pair. It does not
change the checked-in runtime worker policy: use its artifact to decide whether
such a change is warranted. Pass `--sizes` to narrow a local sweep, or
`--operations mul` / `--operations sqr` to select one operation.

The checked-in SSA/FFT point-worker cap is seven on Apple arm64 and four on
other targets. The Apple setting is an M5 Max measurement, not a cross-target
claim: `worker-sweep-03886b6-m5max-20260804.json` explores caps 1..17, while
the decision-grade `ssa-workers7-03886b6-m5max-20260804.json` holds every
other compile-time policy constant and records start/end host load.

Architectural suggestions that do not map cleanly to one boxed matrix cell
still receive executable upper-bound experiments. `run_architectural_ideas.py`
covers repeated modular traces, independent accumulator scheduling, fixed-scale
storage, and p-adic modular dispatch. `run_atomic_bigint.py` measures a safe
immutable-CAS prototype against locked unique mutation, while
`run_consumed_ops.py` measures caller-owned destinations for the operation
families not yet exposed through compound assignment. These artifacts are
hypothesis evidence, not production wins: the audit records omitted semantics
and requires a separate guarded full-language A/B before retaining a change.

The page-hazard policy can be compared within one byte-identical benchmark
binary by building with `-DBN_PAGE_HAZARD_RUNTIME_TOGGLE=1` and setting
`TUNGSTEN_BN_PAGE_HAZARD=0` or `1`. The toggle covers both equal-product and
add/sub-style placement predicates (including generic N×1 multiplication) and
compiles away in normal builds. Separate-process results still need inactive
controls because heap placement can move offset-sensitive kernels even when
the binary hash is identical.

For a compile-time optimization hypothesis, use the isolated boxed-operation
A/B driver rather than comparing raw kernels or replacing the normal harness:

```sh
benchmarks/big_math/run_variant_ab.py \
  --label eq3-inline \
  --operations mul \
  --sizes 3 \
  --baseline-extra-flags=-DBN_MUL_EQ3_INLINE=0 \
  --rounds 9 --target-ms 110 \
  --output results/eq3-inline.json
```

It builds both variants from the same source in a temporary directory,
alternates their order each round, and records paired median/IQR results,
within-build GMP ratios, flags, commit, load, power state, and raw samples in
JSON. A production decision still requires focused differential tests and an
affected-matrix screen; the driver does not auto-accept a candidate. Runs below
nine rounds or a 110 ms target are marked non-acceptance in both stderr and
JSON, so short smoke tests cannot disposition a suggestion.

After a fast default-matrix screen, `run_residual_matrix.py` remeasures every
cell at or above a chosen Tungsten/GMP ratio with the acceptance timing policy:

```sh
benchmarks/big_math/run_residual_matrix.py \
  --screen results/matrix-screen.json --threshold 0.95 \
  --runs 9 --target-ms 110 --output results/residual-accurate.json
```

The output retains the screen ratio, accurate median and IQR, machine metadata,
and source-screen hash. This helper is deliberately limited to the default
matrix through 8192 limbs; use `--full` for the separately selected large/FFT
bands rather than extrapolating a fast-screen result.

All rows use a common input size of `N * 64` bits. That is a Tungsten/GMP/Rust
limb count, not an assertion about every implementation's internal layout:
Odin currently stores 63 payload bits in each `u64` digit. Immutable lanes keep
one previous result live until the next result exists. GMP and Odin instead use
their idiomatic mutable APIs with two alternating, capacity-retaining result
destinations. Each lane calibrates its own iteration count to the requested
timing window.

The `add1`, `sub1`, `mul1`, and `div1` rows are deliberately API-shaped
unsigned-word operations, not ordinary balanced boxed/boxed calls. Each lane
uses the fastest form its API offers for a hoisted one-limb operand: Tungsten
direct C uses its decoded-word entries, the Tungsten native lane uses
its ordinary operator with a pre-built one-limb BigInt, GMP uses `mpz_*_ui`,
and Rust and Boost use their `u64`/builtin-integer operator overloads. Odin, Go,
and Node have no unsigned-word entry that fits the full `2^63..2^64` word
(Odin's digit is 63 bits; math/big and BigInt expose no scalar API), so those
lanes pass a pre-built one-limb bignum operand through the ordinary two-operand
call. The
ordinary `add`, `sub`, `mul`, and `div` rows continue to measure their generic
two-BigInt dispatch.

The matrix covers add, subtract, multiply, square, divide, modulo, gcd, bitwise
operations, shifts, comparison, negate/absolute value, power, modular power,
lcm, integer square root, and decimal conversion in both directions. The
division and modulo dividend is `2N` limbs and divisor is `N`; integer square
root takes a `2N`-limb input. Rust uses its public `modpow`; Odin's optimized
Montgomery/window modular exponentiation is shipped under its `internal_*` API,
which the metadata calls out explicitly.

The same command also runs a mixed-size capacity-policy experiment unless
`--no-capacity` is given. `--capacity-only` skips arithmetic. Use `--list` for
the complete operation, size, and policy catalog.

For allocation/alias-safe algebraic identity timing, build the native harness
and run:

```sh
benchmarks/big_math/run.sh --build-only
benchmarks/big_math/bench_big_math --bench-fastpaths 64 10000 7
```

This validates and times identities such as `x * 1`, `x / 1`, `x - x`, zero
shifts, bitwise self/zero/negative-one cases, gcd/lcm identities, powers 0/1,
and modular-power constants. The harness never releases a result that aliases
one of its live operands.

For idiomatic accumulator loops, including allocation-free add, multiply,
one-word divide, and one-word modulo when the compiler proves the prior value
dies, run:

```sh
REPS=15 benchmarks/big_math/run_program_loops.sh
```

The script builds Tungsten with `--release --native --fast`, builds its GMP
twin with `-O3 -mcpu=native`, alternates lane order, checks matching output,
and reports median nanoseconds per iteration. These are end-to-end language
loops rather than raw limb-kernel timings; shared or escaped accumulators still
take the immutable runtime path.

The feature-isolated modulo destination sweep is reproducible with:

```sh
python3 benchmarks/big_math/run_program_mutation_ab.py --feature mod \
  --rounds 9 --output /tmp/program-mod-mut.json
```

It tests 2 through 128 limbs, retains exact checksums and LLVM call counts, and
records the GMP version plus machine/load metadata in JSON.

Use `--feature sqr` with the same command to isolate a consumed one-limb
self-square after modulo has retained a larger destination buffer.

To reproduce the compile-time power-of-two modular-context A/B, including
GMP's public destination-reusing `mpz_tdiv_r_2exp` lane, run:

```sh
python3 benchmarks/big_math/run_mod_pow2_context_ab.py --rounds 9 \
  --target-ms 60 --output /tmp/mod-pow2-context.json
```

The identical Tungsten source is compiled with the specialization disabled
and enabled under `--release --native --fast`. The JSON retains per-width
calibrated iteration counts, raw samples, IQRs, exact checksums, emitted-call
counts, source/binary hashes, GMP version, and machine/load metadata. This is
a modular-loop experiment outside the default operation matrix; report its GMP
comparisons separately rather than treating a control win as a matrix win.

Use `--comparison fusion` with the same runner to hold the power-of-two
reduction constant and compare separate `r += x; r %= 2^k` operations with
the compiler's adjacent modular-add fusion. This second comparison records the
fused call count independently and uses the same public-GMP lane.

To reproduce the constant-argument function experiment (ordinary recomputation,
current pure-`fn` memoization, and an ideal manually hoisted value), run:

```sh
python3 benchmarks/big_math/run_interprocedural_constant.py \
  --rounds 9 --output /tmp/interprocedural-constant.json
```

This is a compiler-opportunity bound rather than a GMP operation lane.

To distinguish ordinary compiled BigInt bindings from explicit dictionary
lookup and a user-hoisted cached binding, run:

```sh
python3 benchmarks/big_math/run_symbol_lookup.py \
  --rounds 9 --output /tmp/symbol-lookup.json
```

To compare Tungsten's full-width `uint64_t` radix with an Odin-style 63-bit
"nail" radix on the same ARM64 machine:

```sh
clang -O3 -DNDEBUG -mcpu=native -std=c11 -Wall -Wextra -Werror \
  benchmarks/big_math/bench_limb_nails.c -lm -o /tmp/bench_limb_nails
/tmp/bench_limb_nails --target-ms 50 --samples 11
```

The standalone screen validates `add_n` and `mul_1` against independent
`__uint128_t` oracles, then reports raw time per limb and density-corrected
time per useful bit.

`run.sh` compiles `bench_big_math.c` with the runtime included as a single
translation unit so the benchmark can time internal arithmetic kernels without
exporting benchmark-only runtime APIs. If `pkg-config gmp` is unavailable, the
benchmark still builds and prints Tungsten-only timings.

For the small-size Toom crossover sweep:

```sh
benchmarks/big_math/run_toom_sweep.sh
```

That benchmark forces schoolbook, Toom-2, Toom-3, Toom-4, the internal ladder,
and the public dispatcher for equal-length limb counts from 8 through 2048,
checking every forced result against schoolbook before timing.

It also accepts dense ranges and optional NTT timing:

```sh
benchmarks/big_math/run_toom_sweep.sh 1:128
benchmarks/big_math/run_toom_sweep.sh 225:320 320:512
benchmarks/big_math/run_toom_sweep.sh --ntt 1930:2005
```

To record a local forced-kernel threshold sweep, run:

```sh
make -C runtime tune-bigint
```

This records a best-of-9 raw sweep in
`runtime/generated/bigint_thresholds.last.txt`; set `REPS`, `RANGES`, or `LOG`
to override those defaults. It deliberately does not infer or activate a
runtime threshold: forced-kernel curves are discontinuous at fixed shapes and
recursive leaves, and neither a first-win rule nor a smooth fitted crossover
predicts the boxed-operation optimum reliably. Test a proposed cutoff with
`run_variant_ab.py` over every boxed cell whose dispatch changes, then update
the checked-in default only when that A/B passes the acceptance rule.

Normal builds still include `runtime/generated/bigint_thresholds.h` when a
developer creates one explicitly for an experiment; otherwise the checked-in
defaults in `runtime.c` are used.

For direct comparison of Tungsten's forced Toom kernels with GMP's public
equal-length multiplication dispatcher:

```sh
benchmarks/big_math/run_toom_gmp_compare.sh
```

That benchmark calls Tungsten's forced Toom-2/3/4 kernels and public
`mpn_mul_n`, checking every forced-kernel result against `mpn_mul_n` before
timing.

## Factorial vs. Stirling (pure-Tungsten)

A language-level benchmark (a `.w` program, not a runtime microbenchmark)
comparing the exact factorial against Stirling's approximation
`sqrt(2*pi*n) * (n/e)^n` for 100! and 2000!:

```sh
benchmarks/big_math/run_stirling.sh
```

`stirling_factorial.w` runs the comparison two ways and prints them side by
side:

- **bigint** — an arbitrary-precision float built on the language's `## big`
  BigInt (a 40-digit integer mantissa + a base-10 exponent), with `e` and
  `2*pi` as 40-digit integer constants. The exact factorial is an exact bigint,
  and the accuracy comparison (matching leading digits, relative error) is done
  with bigint subtraction and division. No IEEE float ever touches the
  magnitudes, so 2000! (~5736 digits, ~10^5735) is handled exactly.

- **float/log** — the "obvious" `f64` approach made overflow-proof by never
  forming `n!`: accumulate `ln(n!)` as a sum of logs and evaluate Stirling in
  natural log. Fast and overflow-proof for any `n`, but capped at `f64`'s
  ~15-16 significant digits.

For both, the measured "1 part in N" Stirling error matches the textbook
series prediction (`1/(12n)`, then `288 n^2`, then `~373 n^3`). The takeaways:

- The bigint path emits the **actual digits** of `n!` and resolves the relative
  error as deeply as the mantissa width allows. The float/log path agrees on
  magnitude (exact digit count) and the larger errors but **cannot print the
  factorial's digits** and hits a precision wall: for 2000! its deepest
  correction bottoms out at ~2 ULPs of the log sum (it reports ~1 in 2.7e11,
  where the bigint path measures the true ~1 in 3.0e12).

- The float/log path is far cheaper — the Stirling formula is a handful of
  hardware float ops (~30 ns) versus arbitrary-precision sqrt/division/
  exponentiation (~40 us). It is the right tool when you only need the
  magnitude or a coarse error; the bigint path is the right tool when you need
  every digit.

For a broader local language comparison:

```sh
benchmarks/big_math/run_language_compare.sh
```

That script benchmarks same-sized integer multiplication in C/GMP, Fortran/GMP
via `ISO_C_BINDING`, the Tungsten runtime BigInt dispatcher, Go `math/big`,
Ruby `Integer`, Python `int`, Node `BigInt`, and Rust `num-bigint` when the
relevant tools are installed. It prints a fixed-width table by default; set
`FORMAT=csv` for machine-readable output.
