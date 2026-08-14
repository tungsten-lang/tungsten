# WValue Bit Layouts

Quick reference for the NaN-boxed `uint64_t` encoding. See
`doc/specification/wvalue_encoding.md` for the full specification.

Reference implementation: `stages/tungsten/runtime/wvalue.h` (standalone C header, MIT licensed).

---

## Value Space (ordered low to high)

```
0x0000_0000_0000_0000                       nil
0x0000_0000_0000_0001                       false
0x0000_0000_0000_0002                       true
0x0000_0000_0000_0003                       undef
0x0000_0000_0000_0004                       memo miss (internal)
0x0000_0000_0000_00x0+                      heap objects (16-byte aligned ptr | 4-bit sub-tag)
0x0001_0000_0000_0000 .. 0xFFF1_0000_0000_0000  biased IEEE 754 doubles
0xFFF1_(payload > 0)                        reserved (payload 0 = biased -inf)
0xFFF2_xxxx_xxxx_xxxx                       simd2d  (Vec2f, Point2D, Vec2i — half2/short2 w/ subtags)
0xFFF3_xxxx_xxxx_xxxx                       simd3d  (Vec3f — half3 48-bit layout)
0xFFF4_xxxx_xxxx_xxxx                       array (WArray*, 16-byte aligned;
                                            bit 47 + low nibble reserved flags)
0xFFF5                                      free tag slot (v4)
0xFFF6_xxxx_xxxx_xxxx                       sockaddr (32-bit IPv4 + 16-bit Port endpoint)
0xFFF7                                      free tag slot (v4)
0xFFF8_xxxx_xxxx_xxxx                       instant (Unix ms since epoch)
0xFFF9_xxxx_xxxx_xxxx                       string / symbol (SSO-5)
0xFFFA_xxxx_xxxx_xxxx                       int     (i48)
0xFFFB_xxxx_xxxx_xxxx                       bigint (WBigint*, 47-bit pointer;
                                            bit 47 reserved for tag-sign)
0xFFFC_xxxx_xxxx_xxxx                       lexical (token, lexchar, slice, char)
0xFFFD_xxxx_xxxx_xxxx                       numeric (decimal, currency, quantity)
0xFFFE_xxxx_xxxx_xxxx                       packed  (color, complex, rational, node, date, ipv4, body, location/range)
0xFFFF_xxxx_xxxx_xxxx                       duration
```

Truthiness: `v > 1` (unsigned). Only nil and false are falsey.

---

## Object Space (0x0000)

```
63              48 47                                    4 3     0
┌────────────────┬────────────────────────────────────────┬───────┐
│   0x0000       │   44-bit pointer (16-byte aligned)     │subtag │
└────────────────┴────────────────────────────────────────┴───────┘
```

Sub-tags: 0=generic 1=atomic 2=free(was bigint, now tag 0xFFFB) 4=struct
5=hash 6=closure 7=regex 8=range 9=small-array A=socket B=string-buffer C=class D=uuid
E=regex-match F=domain

## Array (0xFFF4)

```
63              48 47 46                                        4 3    0
+----------------+--+------------------------------------------+------+
|   0xFFF4       |F |     WArray* bits 46-4 (16-byte aligned)  |flags |
+----------------+--+------------------------------------------+------+
```

v5: Array left object space for its own top-level tag — `w_is_array` is
one tag compare, and the emitter's inline fast paths (get/set/guard)
drop the five-instruction object-space + subtag test for a single
`lshr 48; icmp eq 0xFFF4`. Bit 47 (`F`) and the low nibble are RESERVED
value-level flag bits (candidates: arena-vs-heap, small-vs-full —
boxing-time facts identical on every reference; per-object state like
frozen stays in the header flags byte). Pointer extraction:
`v & 0x0000_7FFF_FFFF_FFF0` (W_ARRAY_PTR_MASK). The dispatch key stays
the historical `0x0A` (w_dispatch_key maps the tag back), so inline
caches, g_type_class, and the compiler's type_dispatch_key are unchanged
— the BigInt v4 playbook. SmallArray (subtag 9), BigArray (generic
type 18), and packed Body (0xFFE6 facade) are unaffected.

