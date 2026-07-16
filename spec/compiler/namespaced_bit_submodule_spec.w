# A bit may pair lib/<name>.w with namespaced implementation modules under
# lib/<name>/. External users should still address those as `use <name>/...`.

use metaflip/scheme

if ffw_default_capacity(3) != 127
  << "namespaced bit submodule failed"
  exit(1)

<< "namespaced bit submodule ok"
