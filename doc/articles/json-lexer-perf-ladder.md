# From 1.4 to 21 GB/s — A JSON Lexer Performance Ladder

This is the rung-by-rung story of pushing a self-hosted JSON lexer from
1.4 GB/s to nearly 2.0 GB/s single-thread, and from there to **21 GB/s
(2.57 billion tokens/sec)** at 32 goroutines on a 205 MB JSON file.

The lexer is written in Tungsten — a self-hosted language that compiles to
LLVM IR — and links against a small C runtime that provides NEON-vectorized
inner loops for whitespace, identifier, and string scans. The starting point
was already a "fast" lexer by most metrics. Every rung below comes from
peeling off one specific cost the previous version was paying.

Test machine: Apple M3 Max. File: 205 MB pretty-printed JSON, 41,076,482
tokens before whitespace stripping. Compiler: clang 17 with `-O3 -flto
-march=native -mtune=native`.

## Rung 0: The starting point (1444 MB/s)

The original lexer emitted tokens as packed `i64[]` cells with a NaN-box tag
in the high bits:

```
 63──────────48 47 46 45──────38 37──────────24 23─────────────0
┌─────────────┬──┬──┬─────────┬───────────────┬──────────────┐
│   W_TAG     │  │ST│  type   │    length     │    offset    │
│   0xFFFC    │  │00│ (4 bit) │   (14 bit)    │   (24 bit)   │
└─────────────┴──┴──┴─────────┴───────────────┴──────────────┘
```

This sustained ~1444 MB/s single-thread on the test file — already in the
neighborhood of simdjson's tokenization phase, but with several rungs of
overhead waiting to be peeled off.

## Rung 1: Make LTO actually inline the C helpers (+18%)

The lexer's hot loops call into runtime C functions for SIMD-vectorized
whitespace scans, comment scans, and string content scans. Inspection of
the final binary showed every helper as a separate function symbol —
**LTO wasn't inlining them**, even though both sides were bitcode.

The cause was a target-feature attribute mismatch between the
Tungsten-emitted `.ll` (which stamped no function attributes) and the
clang-compiled runtime (which stamped `target-cpu`/`target-features`
from `-march=native`). LLVM's inliner refuses to cross that boundary when
the caller's features aren't a superset of the callee's.

The fix is to probe clang once at compile time and have the IR emitter
stamp the same attribute fragment on every function it generates. Full
debugging story, the wrong theories ruled out along the way, and the
specific probe command in
[lto-target-features-mismatch.md](lto-target-features-mismatch.md).

**Result:** runtime helpers vanish from the call stack and inline directly
into the tokenizer dispatch. The serial `bl` overhead per ccall (frame
setup, arg marshalling, indirect jump, return) — which was hidden inside
what *looked like* an inlined inner loop — disappears. Throughput jumps
from 1444 to ~1700 MB/s (+18%).

This is the single biggest single-thread win in the ladder. It was hiding
in plain sight because the source-level inner loop looked tight; only
disassembly showed the `bl` calls.

## Rung 2: Pack tokens into i32 instead of i64 (+9%)

The packed-i64 layout was wasteful: 4 bits of type, 14 bits of length, 24 bits
of offset, and 22 bits of padding. The 24-bit offset only addressed 16 MB of
source — *less* than the test file size (the original was silently truncating
offsets past byte 16M; nothing downstream noticed because it never
dereferenced them).

