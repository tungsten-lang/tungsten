# Satori command-line entry point.
use ../lib/satori

code = satori_main(argv())
if code != 0
  exit(code)
