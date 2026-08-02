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
statistics_autoload_check("facade", Statistics.mean([1, 2, 3]) == ~2.0)

<< "statistics_autoload_spec: all checks passed"
