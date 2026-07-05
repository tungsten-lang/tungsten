# MLton Benchmarks

This directory is a starting point for porting the MLton benchmark suite to
Tungsten.

## Upstream

`upstream/` is a copy of the MLton benchmark directory from:

- Repository: https://github.com/MLton/mlton
- Commit: `e44f16ca8cbe1eea16657bf5bd9208f7de158436`
- Source path: `benchmark/`
- License: HPND-style license, copied in `MLton-LICENSE`

The upstream suite exposes benchmark bodies as Standard ML files under
`upstream/tests/`. Most files define `structure Main` with `doit`; MLton's own
driver in `upstream/main.sml` compiles per-benchmark wrappers and chooses repeat
counts long enough for stable timings.

## Tungsten Ports

`tungsten/` contains hand ports of selected upstream tests. These should preserve
the benchmark shape before trying to tune Tungsten-specific idioms.

Current ports:

- `fib.w` ports `upstream/tests/fib.sml`
- `tak.w` ports `upstream/tests/tak.sml`

These ports use top-level `->` functions, not `fn`, because `fn` is memoized in
Tungsten and would change the recursive benchmark being measured.

Run the current Tungsten ports:

```bash
benchmarks/mlton/run.sh
```

Run one port:

```bash
benchmarks/mlton/run.sh fib
```

The runner compiles with `bin/tungsten-compiler compile --release` and stores
temporary binaries in `/tmp/tungsten-mlton-bench`.
