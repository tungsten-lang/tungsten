# Building a simdjson-Class JSON Classifier in 200 Lines of C

This is the story of going from a JSON lexer at 1.98 GB/s to a JSON
classifier at 4.7 GB/s — closing 81% of the gap to simdjson's stage 1
in a single afternoon, by changing the dispatch model from
"one character per iteration" to "16 characters per iteration."

The lexer that I started with was already heavily optimized and at 95%
of its architectural ceiling for its dispatch model. The honest framing
of *why* it was still 3× slower than simdjson required measuring
simdjson itself — which I did in a previous article. The answer was
clear: simdjson processes 16 source bytes per iteration via NEON, while
my lexer processes 1 byte per iteration via a `case v & 0x3F` switch.
That's a 16× per-dispatch ratio that no amount of micro-optimization
can recover.

The fix had to be architectural: build a 16-byte SIMD classifier. This
article walks through how it works, why each piece is necessary, and
the per-step benchmark numbers.

## The simdjson approach in one sentence

Process JSON in 64-byte chunks (4× 16-byte NEON vectors), compute three
bitmaps per chunk via parallel SIMD comparisons (backslashes, quotes,
structural characters), use bit tricks to track escape-and-string state
across chunks in parallel, then emit one offset per "interesting"
position via a `ctz` loop over the final bitmap.

Total: ~150 lines of C plus ~50 lines of bit-twiddling helpers. Hits
93% of simdjson's per-core throughput on the first try.

## The first prototype: classify only, no string state

The simplest possible 16-byte classifier ignores string state entirely
and just identifies "interesting" characters wherever they appear:

```c
static inline uint8x16_t classify16(uint8x16_t v) {
    uint8x16_t m_quote = vceqq_u8(v, vdupq_n_u8('"'));
    uint8x16_t m_lb    = vceqq_u8(v, vdupq_n_u8('{'));
    uint8x16_t m_rb    = vceqq_u8(v, vdupq_n_u8('}'));
    /* ... etc for [ ] , : */
    return vorrq_u8(/* ... combine all */);
}
```

Then iterate the bitmap with `ctz` to emit offsets. This isn't a
correct lexer — it'll emit the position of every `{` or `,` regardless
of whether it's inside a string. But as a throughput probe it tells us
the architectural ceiling.

**Result: 5,929 MB/s.** That alone matches simdjson's stage 1 (5,755 MB/s
on the same file). The architectural ceiling is reachable.

## What was missing: string state

JSON strings can contain any byte except an unescaped `"`. A `,` inside
a string is data, not a structural character. To produce a correct
output, the classifier must track whether each position is "inside a
string" (and therefore should be ignored for structural classification).

The naive approach is sequential: walk the bitmap byte by byte, flip a
state bit at each unescaped quote, suppress emission inside strings.
This works but bottlenecks on the carry chain — every position depends
on the state of the previous position.

simdjson does it in parallel via two clever tricks: **prefix XOR via
polynomial multiply** and **escape detection via bit arithmetic**.

## Trick 1: prefix XOR via PMULL

Given a 64-bit bitmap `Q` where bit `i` is set iff position `i` is an
unescaped quote, we want to compute the **in-string bitmap** `S` where
bit `i` is set iff position `i` is currently inside a string.

