# C-builtin → Tungsten port campaign

Goal: move runtime IC handlers (`w_ic_*` in `runtime/runtime.c`) into real
Tungsten bodies in `core/*.w`, keeping performance within 10% of the C
handler. Benchmarks live in this directory (`run.sh`, one `.w` per method,
best-of-3 ns/op with a printed checksum); behavioral goldens in
`checks/edge_cases.w` must stay byte-identical across a port.

## Migration recipe

1. Write the Tungsten body in the class's **live** source file (see gotchas).
2. Retire the IC registration line (`w_ic_<type>_table[N].name = WN_x;`) in
   `w_init_ic_tables` — blanking a middle slot is safe (the resolve scan
   terminates on null `fn`, not null name).
3. Add the method name to the matching **autoload trigger list** in
   `compiler/lib/loader.w` (~line 520-590): primitive receivers carry no
   class reference, so without the trigger the class file never loads and
   dispatch dies with "undefined method". This is what the existing
   `("join" "compact" "dup" ...)` lists are for.
4. Rebuild, `checks/edge_cases.w` diff vs golden, `RUN_CORE_SPECS=1 make
   specs`, then `run.sh` vs a baseline captured on the pre-port build.

## Round 1 results (2026-07-18)

| method | C ns/op | Tungsten ns/op | verdict |
|---|---|---|---|
| Array#take | 156 | 154 | **kept** (parity) |
| Array#drop | 150 | 156 | **kept** (+4.5%) |
| Integer#gcd | 28 | 41 (was 62) | reverted |
| Integer#lcm | 24 | 36 (was 46) | reverted |
| String#capitalize | 25 | 40 | reverted |
| String#swapcase | 25 | 41 | reverted |
| Array#reverse | 284 | 560 | reverted |
| Array#uniq | 3649 | 7133 | reverted |
| Array#minmax | 167 | 250 | reverted |

## Round 2 results (2026-07-18, later the same day)

The "fixed method-call overhead" below was diagnosed and **fixed**: it was
never dispatch. The raw-int promotion analysis (lowering/analysis.w) was
blind to `## i64` assign hints, so loop temps assigned FROM hinted vars
(`t = b`, `r = a % b`) stayed boxed — one `w_int` + one `w_to_i64` runtime
call per loop iteration. Two analysis fixes landed:

1. `## i64`-style hints now seed the promotion fixed point as authoritative
   machine-int facts (plus `$value` counts as int-shaped).
2. Raw-consuming intrinsics (`wvalue_from_bits`, `ccall_nobox`, raw loads)
   no longer force-box their operands in escape positions (`return
   wvalue_from_bits(tag | x)` was boxing `x`).

With those, a same-binary A/B (IC `gcd` vs type-class `gcd2`, identical
bodies) closed from 27.5/40.5 to 27.3/27.9 — **dispatch is ~2% overhead,
not 50%**.

| method | C ns/op | Tungsten ns/op | verdict |
|---|---|---|---|
| Integer#gcd | 28.1 | 27.4 | **kept** (parity) |
| Integer#lcm | 23.9 | 10.1 | **kept** (2.3x FASTER — raw inlined-gcd path) |

Diagnosis recipe that worked: same-binary A/B via a twin method name with
no IC entry (forces type-class dispatch, no rebuild needed), `sample` the
hot loop, then read the method's emitted `.ll` — `w_int`/`w_to_i64` pairs
inside a loop body are the smoking gun. Watch for: ternaries defeat
promotion (`x = c ? a : b` boxes x — use `if`), and any var read inside a
`return <non-exempt call>(...)` gets escape-boxed.

Still open for future rounds: String#capitalize/swapcase (extra buffer
copy — needs a buffer-stealing `w_string_take_byte_array`), Array#reverse/
uniq/minmax (per-element `w_int(i)` + `w_array_idx` calls — needs an
ebits-aware raw `self[i]` fast path inside Array class bodies).

## Round 3 results (2026-07-18)

Raw-index array-load twins landed (9354ed2): `w_array_idx_i64` /
`w_array_get_i64`, emitted whenever the index is already a raw machine
int — every promoted loop var qualifies. Ports re-measured:

| method | C ns/op | Tungsten ns/op | verdict |
|---|---|---|---|
| Array#reverse | 284 | 260 | **kept** (8% FASTER) |
| Array#take | 156 | 148 | kept, improved |
| Array#drop | 150 | 140 | kept, improved |
| Array#uniq | 3649 | 5264 | re-reverted |
| Array#minmax | 167 | 253 | re-reverted |

uniq/minmax's remaining gap (~1.2-1.4ns/element) is the element load
being an out-of-line call vs C's inline `array_slot_load_decoded` in the
scan loops. Closing it needs an ebits-aware inline load (an
:array_get_inline variant that handles non-w64 receivers + bounds/wrap
semantics), or C-style locals kept out of alloca slots. Next lever.

