# Signal's public analysis classes must resolve through the Core autoload
# manifest without an explicit `use signal`.

-> signal_autoload_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

signal_autoload_check("signal.class", Signal.class_name == "Class")
signal_autoload_check("signal_spectrum.class",
                      SignalSpectrum.class_name == "Class")
signal_autoload_check("signal_spectral_estimate.class",
                      SignalSpectralEstimate.class_name == "Class")

estimate = Signal.periodogram([~1.0, ~0.0], sample_rate: ~2.0)
signal_autoload_check("signal.periodogram",
                      estimate.class_name == "SignalSpectralEstimate" &&
                      estimate.nfft == 2 && estimate.bin_count == 2)

<< "signal_autoload_spec: all checks passed"
