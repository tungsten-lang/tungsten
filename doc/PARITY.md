# Cross-engine parity suite

Tungsten has three engines that each implement the language separately:
the native interpreter (`bin/tungsten run --interpret`,
`compiler/lib/interpreter.w`), the WIRE → LLVM compiled path
(`bin/tungsten compile` / `-o`), and the Ruby tree-walker
(`bin/tungsten --interpret`, `implementations/ruby/`). The parity suite
runs the *same* program through the engines and diffs the transcripts, so a
behaviour that quietly drifts in one engine shows up as a red diff instead
of surviving as folklore.

```sh
make parity                                   # spec/parity, interp vs compiled
scripts/parity.sh --files units_conversion    # one spec (bare names resolve)
scripts/parity.sh --engines interp,compiled,ruby
scripts/parity.sh --jobs 8 --verbose --keep   # print transcripts, keep work dir
```

`scripts/test-specs.sh` runs the suite as a default stage (after the
interpreted lanes); `RUN_PARITY_SPECS=0` skips it. The last line of every
run is the summary `parity: N pass, N xfail, N fail, N xpass`, and the exit
status is non-zero on any `fail` or `xpass`.

## What a spec is

A parity spec is a small deterministic program under `spec/parity/` named
`*_spec.w` that prints values with `<<`. It does not assert; the assertion
is the diff. A spec passes when

- every selected engine's stdout+stderr+exit code agree byte-for-byte
  (only trailing whitespace is stripped; the exit code is appended as an
  `exit=N` line, so a crash in one engine is a divergence too), and
- no output line starts with `FAIL`.

Keep each spec focused on one surface (one area, ideally one printing
rule). A single divergent line turns the whole spec red, so anything that
diverges today lives in its *own* small spec — the passing lines around it
stay green and keep guarding the rest of the area.

Engines: `interp` and `compiled` are the default pair. `ruby` adds the Ruby
tree-walker; it is off by default because it disagrees on 27 of the 39
specs the default pair agrees on (unported surfaces like `recase`, `Σ`,
`graphemes` and two-argument `raise`, plus Ruby's own numeric tower — see
the "Ruby tree-walker as a third column" section of
`spec/parity/DIVERGENCES.md`). Run it on purpose when working in
`implementations/ruby/`. `nofree` (`TUNGSTEN_FREE=0`) and
`noinfer` (`TUNGSTEN_PARAM_INFER=0`) are compiled variants with a lowering
switch flipped; each gets its own cache so the incremental cache cannot
serve a plain-compiled artifact under the variant's name.

The suite compiles into its own incremental cache — `build/cache/parity`,
or `$TUNGSTEN_CACHE_DIR/parity` when a cache root is already set (so the
stage `test-specs.sh` runs never touches the spec suite's slots), or
`$TUNGSTEN_PARITY_CACHE_DIR` when that is set explicitly.

## Adding a spec

1. Write `spec/parity/<area>_<topic>_spec.w` with a one-paragraph header
   comment and `<< "label [expr]"` lines. Use 2-space indent, double-quoted
   strings, no trailing `()` on zero-arg calls.
2. `bin/tungsten -c spec/parity/<name>_spec.w` must say `200 OK`.
3. `scripts/parity.sh --files <name>` — iterate until it is PASS, or split
   the divergent line(s) into their own xfail spec (below).
4. Add the path to `parity_specs` in `scripts/spec-lanes.sh`. Every tracked
   `spec/**/*_spec.w` must be classified there; an unlisted file fails the
   whole suite closed.

## xfail policy

A spec whose engines are *expected* to disagree carries, as its first line,

```
## parity xfail <one-line reason: what each engine does>
```

It is reported `XFAIL` (green) while the engines still disagree. When a fix
lands and the engines agree, the run reports `XPASS` — a failure — and the
fix must also drop the header and the spec's row in
`spec/parity/DIVERGENCES.md`. That keeps the ledger honest in both
directions: a divergence cannot be forgotten, and a fixed one cannot linger
as "known". An xfail spec must still be a real program (`-c` clean) that at
least one engine runs to completion; a spec that both engines reject is a
missing feature, not a parity fact, and does not belong here.

`spec/parity/DIVERGENCES.md` is the ledger: one row per xfail spec with the
area, the two outputs, a one-line hypothesis and where to look in
`compiler/lib`. The row is not optional — an xfail spec with no row (its
file name in a table's `Spec` column) is reported `FAIL`, so the header and
the explanation land in the same change. Findings that cannot be seeded as a spec (because
`bin/tungsten -c` rejects the program) are listed there too, marked as such.
