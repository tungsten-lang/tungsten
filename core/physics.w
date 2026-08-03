# Physics — physical constants, ideal-gas thermodynamics, Euler systems of
# gas dynamics, and finite-volume machinery for solving them.
#
# Orchestrator for core/physics/ (module-split pattern; the use order is
# the dependency chain):
#
#   constants       + Physics facade root; CODATA constants (Quantity + _si)
#   ideal_gas       + IdealGas equation of state
#   euler           + EulerSystem / CompressibleEuler / IsothermalEuler
#   wave_solver     + LaxFriedrichs fluctuation solver, + Minmod limiter
#   finite_volume   + FiniteVolume grids with native f64[] sweep kernels
#   simulation      + EulerSimulation — dimensioned config, run loop, frames
#
# The Euler blocks mirror Lanyon's formally verified CompressibleEuler C
# implementations (github.com/lanyonai/CompressibleEuler): the same state
# layouts, fluxes, wavespeeds, Lax–Friedrichs wave/speed families,
# fluctuations, minmod reconstructions, and validity predicates. The
# project ~/math/lanyonai/compressible-euler cross-validates this module
# against those C blocks line by line.
#
# Layer rule: Quantities (units of measurement) live at configuration and
# reporting boundaries; every hot loop runs on raw f64[] typed arrays.

use core/physics/constants
use core/physics/ideal_gas
use core/physics/euler
use core/physics/wave_solver
use core/physics/finite_volume
use core/physics/simulation
