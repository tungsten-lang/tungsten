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

For direct forced-kernel comparison against GMP's internal Toom functions:

```sh
benchmarks/big_math/run_toom_gmp_compare.sh
```

That benchmark calls Tungsten's forced Toom-2/3/4 kernels and GMP's exported
`__gmpn_toom22_mul`, `__gmpn_toom33_mul`, and `__gmpn_toom44_mul` directly,
checking every result against `mpn_mul_n`.

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