The relationship: `S[i] = Q[0] XOR Q[1] XOR ... XOR Q[i]`. (After 0
quotes you're not in a string; after 1 quote you are; after 2 quotes
you're back out; etc.)

This is the **prefix XOR** of the quote bitmap. Computing it
sequentially is a 64-step carry chain. Computing it in parallel
requires multiplying `Q` by the all-ones constant in **GF(2)**
(polynomial arithmetic mod 2):

```
prefix_xor(Q) = Q × (~0)   [in GF(2)]
```

This is the classic carry-less multiply identity. On aarch64, NEON
provides `vmull_p64`, the polynomial multiply instruction:

```c
__attribute__((target("crypto")))
static inline uint64_t prefix_xor(uint64_t bitmap) {
    poly64x1_t a = vcreate_p64(bitmap);
    poly64x1_t ones = vcreate_p64(~0ULL);
    poly128_t r = vmull_p64(a, ones);
    return (uint64_t)vgetq_lane_u64(vreinterpretq_u64_p128(r), 0);
}
```

`vmull_p64` is part of the AES/crypto extension on aarch64, so the
function needs `target("crypto")` to be visible to the compiler. Apple
Silicon supports it natively.

**One instruction**. Replaces a 64-step sequential dependency with a
single ~6-cycle PMULL. The fundamental win that makes the whole
parallel string-state idea work.

## Trick 2: escape detection via bit arithmetic

Quotes can be escaped: `\"` is a literal quote inside a string, not a
string terminator. To filter escaped quotes from the raw quote bitmap,
we need an "escaped" bitmap `E` where bit `i` is set iff position `i`
is the character after an unescaped backslash.

The complication: backslashes can themselves be escaped. `\\` is two
backslashes that become a single literal backslash. `\\\` is `\\`
(literal) + `\` (escape character). `\\\"` is `\\` + `\"` — three
backslashes followed by a literal quote, with the quote being escaped.

The rule: a character is escaped iff the number of consecutive
backslashes immediately preceding it is **odd**.

simdjson computes this via a few-line bit trick:

```c
static inline uint64_t find_escaped(uint64_t backslash, uint64_t *prev_escaped) {
    if (backslash == 0) {
        uint64_t escaped = *prev_escaped;
        *prev_escaped = 0;
        return escaped;
    }
    backslash &= ~*prev_escaped;
    uint64_t follows_escape = (backslash << 1) | *prev_escaped;
    const uint64_t even_bits = 0x5555555555555555ULL;
    uint64_t odd_sequence_starts = backslash & ~even_bits & ~follows_escape;
    uint64_t sequences_starting_on_even_bits;
    int carry = __builtin_add_overflow(odd_sequence_starts, backslash,
                                        &sequences_starting_on_even_bits);
    *prev_escaped = (uint64_t)carry;
    uint64_t invert_mask = sequences_starting_on_even_bits << 1;
    return (even_bits ^ invert_mask) & follows_escape;
}
```

The full derivation is in simdjson's source code — the gist is that
adding `backslash` to its own "odd starts" mask propagates carry bits
in a way that distinguishes odd-length runs from even-length ones, and
the result is a bitmap of escaped positions for the entire 64-byte
chunk.

It also handles the cross-chunk case via `prev_escaped`, which carries
1 bit between chunks: "did the previous chunk end with an unfinished
backslash run?"

I worked through this on paper for `\\` (run of 2), `\\\` (run of 3),
`\\\\\` (run of 5), and the cross-chunk `\` at position 63 case to
convince myself it was correct. It is. simdjson's authors deserve the
credit for finding this; it's beautifully terse for what it does.

## Putting it together: per-block 64-byte classifier

```c
static inline uint64_t classify_block_64(const uint8_t *src,
                                          uint64_t *prev_in_string,
                                          uint64_t *prev_escaped) {
    /* 1. Load 4× 16 bytes */
    uint8x16_t v0 = vld1q_u8(src + 0);
    uint8x16_t v1 = vld1q_u8(src + 16);
    uint8x16_t v2 = vld1q_u8(src + 32);
    uint8x16_t v3 = vld1q_u8(src + 48);

    /* 2. NEON byte comparisons → 64-bit bitmaps */
    uint64_t backslash = to_bitmask4(/* vceqq with '\\' */);
    uint64_t quote_raw = to_bitmask4(/* vceqq with '"'  */);
    uint64_t structural = to_bitmask4(/* vorrq of vceqq with { } [ ] , : */);

    /* 3. Filter quotes: ignore escaped ones */
    uint64_t escaped = find_escaped(backslash, prev_escaped);
    uint64_t quote = quote_raw & ~escaped;

    /* 4. Compute in_string via prefix XOR + cross-block carry */
    uint64_t in_string = prefix_xor(quote) ^ *prev_in_string;
    *prev_in_string = (uint64_t)((int64_t)in_string >> 63);

    /* 5. Emit positions: structural outside strings + opening quotes */
    return (structural & ~in_string) | (quote & in_string);
}
```

The `to_bitmask4` helper packs four 16-byte NEON masks (each lane
0xFF or 0) into a 64-bit bitmap via simdjson's `vandq_u8` +
`vpaddq_u8` pattern. ~7 NEON ops, runs in parallel with everything else.

The whole per-block work is ~30 NEON instructions, ~10 scalar
operations, and one PMULL. The output is a 64-bit emit bitmap that
gets consumed by a `ctz` loop:

```c
while (emit) {
    int bit = __builtin_ctzll(emit);
    out[out_idx++] = pos + bit;
    emit &= emit - 1;
}
```

`ctz` finds the lowest set bit; `emit & (emit - 1)` clears it; repeat
until the bitmap is zero. ~5 cycles per emitted offset.

## Results

Standalone C bench, on a 205 MB pretty-printed JSON file, Apple M3 Max:

```
                              MB/s        speedup vs current   simdjson ratio
─────────────────────────     ──────      ────────────────     ──────────────
Tungsten existing lexer       1980        1.0×                 0.34×
Classifier prototype          5929        2.99×                1.03×
Full classifier (with         5336        2.69×                0.93×
  string state + escape)
simdjson stage 1              5755        2.91×                1.0×
```

**The full classifier with correct string state lands at 5336 MB/s,
93% of simdjson's stage 1 throughput.** The prototype-without-state
hit 5929 because it skipped the work that the PMULL+escape steps add
(~600 MB/s of overhead).

The remaining 7% gap to simdjson is a combination of:
- Slightly less optimized `to_bitmask4` (simdjson's variant uses a
  different shuffle pattern).
- Less aggressive LLVM unrolling (simdjson is structured to encourage
  the inliner to unroll the per-block work harder).
- Minor differences in how the per-thread offset buffer is managed.

None of these are fundamental. The dispatch model is right; the
per-cycle work is right; the per-byte work is right.

## Parallel scaling

The classifier is embarrassingly parallel — each thread gets its own
output buffer, no shared state. Sweep across 1-32 threads on a
16-core machine:

```
Threads:                       1       2       4       8       16      32
───────────────────────       ──────  ──────  ──────  ──────  ──────  ──────
Tungsten existing             1808    3371    6770    13688   20869   21070
Tungsten SIMD classifier      5336    10491   20596   39845   51676   34625
simdjson stage 1              5755    11353   22476   43582   59871   49760
```

**Peak: 51,676 MB/s at 16 threads** — 86% of simdjson's parallel peak.
Both implementations regress slightly at 32 threads as the memory
subsystem saturates and per-thread cache pressure compounds.

## Integration into Tungsten

The standalone C bench is interesting but not useful on its own. The
real win is exposing the classifier as a Tungsten lexer that any
Tungsten code can call. That's three pieces:

1. **A runtime helper** (`w_json_simd_classify`) in
   `bits/tungsten-json/runtime/json_simd.c` (currently `#include`d from
   `runtime/runtime.c`; future per-bit runtime archives will detach it)
   that wraps the C function with a stable `int64_t (data_ptr, len,
   out_ptr)` ABI.

