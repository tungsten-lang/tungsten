# rung command-line entry point.
use ../lib/rung

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

code = rung_main(argv())
if code != 0
  exit(code)
