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

The default lanes are Tungsten and GMP. `--python`, `--rust`, and `--odin`
enable CPython `int`, Rust `num-bigint` 0.5.1, and Odin `core:math/big`;
`--all` enables all three. Rust and Odin harnesses are persistent
sources in `rust/` and `odin/`, built with release optimization and the native
CPU target only when selected. Dependencies and compiler versions are recorded
in JSON metadata.

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

All rows use a common input size of `N * 64` bits. That is a Tungsten/GMP/Rust
limb count, not an assertion about every implementation's internal layout:
Odin currently stores 63 payload bits in each `u64` digit. Immutable lanes keep
one previous result live until the next result exists. GMP and Odin instead use
their idiomatic mutable APIs with two alternating, capacity-retaining result
destinations. Each lane calibrates its own iteration count to the requested
timing window.

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

For idiomatic accumulator loops, including allocation-free add, multiply, and
one-word divide when the compiler proves the prior value dies, run:

```sh
REPS=15 benchmarks/big_math/run_program_loops.sh
```

The script builds Tungsten with `--release --native --fast`, builds its GMP
twin with `-O3 -mcpu=native`, alternates lane order, checks matching output,
and reports median nanoseconds per iteration. These are end-to-end language
loops rather than raw limb-kernel timings; shared or escaped accumulators still
take the immutable runtime path.

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

To generate local candidate runtime thresholds, run:

```sh
make -C runtime tune-bigint
```

This writes `runtime/generated/bigint_thresholds.h` and the raw sweep output
next to it. Normal builds do not tune automatically; they include that generated
header only when it exists, otherwise the checked-in defaults in `runtime.c` are
used. Treat generated thresholds as machine/profile-specific benchmark output
and review the sweep before committing or using them for release builds.

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
