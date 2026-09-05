# First use starts with a newly registered class, without an explicit import.
observable = PhysicalObservable.new("mass", :kg)
observation = PhysicalObservation.new(observable, Measurement.new(~2.0, ~0.1), "run")
dataset = ExperimentalDataset.new(observable, [observation])
estimate = dataset.fit_constant
raise "Physics estimate autoload" if estimate.class_name != "PhysicsEstimate"
raise "Physics facade autoload" if Physics.speed_of_light_si != ~299792458.0
raise "Burgers autoload" if BurgersEquation.godunov_flux(~1.0, ~2.0) != ~0.5
raise "Diagnostics autoload" if FiniteVolumeDiagnostics.linf_error([~2.0], [~1.0]) != ~1.0
raise "Euler autoload" if CompressibleEuler.new(2, ~1.4).nstate != 4
raise "Simulation autoload" if EulerSimulation.isothermal(1).dim != 1
<< "physics_autoload_spec: all checks passed"