Pointer extraction: `v & ~0xF`
Sub-tag extraction: `v & 0xF`

---

## Biased Double

```
 box:   biased = ieee754_bits + 0x0001_0000_0000_0000
 unbox: ieee754_bits = biased - 0x0001_0000_0000_0000

 All NaN variants normalized to canonical qNaN before biasing.
 Biased NaN = 0x7FF9_0000_0000_0000.

 The ceiling is EXACT (v4): canonicalization makes -inf
 (0xFFF0_0000_0000_0000) the largest boxable raw pattern, so biased
 doubles end at 0xFFF1_0000_0000_0000 and the seven prefixes above it
 (0xFFF2..0xFFF8) are tag space. Check: (v - bias) <= 0xFFF0_0000_0000_0000.
```

---

## SIMD 2D Vectors & Points (0xFFF2)

```
63              48 47    44 43              32 31              16 15               0
┌────────────────┬─────────┬──────────────────┬──────────────────┬──────────────────┐
│     0xFFF2     │ Sub-Tag │   Unused (0x0)   │  y (half/short)  │  x (half/short)  │
└────────────────┴─────────┴──────────────────┴──────────────────┴──────────────────┘

Sub-tags (bits 47..44):
  0x0: Vec2f    (two 16-bit IEEE half floats x, y — maps directly to Metal half2)
  0x2: Point2D  (two 16-bit IEEE half coordinates x, y with point geometry semantics)
  0x3: Vec2i    (two 16-bit signed integers x, y — maps directly to Metal short2)
```

---

## SIMD 3D Vector (0xFFF3)

```
63              48 47              32 31              16 15               0
┌────────────────┬──────────────────┬──────────────────┬──────────────────┐
│     0xFFF3     │  z (metal::half) │  y (metal::half) │  x (metal::half) │
└────────────────┴──────────────────┴──────────────────┴──────────────────┘

Dedicated 48-bit payload: three 16-bit IEEE half floats (x, y, z).
Maps 1:1 with Metal shading language `half3` and `simd_half3`.
```

---

## Network Socket Endpoint / SockAddr (0xFFF6)

```
63              48 47              32 31                             0
┌────────────────┬──────────────────┬────────────────────────────────┐
│     0xFFF6     │  port (16 bits)  │      IPv4 Address (32 bits)    │
└────────────────┴──────────────────┴────────────────────────────────┘

Dedicated 48-bit payload: 16-bit TCP/UDP port number (0..65535) + 32-bit IPv4 address (A.B.C.D).
Maps bit-for-bit with POSIX `sockaddr_in` (sin_port | sin_addr.s_addr).
Frees subtype 100 in Packed types (0xFFFE).
```

---

## BigInt (0xFFFB)

```
63              48 47 46                                            0
+----------------+--+-----------------------------------------------+
|   0xFFFB       |S |      47-bit WBigint* (16-byte aligned)        |
+----------------+--+-----------------------------------------------+
```

BigInt rides its own top-level tag (0xFFFB) adjacent to Int (0xFFFA), allowing
a single 15-bit mask to test `w_is_integer_any` branchlessly. Bit 47
(`S`) is the ACTIVE tag-sign overlay: the value's effective sign is the
header sign XOR `S`, so `-x` and `abs` hand out the SAME buffer with `S`
flipped — O(1), zero allocation, at every width. Every sign read from a
boxed value goes through `w_bigint_view` (header alone is not the sign);
magnitude reads are overlay-independent. The buffer's `shared` byte counts
outstanding tag aliases so the recycler frees it exactly when the last
reference dies. A tag-flipped value is a linked view: `y = -x` then
`x.neg!` moves both consistently (the documented bang-sharing caveat).
Pointer extraction: `v & 0x0000_7FFF_FFFF_FFFF`. The dispatch key stays
the historical `0x02`, so inline caches and the type-class tables are
unchanged by the encoding move.

---

## String / Symbol (0xFFF9)