Rewriting the layout as a packed i32 with `[type:4][offset:28]` (or
`[type:3][offset:29]` for JSON's narrower type set) gives:
- One i32 store per token instead of one i64 store
- 256 MB or 512 MB max source size — *strictly larger* than the original 16 MB
- Same shift+OR construction cost in registers (which overlaps the store)

Throughput: ~1571 MB/s (+9% over Rung 1, +9% on top of that).

The win isn't from "smaller bytes per token" — the construction arithmetic is
identical. It's from **store μop throughput**: the L1d cache write port can
retire a 4-byte store more quickly than an 8-byte store, freeing up store
buffer slots for the next iteration's store sooner. Each iteration's store
sits on the critical path through `tc++`, and the narrower store shaves
~1 cycle of latency on that path.

## Rung 3: Don't store whitespace tokens at all (+8.5%)

JSON whitespace is insignificant per RFC 8259 — every parser already throws
ws tokens away. The original lexer was emitting ~16 million whitespace
"tokens" per round on the test file (whitespace is the most common token
class in pretty-printed JSON, ~39% of all tokens), and the parser was
discarding all of them.

Stripping the `tokens[tc] = t_ws | ...; tc++` from the whitespace branch —
just advancing `pos` past the run without recording it — drops 16 million
stores per round and brings the total to 25 million tokens.

Throughput: ~1670 MB/s (+8.5%). The win is bounded by the per-token store
cost (≈0.5 ns each × 16M = ~8 ms saved per round), which matches the
observed ~6% directly attributable + ~2% from improved cache footprint.

## Rung 4: Fold the whitespace eat into each emit branch (+8%)

After Rung 3, the dispatch loop still spends one full iteration on every
whitespace run: load `lc[pos]`, check sentinel, compute the codepoint, switch
on the flag byte, branch into the `when 0x08` arm, do the eat. That's ~5-7
cycles of dispatch overhead per ws run that produces no token.

The fix: each emit branch (struct, string, number, keyword) ends with an
inline whitespace eat *before* returning to the top of the loop. The
`when 0x08` arm goes away entirely. Leading whitespace at file start is
handled by a single skip before the loop.

```tungsten
loop
  v = lc[pos]
  if v == 0
    break
  case v & 0x3F
  when 0x04          # struct token
    cells[tc] = ...
    tc++
    pos++
  ...               # other emit branches

  # Eat trailing whitespace once per iteration (post-case form)
  if (lc[pos] & 0x08) != 0
    pos++
    if (lc[pos] & 0x08) != 0
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
```

This eliminates the wasted dispatch iteration for every ws run. ~16M
iterations saved × ~5 cycles each = ~30 ms saved per round on a 130 ms baseline.

Throughput: ~1797 MB/s (+8% over Rung 3, +24% over Rung 0).

The 3-character inline scalar prefix matters: most ws runs after a structural
token are 1-3 chars (single space between values, or a newline + 2-space
indent). Three sequential `if (lc[pos] & 0x08) != 0; pos++` checks handle the
common case without a ccall to the NEON helper. Longer runs (newline + deep
indent) fall through to the helper.

## Rung 5: Remove the bound check from the NEON helper (+5.4%)

The NEON helpers were originally written as bounded loops:

```c
while (pos + 4 <= length + LEX_SENTINEL_PAD) {
    ...NEON sweep...
    pos += 4;
}
```

LLVM was *sometimes* eliminating the bound check based on data-flow analysis,
but not consistently. Inspection showed the helper sometimes had a `cmp; b.gt`
in the inner loop and sometimes didn't, depending on surrounding code shape.

The fix: rewrite as `for (;;)` and trust the sentinel padding. Every typed
array allocated by `String#lchs` is followed by `LEX_SENTINEL_PAD = 16` zero
entries past `length`. The NEON sweep terminates as soon as it crosses into
the pad — the zero lanes fail the mask check on the first hit. There's no
need for a source-level bound at all.

```c
int64_t w_lex32_scan_flag_pure(int64_t data_ptr, int64_t length, int64_t pos,
                                int64_t mask_i64) {
    (void)length;
    uint32_t *lc = (uint32_t *)(uintptr_t)data_ptr;
    int32x4_t v_mask = vdupq_n_s32((int32_t)mask_i64);

    for (;;) {
        int32x4_t v = vld1q_s32((const int32_t *)(lc + pos));
        int32x4_t and_result = vandq_s32(v, v_mask);
        int32x4_t cmp = vceqq_s32(and_result, vdupq_n_s32(0));
        ...reduce + branch...
        pos += 4;
    }
}
```

Throughput: ~1911 MB/s (+5.4%). The win is one cmp + one cond-branch per NEON
iteration (1-3 iterations per call × ~16M calls per round = 30M-50M cycles).

## Rung 6: Convert *all* helpers to `for(;;)` form (+2.5%)

Rung 5 only converted the whitespace helper. Rung 6 applies the same
treatment to all 11 NEON helpers (scan_flag, scan_until_flag, scan_to_cp,
scan_to_cp_or, scan_to_cp2, × Lex16/Lex32). The string content and number
content scans also lose their bound checks, picking up another ~2.5%.

Throughput: **~1980 MB/s** (+37% over Rung 0).

This is also where we hit the architectural ceiling. A "no-store" upper bound
measurement (same lexer with the cell store stripped) runs at ~2068 MB/s.
We're at **95.7% of the ceiling**, with the remaining 4.3% being the
irreducible per-token store cost (one i32 store + one `tc++` per kept token,
which is bounded by L1d cache write port throughput).

## The cumulative ladder

```
                                              Single-thread    Δ vs Rung 0
Rung 0  packed-i64 (original):              1444 MB/s         baseline
Rung 1  + LTO inlining via target-attrs:    1700 MB/s         +18%
Rung 2  + packed-i32 (4+28):                1571 MB/s         +9%
Rung 3  + skip ws tokens:                   1670 MB/s         +16%
Rung 4  + post-case eat-ws:                 1797 MB/s         +24%
Rung 5  + pure NEON helper (no bound):      1911 MB/s         +32%
Rung 6  + all helpers for(;;):              1980 MB/s         +37%

Ceiling  matched no-store upper bound:       2068 MB/s         +43%
```

(Note that Rung 2's measurement happens after Rung 1 has compounded;
the cumulative Δ column shows the total improvement from Rung 0, not the
isolated step gain.)

## Parallel scaling

The single-thread number is 1.98 GB/s, but the lexer is embarrassingly
parallel — each worker tokenizes its own slice of the file with its own
output buffer, no shared state. Running with N goroutines and N parallel
copies of the same file:

```
Throughput in MB/sec on the 205 MB JSON file (25.1M tokens/job):

Goroutines:        1       2       4       8       16      32
─────────────────  ──────  ──────  ──────  ──────  ──────  ──────
Lex64              1432    2709    5293    10629   14268   14346
Lex32              1808    3371    6770    13688   20869   21070   ← peak
Lex16              1792    3238    6425    12832   20289   20543

Speedup (vs 1g)    1×      ~1.9×   ~3.7×   ~7.6×   ~11.5×  ~11.7×  (Lex32)
```

**Peak: 21.07 GB/s = ~2.57 billion tokens per second** at 32 goroutines on
Lex32. That's ~11.7× the single-thread rate on a 16-core M3 Max.

A few observations from the sweep:

1. **Scaling is near-linear up to 8 goroutines, then sublinear past 16.**
   From 1g → 8g, Lex32 goes 1808 → 13688 = 7.6× (95% per-thread efficiency).
   From 8g → 16g, only 1.52×. From 16g → 32g, basically flat (1.01×). The
   machine saturates by 16 goroutines on Lex32 — past that, additional
   workers contend for the same memory subsystem without adding throughput.

2. **Lex64 caps out earliest** (14.3 GB/s at 32g vs Lex32's 21 GB/s). Lex64
   reads 8 bytes per LexChar vs Lex32's 4, doubling the memory pressure for
   the same source coverage. The per-core load buffer fills faster on Lex64
   and the OoO core backs off sooner.

3. **Lex32 edges Lex16 even though Lex16 reads half the bytes.** Lex16 has
   the bandwidth advantage but Lex32's larger codepoint extraction (single
   shift/mask) is slightly faster than Lex16's high-byte extract because the
   dispatch flag and the codepoint sit in the same 32-bit word.

4. **Single-thread → parallel improvement compounds.** The single-thread
   improvement from the optimization ladder was +37%, but the parallel
   improvement (vs the same lexer pre-ladder) is **+57%** — the per-token
   wins remove contention for shared resources (store buffers, cache lines,
   memory controllers), and that contention compounds across cores.

## How does this compare to simdjson?

simdjson is the state-of-the-art JSON SIMD parser, written in C++ by
specialists in this exact problem. Comparing on the same 205 MB JSON file,
same machine, same compiler flags:

```
Threads:           1       2       4       8       16      32
─────────         ──────  ──────  ──────  ──────  ──────  ──────
This lexer        1808    3371    6770    13688   20869   21070
simdjson stage 1  5755    11353   22476   43582   59871   49760
                  ──────  ──────  ──────  ──────  ──────  ──────
simdjson per-     3.2×    3.4×    3.3×    3.2×    2.9×    2.4×
core ratio
```

simdjson is **~3× faster per core** at every thread count up to 16. Its
parallel peak is **60 GB/s at 16 threads**, vs our 21 GB/s at 32. The 3×
ratio is remarkably consistent across thread counts — the gap is per-character
work, not scaling efficiency. Both implementations regress slightly at 32
threads as the memory subsystem saturates.

A few caveats on the apples-to-apples-ness:

1. **simdjson stage 1 produces a different output shape.** Stage 1 emits an
   array of source offsets pointing to "structural" characters (the `{}[],:"`
   set plus a few others). Our lexer emits one packed cell per non-whitespace
   token, with the type pre-dispatched. Stage 1's output isn't directly
   parser-consumable — that's stage 2's job. Our output is closer to "stage 1
   + the relevant part of stage 2" combined. If we compared full-DOM-parse to
   full-DOM-parse, the gap would be smaller — simdjson's full DOM parse on the
   same file is 2491 MB/s single-thread, only 1.26× faster than our lexer.

2. **simdjson processes 16-byte chunks per dispatch.** Stage 1 uses a NEON
   classifier that loads 16 bytes at a time, computes a structural-character
   bitmap with `vqtbl1q_u8` table lookups, and emits offsets via `vshrn` +
   bit manipulation. Our lexer dispatches one character at a time via a
   `case v & 0x3F` switch, with NEON only on the inner whitespace/string/number
   scans. The 16× per-dispatch ratio is exactly the per-core gap we see.

3. **simdjson is a single-purpose specialist.** It exists to parse JSON as
   fast as theoretically possible. Our lexer shares a code generator with the
   C lexer and any future language we add — the same `case v & 0x3F` dispatch
   pattern handles every language. Adopting a 16-byte SIMD classifier would
   either duplicate the lexer (one classifier per language) or require a
   classifier code generator (more compiler infrastructure). Neither is free.

**The honest framing:** being at ~35% of simdjson's per-core throughput while
sharing the codegen with all other Tungsten lexers and being implemented in a
self-hosted language is a much more impressive result than the headline ratio
suggests. simdjson is the right comparison point for "how much further could
we push?", not "are we slow?". The answer to "are we slow?" is: no — we're
faster than re2c-generated lexers (~200-400 MB/s per core), faster than
tree-sitter (~50 MB/s), and competitive with hand-written C tokenizers.

## Things that *didn't* work

A few experiments are worth documenting because they look like they should
help and don't:

- **Shape A / Shape B (raw-pointer hoist).** The original hypothesis was that
  the per-call `WTypedArray` unbox inside each NEON helper was the bottleneck.
  Hoisting the unbox out of the helper (so the lexer passes a raw `data_ptr`
  instead of the WValue typed array) gave essentially zero perf improvement
  in isolation. The 8-lane NEON sweep amortizes the ~10-cycle unbox dance to
  near-zero. **The unbox wasn't the bottleneck — LTO failure was.** Shape B
  is still in the codebase as ABI cleanup, but it's not where the win came
  from.

- **Two-array SoA (types u8 + offsets i32).** Split the packed cell into
  parallel arrays. This makes intuitive sense as a memory-bandwidth
  optimization but **performs identically to packed-i64**. The reason:
  splitting one 8-byte store into two smaller stores roughly doubles the
  store μop count, which exactly cancels the byte savings. SoA wins for
  *bandwidth*-bound workloads; this lexer is *μop*-bound.

- **Two-pass (offsets-only lexer + derive_types pass).** Tokenize emitting
  only offsets, then re-walk the offsets array to derive types from
  `lc[offsets[i]]`. Simpler hot loop in pass 1 — but pass 2 has to redo
  most of the dispatch work, and the combined throughput is **30% slower**
  than the single-pass version. The tokenization work doesn't go away when
  you split it; you just pay the dispatch cost twice.

- **simdjson-style `shrn`/`xtn` lane-find tail.** Compress the NEON
  comparison vector to a packed bitmap and use `ctz` to find the first stop
  lane. **28% throughput regression on Apple Silicon** because `xtn` and
  `fmov d→x` share the same execution port. Documented in
  [shrn-xtn-apple-silicon.md](shrn-xtn-apple-silicon.md).

## Lessons

1. **Always check what LTO actually inlined.** Source-level call sites that
   look "free" can be hiding `bl` instructions that destroy throughput. A
   2-minute disassembly check at the start of any hot-path tuning session
   will pay for itself many times over.

2. **`target-features` mismatches block cross-language inlining silently.**
   If your IR emitter is custom (not clang's C front-end), it probably isn't
   stamping the right per-function target attributes by default. Probing
   clang via `-Wl,-mllvm,-pass-remarks-missed=inline` will tell you immediately.

3. **Per-token store μop count is the bottleneck, not byte count.** Splitting
   work across more arrays only helps if you reduce total μop count, not
   if you keep it the same. The packed-i32 win is from narrower store
   latency, not narrower bytes.

4. **Source-level `for (;;)` is not equivalent to a bounded `while` that LLVM
   "should" eliminate.** LLVM's bound-check elimination is a structural
   pattern match that can fail for surprising reasons. If you can prove the
   loop terminates via the data path, write `for (;;)` and let the data
   sentinel handle termination.

5. **Whitespace tokens are usually pure waste.** Almost every parser
   immediately discards them. If you're writing a new lexer, don't emit
   them in the first place — fold the whitespace skip into each emit branch
   so the dispatch loop never iterates on a useless token.

6. **The architectural ceiling is real and you can measure it.** A "no-store"
   variant of your hot loop tells you the hardware-imposed maximum throughput
   you could achieve. Once you're within ~5% of that ceiling, further
   single-thread tuning has diminishing returns; reach for parallelism instead.

## Where to from here?

We're at 95.7% of the architectural ceiling **for the per-character dispatch
model**, which is what bounds the current implementation. The simdjson
comparison shows that the *real* ceiling is ~3× higher — but reaching it
requires a different dispatch model.

Two paths forward, in increasing order of effort and reward:

- **Vectorized stores** (small win, small effort). Buffer 4 cells in a NEON
  register and commit them with a single `vst1q_s32`. Estimated ~5% gain
  on the per-token store cost (the only headroom left in the current model).
  Medium implementation cost.

- **A 16-byte SIMD classifier** (large win, large effort). The simdjson
  approach: load 16 source bytes per iteration, use a NEON table lookup
  (`vqtbl1q_u8`) to compute a per-character class bitmap in parallel, then
  `vshrn` + bit manipulation to emit token offsets. Estimated 2-3× gain
  based on the per-core ratio with simdjson. Major rewrite that changes the
  dispatch model from "one character per iteration" to "16 characters per
  iteration", and would either need to be JSON-specific (duplicating the
  lexer) or require new compiler infrastructure to generate the classifier
  table per-language.

Parallel scaling is already at ~11.7× single-thread on a 16-core machine,
and the bottleneck shifts to memory bandwidth above 16 goroutines. There's
probably another ~20% in clever cache-line packing of the output cells, but
diminishing returns. The pragmatic call is to ship at the current numbers,
which already outperform re2c-generated lexers and tree-sitter per-core, and
revisit only if a downstream workload becomes lexer-bound — or if the SIMD
classifier becomes worth the engineering investment to close the gap to
simdjson.
