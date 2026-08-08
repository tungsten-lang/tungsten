# Physics — physical models, numerical solvers, and experimental data.
#
# One facade owns both previously divergent APIs:
#
#   experimental    Measurement, observations, covariance, and constant GLS
#   thermodynamics  physical constants and an ideal-gas equation of state
#   hyperbolic PDE  Euler systems, Burgers references, wave solvers, and FV
#
# Selected constants, gas-law helpers, and simulation configuration accept
# Quantities; experiment units are metadata and finite-volume hot loops use raw
# SI f64[] storage. Repository checks are regression evidence, not formal proof
# artifacts.

use core/measurement
use core/linalg
use core/physics/constants
use core/physics/ideal_gas
use core/physics/euler
use core/physics/wave_solver
use core/physics/burgers
use core/physics/finite_volume
use core/physics/finite_volume_diagnostics
use core/physics/simulation
use core/physics/experiment

+ Physics
  -> .observable(name, unit = nil, symbol = nil, description = nil)
    PhysicalObservable.new(name, unit, symbol, description)

  -> .observation(observable, measurement, run_id,
                  captured_at = nil, metadata = nil)
    PhysicalObservation.new(
      observable, measurement, run_id, captured_at, metadata)

  -> .dataset(observable, observations, covariance = nil)
    ExperimentalDataset.new(observable, observations, covariance)

  -> .fit_constant(dataset)
    dataset.gls_mean
