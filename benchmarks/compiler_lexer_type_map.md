# Lexer token-symbol mapping direct-call trial

Status: rejected after the complete correctness and balanced 5+5 performance
gate. The current-source trial is in `/tmp/tungsten-lexer-type-map-current`;
production `compiler/lib/lexer.w` is unchanged.

Both roots were rebased after the retained Array#join v6 integration. At the
static handoff, shared `compiler/`, `core/`, `runtime/`, and `languages/` are
byte-identical to the isolated baseline; the isolated candidate differs from
that baseline only at `compiler/lib/lexer.w`.

## Motivation

Every materialized token goes through `Lexer#emit` or `Lexer#emit_at`. Both
currently dispatch dynamically to `Lexer#type_sym_to_id`, which then dispatches
through `_a`, `_b`, and `_c` until it finds the token's range. The mapping is
pure and closed over the constants in `core/token.w`, so the dynamic chain is
more work than the symbol cases themselves. There are 149 literal emit sites
in the lexer (42 mapped to the first segment, 23 to the second, and 84 to the
third); these are static source-site counts, not a claim about runtime token
frequency.

## Candidate and compatibility boundary

The isolated candidate moves the exact mapping into four top-level helpers:

- `lexer_type_sym_to_id`
- `lexer_type_sym_to_id_a`
- `lexer_type_sym_to_id_b`
- `lexer_type_sym_to_id_c`

Only the internal `emit` and `emit_at` call sites are routed directly to the
top-level aggregate. The four existing public `Lexer#type_sym_to_id*` methods
remain as one-call compatibility wrappers, so ordinary callers such as
`compiler/lex_parity.w` retain their API and virtual public dispatch.

There is one deliberate devirtualization caveat. An external subclass that
overrides `type_sym_to_id` can still observe its override through an explicit
public call, but inherited `emit`/`emit_at` no longer consult it. Likewise, an
override of only `_a`, `_b`, or `_c` no longer changes the aggregate wrapper.
The static gate proves there is no `Lexer` subclass in `compiler/`, `core/`, or
`languages/`; repository search also found no production override. Tungsten
has no final/private declaration that would express this assumption, so the
general language-design wish is recorded under “Non-virtual internal methods”
in `doc/SYNTAX_WISHLIST.md`. No syntax was changed.

## Exactness and focused semantics

`scripts/audit-lexer-type-map.rb` mechanically removes only the added helper
block, restores the old mapping block, and restores the two call spellings.
The normalized candidate must then be byte-identical to the baseline lexer,
which protects unrelated strings and comments from accidental replacement.
It also proves:

- all 133 refined `T_*` constants through id 159 match in name, value, and
  order;
- every numeric slot 0 through 159 is audited, including gaps;
- `T_UNKNOWN=0` and broad-only `T_OP=11` remain intentionally unmapped;
- symbols and ids are unique; and
- only `compiler/lib/lexer.w` differs between the matched source roots.

`spec/compiler/lexer_type_map_direct_spec.w` contains the complete 133-entry
table and checks the aggregate plus all three public segment methods. It pins
unknown/`T_OP` behavior, representative `emit`/`emit_at` packing from every
segment, and ordinary public aggregate override dispatch. Identical copies are
in both isolated roots so the eventual gate can compare baseline/candidate
compiled and tree-interpreter output.

The static audit has passed:

```text
PASS lexer type-map static audit: exact source transform
PASS mapping audit: 133/133 core token constants, every id 0..159 checked
PASS devirtualization audit: no Lexer subclass in compiler/core/languages
PASS matched roots: only compiler/lib/lexer.w differs
```

## Deferred build and balanced 5+5 gate

`scripts/bench-lexer-type-map.sh` first reruns all static gates. It then uses
one explicitly supplied bootstrap compiler and the same temporary source,
output, LLVM, and working-directory paths for sequential baseline/candidate
compiler builds. Correctness runs the focused spec in both compiled and
tree-interpreter modes and requires identical output.

For performance it freezes one candidate source snapshot and makes both trial
compilers compile the same absolute `compiler/tungsten.w` path from the same
working directory. Warmup and every measured pair must emit byte-identical
LLVM. Five alternating pairs yield exactly five baseline and five candidate
legs.

When the benchmark lane is free, run correctness before timings:

```sh
BOOTSTRAP_COMPILER=/path/to/one/bootstrap \
  CHECK_ONLY=1 scripts/bench-lexer-type-map.sh

BOOTSTRAP_COMPILER=/path/to/one/bootstrap \
  RESULTS_OUT=/tmp/lexer-type-map-results.txt \
  scripts/bench-lexer-type-map.sh
```

Retain only if paired-median and aggregate load+parse ratios are both at most
0.97, while paired and aggregate total compiler time, wall time, and user CPU
are all at most 1.00. A passing first campaign still requires an independent
repeat with every aggregate ratio below 1.00. Otherwise discard the candidate.

## Result

An initial correctness run exposed stale interpreter code in the older
prepared roots, so the exact lexer-only transform was rebased onto the current
compiler before measurement. Both current trial compilers then passed the
complete 133-entry mapping audit and matched in compiled and tree-interpreter
execution. Warmup and every measured self-host pair emitted byte-identical
LLVM.

| metric | baseline median | candidate median | paired ratio | aggregate ratio |
|---|---:|---:|---:|---:|
| load/parse | 5.210 | 5.267 | 1.030 | 1.012 |
| total compiler | 2.496 | 2.589 | 1.081 | 1.046 |
| wall | 7.740 | 8.010 | 1.025 | 1.023 |
| user CPU | 7.100 | 7.230 | 1.011 | 1.012 |

The direct helper lost every aggregate metric and missed the primary
load/parse gate, so no repeat or production integration is warranted. Raw
results are retained at `/tmp/lexer-type-map-results-1.txt`.
