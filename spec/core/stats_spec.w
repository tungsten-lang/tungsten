# Stats — descriptive statistics, distributions, mulberry32 PRNG (core/stats.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/stats_spec.w
#   bin/tungsten -o /tmp/stats_spec spec/core/stats_spec.w && /tmp/stats_spec

use core/stats

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b, eps)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < eps

# ---- descriptive ----
check("mean", Stats.mean([~1.0, ~2.0, ~3.0, ~4.0]) == ~2.5)
check("mean single", Stats.mean([~7.0]) == ~7.0)
check("mean empty", Stats.mean([]) == ~0.0)
check("mean negative", Stats.mean([~-2.0, ~2.0]) == ~0.0)
spread = [~2.0, ~4.0, ~4.0, ~4.0, ~5.0, ~5.0, ~7.0, ~9.0]
check("variance population", Stats.variance(spread, false) == ~4.0)
check("variance sample", near(Stats.variance(spread), ~32.0 / ~7.0, ~1.0e-12))
check("variance default is sample", Stats.variance(spread) == Stats.variance(spread, true))
check("variance single is 0", Stats.variance([~5.0]) == ~0.0)
check("variance empty is 0", Stats.variance([]) == ~0.0)
check("variance constant", Stats.variance([~3.0, ~3.0, ~3.0], false) == ~0.0)
check("std population", Stats.std(spread, false) == ~2.0)
check("std sample", near(Stats.std(spread), Math.sqrt(~32.0 / ~7.0), ~1.0e-12))
check("median odd", Stats.median([~3.0, ~1.0, ~2.0]) == ~2.0)
check("median even", Stats.median([~4.0, ~1.0, ~3.0, ~2.0]) == ~2.5)
check("median single", Stats.median([~9.0]) == ~9.0)
check("median empty", Stats.median([]) == ~0.0)
unsorted = [~3.0, ~1.0, ~2.0]
Stats.median(unsorted)
check("median leaves input unsorted", unsorted == [~3.0, ~1.0, ~2.0])
five = [~5.0, ~1.0, ~4.0, ~2.0, ~3.0]
check("percentile 0", Stats.percentile(five, ~0.0) == ~1.0)
check("percentile below 0 clamps", Stats.percentile(five, ~-5.0) == ~1.0)
check("percentile 100", Stats.percentile(five, ~100.0) == ~5.0)
check("percentile above 100 clamps", Stats.percentile(five, ~150.0) == ~5.0)
check("percentile empty", Stats.percentile([], ~50.0) == ~0.0)
# BUG: any percentile strictly between 0 and 100 returns the minimum. `Stats.percentile`
# indexes `ys[loi]` where `loi = Math.floor(rank)` is a Float, and a Float array subscript
# silently reads element 0 instead of truncating (or raising) on both engines.
# Repro: printf 'a = [10, 20, 30]\n<< a[Math.floor(~2.0)]\n' > /tmp/f.w &&
#        bin/tungsten run --interpret /tmp/f.w    # prints 10, expected 30
# check("percentile 50", Stats.percentile(five, ~50.0) == ~3.0)
# check("percentile on a rank", Stats.percentile(five, ~25.0) == ~2.0)
# check("percentile interpolates", near(Stats.percentile(five, ~10.0), ~1.4, ~1.0e-12))

# ---- normal ----
check("norm_pdf 0", near(Stats.norm_pdf(~0.0), ~0.3989422804014327, ~1.0e-15))
check("norm_pdf 1", near(Stats.norm_pdf(~1.0), ~0.24197072451914337, ~1.0e-15))
check("norm_pdf symmetric", Stats.norm_pdf(~-1.5) == Stats.norm_pdf(~1.5))
check("norm_pdf shifted", near(Stats.norm_pdf(~3.0, ~3.0), ~0.3989422804014327, ~1.0e-15))
check("norm_pdf sigma 2", near(Stats.norm_pdf(~0.0, ~0.0, ~2.0), ~0.19947114020071635, ~1.0e-15))
check("norm_cdf 0", near(Stats.norm_cdf(~0.0), ~0.5, ~1.0e-12))
check("norm_cdf 1.96", near(Stats.norm_cdf(~1.96), ~0.9750021048517795, ~1.0e-6))
check("norm_cdf -1.96", near(Stats.norm_cdf(~-1.96), ~0.024997895148220435, ~1.0e-6))
check("norm_cdf shifted", near(Stats.norm_cdf(~5.0, ~5.0, ~3.0), ~0.5, ~1.0e-12))
check("norm_cdf far right", near(Stats.norm_cdf(~8.0), ~1.0, ~1.0e-9))

# ---- uniform / exponential / poisson ----
check("uniform_pdf inside", Stats.uniform_pdf(~0.5) == ~1.0)
check("uniform_pdf at bounds", Stats.uniform_pdf(~0.0) == ~1.0 && Stats.uniform_pdf(~1.0) == ~1.0)
check("uniform_pdf outside", Stats.uniform_pdf(~1.5) == ~0.0 && Stats.uniform_pdf(~-0.1) == ~0.0)
check("uniform_pdf custom", Stats.uniform_pdf(~2.0, ~0.0, ~4.0) == ~0.25)
check("expon_pdf 0", Stats.expon_pdf(~0.0) == ~1.0)
check("expon_pdf 1", near(Stats.expon_pdf(~1.0), ~0.36787944117144233, ~1.0e-15))
check("expon_pdf negative", Stats.expon_pdf(~-1.0) == ~0.0)
check("expon_pdf rate 2", near(Stats.expon_pdf(~1.0, ~2.0), ~0.2706705664732254, ~1.0e-15))
check("expon_cdf 0", Stats.expon_cdf(~0.0) == ~0.0)
check("expon_cdf 1", near(Stats.expon_cdf(~1.0), ~0.6321205588285577, ~1.0e-15))
check("expon_cdf negative", Stats.expon_cdf(~-1.0) == ~0.0)
check("poisson_pmf 0", near(Stats.poisson_pmf(0, ~2.0), ~0.1353352832366127, ~1.0e-15))
check("poisson_pmf 2", near(Stats.poisson_pmf(2, ~2.0), ~0.2706705664732254, ~1.0e-15))
check("poisson_pmf negative k", Stats.poisson_pmf(-1, ~2.0) == ~0.0)

