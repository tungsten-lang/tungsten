# Numeric-prefix incremental lowering experiment

Item 2 of the sequential improvements, 2026-09-04. **Not promoted.** The
compiler source remains unchanged; `implementation.patch` preserves the
opt-in experiment for review and replay. General dependency-aware per-file
lowering remains future work, requiring relocatable namespaces and dependency
summaries for whole-program inference. This narrow experiment does not test
or disprove that larger design.

The patch adds `TUNGSTEN_LIBRARY_PREFIX_CACHE=1`. It snapshots an unchanged
leading group of independent raw i64/f64 numeric function files, so editing a
later source can reuse those functions. Eligibility excludes calls, external
variables/constants, captures, default parameters, and interleaved source
files. The complete whole-program ABI/type-fact key is retained. All restored
functions still pass through the ordinary mid-end and emitter.

Validation passed:

- stage-1/stage-2 compiler LLVM byte identity;
- cache-off/store/hit LLVM and symbol-map byte identity;
- a downstream body edit hits the same prefix artifact;
- editing the cached file invalidates that artifact;
- adding a forward call makes the prefix shortcut ineligible;
- independently linked programs produce the expected changed results.

Six alternating linked edit pairs on Apple M5, LLVM 23.1.0, release/native/fast
with `--no-lto`, had medians of 0.381508 s for prefix reuse and 0.363358 s for
the existing whole-library cache. The synthetic fixture has 100 scalar
polynomial helpers. The roughly 5% higher median does not support retaining
this shortcut as a performance improvement. Hardware was not reserved; these
are local diagnostic measurements, not a regression conclusion or a general
incremental-compilation result. Exact individual pairs are in `result.json`.

Replay from the repository root:

```sh
git apply --unidiff-zero experiments/incremental-prefix/implementation.patch
bin/tungsten build --no-bits
python3 scripts/test-library-prefix-cache.py
git apply --reverse --unidiff-zero experiments/incremental-prefix/implementation.patch
```

The runner retains detailed LLVM, symbol maps, logs, and JSON measurements in
`build/reports/library-prefix`. It deliberately fails on an unpatched compiler
instead of mistaking a whole-library hit for a prefix hit.
