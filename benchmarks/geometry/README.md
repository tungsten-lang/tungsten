# Geometry construction benchmark

Run from the repository root on macOS:

```sh
ruby benchmarks/geometry/compare_mesh.rb 68b485e 100 200 400
ruby benchmarks/geometry/compare_topology.rb 68b485e
```

The scripts compile both implementations with the same current compiler and
shared dependencies. The baseline substitutes `core/geometry/mesh.w`
from the named revision, with `Int` added to its accepted integer class names
for compatibility with current main; storage and topology algorithms are
unchanged. `GEOMETRY_COMPILER` can select a current compiler binary explicitly
when the local worktree still has an older build. Generated sources/binaries stay in temporary
directories which Ruby cleans on exit. The benchmark times mesh construction
through its first topology query and checks disk edge count, Euler
characteristic, and genus. `input` and `mesh` modes expose input/storage costs
and the effect of lazy topology separately. Peak RSS includes program inputs.

Observed local paired run, 2026-09-05, standard native compile, before the
rebase onto main's newer compiler/runtime (not a current-toolchain speed claim):

| Faces | Previous build + audit | Packed build + audit | Previous peak RSS | Packed peak RSS |
| ---: | ---: | ---: | ---: | ---: |
| 20,000 | 164 ms | 84 ms | 77.3 MB | 14.4 MB |
| 80,000 | 716 ms | 342 ms | 300.2 MB | 47.4 MB |
| 320,000 | 3,674 ms | 1,538 ms | 1,260.2 MB | 187.1 MB |

At 320,000 faces the input-only processes used about 41.4 MB; constructing
the new mesh without its lazy audit used 129.0 MB and took 87 ms. These are
local grid measurements, not a bound for arbitrary incidence, huge exact
coordinates, or interpreter execution. Packed topology adds orientability
and reusable incidence to the existing reports. It still sorts numerical
edge keys and retains copied Array coordinates/faces.

The differential script compares every unchanged diagnostic against the old
link-graph implementation on 500 deterministic generated meshes (seed 73921),
including duplicates, isolates, high-incidence edges, and disconnected links.
The Core spec separately checks parity repair for every tetrahedron winding,
RP2/Mobius nonorientability, genus on torus + sphere components, boundary
cycles, and defensive accessors. The previous report withholds genus on
inconsistent winding, so that intentionally changed field is excluded from
the historical comparison.
