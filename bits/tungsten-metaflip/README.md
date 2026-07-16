# tungsten-metaflip

`tungsten-metaflip` is the distributable core of Metaflip: an adaptive,
exact-gated search for low-rank matrix-multiplication tensor decompositions
over GF(2). The fleet keeps independent CPU basins and schedules a diverse
portfolio of Metal kernels, with the GPU enabled by default when supported.

Version 0.1 is intentionally GF(2)-only. It includes the production fleet,
the pure-Tungsten GPU sources it builds, and the small set of exact schemes
needed to start supported campaigns. Ternary search, proof campaigns, exploratory
benchmarks, and the full certificate collection remain outside this bit.

```text
tungsten-metaflip/
├── Bitfile
├── bin/metaflip.w
├── lib/metaflip.w
├── lib/metaflip/
│   ├── scheme.w
│   ├── verify.w
│   ├── compose.w
│   ├── fleet.w
│   ├── rect.w
│   ├── tui.w
│   ├── paths.w
│   ├── fleet/
│   ├── rect/
│   ├── strategies/
│   ├── kernels/
│   └── seeds/
└── spec/
```

## Build

A Tungsten compiler is required both to build the coordinator and, for the
current release, at run time when the fleet materializes specialized workers.
Worker builds resolve the driver through `METAFLIP_TUNGSTEN`, `TUNGSTEN_BIN`,
`TUNGSTEN`, `TUNGSTEN_ROOT`, and finally `tungsten` on `PATH`.
From a checkout of this bit:

```sh
tungsten compile bin/metaflip.w \
  --out ./metaflip --release --fast --lto
```

Or let Bit preserve the executable, runtime worker sources, and assets as one
relocatable build tree:

```sh
bit build --release
./build/bin/metaflip --self-test --no-gpu
```

From the Tungsten monorepo, use its checked-out compiler:

```sh
bin/tungsten compile bits/tungsten-metaflip/bin/metaflip.w \
  --out bits/tungsten-metaflip/metaflip --release --fast --lto
```

Run a CPU-only smoke test before starting a long campaign:

```sh
./metaflip --self-test --no-gpu
```

The package also ships a compile-time layout check and an optional one-epoch
Metal integration check:

```sh
tungsten compile spec/package_layout_test.w --out /tmp/metaflip-layout-test
/tmp/metaflip-layout-test

tungsten compile spec/gpu_smoke.w --out /tmp/metaflip-gpu-smoke
/tmp/metaflip-gpu-smoke "$PWD/lib/metaflip"

tungsten compile spec/metallib_runtime_fallback_smoke.w --out /tmp/metaflip-msl-fallback-smoke
PATH="$PWD/spec/fixtures/offline-metal-failure:$PATH" /tmp/metaflip-msl-fallback-smoke "$PWD/lib/metaflip"
```

## Run

Square campaigns select their tensor explicitly:

```sh
./metaflip --tensor 3x3
./metaflip --tensor 5x5 --secs 3600
./metaflip --tensor 7x7 --no-gpu
```

The executable normally locates `lib/metaflip/` beside its installed build
tree. `--runtime-root PATH` or `METAFLIP_RUNTIME_ROOT` can select an unpacked
bit explicitly. `--asset-root`, `--repo-root`, `METAFLIP_ROOT`, and
`METAFLIP_ASSET_ROOT` remain compatibility aliases for one release.

The same binary accepts the bundled rectangular profiles using full labels
such as `2x2x5`, `2x2x6`, `2x2x9`, `2x5x6`, and `4x5x7`. `--rect` runs the adaptive multi-shape
portfolio. Thread and lane counts have hardware-aware defaults; use `-J` and
`--gpu-walkers` only when an experiment needs fixed allocation. The current
Metal throughput knee is 8,192 walkers with 40,000 trajectory steps per
scheduler epoch. Adaptive rectangular scheduling keeps each active child at
that occupancy floor and rotates shapes between epochs; larger explicit lane
budgets can run one additional shape per 8,192 walkers. `--gpu-walkers` and
`--gpu-steps` override those defaults. The default portfolio includes the
explicit `2x2x7`, `2x2x8`, and `2x2x9` fronts; each has exact `R`, `R+1`, and
`R+2` restart strata, and the rank-24, rank-27, and rank-31 targets are
evaluated independently.

