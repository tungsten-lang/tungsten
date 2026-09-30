# Pins of the baseline programs

The baselines are built out of tree by `build.sh` from clones that are checked against these commits; no third-party source is
stored in the repository. The instrumentation applied to the copies is in `adapters/patches/` (`adapters/patches/NOTICE.md`).

## Programs

| name | program | repository | commit | licence | binary |
| --- | --- | --- | --- | --- | --- |
| `km2022` | `flip`, directory `code/` (Kauers, Moosbauer, *Flip graphs for matrix multiplication*, arXiv 2212.01175) | https://github.com/jakobmoosbauer/flips | `e31a0a0f0d2577cee5da047ca7dcae0c61992e40` (2025-12-09) | GPL-3 | `km2022_flip` |
| `km2024` | `flip`, directory `updated_code/` (with the plus transition of Arai, Ichikawa, Hukushima, arXiv 2312.16960) | same commit | same | GPL-3 | `km2024_flip` |
| `tfg` | `flip_graph` of `ternary_flip_graph` (Perminov, arXiv 2511.20317, 2603.02398), run with `--ring Z2` | https://github.com/dronperminov/ternary_flip_graph | `b942f005c61882f678fafb65ba4f9f348f9ef8df` (2026-08-06) | MIT | `tfg_flip_graph` |

The clones live in `~/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota/{flips,tfg}` (`SOTA_SRC` of `build.sh`),
the build in `.../sota/build/` (`SOTA_BUILD`), the binaries in `.../sota/build/bin/`.

## Toolchain

| | |
| --- | --- |
| host | Apple M5 Max, macOS 26.7.1 (Darwin 25.6.0), arm64 |
| compiler | Homebrew clang 23.1.0 (`/opt/homebrew/opt/llvm/bin/clang++`), the compiler behind the Tungsten backend |
| OpenMP | `libomp.dylib` of the same Homebrew LLVM 23.1.0 (`tfg` only; run with `OMP_NUM_THREADS=1` and `--threads 1`) |
| flags, all programs | `-O3 -flto -mcpu=apple-m5 -std=c++17 -DNDEBUG` |
| flags, additional | `km2022`: `-DEXPECT`, the program's own switch for branch hints; `tfg`: `-fopenmp` with the include and library paths of that `libomp` |

`-mcpu=apple-m5` is the CPU that this compiler selects for `-mcpu=native` on the host. Instructions retired on a fixed trajectory
(3x3x3, 260,908 steps of `km2022` from the standard algorithm): 1.99G with `-O3 -flto`, 1.89G with `-DEXPECT` added. On 4x4x4, for
3 s of CPU, `-flto` lowers `km2024` from 1622 to 1425 instructions per flip and leaves `tfg` at 1456 (1465 without).

## Build record

`build.sh` writes `.../sota/build/BUILD-INFO.txt`. The record of the build used for the runs of this branch; two independent builds
give bit-identical executables:

```
built:      2026-09-30T06:23:35Z
host:       Darwin 25.6.0 arm64, Apple M5 Max
compiler:   Homebrew clang version 23.1.0  (/opt/homebrew/opt/llvm/bin/clang++)
flags:      -O3 -flto -mcpu=apple-m5 -std=c++17 -DNDEBUG   (km2022 adds: -DEXPECT; tfg adds: -fopenmp -I/opt/homebrew/opt/llvm/lib/clang/23/include -L/opt/homebrew/opt/llvm/lib -Wl,-rpath,/opt/homebrew/opt/llvm/lib)
libomp:     /opt/homebrew/opt/llvm/lib/libomp.dylib
flips:      e31a0a0f0d2577cee5da047ca7dcae0c61992e40   (code/ -> km2022, updated_code/ -> km2024)
tfg:        b942f005c61882f678fafb65ba4f9f348f9ef8df
sha256:     15b85a0b0b418ecde89303d25b046cc1bb0129ee76c451acb32d2024483bd19e  bin/km2022_flip
sha256:     1826e0a418d60b1a6eed05e0def20f178c2b5c47026a3f92713091166e100d8b  bin/km2024_flip
sha256:     edbfc6f381e273abc29c1448c35e90eb2e5f3461e93774cac8f9fb7df9cd8c90  bin/tfg_flip_graph
patch:      1dc626b7983c7e84565cadc71205bee547c76decedc61dd41f1f26c00621fd5b  adapters/patches/km2022-instrumentation.patch
patch:      d52bd19b35f0abd5993b7485c27381772a0693ccc8f113d126489cf94aa302a6  adapters/patches/km2024-instrumentation.patch
patch:      d90939037d3f4422ca61a07a63a4d2ba3476fbf49ebe9466e4e5d084a08165aa  adapters/patches/tfg-instrumentation.patch
```

## Instrumented behaviour

Equal seeds give the same trajectory with and without the patches (`check-patches.sh`):

```
km2024: 80 identical of 80 compared
km2024 (KM_LOOP): 20 identical of 20 compared
km2022: 40 identical of 40 compared
tfg: 40 identical of 40 compared
```
