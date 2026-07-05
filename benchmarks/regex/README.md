# Regex engine: homegrown Tungsten vs oniguruma vs POSIX

Tungsten's regex engine (`core/regex.w`) is written in pure Tungsten — a
parse-to-program + backtracking VM, no external dependency. This benchmark
measures its match throughput against two C engines:

- **oniguruma** — the engine Tungsten *used to* link (and what Ruby embeds), so we
  measure it via Ruby. It's a mature, optimized regex library.
- **POSIX `regcomp`/`regexec`** — the regex engine in libc, no install needed.

Correctness (39 features — quantifiers, anchors, classes, groups, alternation,
Unicode) is guarded by `compiler/test/regex_features.w`, a self-contained
compiled test:

```bash
bin/tungsten -o /tmp/rxf compiler/test/regex_features.w && /tmp/rxf
```

## Workload

Pattern `(\d+)-(\d+)` (two captured number groups) matched against the 31-char
subject `"the order id is 4521-9837 today"`. The pattern is compiled once; only
the *match* is timed, in a tight loop. POSIX uses the equivalent ERE
`([0-9]+)-([0-9]+)`.

## Results (M-series mac)

| Engine                         | ns/match | relative |
|--------------------------------|----------|----------|
| **mine** — pure Tungsten       | ~930     | 1× (≈ POSIX) |
| POSIX `regcomp` (libc C)       | ~908     | ~1.0× (par) |
| **oniguruma** (via Ruby)       | ~153     | **6× faster** |

So the homegrown engine now **matches POSIX `regcomp`** and is **~6× slower than
oniguruma** — for a backtracking VM written in a high-level, self-hosted language
with zero dependencies.

The engine started at ~5470 ns/match; a sequence of optimizations took it to ~930
(**~5.9× faster**):

1. **Raw 64-bit Char compare** — `w_eq`/`w_lt`/… now short-circuit char-vs-char
   to a single tagged-WValue integer compare (the codepoint lives in the high
   bits, so the raw order *is* codepoint order). Speeds every literal/range step.
2. **Flat instruction encoding** — the program is three parallel integer arrays
   (`@op`/`@a`/`@b`) instead of an array of boxed `[op,a,b]` tuples, removing a
   layer of array-of-array indirection on every dispatch.
3. **`OP_FLAG` opcode** — a lone `\d`/`\w`/`\s` (or negated `\D`/`\W`/`\S`)
   compiles to one opcode whose match test is a single `char & flagbit`, using
   the class-membership bits the Char tag already carries. This skips the generic
   `OP_CLASS` path (two hash lookups + a set/range loop + a string compare *per
   character*) — the dominant cost on digit-heavy patterns like this benchmark.
4. **First-character prefix scan** *(biggest single win: ~4290 → ~1790)* — an
   unanchored match retries the whole VM at every start position. `compute_anchor`
   walks the program past the leading `SAVE`/`JMP` ops to the first *consuming*
   op; if it pins the first character (a literal, or a non-negated `\d\w\s`),
   `match()` skips every subject position that can't start a match with a single
   `char ==`/`char & flag` test instead of running — and failing — the full
   machine there. This subject has a 15-char non-digit prefix before `4521`, so
   the scan replaces ~15 failed VM starts with 15 cheap byte tests. It bails to
   "try every position" the moment the program branches (`SPLIT`/`?`/`*`/`|`),
   uses `.`/`[..]`/a negated flag, or anchors with `^` — so no valid match is
   ever skipped.
5. **Single-allocation span materialization** *(~1790 → ~1405)* — a match/capture
   span `[a,b)` is a window into the decoded codepoint array; `span_str` hands
   `(array, start, len)` to one runtime call (`w_string_from_codes`) that
   UTF-8-encodes the window into a single buffer. This replaced a per-codepoint
   loop doing `out = out + from_codepoint(cp)` — O(n²) with one string allocation
   *per character*. Like oniguruma/POSIX the match positions stay as offsets; we
   just build the result string once. Biggest on long matches (`a+` over 200
   chars: ~16.4µs → ~11.2µs) but even the 3-capture benchmark dropped ~22%
   (≈34 short-lived allocations → 3).
6. **Fused quantifier (`OP_REP`)** — a `*`/`+` over a *single consuming op*
   (`\d+`, `a+`, `[a-z]+`, `.*`) compiles to one opcode that consumes every
   match in a tight loop, then backtracks by position — depth-1 instead of one
   recursive `run()` frame per repetition. The body op sits right after `OP_REP`
   as a match template (so no third operand slot is needed); `X+` still emits the
   mandatory first `X` ahead of it, so the prefix scan is unaffected. Long
   matches win big (`a+` over 200 chars: ~11.2µs → ~5.1µs, the 200-deep recursion
   gone); the benchmark's two `\d+` groups gained ~8%. Nullable bodies (`(a*)*`)
   keep the guarded recursive path — only single-op quantifiers fuse.
