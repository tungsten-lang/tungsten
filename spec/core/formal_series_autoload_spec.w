# FormalPowerSeries is directly discoverable without an explicit use.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

series = FormalPowerSeries.constant(1, 3)
check("autoload.class", series.class_name == "FormalPowerSeries")
check("autoload.coefficient.constant",
      series.coefficient(0) == Expression.constant(1))
check("autoload.coefficient.zero",
      series.coefficient(1) == Expression.constant(0))
check("autoload.transcendental",
      series.exp.coefficient(3) ==
        Expression.constant(0))

<< "formal_series_autoload_spec: all checks passed"
