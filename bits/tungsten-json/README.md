# tungsten-json

High-throughput JSON parser for Tungsten. Drop-in faster `JSON.parse` via a
16-byte SIMD JSON structural classifier (simdjson stage-1 algorithm).

## What it provides

- **A `+ JSON` override** that conforms to the JSON contract in core
  `lib/json.w` — same return types, same value tree, same call sites.
  Existing code that calls `JSON.parse(s)` doesn't change.

- **`bits/tungsten-json/lib/lexer{,16,32,_simd}.w`** — Tungsten lexer
  drivers for the per-character (NEON-helpers) and 16-byte SIMD
  classifier paths. These are *copies* of `languages/json/lexer*.w`
  kept in sync as the production-intended source. The originals in
  `languages/json/` remain as a reference / playground for experimenting
  with new variants without touching the bit.

- **`bits/tungsten-json/runtime/json_simd.c`** — the C implementation of
  the SIMD classifier (NEON intrinsics, `vmull_p64` PMULL prefix-XOR,
  simdjson's escape detection bit math). Currently included from core
  `runtime/runtime.c` until per-bit runtime archives land.

- **`bits/tungsten-json/benchmarks/`** — single-thread and parallel
  benchmark drivers, plus `comparison/` for head-to-head benches against
  simdjson and jq.

- **`bits/tungsten-json/spec/`** — contract tests that run any JSON
  implementation through the same suite. Used to verify both core's
  recursive parser and this bit's SIMD path produce identical value
  trees.

## Performance

On a 205 MB pretty-printed JSON file (Apple M3 Max):

```
                              MB/s        speedup vs core
─────────────────────────     ──────      ───────────────
core lib/json.w (recursive)   ~280        1.0×
core lexer32.w (Tungsten)     1980        7.1×
this bit (SIMD classifier)    4681        16.7×
simdjson stage 1              5755        20.5×
```

Parallel peak: 37 GB/s at 16 goroutines (vs simdjson's 60 GB/s).

See [doc/articles/simd-classifier-from-scratch.md](../../doc/articles/simd-classifier-from-scratch.md)
for the full implementation walkthrough and benchmark numbers.

## Usage

```tungsten
use json
use tungsten-json    # loading the bit installs the override

result = JSON.parse(File.read("big.json"))
```

The override is automatic when the bit is loaded. Code that doesn't
load `tungsten-json` continues to use the default recursive-descent
parser in core `lib/json.w`.

## License

MIT. Reimplements simdjson's algorithms (find_escaped, prefix_xor,
to_bitmask) — simdjson is dual-licensed Apache 2.0 / MIT, used here
under MIT. See <https://github.com/simdjson/simdjson> for the original.
