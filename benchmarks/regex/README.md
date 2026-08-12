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

| Engine                         | ns/match | relative to Tungsten |
|--------------------------------|----------|----------------------|
| **mine** — pure Tungsten       | ~350     | 1× |
| POSIX `regcomp` (libc C)       | ~961     | 2.7× slower |
| **oniguruma** (via Ruby)       | ~158     | 2.2× faster |

So the homegrown engine is now about **2.7× faster than POSIX `regcomp`** on
this capture-heavy workload and **~2.2× slower than oniguruma** — for a
backtracking VM written in a high-level, self-hosted language with zero
dependencies.

The engine started at ~5470 ns/match; the full sequence of optimizations took it
to ~350 (**~15.6× faster**):

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
11. **Untagged `i64[]` VM characters** — the VM used to retain full 64-bit Char
    WValues. Once the decoded subject moved through an ivar, typed-array access
    lost its static view; the high tag bits made each read promote to BigInt and
    each flag mask allocate again. The VM now strips only tag/subtype bits once
    when the subject cache changes, retaining the 46-bit codepoint/metadata
    payload in an `i64[]`, and uses typed `@op`, `@b`, guard, capture, prefix,
    and subject views in the matcher. On the current compiler this removed a
    severe regression from 45,575 to 350 ns/match (**130×** on the raw median;
    historical pre-regression builds were ~930 ns/match).

## Representation: the Char tag (codepoints + class flags)

`String#codes` provides canonical **Char WValues**, not 1-char strings. A Char
carries the **codepoint in bits 25-45** — so raw `==` and `<` order by codepoint
(`[a-z]`/`[5-z]`/`[α-ω]` sort correctly across Unicode categories) — and the
**`\d`/`\w`/`\s` class flags at the LSB**, so `char & 1/2/4` is a Unicode-correct
branchless test (`中` is a `\w`). Regex strips the outer WValue tag/subtype bits
and stores the unchanged 46-bit payload privately. Span materialization still
reads the codepoint from bits 25-45, so the internal form preserves the canonical
Char semantics without exposing a second public character representation.

## Where the time goes (and what's left)

The before/after profile confirms this was an allocation-path win rather than a
smaller VM. `Regex#run` is 1,649 ARM64 instructions before and 1,645 after, but
its dynamic `_bit_binop` call site is gone. A five-second sample of the regressed
build found 454 of 471 samples in `bigint_arena_take`; a five-second sample of
the unboxed build found zero BigInt frames in 4,049 main-thread samples.

The remaining overhead is Tungsten-level: `run()` still recurses at each real
backtrack point, each successful benchmark match materializes three result
strings plus its capture array, and most opcode comparisons/counter updates are
still boxed inline-i48 operations. De-recursing into an explicit backtrack stack
and offering a capture-free `match?` execution path are the next likely levers.

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

The script explicitly uses a Tungsten `--release` build. It needs `ruby` (for
the onig number) and `clang` (for the POSIX harness). Results above are medians
of three runs on 2026-08-12: Apple M5 Max, macOS 26.6.1, Apple clang 21.0.0,
Ruby 4.0.6.
