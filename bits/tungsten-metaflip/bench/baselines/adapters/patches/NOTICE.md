# Instrumentation patches: provenance and licences

The three patches are applied by `../../build.sh` to copies of the programs' sources; the clones themselves are left untouched.
Each patch adds environment-controlled seeding, target and CPU-budget handling and progress lines (see `../README.md`); none changes
the search.

| patch | applies to | upstream | licence of the upstream code |
| --- | --- | --- | --- |
| `km2022-instrumentation.patch` | `code/main.cpp`, `code/randompath.cpp` | https://github.com/jakobmoosbauer/flips (commit `e31a0a0`) | GNU GPL v3 or later (`LICENSE` of the repository; source headers of `code/`) |
| `km2024-instrumentation.patch` | `updated_code/{main_mm.cpp,tensor.hpp,tensor.cpp}` | same | GNU GPL v3 (repository `LICENSE`) |
| `tfg-instrumentation.patch` | `flip_graph.cpp`, `src/flip_graph.hpp` | https://github.com/dronperminov/ternary_flip_graph (commit `b942f00`) | MIT |

The hunks quote lines of the upstream files as context and are therefore covered by the licence of the file they patch (GPL-3 for the
two Kauers-Moosbauer patches, MIT for the third). The programs are built and run as separate executables; nothing of them is linked
into or distributed with the metaflip binaries. The adapters, converters and this documentation are part of the metaflip bit and
carry its licence.