2. **Two helper helpers** (`w_string_byte_ptr` and `w_string_byte_length`)
   that extract the raw byte pointer and length from a Tungsten String
   WValue, since the classifier wants raw bytes and Tungsten's
   `read_file()` returns a String.

3. **A Tungsten driver** (`bits/tungsten-json/lib/lexer_simd.w`, with a
   reference copy maintained in `languages/json/lexer_simd.w`) that wires
   them together:

```tungsten
## i64: count, src_ptr, src_len, out_ptr
## i32[]: tokens
-> json_tokenize_simd(source, tokens)
  src_ptr = ccall_nobox("w_string_byte_ptr", source)
  src_len = ccall_nobox("w_string_byte_length", source)
  out_ptr = ccall_nobox("w_typed_array_data_ptr", tokens)
  count = ccall_nobox("w_json_simd_classify", src_ptr, src_len, out_ptr)
  count
```

That's it. Five lines of glue, three ccalls, and the Tungsten code can
now call into the classifier as cleanly as any other lexer.

**Tungsten-driver throughput** (with the ccall overhead):

```
Goroutines:               1       2       4       8       16      32
──────────────────       ──────  ──────  ──────  ──────  ──────  ──────
SIMD lexer (Tungsten)    4681    7960    15646   27870   37187   34096
SIMD lexer (standalone)  5336    10491   20596   39845   51676   34625
Tungsten overhead         12%     24%     24%     30%     28%     1.5%
```

Single-thread overhead is small (~12%, mostly the three per-call
ccalls). Parallel overhead is bigger (~28-30% at 8-16 threads),
attributable to Tungsten's goroutine scheduler vs raw pthreads.
Compared to the *existing* Tungsten lexer, the SIMD lexer is still
**1.78× to 2.59× faster** at every concurrency level.

Compared to simdjson's standalone C/pthreads implementation, the
Tungsten SIMD lexer reaches **62% of simdjson's parallel peak**
(37 GB/s vs 60 GB/s). For a self-hosted-language lexer that calls into
runtime helpers via a function-call boundary on every invocation,
that's a strong number.

## The output is different from our existing lexer

This isn't a drop-in replacement. The two lexers produce different
output shapes:

