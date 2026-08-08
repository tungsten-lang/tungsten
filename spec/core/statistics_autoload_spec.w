# Statistics and its public result/accumulator classes autoload without an
# explicit `use statistics` directive.

-> statistics_autoload_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

statistics_autoload_check("summary",
                          StatisticsSummary.class_name == "Class")
statistics_autoload_check("accumulator",
                          StatisticsAccumulator.class_name == "Class")
statistics_autoload_check("bivariate_summary",
                          StatisticsBivariateSummary.class_name == "Class")
statistics_autoload_check("bivariate_accumulator",
                          StatisticsBivariateAccumulator.class_name == "Class")
statistics_autoload_check("weighted_summary",
                          StatisticsWeightedSummary.class_name == "Class")
statistics_autoload_check("weighted_accumulator",
                          StatisticsWeightedAccumulator.class_name == "Class")
statistics_autoload_check("multivariate_summary",
                          StatisticsMultivariateSummary.class_name == "Class")
statistics_autoload_check("multivariate_accumulator",
                          StatisticsMultivariateAccumulator.class_name == "Class")
statistics_autoload_check("linear_model_result",
                          StatisticsLinearModelResult.class_name == "Class")
statistics_autoload_check("regression_diagnostics",
                          StatisticsRegressionDiagnostics.class_name == "Class")
statistics_autoload_check("robust_mean_result",
                          StatisticsRobustMeanResult.class_name == "Class")
statistics_autoload_check("cheap_subsampling_result",
                          StatisticsCheapSubsamplingResult.class_name == "Class")
statistics_autoload_check("conformal_rank_result",
                          StatisticsConformalRankResult.class_name == "Class")
statistics_autoload_check("half_mass_conformal_result",
                          StatisticsHalfMassConformalResult.class_name == "Class")
statistics_autoload_check("relative_fit_result",
                          StatisticsRelativeFitResult.class_name == "Class")
statistics_autoload_check("empirical_bernstein_sequence",
                          StatisticsEmpiricalBernsteinSequence.class_name == "Class")
statistics_autoload_check("confidence_sequence_result",
                          StatisticsConfidenceSequenceResult.class_name == "Class")
statistics_autoload_check("facade", Statistics.mean([1, 2, 3]) == ~2.0)

<< "statistics_autoload_spec: all checks passed"