```
Inline string (len 0-5):
63              48 47    44 43         4 3  1  0
┌────────────────┬────────┬────────────┬─────┬──┐
│   0xFFF9       │ 0 pad  │ char data  │ len │0 │  ← string
└────────────────┴────────┴────────────┴─────┴──┘

Heap string (len > 5):
63              48 47                       4 3  1  0
┌────────────────┬────────────────────────────┬─────┬──┐
│   0xFFF9       │ WString* (16-byte aligned) │  7  │0 │  ← heap sentinel
└────────────────┴────────────────────────────┴─────┴──┘

Symbol:
63              48 47                                  1  0
┌────────────────┬─────────────────────────────────────┬──┐
│   0xFFF9       │          47-bit symbol ID            │1 │
└────────────────┴─────────────────────────────────────┴──┘
```

---

## Int (0xFFFA)

```
63              48 47                                            0
┌────────────────┬────────────────────────────────────────────────┐
│   0xFFFA       │       48-bit signed integer (two's complement) │
└────────────────┴────────────────────────────────────────────────┘

Range: ±140,737,488,355,328 (±2^47)
Unbox: ((int64_t)(v << 16)) >> 16
```

This tag is the inline representation of `Int`, Tungsten's exact,
auto-promoting integer implementation. `Integer` is its generic,
representation-independent parent; overflow continues as heap `BigInt`.

---

## Instant (0xFFF8)

```
63              48 47                                            0
┌────────────────┬────────────────────────────────────────────────┐
│   0xFFF8       │   48-bit signed milliseconds from Unix epoch   │
└────────────────┴────────────────────────────────────────────────┘

Range: ~2491 BC to ~6431 AD, 1ms precision, always UTC.
```

---

## Lexical + Char (0xFFFC)

Four subtypes via bits 47-46:

### Token (subtype 00)

```
63        48 47 46 45     40 39       32 31         20 19              0
┌──────────┬─────┬─────────┬───────────┬─────────────┬─────────────────┐
│  0xFFFC  │ 0 0 │ flags   │ tok type  │  length     │   byte offset   │
│          │     │  6b     │   8b      │   12b       │     20b         │
└──────────┴─────┴─────────┴───────────┴─────────────┴─────────────────┘

256 token kinds. Max 4,095 byte tokens. Max 1 MB source files.
Offset at LSB for cheapest extraction.
```

### LexChar (subtype 01)

```
63        48 47 46 45   39 38          18 17 16 15    11 10    7 6      0
┌──────────┬─────┬───────┬──────────────┬─────┬────────┬───────┬────────┐
│  0xFFFC  │ 0 1 │ free  │  codepoint   │utf8 │  cat   │ digit │lex_flg │
│          │     │  7b   │    21b       │ 2b  │  5b    │  4b   │  7b    │
└──────────┴─────┴───────┴──────────────┴─────┴────────┴───────┴────────┘

Lex flags at LSB (bit-testable, no shift):
  bit 0: may_combine    bit 1: is_quote       bit 2: is_operator
  bit 3: is_hex         bit 4: is_whitespace  bit 5: is_id_continue
  bit 6: is_id_start
```

### Slice (subtype 10)

```
63        48 47 46 45      38 37          24 23                       0
┌──────────┬─────┬──────────┬──────────────┬──────────────────────────┐
│  0xFFFC  │ 1 0 │  free    │   length     │      byte offset         │
│          │     │   8b     │    14b       │        24b               │
└──────────┴─────┴──────────┴──────────────┴──────────────────────────┘

Max 16,383 byte slices. Max 16 MB buffers.
Zero-copy reference into goroutine-local buffer.
```

### Char (subtype 11)

```
63        48 47 46 45 44 43 42    39 38          30 29 28 27   23 22 21 20       0
┌──────────┬─────┬──┬──┬──┬────────┬──────────────┬─────┬───────┬─────┬──────────┐
│  0xFFFC  │ 1 1 │Em│As│Pr│ digit  │  case_delta  │width│  cat  │utf8 │codepoint │
│          │     │1b│1b│1b│  4b    │    9b (±255) │ 2b  │  5b   │ 2b  │   21b    │
└──────────┴─────┴──┴──┴──┴────────┴──────────────┴─────┴───────┴─────┴──────────┘

Codepoint at LSB: (v & 0x7F) extracts ASCII directly.
Width: 0=zero 1=narrow 2=wide 3=ambiguous
Category: 0-4=Letter 5-7=Number 8-10=Separator 11-13=Mark 14-20=Punct 21-24=Symbol 25-29=Other
```

