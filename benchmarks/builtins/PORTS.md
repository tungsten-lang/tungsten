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

## Round 4 results (2026-07-18) — campaign targets complete

Two inline-fast-path families landed (1334067), emitted as private
alwaysinline IR helpers per module: raw-index array reads (round 3's
call twins now fold into call sites) and int-int comparisons (op map
routes eq/neq/lt/gt/lte/gte through guards; non-int pairs still call the
runtime ladder). Profiling minmax had shown w_lt+w_gt at 60% of runtime;
the C handlers' only edge was clang intra-TU inlining of
w_value_compare.

Final scoreboard — every kept port now BEATS its retired C handler:

| method | C ns/op | Tungsten ns/op | delta |
|---|---|---|---|
| Array#take | 156 | 122 | -22% |
| Array#drop | 150 | 123 | -18% |
| Array#reverse | 284 | 237 | -16% |
| Array#uniq | 3649 | 2381 | -35% |
| Array#minmax | 167 | 114 | -32% |
| Integer#gcd | 28.1 | 27.2 | parity |
| Integer#lcm | 23.9 | 10.0 | -58% |

Still open: String#capitalize/swapcase (buffer-steal primitive), and the
wider IC catalog (string split/replace/include?/chars/reverse, int
chr/to_s(base), hash merge!/each). The compare + array fast paths are
global codegen wins — re-baseline any future port measurements.

## Round 5 results (2026-07-18) — original 9-method slate complete

String#swapcase/#capitalize landed at parity (603a632): inline-mode
receivers (<= 5 bytes) transform in registers on $value with ZERO
allocations (C malloc'd even for "a"); slab/heap receivers walk raw bytes
(new `w_string_data_ptr`) into one u8[len+1] buffer stolen by the result
via `w_string_take_byte_array` (no-copy twin of w_string_from_byte_array).
swapcase 24.2ns vs C 25.4 (-4%); capitalize 24.9 vs 24.6 (+1%).

Two reusable primitives now exist for any byte-producing string port:
`w_string_data_ptr` (raw read pointer, modes 6-7) and
`w_string_take_byte_array(bytes, len)` (buffer steal, u8[len+1] contract).
New-primitive checklist grew one entry: the INTERPRETER's ccall /
ccall_nobox allowlists (compiler/lib/interpreter.w ~1200/~1350) must gain
every new name, or -e/eval dies with "Unsupported ccall" while compiled
code works.

All nine round-1 targets are now Tungsten. Next candidates from the
original catalog: String#include?/starts_with/ends_with (strstr/strncmp
one-liners — port likely loses to SIMD strstr on long strings; measure),
String#chars/reverse (UTF-8 walks), Integer#chr (UTF-8 encode, buildable
on the inline-string bit pattern), Int#to_s(base), Hash#merge!/each.

## Round 6 results (2026-07-18) — Integer#chr / #to_s / #to_s(base)

First entries from the wider IC catalog, all kept:

| method | C ns/op | Tungsten ns/op | delta |
|---|---|---|---|
| Integer#chr | 10.0 | 9.0 | -10% (inline UTF-8, zero alloc) |
| Integer#to_s | 146 | 137 | -6% (inline small; delegate tail) |
| Integer#to_s(base) | 46.5 | 48.5 | +4% (delegates digit loop) |

Pattern refined this round: **hybrid inline + C-tail delegation**. The
common case (small ints for to_s, all codepoints for chr) transforms in
registers on $value with no allocation; the rare/large tail delegates to
a boxed-in/boxed-out C wrapper (w_int_to_str_boxed etc.) via plain ccall,
matching the former handler's stack-buffer-then-intern cost exactly. This
beats both "all Tungsten" (a u8-buffer allocation the C path avoids) and
"all C" (loses the zero-alloc small-int win). Plain-ccall wrappers work
identically compiled/interpreted with no raw-marshaling — prefer them
over ccall_nobox when an arg or the return is a WValue.

## Round 7 results (2026-07-18) — Array#copy

| method | C ns/op | Tungsten ns/op | delta |
|---|---|---|---|
| Array#copy | 144 | 122 | -15% (raw-index loads) |

13 builtins ported, all at-or-faster than C. Compiler-perf side this
session added a 3-part string hash/eq sweep (~10% on lowering.w); one
attempt (== identity short-circuit in __w_eq_fast) was a verified
negative — the compiler's symbol == is usually false, so it only added a
failed compare before w_eq. Reverted; recorded so it isn't re-tried.

## Round 8 results (2026-07-18) — Array#delete_at + write fast path

| method | C ns/op | Tungsten ns/op | delta |
|---|---|---|---|
| Array#delete_at | 48.5 | 31.4 | -35% |

