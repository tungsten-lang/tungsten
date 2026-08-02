# Compiled Complex correlation contract. Complex's generic numeric tower is
# native-compiler-only, while the rest of signal_spec runs in both engines.

use signal

-> signal_complex_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

sample = Complex<f64>.new([~1.0, ~1.0])
correlation = Signal.correlate([sample], [sample])
signal_complex_check("correlate.complex_conjugates_reference",
                     close?(correlation[0].real, ~2.0) &&
                     close?(correlation[0].imag, ~0.0))

<< "signal_complex_spec: all checks passed"
