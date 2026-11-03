# Lightweight deterministic RNG smoke battery.
#
# This catches gross stream regressions; it is not TestU01, PractRand, a proof
# of independence, or a certification for scientific/cryptographic use.

use core/math
use core/probability/linear_algebra
use core/probability/primitives
use core/probability/rng

+ ProbabilityRandomBatteryResult
  ro :sample_count, :bin_count, :mean, :variance
  ro :serial_correlation, :chi_square

  -> new(sample_count, bin_count, mean, variance,
         serial_correlation, chi_square, heuristic_pass)
    @sample_count = sample_count
    @bin_count = bin_count
    @mean = mean
    @variance = variance
    @serial_correlation = serial_correlation
    @chi_square = chi_square
    @heuristic_pass = heuristic_pass
    self

  -> heuristic_pass?
    @heuristic_pass

  -> certified?
    false


+ ProbabilityRandomTests
  -> .basic(rng, sample_count = 10000, bin_count = 16)
    if !ProbabilityNumerics.integer?(sample_count) || sample_count <= 0
      raise "probability random battery sample count must be a positive integer"
    if !ProbabilityNumerics.integer?(bin_count) || bin_count <= 0
      raise "probability random battery bin count must be a positive integer"
    ProbabilityRandom.require_rng(rng)
    if sample_count < 2
      raise "probability random battery needs at least two samples"
    values = []
    bins = []
    bin_count.times -> bins.push(0)
    i = 0
    while i < sample_count
      value = ProbabilityRandom.random_unit(rng)
      values.push(value)
      bin = (value*bin_count).to_i
      bin = bin_count - 1 if bin >= bin_count
      bins[bin] = bins[bin] + 1
      i += 1
    mean = ProbabilityNumerics.sum(values) / (sample_count + ~0.0)
    squares = []
    covariance_terms = []
    i = 0
    while i < sample_count
      difference = values[i] - mean
      squares.push(difference*difference)
      if i + 1 < sample_count
        covariance_terms.push(
          difference*(values[i + 1] - mean))
      i += 1
    square_sum = ProbabilityNumerics.sum(squares)
    variance = square_sum / (sample_count - ~1.0)
    serial = square_sum == ~0.0 ? ~0.0 : (
      ProbabilityNumerics.sum(covariance_terms) / square_sum)
    expected = sample_count / (bin_count + ~0.0)
    chi_terms = []
    i = 0
    while i < bins.size
      difference = bins[i] - expected
      chi_terms.push(difference*difference / expected)
      i += 1
    chi_square = ProbabilityNumerics.sum(chi_terms)
    mean_limit = ~6.0*Math.sqrt((~1.0 / ~12.0) / sample_count)
    variance_limit = ~6.0*Math.sqrt((~1.0 / ~180.0) / sample_count)
    serial_limit = ~6.0 / Math.sqrt(sample_count + ~0.0)
    degrees = bin_count - ~1.0
    chi_limit = degrees + ~6.0*Math.sqrt(~2.0*degrees)
    pass = (ProbabilityLinearAlgebra.absolute(mean - ~0.5) <= mean_limit &&
            ProbabilityLinearAlgebra.absolute(
              variance - ~0.08333333333333333) <= variance_limit &&
            ProbabilityLinearAlgebra.absolute(serial) <= serial_limit &&
            chi_square <= chi_limit)
    ProbabilityRandomBatteryResult.new(
      sample_count, bin_count, mean, variance,
      serial, chi_square, pass)