---

## Numeric (0xFFFD)

Three subtypes via bits 47-46:

### Decimal (subtype 00)

```
63              48 47 46 45                         7 6               0
┌────────────────┬─────┬──────────────────────────────┬───────────────┐
│   0xFFFD       │ 0 0 │  39-bit signed significand   │ 7-bit signed  │
│                │     │  ±274,877,906,943            │ scale (-64…63)│
└────────────────┴─────┴──────────────────────────────┴───────────────┘

value = sig × 10^scale
```

### Currency (subtype 01)

```
63              48 47 46 45    42 41                     5 4        0
┌────────────────┬─────┬────────┬──────────────────────────┬────────┐
│   0xFFFD       │ 0 1 │sym_id  │  37-bit signed sig       │ 5-bit  │
│                │     │  4b    │  ±68,719,476,735         │ scale  │
└────────────────┴─────┴────────┴──────────────────────────┴────────┘

sym_id: 0=$  1=€  2=£  3=¥  4=₹  5=¥(CNY)  6=₩  7=₿
        8=Fr 9=C$ 10=A$ 11=R$ 12=₽ 13=฿ 14=zł 15=reserved
```

### Quantity (subtype 11)

```
63              48 47 46 45         38 37                 7 6        0
┌────────────────┬─────┬─────────────┬──────────────────────┬────────┐
│   0xFFFD       │ 1 1 │  unit_id    │ 31-bit signed sig    │ 7-bit  │
│                │     │    8b       │ ±1,073,741,823       │ scale  │
└────────────────┴─────┴─────────────┴──────────────────────┴────────┘

unit_id: 0-118 built-in units, 119-253 custom, 254 reserved, 255=percent
Percentage: sig=765, scale=-2, unit_id=0xFF → "7.65%"
```

---

## Packed Types (0xFFFE)

Six subtypes via bits 47-45:

### Color (subtype 000)

```
63        48 47  45 44      37 36      29 28      21 20     13 12       0
┌──────────┬──────┬──────────┬──────────┬──────────┬─────────┬──────────┐
│  0xFFFE  │ 000  │   red    │  green   │   blue   │  alpha  │  flags   │
│          │      │   8b     │   8b     │   8b     │   8b    │   12b    │
└──────────┴──────┴──────────┴──────────┴──────────┴─────────┴──────────┘
```

### Complex (subtype 001)

```
63        48 47  45 44          29 28    23 22            7 6         1
┌──────────┬──────┬──────────────┬────────┬───────────────┬───────────┐
│  0xFFFE  │ 001  │ real sig     │ r.scl  │  imag sig     │  i.scl    │
│          │      │  16b (±32K)  │  6b    │  16b (±32K)   │   6b      │
└──────────┴──────┴──────────────┴────────┴───────────────┴───────────┘
```

### Rational (subtype 010)

```
63        48 47  45 44                  20 19                        0
┌──────────┬──────┬──────────────────────┬────────────────────────────┐
│  0xFFFE  │ 010  │ numerator (signed)   │  denominator (unsigned)    │
│          │      │    25b (±16,777,215) │    20b (1…1,048,575)       │
└──────────┴──────┴──────────────────────┴────────────────────────────┘
```

### DateTime (subtype 100)

```
63        48 47 45 44     33 32 29 28 24 23 19 18  13 12   7 6      1
┌──────────┬─────┬─────────┬─────┬─────┬─────┬──────┬──────┬────────┐
│  0xFFFE  │ 100 │  year   │ mon │ day │hour │ min  │ sec  │  tz    │
│          │     │ 12b(±2K)│ 4b  │ 5b  │ 5b  │  6b  │  6b  │ 6b(±31)│
└──────────┴─────┴─────────┴─────┴─────┴─────┴──────┴──────┴────────┘

tz = half-hours from UTC (e.g., +5:30 = 11, -8:00 = -16)
```

