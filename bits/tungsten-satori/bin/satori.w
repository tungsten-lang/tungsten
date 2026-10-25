# Satori command-line entry point.
use ../lib/satori

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

code = satori_main(argv())
if code != 0
  exit(code)