7. **Decode cache** — `match()` re-decoded the subject (`String#codes`) on every
   call. Cache the decoded Char array keyed on the subject; repeated matches
   against the same string (scan, multi-pattern) reuse it. The key check is an
   O(1) bit-compare for the same object (`w_eq` short-circuits `a==b`). ~1270 →
   ~1065 ns — skips both the decode and the per-match array allocation.
8. **Prefilter as a first-char set** — generalize the single-char pin into a
   prefilter computed once at compile time (not per match): a set of literal
   first-chars plus an OR of `\d\w\s` flag masks. Now alternations (`foo|bar`),
   class/flag-prefixed, and `a*b` get a prefilter instead of scanning every
   position with the full VM.
9. **Boyer-Moore/Sunday literal-prefix skip** — a fixed literal prefix of 4+
   chars builds a bad-character skip table and strides over non-matching regions
   by `skip[char past the window]` instead of one position at a time.
10. **C prefilter scan** — the hot scan loop (`subj[i] == ch` / `subj[i] & flag`)
   was ~13 ns/position: that's *boxed array-access* overhead, not the test (the
   `@subj` typed array isn't indexed with a raw load in the VM). A C helper
   (`w_regex_scan_char`/`_flag`) does the scan with raw `int64` access — ~13 →
   ~1 ns/position. The 15-char lead on the benchmark went ~194 → ~15 ns; headline
   ~1061 → ~930 ns, reaching POSIX parity. (Codepoint-int args, not Char
   WValues — those mangle across the ccall boundary.)

## Representation: the Char tag (codepoints + class flags)

The engine matches on **Char WValues** (`String#codes`), not 1-char strings. The
Char tag was redesigned to carry the **codepoint in the high bits** — so a raw `==`
and `<` order by codepoint (`[a-z]`/`[5-z]`/`[α-ω]` sort correctly across Unicode
categories) — and the **`\d`/`\w`/`\s` class flags at the LSB**, so `char & 1/2/4`
is a single Unicode-correct branchless test (`中` is a `\w`). The VM compares Chars
directly and masks the flags. This replaced an earlier 1-char-string
representation (and a plain-int "lexint" stepping stone): it's correct on UTF-8 and
uses one canonical char representation.

Earlier a Char-WValue compare was measurably slower than a plain-int compare in
the Tungsten VM because char `==`/`<` didn't lower to a raw 64-bit compare;
optimization #1 above closed that gap, so char comparison is now as cheap as int
comparison.

## Where the time goes (and what's left)

The remaining overhead is Tungsten-level, not algorithmic or comparison-bound:

1. **Per-match decode** — `match()` calls `subject.codes()` (one O(n) allocation
   of Char WValues per call). Unavoidable when the subject changes; for repeated
   matches against the same subject it could be cached. Measured at ~3.6% — small.
2. **Recursive backtracking** — `run()` recurses on every `OP_SPLIT` (each greedy
   `+`/`*` step and each backtrack point is a Tungsten function call). De-recursing
   into an explicit backtrack-stack loop is the **next big lever**: the benchmark's
   two `\d+` groups alone spend ~8 recursive `run()` calls per match.
3. **Pattern optimization** — onig (and to a lesser extent POSIX) do first-char/
   prefix scanning and DFA caching. The first-char prefix scan (#4 above) is now
   done; still missing are a multi-char literal-prefix `memmem` scan and a
   Thompson-NFA (non-backtracking) mode for capture-light patterns, which would
   bound pathological backtracking.

The flat encoding, `OP_FLAG`, and the first-char prefix scan are done; de-recursing
`run()` (#2) — replacing the per-`SPLIT` recursive call with an explicit
backtrack-stack loop — is the next big perf lever.

## Correctness and limitations

The engine is a backtracking VM, so it is **correct** but shares the standard
backtracking failure mode. Correctness is locked down by
`compiler/test/regex_features.w` (56 checks: the full feature matrix plus
zero-width/empty edge cases and nullable-loop termination).

- **Empty-match loops are guarded.** A quantifier over a nullable body
  (`(a*)*`, `(a?)*`, `(a+)+`) used to recurse forever on the empty match and
  crash with a stack overflow; an `OP_MARK`/`OP_GUARD` progress check now stops a
  loop iteration that consumed nothing. These cases match correctly and
  terminate.
- **Catastrophic backtracking is *not* bounded.** Like PCRE, oniguruma, Java,
  and Python, a pathological pattern such as `(a+)+b` against a long
  non-matching run of `a`s takes exponential time (empirically `(a+)+b` on ~24
  `a`s + `c` runs for many seconds). The principled fix is a **Thompson-NFA /
  Pike-VM mode** (linear time, no catastrophe) for backreference-free patterns —
  this engine has no backreferences, so such a mode would be sound. A generous
  per-match step budget that *raises* (never silently returns the wrong answer)
  would be a smaller safety valve. Neither is implemented yet; treat untrusted
  patterns/inputs accordingly.

## Reproduce

```bash
bash benchmarks/regex/run.sh
```

Needs `ruby` (for the onig number) and `clang` (for the POSIX harness).