### IPv4 (subtype 101)

```
63        48 47  45 44                          13 12      7 6      1
┌──────────┬──────┬──────────────────────────────┬─────────┬────────┐
│  0xFFFE  │ 101  │    32-bit IPv4 address       │  CIDR   │ flags  │
│          │      │    (network byte order)      │   6b    │  6b    │
└──────────┴──────┴──────────────────────────────┴─────────┴────────┘
```

### Location (subtype 111)

Mode is a 2-bit field at bits 44:43 (bit 44 sat unused above the
original 1-bit mode in every existing value — Point and File payloads
both top out at 43 bits — so folding it into the mode field is a
purely additive change; both legacy encodings keep their exact old bit
patterns).

```
Point mode (bits 44:43 = 00):
63        48 47 45 44 43 42                 22 21                     0
┌──────────┬─────┬──┬──┬──────────────────────┬───────────────────────┐
│  0xFFFE  │ 111 │0 │0 │  x (21b, signed)     │  y (22b, signed)      │
└──────────┴─────┴──┴──┴──────────────────────┴───────────────────────┘

File mode (bits 44:43 = 01):
63        48 47 45 44 43 42          29 28             11 10         0
┌──────────┬─────┬──┬──┬──────────────┬─────────────────┬────────────┐
│  0xFFFE  │ 111 │0 │1 │  file_id     │    line         │   col      │
│          │     │  │  │   14b        │    18b          │   11b      │
└──────────┴─────┴──┴──┴──────────────┴─────────────────┴────────────┘

File mode covers: 16,384 files, 262,143 lines, 2,047 columns.

FileOffset mode (bits 44:43 = 10):
63        48 47 45 44 43 42          29 28                          0
┌──────────┬─────┬──┬──┬──────────────┬───────────────────────────┐
│  0xFFFE  │ 111 │1 │0 │  file_id     │   byte offset             │
│          │     │  │  │   14b        │       29b                │
└──────────┴─────┴──┴──┴──────────────┴───────────────────────────┘

FileOffset covers: 16,384 files, 512 MiB byte offset per file. A
single point (like Point/File); an AST span is a pair of these in the
node's :loc/:loc_end slots. Line/col for error display are NOT stored
here — reconstructed lazily from a per-file newline-offset table built
once and binary-searched, avoiding the 18-bit line / 11-bit col
ceiling that File mode has on generated or minified sources.

Range mode (bits 44:43 = 11) — immediate integer Range, NOT a
Location (w_is_location excludes mode 11). A sub-mode bit at 42
splits the payload; the exclusive bit sits at LSB in both:

Loop shape (bit 42 = 0):
63        48 47 45 44 43 42 41 40                                  1  0
┌──────────┬─────┬──┬──┬──┬──┬──────────────────────────────────────┬──┐
│  0xFFFE  │ 111 │1 │1 │0 │s │      end (40b, unsigned)             │ex│
└──────────┴─────┴──┴──┴──┴──┴──────────────────────────────────────┴──┘

s = start (0 or 1). Covers 0..n and 1..n for n < 2^40 — the dominant
loop/iteration shape.

Span shape (bit 42 = 1):
63        48 47 45 44 43 42 41              22 21                  1  0
┌──────────┬─────┬──┬──┬──┬──────────────────┬──────────────────────┬──┐
│  0xFFFE  │ 111 │1 │1 │1 │ start (20b, sgn) │   end (21b, signed)  │ex│
└──────────┴─────┴──┴──┴──┴──────────────────┴──────────────────────┴──┘

Covers a..b with start in ±2^19, end in ±2^20 — small literals and
slices, including negative-index slices (0..-1) and empty ranges
(5..2, iterates zero times).

Construction goes through the w_range_imm_try funnel: packed value
when the range fits (loop shape tried first), W_NIL when it must fall
back to the heap Range (subtag 8) — same inline/heap discipline as
Int→BigInt. Heap keeps: other starts, end ≥ 2^40, stepped ranges
(a..b/n), BigInt bounds.
>>>>>>> Stashed changes
```

---

