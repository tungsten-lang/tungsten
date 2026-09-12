# Metaflip command-line entry point.

use ../lib/metaflip/fleet

# Closed-world contracts: the entry program owns the complete method and type
# universe, so the compiler can devirtualize sends and emit only the reachable
# Core cohort.  Library files reached through `use` must not declare these.
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
