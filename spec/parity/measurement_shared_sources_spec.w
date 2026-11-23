# Identical transcripts on the compiler, native interpreter and Ruby engine.
use physics

-> check_close(actual, expected)
  raise "expected [expected], got [actual]" if (actual - expected).abs > ~1.0e-12

tare = ~12.0 ± ~0.08
one = ~32.0 ± ~0.04
two = ~32.0 ± ~0.04
first = one - tare
second = two - tare
check_close(first.covariance_with(second), ~0.0064)
check_close(first.correlation_with(second), ~0.8)
check_close((-tare).covariance_with(tare), ~-0.0064)
check_close(one.covariance_with(two), ~0.0)
check_close((first - second).uncertainty, Math.sqrt(~0.0032))
check_close((first + tare - one).uncertainty, ~0.0)
check_close(((tare * tare).sqrt - tare).uncertainty, ~0.0)
check_close((tare / (tare + ~0.0)).uncertainty, ~0.0)
check_close((first * ~-2.0).covariance_with(second), ~-0.0128)
check_close(tare.expanded.covariance_with(tare), ~0.0064)

restored = first
restored += tare
check_close((restored - one).uncertainty, ~0.0)

calibration = Calibration.linear(~2.0, ~1.0)
check_close(calibration.apply(tare).covariance_with(tare), ~0.0128)

mass = Physics.observable("sample", :g)
runs = []
[~32.02, ~31.98, ~32.04, ~32.00].each ->(value)
  runs.push(Physics.observation(mass, (value ± ~0.04) - tare, runs.size))
dataset = Physics.dataset(mass, runs)
raise "missing inferred covariance" if dataset.covariance_source != :inferred
fit = dataset.fit_constant
check_close(fit.value, ~20.01)
check_close(fit.uncertainty, Math.sqrt(~0.0068))
check_close(fit.measurement.covariance_with(tare), ~-0.0064)
check_close((fit.measurement + tare).uncertainty, ~0.02)
check_close(fit.chi_square, ~1.25)
raise "wrong degrees of freedom" if fit.degrees_of_freedom != 3
<< "shared measurement sources passed"
