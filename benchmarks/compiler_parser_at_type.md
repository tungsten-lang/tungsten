# Parser current-token type-test trial

Status: rejected after the complete correctness and balanced 5+5 performance
gate. The isolated candidate remains in `/tmp/tungsten-parser-at-type-prep`;
production `compiler/lib/parser.w` is unchanged.

## Motivation

The parser contains 429 executable bare calls to `Parser#at_type?` (431 textual
matches when its explanatory comment and method declaration are included).
The receiver is always the current parser and the implementation is never
overridden in the repository, but each call is still emitted as an
inline-cached method dispatch. Packed-token decoding is already a direct
top-level helper, so the dispatch can cost more than the actual shift, mask,
and comparison.

## Candidate

The isolated candidate adds:

```w
-> parser_at_type(p, type_id)
  parser_tok_type(p) == type_id
```

All internal parser grammar sites call that top-level function with
`@current_packed`; the public `Parser#at_type?` method remains as a compatibility
wrapper. This intentionally does not change syntax or the behavior of public
dispatch. The related desire for explicitly non-virtual/private class helpers
is recorded in `doc/SYNTAX_WISHLIST.md`.

`Parser` is internal/final in practice, not in the language. A hypothetical
external subclass that overrides `at_type?` and then inherits a grammar method
would observe a difference: that inherited grammar method now uses the direct
helper instead of the override. There are no such overrides in the repository,
and this is the same internal-class assumption as the retained direct packed-
token decoder migration. The public `at_type?` method itself remains virtual.

## Static audit and focused gate

`scripts/bench-parser-at-type.sh` first proves that the candidate is exactly a
mechanical rewrite: after removing the six-line helper, it must equal the
baseline under the audited bare-call substitution and the one-line wrapper
delegation. It also requires exactly 429 rewritten executable calls, rejects
explicit-receiver sites, and requires the compiler, core, runtime, and lexer
inputs to differ only at `compiler/lib/parser.w`. The audit currently passes.

`spec/compiler/parser_at_type_direct_spec.w` covers small packed Integers,
tagged packed values that materialize as BigInt after Array storage, maximum
neighboring offset/length fields, zero tokens, current-token mutation,
`minus_token?`, `star_token?`, `at_name_or_constant?`, inherited wrapper use,
and ordinary public override dispatch. Identical copies live in both isolated
roots so each trial compiler can exercise its own parser source in compiled and
tree-interpreter modes. The existing packed-token access spec runs beside it.

The harness requires one explicit `BOOTSTRAP_COMPILER` and uses that exact
executable for both trial builds. The builds run sequentially through the same
temporary source, output, LLVM, and working-directory paths; only the audited
parser source changes between them. For the identity/performance campaign it
then copies one candidate source tree to a second immutable temporary snapshot;
both resulting compilers compile the same absolute `compiler/tungsten.w` path
from the same working directory. Warmup and every measured pair must emit
byte-identical LLVM before its timings are accepted. The declared five-pair
ordering gives five baseline and five candidate legs with alternating
baseline-first/candidate-first orientation.

Source-only/static preparation commands:

```sh
STATIC_ONLY=1 scripts/bench-parser-at-type.sh
```

Once the benchmark lane is free, run correctness without timings first, then
the fixed 5+5 campaign:

```sh
BOOTSTRAP_COMPILER=/path/to/one/bootstrap \
  CHECK_ONLY=1 scripts/bench-parser-at-type.sh

BOOTSTRAP_COMPILER=/path/to/one/bootstrap \
  RESULTS_OUT=/tmp/parser-at-type-results.txt \
  scripts/bench-parser-at-type.sh
```

## Retention gate

Before integration:

1. Run compiled and interpreter parser regressions, including packed high-bit
   lexical tokens and UTF-8/codepoint offsets.
2. Build baseline and candidate compilers from the same bootstrap.
3. Compile one fixed source tree through both binaries, require byte-identical
   LLVM output, and run a balanced 5+5 load+parse/self-host campaign.
4. Retain only if both paired and aggregate load+parse are at or below the
   usual 0.97 gate; paired and aggregate total compiler time, wall time, and
   user CPU must all remain at or below 1.00.
5. Repeat independently and require every aggregate ratio below 1.00.

## Result

Both trial compilers were built with the same bootstrap
(`23c46d5d...c4ad2b`). The direct-call and packed-token specs matched in
compiled and tree-interpreter execution, and every warmup/measured compiler
pair emitted byte-identical LLVM. The performance gate nevertheless failed:

| metric | baseline median | candidate median | paired ratio | aggregate ratio |
|---|---:|---:|---:|---:|
| load/parse | 4.933 | 4.982 | 0.998 | 0.897 |
| total compiler | 2.211 | 2.430 | 1.091 | 0.985 |
| wall | 7.170 | 7.430 | 1.035 | 0.924 |
| user CPU | 6.820 | 6.940 | 1.021 | 1.017 |

One slow baseline leg made the aggregate ratios look artificially favorable;
the balanced paired medians are the relevant signal. Load/parse was flat and
total, wall, and user time all regressed, so no repeat campaign or production
integration is warranted. Raw results are retained at
`/tmp/parser-at-type-results-1.txt`.