## The blocking finding: fixed method-call overhead

Every failed port lost to the same tax: a dispatched Tungsten type-class
method costs **~13-15ns more per call** than a C IC handler, even when the
body compiles to the identical raw-i64 loop (verified with Integer#gcd:
raw-payload Euclid loop + bit-test dispatch guard still ran 41ns vs C's
28ns; the loop itself accounts for ~18ns in both). Per-element costs in
array loops (`self[i]` slot load + `out.push`) add another ~2-4ns/element
over C's direct `array_slot_load_decoded` loop.

Until that fixed overhead shrinks, only builtins with ≳100ns of real work
(take/drop/compact/dup-sized loops or bigger) can pass a 10% bar. Fixing
the overhead is the highest-leverage next step — it unblocks this whole
campaign AND speeds up every method call in the language. Suspects, in
order: `w_method_call_cached`'s arity-path arg copy (`WValue a[8]` +
arity switch), callee prologue (backtrace/`.wfm` bookkeeping, exception
frame setup), `TUNGSTEN_FREE` accounting, return boxing.

Working (already-optimized) bodies for the reverted methods are preserved
in git history on this file's introduction commit — see the diff that
accompanies it — and in the discussion notes below. Re-land them once the
call overhead is fixed; goldens and benches here are ready.

### Reverted bodies (reference copies)

`Integer#gcd` (raw small-int fast path; receiver of class Integer is always
a NaN-boxed immediate, BigInt dispatches its own class):

```
  -> gcd(other)
    if ((wvalue_bits(other) >> 48) & 0xFFFF) == 0xFFFA
      a = ($value & 0xFFFFFFFFFFFF) ## i64
      if (a & 0x800000000000) != 0
        a -= 281_474_976_710_656
      if a < 0
        a = 0 - a
      b = (wvalue_bits(other) & 0xFFFFFFFFFFFF) ## i64
      if (b & 0x800000000000) != 0
        b -= 281_474_976_710_656
      if b < 0
        b = 0 - b
      while b > 0
        t = b
        b = a % b
        a = t
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      return wvalue_from_bits((tag | a) ## i64)
    ga = self < 0 ? 0 - self : self
    gb = other < 0 ? 0 - other : other
    while gb > 0
      gt = gb
      gb = ga % gb
      ga = gt
    ga

  -> lcm(other)
    return 0 if self == 0 || other == 0
    r = (self / gcd(other)) * other
    r < 0 ? 0 - r : r
```

`String#swapcase` / `#capitalize` (byte-view pattern per core/base64.w;
`w_string_bytes_view` was added to runtime.c for this and stays exported).
Extra cost vs C is one buffer copy: C's handler `w_string_take`s its malloc'd
buffer, while `w_string_from_byte_array` copies. A `w_string_take_byte_array`
(buffer-stealing) primitive would close most of the 15ns gap:

```
  -> swapcase
    sc_src = ccall("w_string_bytes_view", self) ## u8[]
    sc_n = sc_src.size ## i64
    sc_out = u8[sc_n]
    sc_src_ptr = ccall_nobox("w_u8_live_data_ptr", sc_src) ## i64
    sc_out_ptr = ccall_nobox("w_u8_live_data_ptr", sc_out) ## i64
    sc_i = 0 ## i64
    while sc_i < sc_n
      sc_b = raw_load_u8(sc_src_ptr, sc_i) ## i64
      if sc_b >= 97 && sc_b <= 122
        sc_b -= 32
      elsif sc_b >= 65 && sc_b <= 90
        sc_b += 32
      raw_store_u8(sc_out_ptr, sc_i, sc_b)
      sc_i += 1
    ccall("w_string_from_byte_array", sc_out)
```

(capitalize: same loop with `if sc_i == 0 && lower -> upper;
elsif sc_i > 0 && upper -> lower`.)

`Array#reverse` / `#uniq` / `#minmax`: straight ports of the C loops
(descending push loop; quadratic `==` seen-scan; `[nil, nil]` on empty +
`<`/`>` sweep). Per-element `self[i]`/`push` overhead ~2× the C handler on
64-element receivers. Need cheaper compiled element access (or a typed
`self` fast path in class-body loops) before re-landing.

## File gotchas learned this round

- **Live vs scaffold class files**: `core/string.w` and `core/numeric/int.w`
  are inert design scaffolds — bodies there never dispatch. The live files
  are `core/string_native.w` (String, 0xF9) and `core/integer.w` (Integer,
  0xFA). `core/array.w` is live.
- `.wfm` function-metadata names are content-hash deduped (`__wy_*`), so
  identical bodies (e.g. `succ`/`next`) share one entry — don't diagnose
  method registration from `.wfm` strings alone.
- `--ast` parses fresh source, but a program only sees an autoloaded class
  if a trigger fires (recipe step 3). Test ports with a compiled program
  that calls ONLY the ported method.