## Duration (0xFFFF)

### Mode 0 — Nanoseconds (bit 47 = 0)

```
63              48 47 46                                             0
┌────────────────┬──┬─────────────────────────────────────────────────┐
│   0xFFFF       │0 │     47-bit signed nanoseconds                   │
│                │  │     ±70,368,744,177,663 (≈ ±19.5 hours)         │
└────────────────┴──┴─────────────────────────────────────────────────┘
```

### Mode 1 — Months + Milliseconds (bit 47 = 1)

```
63              48 47 46             32 31                            0
┌────────────────┬──┬──────────────────┬───────────────────────────────┐
│   0xFFFF       │1 │ 15-bit signed    │  32-bit unsigned              │
│                │  │ months (±16,383) │  milliseconds (≤4,294,967,295)│
└────────────────┴──┴──────────────────┴───────────────────────────────┘

Months: ±1,365 years.  Milliseconds: ≈49.7 days (covers any calendar month).
```

---

## Heap Overflow — Domain Objects (sub-tag 0xF)

When domain type values exceed NaN-box capacity, they promote to a 32-byte
heap struct stored with sub-tag 0xF:

```c
typedef struct {
    uint8_t domain_type;   // 0=decimal 1=currency 2=quantity 3=duration
    uint8_t pad[7];
    int64_t sig;           // full 64-bit significand
    int32_t scale;
    int32_t extra;         // symbol_id / unit_id / duration mode
    int64_t extra2;        // duration mode 1: ms
} WDomainHeap;             // 32 bytes, 16-byte aligned
```

Arithmetic operations dispatch transparently through both inline and heap paths.

---

## Instruction Counts

| Operation         | x86-64   | ARM64   | Method                              |
| ----------------- | :------: | :-----: | ------------------------------------|
| Truthiness        | 1        | 1       | `cmp v, 1` (unsigned >)             |
| Nil check         | 1        | 1       | `test v, v` (== 0)                  |
| Type check (tag)  | 2        | 2       | `shr 48` + `cmp`                    |
| Box int           | 2        | 2       | `and mask` + `or tag`               |
| Unbox int         | 2        | 1       | `shl 16` + `sar 16` (ARM64: `sbfx`) |
| Box double        | 1        | 1       | `add bias`                          |
| Unbox double      | 1        | 1       | `sub bias`                          |
| Unbox codepoint   | 1        | 1       | `and 0x1FFFFF` (Char LSB)           |
| Char category     | 2        | 2       | `shr 23` + `and 0x1F`               |
| Pointer extract   | 1        | 1       | `and ~0xF`                          |
| Sub-tag extract   | 1        | 1       | `and 0xF`                           |
| Pass/return value | 1 reg    | 1 reg   | single register (rdi / x0)          |
| Array element     | 8 B      | 8 B     | vs 16 B for tagged union            |

---

## Usage Notes

**Normalization.** Decimal, currency, and quantity constructors MUST normalize
the significand by stripping trailing zeros (dividing sig by 10 and
incrementing scale while `sig % 10 == 0 && sig != 0`). This ensures that
`1.20` and `1.2` produce the same bit pattern.

**Currency arithmetic.** Adding currencies with mismatched symbol IDs is a
runtime error. Multiplying currency by a scalar (int or decimal) is supported.

**Quantity arithmetic.** Adding quantities with mismatched unit IDs is a
runtime error (dimension mismatch). Custom units are registered at runtime
via `w_register_unit(int id, const char *name)` for IDs 119-253.

**Duration cross-mode.** Adding a mode 0 (ns) duration to a mode 1 (months+ms)
duration converts the ns value to ms (truncating sub-ms precision) and adds
to the ms component. Subtracting mixed-mode durations is an error.

**Slice lifetime.** Slices borrow from an immutable buffer (source file or
request body). They MUST be promoted to a string (SSO-5 or heap WString)
before the buffer is freed.

**Heap strings.** `WString` is `{ uint32_t len; char data[]; }` — a
length-prefixed, null-terminated, flexible array member. The inline SSO-5
encoding covers strings up to 5 bytes; anything longer allocates a WString.
Strings are immutable.