- **`lexer32.w`** (existing, packed-i32): one cell per non-ws token,
  with type bits + offset bits packed into an i32. Includes structural
  chars, string opens, **and** number/keyword positions. Each cell
  carries enough info for a parser to dispatch on token type
  immediately. ~25.1M cells per round on the test file.

- **`lexer_simd.w`** (new, SIMD classifier): one i32 offset per
  structural char (when not inside a string) **and** one offset per
  unescaped string-open quote. Does NOT include number/keyword
  positions — those are recovered downstream by walking between
  consecutive structural offsets and inspecting the source bytes.
  ~24.9M offsets per round on the test file.

The 200K-token difference is the count of number+literal tokens our
existing lexer emits. The SIMD lexer leaves that work to a downstream
pass — which is fast (one source-byte read per emitted offset) but
shifts the cost.

For *raw lexer throughput* the SIMD lexer wins. For *end-to-end JSON
parsing throughput* the gap closes because the downstream pass to
recover number/keyword starts adds back some work. A fair comparison
of "produce an indexable token stream" would put the SIMD lexer
somewhere around 4-5 GB/s end-to-end vs the existing lexer's 1.98
GB/s — still a meaningful win, just not 2.6×.

## Lessons

1. **simdjson's algorithms are portable.** The PMULL prefix-XOR trick,
   the find_escaped bit math, and the to_bitmask compress — all of
   these are documented in simdjson's source and translate cleanly to
   200 lines of independent C. They're not magic; they're just
   non-obvious until someone shows them to you.

2. **The dispatch model dominates everything else.** Going from 1 char
   per iteration to 16 chars per iteration produced a ~2.7× speedup.
   No amount of inner-loop micro-optimization on the per-character
   model could have come close. When you're comparing per-core
   throughput between two implementations and one is 3× faster, **the
   difference is almost certainly in how much work each iteration
   does**, not in how cheap each iteration is.

3. **`vmull_p64` is on a separate execution port from `xtn`/`shrn`.**
   This is a happy contrast to the [Apple Silicon shrn-port-pressure
   gotcha](shrn-xtn-apple-silicon.md) — PMULL operations dispatch to
   the AES/crypto unit, which is independent of the narrow-and-transfer
   pipeline. So while we couldn't use shrn for fast lane finding in the
   existing lexer's NEON helpers, we *can* use PMULL for parallel
   prefix XOR in the SIMD classifier without contention.

4. **The first prototype told us the ceiling, the second prototype hit
   the ceiling.** I built two versions: a "no string state" prototype
   (5929 MB/s) and a full version with PMULL+escape handling
   (5336 MB/s). The first proved the ceiling existed at ~6 GB/s; the
   second proved it was reachable while preserving correctness. That
   structure made the work feel safe at every step — I never spent
   time on the full version not knowing whether it could be fast.

5. **Self-hosted-language overhead is real but small.** The 12%
   single-thread gap between the standalone C bench and the Tungsten
   driver is the cost of going through a few `ccall_nobox` boundaries.
   That's a much smaller hit than I expected, and it confirms that
   Tungsten's compile-time inlining of ccalls is doing its job. The
   parallel gap is bigger because of goroutine scheduler overhead, not
   the per-call cost. There's probably another 10-15% available by
   tuning the Tungsten scheduler, but that's a different project.

## Where this leaves the JSON lexer story

Three lexers now ship in `languages/json/` (and in
`bits/tungsten-json/lib/` as the production-intended copies):

- **`lexer.w`** (Lex64) — 1.4 GB/s single-thread, packed-i32 cells,
  scalar implementation. Use when you don't have NEON.

- **`lexer16.w` / `lexer32.w`** — ~1.9 GB/s single-thread, packed-i32
  cells with type bits, NEON helpers for inner scans. The "rich
  output" path: each cell directly tells the parser the token type.

- **`lexer_simd.w`** — 4.7 GB/s single-thread, raw-offset output, full
  16-byte SIMD classifier. The "raw throughput" path: 2.6× faster but
  the parser has to do more work to recover token types.

**Picking between them depends on what the downstream code wants.**
For pre-typed token streams, `lexer32.w` is the right call. For
maximum throughput on a benchmark or a streaming pipeline that's
willing to do its own type recovery, `lexer_simd.w` wins.

The JSON lexer ladder went from 1.4 GB/s to 21 GB/s parallel via the
per-character optimization track. Adding the SIMD classifier track
doubles that again to 37 GB/s, with simdjson sitting at 60 GB/s as
the next target.