delete_at first lost 70% (82ns): self[i]=v fell through to generic method
dispatch. Fixed by adding the WRITE twin of the raw-index array reads —
the self-ref []= path now direct-calls w_array_set / w_array_set_i64
(raw index) instead of dispatching. That flipped it to a 35% win and
speeds every in-Array-body mutation. Pattern confirmed: an in-class op
that both reads AND writes self[i] needs both raw twins to beat C.

14 builtins ported, all at-or-faster than C.

## Round 10 (2026-07-18) — String#reverse (a "ruled out" candidate, cracked)

Round 9 shelved String#reverse as a UTF-8 walk. Cracked it with the
hybrid inline+C-tail shape: inline receivers (<=5 bytes) reverse
codepoints in $value bits (zero alloc, 13.5ns vs C 27ns, -50%); slab/heap
delegate to the exported w_string_reverse (one malloc + intern) because a
Tungsten u8[] port adds a WArray-header alloc per call (+18% on long
strings). Long case 118ns vs 127ns (-7%). 16 builtins ported now.

Lesson: building a u8[] to steal costs a WArray HEADER allocation on top
of the buffer — fine when it replaces the C handler's own allocation
(swapcase/capitalize/to_s tail), but a net add when C reversed in place
on a bare malloc. For those, delegate the tail to a factored-out C
helper and keep only the zero-alloc inline path in Tungsten.

## Round 11 (2026-07-18) — String#chars (another shelved candidate, cracked)

Round 9 shelved String#chars as "array of allocations". Cracked it: each
element codepoint is <= 4 bytes, so build each single-char String inline
in $value bits (zero per-char heap alloc) rather than w_string-per-char.
Source via one w_string_bytes_view. 65ns vs C 88ns (-26%). 17 builtins
ported. (Gotcha: w_string_bytes_view had to be added to the interpreter
ccall allowlist — it was reachable only via the base64 wrapper before, so
the compiled path worked but -e/eval raised "Unsupported ccall".)

## Round 9 (2026-07-18) — remaining candidates surveyed, ruled out

Went looking for the next clean port; each remaining C handler was
verified NOT a >10%-safe win, with the reason:

- Array#fill — C hoists the element encode out of the loop and splats /
  memsets; a per-element Tungsten write can't match.
- Array#include?/index/count — SIMD-backed (w_u64_scan_eq / w_u1_index /
  byte_scan_threaded); a w_eq loop loses.
- Array#clear — sets header start/size=0; no Tungsten truncate primitive.
- Array#unshift / push / pop / shift — deque/storage header ops.
- Array#sort — mergesort, already partly Tungsten (array_mergesort).
- String#include?/starts_with/ends_with — strstr/strncmp; likely lose to
  SIMD strstr on long inputs.
- String#reverse / chars / split — UTF-8 boundary walks + allocation.
- String#center/ljust/rjust — NOT C builtins; undefined even in interp
  (string.w scaffold unwired). Adding them is a feature, not a port.
- Hash#merge! / each — need slot iteration; a closure-per-entry Tungsten
  version loses to C's direct slot loop.

Compiler side: w_eq is the standing #1 hot leaf but is now high-volume-
cheap after the canonical/mode fast paths — growing the alwaysinline
__w_eq_fast to catch it regressed (icache/codesize; see the negative
result below), and reordering the out-of-line w_eq is discouraged by its
own comment. type()/hash/array-access hot spots are handled. Session net:
15 builtins ported (all >= C), lowering.w compile ~3.65s -> ~3.14s.

## Round 12 (2026-07-18) — incremental autoload walk (biggest compiler win)

autoload_pass re-walked the whole growing AST every fixpoint iteration;
collect_autoload_refs was the #1 hot compiler fn (~7%). Now deep-walks
only newly-appended expressions each iteration. Proven safe by
byte-identical --ll across 4 compiler modules + stage1==stage2 + specs.
lowering.w --ll -8%; full compiler build -13% (~14.5s -> 12.6s).

Session tally: 17 builtins ported (all >= C) + 8 compiler speedups.
lowering.w --ll from ~3.65s at session start to ~2.88s (~21% total).

## Round 13 (2026-07-18) — String#bytes (+ confirmed compiler is well-optimized)

Profiled the WHOLE-compiler compile (~11.9s, a much better window than
lowering.w's 2.9s): autoload walker gone (round-12 win holds), remaining
main-thread cost is fundamental (w_eq, hash lookups, dispatch, strbuf
growth memmove) and near-optimal — strbuf grows 2x already. The compiler
is in good shape (~21% faster than session start).

Ported String#bytes: inline receivers read bytes from $value (no view
alloc), slab/heap via data-ptr. First cut used a uniform u8[] view and
lost ~20% to the WArray-header alloc; the split flipped it to ~56ns vs C
~62ns (-10%). 18 builtins ported, all >= C.

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
