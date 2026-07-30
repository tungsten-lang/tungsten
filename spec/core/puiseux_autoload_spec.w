# FormalPuiseuxSeries is directly discoverable without an explicit use.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

series = FormalPuiseuxSeries.new([1, 0, 2], 1, 2)
check("autoload.class",
      series.class_name == "FormalPuiseuxSeries")
check("autoload.ramification",
      series.ramification_index == 2)
check("autoload.leading",
      series.coefficient(Rational.new(1, 2)) ==
      Expression.constant(1))
check("autoload.trailing",
      series.coefficient(Rational.new(3, 2)) ==
      Expression.constant(2))

<< "puiseux_autoload_spec: all checks passed"
