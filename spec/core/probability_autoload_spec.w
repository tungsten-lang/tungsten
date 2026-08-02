# The Probability facade must resolve through core/tungsten without a
# feature-level use. Loading it makes the module's public types discoverable.

-> probability_autoload_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

distribution = Probability.normal(~2.0, ~3.0)
probability_autoload_check("factory",
                           distribution.class_name == "NormalDistribution")
probability_autoload_check("factory.direct.method", distribution.mean == ~2.0)
probability_autoload_check("base.type",
                           ProbabilityDistribution.class_name == "Class")
probability_autoload_check("support.type",
                           distribution.support.class_name ==
                           "ProbabilitySupport")
probability_autoload_check("rng.type",
                           Probability.rng(9).class_name == "ProbabilityRng")
probability_autoload_check("direct.distribution.type",
                           BernoulliDistribution.new(~0.5).discrete?)
probability_autoload_check("gamma.factory",
                           Probability.gamma(~2.0).class_name ==
                           "GammaDistribution")
probability_autoload_check("sampling.type",
                           ProbabilitySampling.class_name == "Class")
probability_autoload_check("process.factory",
                           Probability.wiener.class_name == "WienerProcess")
probability_autoload_check("counter.factory",
                           Probability.counter_rng(9, 2).class_name ==
                           "ProbabilityCounterRng")
probability_autoload_check("multivariate.factory",
                           Probability.multivariate_normal(
                             [~0.0], [[~1.0]]).class_name ==
                           "MultivariateNormalDistribution")
probability_autoload_check("copula.factory",
                           Probability.gaussian_copula(
                             [[~1.0]]).class_name == "GaussianCopula")
probability_autoload_check("accuracy.type",
                           ProbabilityAccuracy.class_name == "Class")
probability_autoload_check("inference.type",
                           ProbabilityDiagnostics.class_name == "Class")

<< "probability_autoload_spec: all checks passed"