Rectangular checkpoints retain a small exact-gated side archive at ranks
`R`, `R+1`, and `R+2`. Slots are selected for term-set distance as well as
rank, so restarts preserve genuinely different doors instead of four nearby
copies of the leader. Metal alternates fleet-best epochs with the exact door
scheduled for that shape's CPU host, including one-host portfolio allocations;
this prevents a broad portfolio from silently sending every GPU epoch back to
the leader. CPU islands likewise retain their OS threads for the campaign
lifetime and reload their coordinator-owned state slots after each round
barrier, avoiding repeated thread allocation without weakening sticky-door
independence. The low-cadence 5-to-4 meet-in-the-middle lane runs
concurrently with CPU islands and Metal walking; its output is joined and
fully verified at the epoch barrier. Every shape in the default mix now has a
specialized cal2zone worker, including `4x4x6`, `4x5x6`, and the full-width
i64 `4x5x7` lane; 5-to-4 MITM is also enabled for the validated small
`2x2x6` profile. Rectangular status
files report CPU moves, GPU moves, MITM attempts/pairs/time, and MITM failures
separately per shape and in total, including work completed by a segment that
later exits unsuccessfully.

Use `--no-gpu` on machines without a supported GPU. The CPU fleet requires a
64-bit Tungsten target. GPU acceleration currently requires macOS on Apple
Silicon and runtime Metal shader compilation. Discoverable `metal` and
`metallib` tools are an optional faster cache tier: Metaflip prepares an
offline library when possible, but a missing or broken offline toolchain falls
back to the compiler-generated sibling MSL without degrading the GPU engine.
`METAFLIP_FORCE_RUNTIME_MSL=1` forces that path for diagnostics.

## Files and state

The package keeps its public API, executable, immutable runtime, mutable state,
and curated results separate:

- `bin/metaflip.w` is the command-line entry source. `bit build` installs it
  as the extensionless `build/bin/metaflip` command.
- `lib/metaflip.w` is the side-effect-free public library entry. Importing it
  exposes scheme, verifier, rectangular, composition, and path APIs without
  starting a fleet.
- `lib/metaflip/` is the single immutable runtime namespace. Its top-level
  files are the public subsystems; `fleet/`, `strategies/`, `kernels/`,
  `rect/`, and `seeds/` contain implementation modules and operational data.
- `lib/metaflip/seeds/gf2/` contains only exact schemes needed to start or
  diversify supported campaigns. These are inputs, not an accumulating
  results archive.
- `lib/metaflip/manifests/seeds.tsv` links every bundled seed by SHA-256 to its
  attributed path in the curated results corpus. `lib/metaflip/SHA256SUMS`
  protects the complete immutable runtime subtree.
- `~/.tungsten/metaflip/` is the default live store for checkpoints, run
  status, near-rank banks, and newly discovered candidates. Override it with
  `METAFLIP_HOME` or `--state-dir PATH`.
- `tungsten-metaflip-results` is the separate curated public repository for
  verified certificates, known bests, attribution, and durable research
  artifacts. Promote a live result there only after independent verification.

Temporary worker binaries, Metal sources and libraries, rejects, and scratch
data may use the system temporary directory. Runtime compiler output is
explicitly directed there, so an installed bit never accumulates generated
CUDA, LLVM, Metal, AIR, or metallib files. These are caches, not certificates.

## Correctness and publication

Every admitted candidate is reconstructed against the complete target tensor;
GPU hits are host-gated before promotion. That gate protects the live search,
but a claimed record should still be replayed independently and published with
its coefficient domain, shape, rank, density, discoverer, provenance, and
digest.

The generalized rectangular k-XOR objectives, endpoint-to-word compilers,
four-line catalyst, and double-annihilation macro under
`lib/metaflip/strategies/` are offline research tools. They can verify a
prescribed local replacement and compile a replayable exact setup/flip/cleanup
word, but they are not production fleet lanes unless matched frontier
experiments show useful candidates.

Bundled seed files can have licenses or attribution requirements different
from the engine. Read [THIRD_PARTY.md](THIRD_PARTY.md) before redistributing a
package archive or adding a new imported seed.

## License

Except for separately identified third-party data, this bit is licensed under
`MIT OR Apache-2.0 WITH LLVM-exception`. See [LICENSE](LICENSE).
