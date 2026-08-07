# Dynamics — dynamical systems: flows and maps, trajectory integration
# (RK4 + symplectic Verlet/Yoshida), fixed points and linear stability,
# Lyapunov exponents and spectra, Kaplan-Yorke dimension, bifurcation
# sweeps, Poincaré sections, and attractor reconstruction (Takens
# embedding, Grassberger-Procaccia correlation dimension).
#
# Orchestrator for core/dynamics/ (module-split pattern; the use order
# is the dependency chain):
#
#   base         + Dynamics facade root; Flow/MapSystem/Hamiltonian contracts
#   systems      classic systems (Lorenz, Rössler, Hénon, logistic, …)
#   integrators  trajectories and orbits; symplectic steppers
#   stability    fixed points, Jacobian spectra, classification
#   lyapunov     Benettin max exponent, QR spectra, Kaplan-Yorke
#   analysis     bifurcation sweeps, period detection, Poincaré sections
#   embedding    delay embedding, correlation dimension
#   continuation equilibrium branches, periodic-orbit shooting, Floquet
#   basins       basin-of-attraction grids (GPU twin: doc/examples/gpu_basins.w)
#
# Numeric substrate: states are plain Arrays of ~f64 Floats; Jacobian
# and spectral work rides LinAlg (solve/qr/eigenvalues); the closure-based
# general ODE API stays in core/solve.w. Quantities (units) belong at
# configuration and reporting boundaries, never inside the steppers.

use core/dynamics/base
use core/dynamics/systems
use core/dynamics/integrators
use core/dynamics/stability
use core/dynamics/lyapunov
use core/dynamics/analysis
use core/dynamics/embedding
use core/dynamics/continuation
use core/dynamics/basins