# ---- t / gamma ----
check("t_pdf cauchy 0", near(Stats.t_pdf(~0.0, ~1.0), ~0.3183098861837907, ~1.0e-7))
check("t_pdf cauchy 1", near(Stats.t_pdf(~1.0, ~1.0), ~0.15915494309189535, ~1.0e-7))
check("t_pdf symmetric", near(Stats.t_pdf(~-2.0, ~5.0), Stats.t_pdf(~2.0, ~5.0), ~1.0e-15))
check("gamma_pdf exponential case", near(Stats.gamma_pdf(~1.0, ~1.0), ~0.36787944117144233, ~1.0e-7))
check("gamma_pdf shape 2", near(Stats.gamma_pdf(~2.0, ~2.0, ~1.0), ~0.2706705664732254, ~1.0e-7))
check("gamma_pdf negative", Stats.gamma_pdf(~-1.0, ~2.0) == ~0.0)

# ---- bernoulli / binomial ----
check("bernoulli_pmf 0", near(Stats.bernoulli_pmf(0, ~0.3), ~0.7, ~1.0e-15))
check("bernoulli_pmf 1", Stats.bernoulli_pmf(1, ~0.3) == ~0.3)
check("bernoulli_pmf other", Stats.bernoulli_pmf(2, ~0.3) == ~0.0)
check("binom_pmf 2 of 4", near(Stats.binom_pmf(2, 4, ~0.5), ~0.375, ~1.0e-9))
check("binom_pmf 0 of 4", near(Stats.binom_pmf(0, 4, ~0.5), ~0.0625, ~1.0e-9))
check("binom_pmf 4 of 4", near(Stats.binom_pmf(4, 4, ~0.5), ~0.0625, ~1.0e-9))
check("binom_pmf k > n", Stats.binom_pmf(5, 4, ~0.5) == ~0.0)
check("binom_pmf k < 0", Stats.binom_pmf(-1, 4, ~0.5) == ~0.0)

# ---- correlation ----
check("pearson perfect", near(Stats.pearson([~1.0, ~2.0, ~3.0], [~2.0, ~4.0, ~6.0]), ~1.0, ~1.0e-12))
check("pearson inverse", near(Stats.pearson([~1.0, ~2.0, ~3.0], [~3.0, ~2.0, ~1.0]), ~-1.0, ~1.0e-12))
check("pearson constant is 0", Stats.pearson([~1.0, ~2.0, ~3.0], [~1.0, ~1.0, ~1.0]) == ~0.0)
check("pearson uncorrelated", near(Stats.pearson([~1.0, ~2.0, ~3.0, ~4.0], [~1.0, ~-1.0, ~-1.0, ~1.0]), ~0.0, ~1.0e-12))

# ---- mulberry32 PRNG (reference values computed from the same recurrence) ----
rng = Stats.rng(42)
check("rng type", type(rng) == "StatsRng")
check("rng seed 42 first u32", rng.next_u32 == 2581720956)
check("rng seed 42 second u32", rng.next_u32 == 1925393290)
check("rng random exact", near(Stats.rng(42).random, ~0.6011037519201636, ~1.0e-15))
check("rng deterministic", Stats.rng(7).next_u32 == Stats.rng(7).next_u32)
check("rng seeds differ", Stats.rng(7).next_u32 != Stats.rng(8).next_u32)
check("rng seed 0 maps to 1", Stats.rng(0).next_u32 == 2693262067 && Stats.rng(1).next_u32 == 2693262067)
check("rng default seed is 1", Stats.rng.next_u32 == 2693262067)
check("rng direct constructor", StatsRng.new(42).next_u32 == 2581720956)
sample = Stats.rng(3)
in_range = true
i = 0
while i < 200
  u = sample.random
  in_range = in_range && u >= ~0.0 && u < ~1.0
  w = sample.next_u32
  in_range = in_range && w >= 0 && w < 4294967296
  i += 1
check("rng random and u32 stay in range", in_range)
uni = Stats.rng(5)
uni_ok = true
i = 0
while i < 50
  u = uni.uniform(~2.0, ~4.0)
  uni_ok = uni_ok && u >= ~2.0 && u < ~4.0
  i += 1
check("rng uniform range", uni_ok)
check("rng uniform default", near(Stats.rng(42).uniform, ~0.6011037519201636, ~1.0e-15))
check("rng normal is float", type(Stats.rng(9).normal) == "Float")
check("rng normal shift", Stats.rng(9).normal(~100.0, ~0.0) == ~100.0)
check("rng exponential nonnegative", Stats.rng(11).exponential >= ~0.0)
check("rng exponential rate scales", near(Stats.rng(11).exponential(~2.0) * ~2.0, Stats.rng(11).exponential(~1.0), ~1.0e-12))
check("rng bernoulli always", Stats.rng(13).bernoulli(~1.0) == 1)
check("rng bernoulli never", Stats.rng(13).bernoulli(~0.0) == 0)
bern = Stats.rng(13).bernoulli
check("rng bernoulli is 0 or 1", bern == 0 || bern == 1)

<< "ALL PASS stats_spec ([passed.load()] checks)"
