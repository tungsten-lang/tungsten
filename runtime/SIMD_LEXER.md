# SIMD Lexer Helpers

NEON-accelerated inner-loop scanners for the Lex16 / Lex32 LexChar
variants. Lives in `runtime/runtime.c` next to the lex16/lex32 packers;
declared and called via Tungsten `ccall` from `languages/c/lexer16.w`
and `languages/c/lexer32.w`.

## What ships today

| Helper              | Width | Lanes | Purpose                                      |
|---------------------|------:|------:|----------------------------------------------|
| `w_lex16_scan_flag` |    16 |     8 | advance past a run of LexChars matching mask |
| `w_lex32_scan_flag` |    32 |     4 | same, 4-lane i32 sweep                       |

Both follow the `int64_t fn(int64_t lc_wval, int64_t pos, int64_t flag_mask)`
shape and return the new position. Tail safety is provided by the
`LEX_SENTINEL_PAD = 16` zero entries appended by the packers — an 8-lane
NEON load past the live `length` always lands inside the allocation.

x86 builds get a scalar fallback with identical semantics (`#ifdef
__aarch64__` gate). The plan is M3 Max-first; portable SSE/AVX
implementations are out of scope and would need their own helpers.

## Calling convention from Tungsten

```tungsten
## i64: pos
## u32[]: lc
fn c_tokenize_fast32(lc, count, tokens)
  ...
  pos = ccall_nobox("w_lex32_scan_flag", lc, pos, 0x20)   # IS_ID_CONTINUE
```

**`ccall_nobox` vs `ccall`:** the helpers return raw `int64_t`, not a
NaN-boxed WValue. Plain `ccall` tags its result as `:i64` (= "WValue
holding int") which is correct for C functions returning WValues
(`w_int`, `w_runtime_dir`, `w_zstd_compress_llvm_escaped`) but causes a
runtime tag-check panic when the result is consumed by the machine-int
unbox path. `ccall_nobox` tags as `:raw_int` instead, so machine-int
targets cast directly and untyped/WValue targets nanbox at the
assignment boundary. Use `ccall_nobox` for any C helper that returns a
raw integer; use `ccall` for any helper that returns a WValue.

The lowering passes `:raw_int` / `:raw_i64` typed values directly as
their raw bits and other values through `ensure_i64_value` (which
NaN-boxes ints). Inside the C helper:

- `lc_wval` is a NaN-boxed pointer to a `WTypedArray`. Unwrap with
  `(WTypedArray *)w_as_ptr((WValue)lc_wval)`.
- `pos` is a raw machine int when the caller declares it via `## i64:`.
  Use directly.
- `flag_mask_i64` arrives boxed unless the caller hoists the literal
  into an `## i64:` local. Truncate with `(uint16_t)` / `(uint32_t)` —
  the low byte holds the actual flag bits regardless.

## Hybrid scalar/SIMD pattern

A bare `ccall` per identifier hands the win away to call overhead
(~5-10 ns per call). Real C source has plenty of 1-3 char identifiers
where the scalar inner loop wins. The recommended call site shape:

```tungsten
when 0x40                                   # IS_ID_START
  start = pos
  pos++
  if (lc[pos] & 0x20) != 0
    pos++
    if (lc[pos] & 0x20) != 0
      pos++
      if (lc[pos] & 0x20) != 0
        pos++
        # 4+ char identifier — vectorize the rest
        pos = ccall_nobox("w_lex32_scan_flag", lc, pos, 0x20)
  tokens[tc] = t_ident | ((pos - start) << 24) | start
  tc++
```

Three inline lookups handle the 1–3 char cases scalar-style; the fourth
hit falls through to the NEON sweep for long identifiers (`SQLITE_API`,
`pthread_mutex_lock`, etc.). Tune the inline depth empirically against
your target sources.

## Adding a new helper

1. Pick the scan kind: flag-match or codepoint-match. Flag scans use
   `vandq_s<N>` + `vceqq_s<N>` to find the first lane where the flag
   bit is absent. Codepoint scans use `vceqq_s<N>` against a broadcast
   target.
2. Write the helper next to `w_lex16_scan_flag` in `runtime/runtime.c`.
   Wrap with `#ifdef __aarch64__` and provide a scalar fallback for x86.
3. Add the `__attribute__((target("+neon")))` attribute on the aarch64
   variant.
4. Use `int64_t` for all parameters and the return value — the Tungsten
   `ccall` ABI expects 64-bit slots.
5. Read past `length` is OK up to `LEX_SENTINEL_PAD` lanes. Don't read
   past `length + LEX_SENTINEL_PAD`.
6. Validate with `bash languages/c/test_token_parity.sh` (cross-width
   token stream parity) and `bash benchmarks/c_lexer/bench_all.sh
   <file.c>` (throughput comparison) after wiring the helper into the
   lexer call site.

## Sentinel pad contract

- Lex64 / Lex32 / Lex16 packers all append `LEX_SENTINEL_PAD = 16`
  trailing zero entries after the live region.
- The lexer's main `while v != 0` loop self-terminates on the first
  zero, so the pad never enters the token output.
- A NEON helper may safely load 16 lanes past `length` of any width —
  the worst case (Lex16 8-lane load) reads 16 bytes which is well
  inside the 16-element pad regardless of element width.
- `length` itself reports the real character count, not the padded
  capacity. Don't use `length + LEX_SENTINEL_PAD` as a logical bound.

## Tunables

`runtime/runtime.h` declares (or will declare):

```c
#define LEX_SENTINEL_PAD       16   /* NEON tail safety, do not lower */
#define NEON_HYBRID_THRESHOLD   8   /* scalar inline depth before ccall */
```

`LEX_SENTINEL_PAD` is a hard contract — every packer and every helper
relies on it. Lowering it requires updating all four packers
simultaneously.

`NEON_HYBRID_THRESHOLD` is purely advisory — the call sites currently
inline 3 lookups before falling through to the helper, derived from
benchmarking against `runtime/runtime.c`. Tune per workload.

## Open work

- Additional helpers for whitespace / hex / digit / string-content
  scans follow the same pattern as `scan_flag` but haven't been added
  yet — same call signature, different mask. The IS_ID_CONTINUE scan
  is wired today; the others would land as separate `ccall_nobox`
  call sites in `lexer16.w` / `lexer32.w`.
- The throughput payoff is workload-dependent: sources with mostly
  short identifiers (3 chars or less) stay entirely on the scalar
  prefix and never touch the helpers. Sources with long identifiers
  (`SQLITE_API_*`, `pthread_mutex_*`) exercise the helpers more.
  Tune the inline depth (`NEON_HYBRID_THRESHOLD`) if a workload
  profile shows ccall overhead exceeding savings.
