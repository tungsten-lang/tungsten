# Core Probability benchmarks

These are compiled microbenchmarks for regression tracking, not cross-language
performance claims:

```sh
bin/tungsten -o /tmp/probability_bench benchmarks/probability/monte_carlo.w
/tmp/probability_bench
```

`monte_carlo.w` measures Philox 32-bit generation and a four-dimensional
multivariate Normal log density. Each reports a checksum so dead-code removal
or semantic drift is visible. Results depend on CPU, compiler profile, and
thermal state; compare repeated runs from the same build configuration.
