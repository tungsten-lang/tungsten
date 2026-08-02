# Inspectable numerical contracts for probability algorithms.
#
# These objects distinguish an implementation description and tested envelope
# from a mathematically certified error bound.  No current contract is certified.

+ ProbabilityNumericalContract
  -> new(operation, arithmetic, algorithm, certified, limitations)
    @operation = operation
    @arithmetic = arithmetic
    @algorithm = algorithm
    @certified = certified
    @limitations = limitations
    self

  -> operation
    @operation

  -> arithmetic
    @arithmetic

  -> algorithm
    @algorithm

  -> certified?
    @certified

  -> limitations
    @limitations

  -> to_s
    (@operation + " [" + @arithmetic + "; " + @algorithm +
     "; certified=" + @certified.to_s + "]")


+ ProbabilityAccuracy
  -> .normal_tail
    ProbabilityNumericalContract.new(
      "Normal log CDF/survival", "IEEE-754 binary64",
      "erfc centrally; 12-term asymptotic Mills ratio beyond 8 sigma",
      false,
      "deterministic but not interval-certified; exp(log tail) can underflow")

  -> .multivariate_normal
    ProbabilityNumericalContract.new(
      "Multivariate Normal log density", "IEEE-754 binary64",
      "checked unpivoted Cholesky and triangular solve",
      false,
      "strict SPD only; conditioning degrades with covariance condition number")

  -> .monte_carlo
    ProbabilityNumericalContract.new(
      "Monte Carlo estimators", "IEEE-754 binary64",
      "explicit pseudo-random streams and compensated weight normalization",
      false,
      "reported diagnostics estimate sampling error; they are not guarantees")

  -> .contract(name)
    return ProbabilityAccuracy.normal_tail if name == :normal_tail
    return ProbabilityAccuracy.multivariate_normal if name == :multivariate_normal
    return ProbabilityAccuracy.monte_carlo if name == :monte_carlo
    raise "probability numerical contract is unknown"
