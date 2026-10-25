# Tungsten Wassat command-line entry point.

use ../lib/wassat

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

# SAT Competition convention: 10 = SATISFIABLE, 20 = UNSATISFIABLE,
# 0 = anything else. Rival solvers and every competition harness use it.
exit(wassat_run_cli(argv()))
