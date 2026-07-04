# WValue Encoding Specification

**Version:** 3.0
**Status:** Normative
**Version:** 2026.07.04

This document is the definitive specification for the WValue NaN-boxed value
encoding used in the Tungsten language runtime. Every dynamic value is
represented as a single `uint64_t`. The encoding is designed for languages
where only `nil` and `false` are falsy, and where inline integers, decimals,
domain-aware types, and packed structured values are more important than
pointer tag variety.

A conforming implementation MUST produce the exact bit patterns described below.
Any deviation is a bug.

The reference implementation is `wvalue.h` — a standalone, dependency-free C
header under the MIT license.

```c
typedef uint64_t WValue;
```

---

## Table of Contents

1. [Value Space Layout](#1-value-space-layout)
2. [Singletons and Object Space (0x0000)](#2-singletons-and-object-space-0x0000)
3. [Biased Doubles](#3-biased-doubles)
4. [String / Symbol (0xFFF9)](#4-string--symbol-0xfff9)
5. [Int (0xFFFA)](#5-int-0xfffa)
6. [Instant (0xFFFB)](#6-instant-0xfffb)
7. [Lexical + Char (0xFFFC)](#7-lexical--char-0xfffc)
8. [Numeric (0xFFFD)](#8-numeric-0xfffd)
9. [Packed Types (0xFFFE)](#9-packed-types-0xfffe)
10. [Duration (0xFFFF)](#10-duration-0xffff)
11. [Heap Overflow (Domain Objects)](#11-heap-overflow-domain-objects)
12. [Type Checking](#12-type-checking)
13. [Constants Reference](#13-constants-reference)
14. [Design Rationale](#14-design-rationale)

---

## 1. Value Space Layout

The full `uint64_t` range is partitioned into contiguous, non-overlapping
regions ordered from low to high:

```
 Hex range                                  Type
 ──────────────────────────────────────────────────────────────
 0x0000_0000_0000_0000                      nil       (singleton)
 0x0000_0000_0000_0001                      false     (singleton)
 0x0000_0000_0000_0002                      true      (singleton)
 0x0000_0000_0000_0003                      undef     (singleton)
 0x0000_0000_0000_0004                      memo miss (internal sentinel)
 0x0000_0000_0000_0005 - 0x0000_0000_0000_000F  reserved sentinels
 0x0000_0000_0000_00x0+                     heap objects (ptr | sub-tag)
 0x0001_0000_0000_0000 - 0xFFF8_FFFF_FFFF_FFFF  biased IEEE 754 doubles
 0xFFF9_xxxx_xxxx_xxxx                      string / symbol
 0xFFFA_xxxx_xxxx_xxxx                      int     (48-bit signed)
 0xFFFB_xxxx_xxxx_xxxx                      instant (48-bit signed Unix ms)
 0xFFFC_xxxx_xxxx_xxxx                      lexical (token, lexchar, slice, char)
 0xFFFD_xxxx_xxxx_xxxx                      numeric (decimal, currency, quantity)
 0xFFFE_xxxx_xxxx_xxxx                      packed  (color, complex, rational, date, ipv4, location)
 0xFFFF_xxxx_xxxx_xxxx                      duration (ns or months+ms)
 ──────────────────────────────────────────────────────────────
```

**Key invariant:** Every valid `WValue` falls into exactly one region. The
type-check functions are mutually exclusive and exhaustive.

---

## 2. Singletons and Object Space (0x0000)

Values with the top 16 bits equal to `0x0000` are either singletons (small
constants) or heap object pointers.

### 2.1 Singletons

| Constant | Value | Truthiness |
|----------|-------|------------|
| `nil` | `0x0000_0000_0000_0000` | Falsy |
| `false` | `0x0000_0000_0000_0001` | Falsy |
| `true` | `0x0000_0000_0000_0002` | Truthy |
| `undef` | `0x0000_0000_0000_0003` | Truthy (internal sentinel) |
| `memo_miss` | `0x0000_0000_0000_0004` | Truthy (memoization sentinel) |

`nil` is zero so that `calloc`-initialized memory defaults to `nil`.

**Truthiness** reduces to a single unsigned compare: `v > 1`.

### 2.2 Heap Objects

All heap-allocated objects use 16-byte-aligned pointers. The low 4 bits
(guaranteed zero by alignment) are repurposed as a sub-tag nibble:

| Nibble | Type | Description |
|--------|------|-------------|
| 0x0 (ptr=0) | nil | (singleton, not a pointer) |
| 0x0 (ptr≠0) | generic | type discriminator in struct header byte |
| 0x1 | false | (singleton, not a pointer) |
| 0x2 | true | (singleton, not a pointer) |
| 0x3 | undef | (singleton, not a pointer) |
| 0x4 | struct | user-defined class instance |
| 0x5 | hash | hash table |
| 0x6 | closure | function closure |
| 0x7 | regex | compiled regex |
| 0x8 | range | range object |
| 0x9 | module | module |
| 0xA | array | dynamic array |
| 0xB | bigint | arbitrary-precision integer |
| 0xC | class | class metaobject |
| 0xD | uuid | 128-bit UUID |
| 0xE | error | error object |
| 0xF | domain | heap-overflow domain type (see §11) |

**Boxing:** `(uint64_t)(uintptr_t)ptr | subtag`

**Pointer extraction:** `value & ~0xF`

**Sub-tag extraction:** `value & 0xF`

**Object check:** `v >= 0x10 && (v >> 48) == 0`

Generic objects (sub-tag 0x0) use a `uint8_t type` field in the struct header
to discriminate between thread, atomic, socket, channel, fiber, bytes, and
response objects.

---

## 3. Biased Doubles

IEEE 754 doubles are stored with a bias added to the raw bit pattern:

```
biased = raw_bits + 0x0001_0000_0000_0000
```

This shifts the entire double range above the object/singleton space and below
the tagged value space:

- **Minimum biased:** `0x0001_0000_0000_0000` (represents `+0.0`)
- **Maximum biased:** `0xFFF8_FFFF_FFFF_FFFF` (represents `-0.0` minus epsilon)
- **Biased NaN:** `0x7FF9_0000_0000_0000` (canonical quiet NaN)

**NaN canonicalization:** All NaN variants (signaling, quiet, with payloads)
MUST be normalized to canonical quiet NaN (`0x7FF8_0000_0000_0000`) before
biasing. NaN lives in double space; there is no separate NaN sentinel.

**Boxing:**
```c
uint64_t bits;
memcpy(&bits, &d, 8);
if ((bits & 0x7FF0000000000000) == 0x7FF0000000000000 &&
    (bits & 0x000FFFFFFFFFFFFF) != 0)
    bits = 0x7FF8000000000000;  // normalize NaN
return bits + 0x0001000000000000;
```

**Unboxing:**
```c
uint64_t bits = v - 0x0001000000000000;
double d;
memcpy(&d, &bits, 8);
```

**Type check:**
```c
(v - 0x0001000000000000) <= 0xFFF7FFFFFFFFFFFF
```

This is a single unsigned subtract + compare — no branch needed.

---

## 4. String / Symbol (0xFFF9)

Strings and symbols share the `0xFFF9` tag, distinguished by bit 0:

- **bit 0 = 0** → string
- **bit 0 = 1** → symbol (interned)

### 4.1 Inline Strings (SSO-5)

Strings of 0-5 bytes are stored inline with no heap allocation:

```
bits 47-44: 0 (padding)
bits 43-4:  up to 5 bytes of character data (byte 0 at bits 4-11)
bits 3-1:   length (0-5)
bit  0:     0 (string flag)
```

Mode value 6 is used for slab-backed interned strings and symbols. Mode value 7
indicates a heap string or symbol.

### 4.2 Slab Interned Strings (SSO-61)

Strings and symbols of 6-61 bytes can live in the permanent string slab. The
`WValue` stores only a 24-bit slab index:

```
bits 47-28: 0
bits 27-4:  slab index (24 bits)
bits 3-1:   6 (slab mode)
bit  0:     0 = string, 1 = symbol
```

The slab itself stores up to 29 bytes in one 32-byte slot or up to 61 bytes in
two contiguous slots:

- slot 0: `[flags][length][30 bytes of payload]`
- slot 1 when needed: `[32 bytes of payload]`

Single-slot strings are NUL-terminated by zero-fill. Two-slot strings use the
second slot entirely for the trailing payload bytes plus the NUL terminator.

### 4.3 Heap Strings

Strings longer than 61 bytes use a heap-allocated `WString`:

```c
typedef struct WString {
    uint32_t len;
    char data[];  // UTF-8, null-terminated
} WString;
```

The pointer is stored in bits 4-47 (16-byte aligned):

```
bits 47-4: WString* (masked with 0x0000_FFFF_FFFF_FFF0)
bits 3-1:  7 (heap sentinel)
bit  0:    0 (string flag)
```

### 4.4 Symbols

Symbols share the exact same mode encoding as strings; only bit 0 differs:

- mode 0-5: inline symbol (SSO-5)
- mode 6: slab-backed interned symbol (24-bit slab index)
- mode 7: heap symbol

---

## 5. Int (0xFFFA)

48-bit signed two's complement integer.

```
bits 63-48: 0xFFFA (tag)
bits 47-0:  signed integer value
```

**Range:** -140,737,488,355,328 to +140,737,488,355,327 (±2^47)

**Boxing:** `0xFFFA000000000000 | (value & 0x0000FFFFFFFFFFFF)`

**Unboxing (sign extension):** `((int64_t)(v << 16)) >> 16`

On ARM64 this compiles to a single `sbfx` instruction.

Values exceeding this range overflow to heap BigInt objects (sub-tag 0xB).

---

## 6. Instant (0xFFFB)

48-bit signed milliseconds from the Unix epoch (1970-01-01T00:00:00Z).

```
bits 63-48: 0xFFFB (tag)
bits 47-0:  signed milliseconds
```

**Range:** approximately 2491 BC to 6431 AD at millisecond precision.

Boxing and unboxing follow the same pattern as Int.

---

## 7. Lexical + Char (0xFFFC)

The `0xFFFC` tag holds four subtypes via a 2-bit discriminator in bits 47-46.
Two subtypes are for compilation pipeline use (Token, LexChar), one for
zero-copy buffer references (Slice), and one for runtime character values (Char).

### 7.1 Token (subtype 00)

Zero-allocation token descriptor indexing into a `LexBuffer`:

```
bits 47-46: 00 (subtype)
bits 45-40: flags (6 bits)
bits 39-32: token type (8 bits, 256 kinds)
bits 31-20: length (12 bits, max 4,095 bytes)
bits 19-0:  byte offset (20 bits, max 1,048,575 = 1 MB)
```

Offset is at the LSB for cheapest extraction (most performance-critical field).
`value & 0xFFFFFFFF` extracts offset+length in a single 32-bit mask.

### 7.2 LexChar (subtype 01)

Lexer-optimized character with hot-path classification flags at LSB:

```
bits 47-46: 01 (subtype)
bits 45-39: free (7 bits)
bits 38-18: codepoint (21 bits, U+0 to U+10FFFF)
bits 17-16: utf8_len - 1 (2 bits, encoding 1-4)
bits 15-11: Unicode category (5 bits, 30 categories)
bits 10-7:  digit_value (4 bits, 0-9 or 0xF=not-a-digit)
bits 6-0:   lex_flags (7 bits)
```

**Lex flags** (bit-testable at LSB, no shift required):

| Bit | Flag | Description |
|-----|------|-------------|
| 0 | may_combine | Next codepoint may modify this one (combining marks, ZWJ) |
| 1 | is_quote | Quote character (`'`, `"`, `` ` ``) |
| 2 | is_operator | Operator character |
| 3 | is_hex | Valid hex digit (0-9, a-f, A-F) |
| 4 | is_whitespace | Space, tab, NBSP, Unicode Zs |
| 5 | is_id_continue | Valid identifier continuation |
| 6 | is_id_start | Valid identifier start |

### 7.3 Slice (subtype 10)

Zero-copy reference into a goroutine-local buffer:

```
bits 47-46: 10 (subtype)
bits 45-38: free (8 bits)
bits 37-24: length (14 bits, max 16,383 bytes)
bits 23-0:  byte offset (24 bits, max 16,777,215 = 16 MB)
```

Used at lex time for source spans and at runtime for HTTP request/response
bodies and file contents. Offset at LSB for efficient buffer indexing.

Slices borrow from an immutable buffer. When a Slice must outlive its buffer
(stored in an object, returned from a function), it promotes to SSO-5 or
heap WString — the copy-on-escape point.

### 7.4 Char (subtype 11)

Runtime character with full Unicode metadata. Codepoint at LSB for cheap ASCII
extraction: `v & 0x7F`.

```
bits 47-46: 11 (subtype)
bit  45:    is_emoji
bit  44:    is_ascii
bit  43:    is_printable
bits 42-39: digit_value (4 bits, 0xF = not-a-digit)
bits 38-30: case_delta (9 bits, signed, ±255)
bits 29-28: width (2 bits: 0=zero, 1=narrow, 2=wide, 3=ambiguous)
bits 27-23: Unicode category (5 bits, 30 categories)
bits 22-21: utf8_len - 1 (2 bits, encoding 1-4)
bits 20-0:  codepoint (21 bits, U+0 to U+10FFFF)
```

**Unicode category encoding** (contiguous ranges for fast range checks):

| Range | Categories | Fast check |
|-------|-----------|------------|
| 0-4 | Lu, Ll, Lt, Lm, Lo | `is_letter = cat <= 4` |
| 5-7 | Nd, Nl, No | `is_number = 5 <= cat <= 7` |
| 8-10 | Zs, Zl, Zp | `is_whitespace = 8 <= cat <= 10` |
| 11-13 | Mn, Mc, Me | `is_combining = 11 <= cat <= 13` |
| 14-20 | Pc, Pd, Ps, Pe, Pi, Pf, Po | Punctuation |
| 21-24 | Sm, Sc, Sk, So | Symbols |
| 25-29 | Cc, Cf, Cs, Co, Cn | Control/Format/Other |

**case_delta:** Signed offset to convert case (e.g., `'A'` has delta +32 to
reach `'a'`). Covers most Latin (±32), Cyrillic (±32-80), and Turkic (±199)
mappings. Rare mappings exceeding ±255 fall back to a lookup table.

---

## 8. Numeric (0xFFFD)

The `0xFFFD` tag holds three numeric domain types via a 2-bit subtype in
bits 47-46. All store a signed significand and signed scale representing the
value `sig × 10^scale`.

### 8.1 Decimal (subtype 00)

General-purpose fixed-point decimal:

```
bits 47-46: 00 (subtype, implicit — zero bits)
bits 45-7:  significand (39 bits, signed)
bits 6-0:   scale (7 bits, signed)
```

| Field | Bits | Range |
|-------|------|-------|
| sig | 39 | ±274,877,906,943 (~11 significant digits) |
| scale | 7 | -64 to +63 |

**Boxing:**
```c
uint64_t s  = (uint64_t)sig   & 0x7FFFFFFFFF;  // 39 bits
uint64_t sc = (uint64_t)scale & 0x7F;           // 7 bits
return 0xFFFD000000000000 | (s << 7) | sc;
```

**Unboxing sig (sign-extend from bit 38):**
```c
((int64_t)((v >> 7) & 0x7FFFFFFFFF) << 25) >> 25
```

**Unboxing scale (sign-extend from bit 6):**
```c
((int8_t)((v & 0x7F) << 1)) >> 1
```

Values exceeding this range overflow to heap WDomainHeap (see §11).

### 8.2 Currency (subtype 01)

Fixed-point decimal with a 4-bit currency symbol ID:

```
bits 47-46: 01 (subtype)
bits 45-42: symbol_id (4 bits, 16 currencies)
bits 41-5:  significand (37 bits, signed)
bits 4-0:   scale (5 bits, signed)
```

| Field | Bits | Range |
|-------|------|-------|
| symbol_id | 4 | 0-15 (16 currencies) |
| sig | 37 | ±68,719,476,735 (±$687M in cents at scale=-2) |
| scale | 5 | -16 to +15 |

**Currency symbol table:**

| ID | Symbol | Currency |
|----|--------|----------|
| 0 | $ | USD |
| 1 | € | EUR |
| 2 | £ | GBP |
| 3 | ¥ | JPY |
| 4 | ₹ | INR |
| 5 | ¥ | CNY (context-disambiguated from JPY) |
| 6 | ₩ | KRW |
| 7 | ₿ | BTC |
| 8 | Fr | CHF |
| 9 | C$ | CAD |
| 10 | A$ | AUD |
| 11 | R$ | BRL |
| 12 | ₽ | RUB |
| 13 | ฿ | THB |
| 14 | zł | PLN |
| 15 | — | reserved |

### 8.3 Quantity (subtype 11)

Fixed-point decimal with an 8-bit unit ID:

```
bits 47-46: 11 (subtype)
bits 45-38: unit_id (8 bits, 256 units)
bits 37-7:  significand (31 bits, signed)
bits 6-0:   scale (7 bits, signed)
```

| Field | Bits | Range |
|-------|------|-------|
| unit_id | 8 | 0-255 (256 unit slots) |
| sig | 31 | ±1,073,741,823 (~9 significant digits) |
| scale | 7 | -64 to +63 |

Unit IDs 0-118 are reserved for built-in units (SI base, SI derived, prefixed,
imperial, compound, information). IDs 119-253 are available for custom
(user-defined) units registered at runtime. ID 254 is reserved. **ID 255
(0xFF) is the sentinel for percentage** — `7.65%` is encoded as
`sig=765, scale=-2, unit_id=0xFF`.

### 8.4 Subtype 10 (Reserved)

Reserved for future use. Implementations MUST NOT produce values with this
subtype.

---

## 9. Packed Types (0xFFFE)

The `0xFFFE` tag holds six structured value types via a 3-bit subtype in
bits 47-45. All fields are packed into the remaining 45 bits.

### 9.1 Color (subtype 000)

```
bits 47-45: 000 (subtype)
bits 44-37: red (8 bits)
bits 36-29: green (8 bits)
bits 28-21: blue (8 bits)
bits 20-13: alpha (8 bits)
bits 12-0:  colorspace/flags (12 bits, reserved)
```

Shifted from the 45-bit boundary: R at bits 36-44, G at 28-35, B at 20-27,
A at 12-19, flags at 0-11.

### 9.2 Complex (subtype 001)

Fixed-point complex number (real + imaginary):

```
bits 47-45: 001 (subtype)
bits 44-29: real significand (16 bits, signed)
bits 28-23: real scale (6 bits, signed)
bits 22-7:  imaginary significand (16 bits, signed)
bits 6-1:   imaginary scale (6 bits, signed)
```

Value = `(real_sig × 10^real_scale) + (imag_sig × 10^imag_scale)i`

### 9.3 Rational (subtype 010)

```
bits 47-45: 010 (subtype)
bits 44-23: numerator (22 bits, signed, ±2,097,151)
bits 22-1:  denominator (22 bits, unsigned, 0-4,194,303)
```

### 9.4 Subtype 011 (Reserved)

### 9.5 Date (subtype 100)

Calendar date with time and timezone:

```
bits 47-45: 100 (subtype)
bits 44-33: year (12 bits, signed, ±2047)
bits 32-29: month (4 bits, 1-12)
bits 28-24: day (5 bits, 1-31)
bits 23-19: hour (5 bits, 0-23)
bits 18-13: minute (6 bits, 0-59)
bits 12-7:  second (6 bits, 0-59)
bits 6-1:   timezone offset (6 bits, signed, ±31 half-hours from UTC)
```

### 9.6 IPv4 (subtype 101)

```
bits 47-45: 101 (subtype)
bits 44-13: address (32 bits, network byte order)
bits 12-7:  CIDR prefix (6 bits, 0-32)
bits 6-1:   flags (6 bits, reserved)
```

### 9.7 Subtype 110 (Reserved)

### 9.8 Location (subtype 111)

Two modes selected by bit 43:

**Mode 0 — 2D point:**
```
bits 47-45: 111 (subtype)
bit  43:    0 (point mode)
bits 42-22: x (21 bits, signed, ±1,048,575)
bits 21-0:  y (22 bits, signed, ±2,097,151)
```

**Mode 1 — Source file location:**
```
bits 47-45: 111 (subtype)
bit  43:    1 (file mode)
bits 42-29: file_id (14 bits, 0-16,383)
bits 28-11: line (18 bits, 0-262,143)
bits 10-0:  column (11 bits, 0-2,047)
```

---

## 10. Duration (0xFFFF)

Two modes selected by bit 47:

### 10.1 Mode 0 — Nanoseconds

```
bits 63-48: 0xFFFF (tag)
bit  47:    0 (ns mode)
bits 46-0:  nanoseconds (47 bits, signed)
```

**Range:** ±70,368,744,177,663 ns (approximately ±19.5 hours).

Designed for benchmarks, CPU timing, and captures fractional microseconds
(1.5µs = 1500ns).

### 10.2 Mode 1 — Months + Milliseconds

```
bits 63-48: 0xFFFF (tag)
bit  47:    1 (months+ms mode)
bits 46-32: months (15 bits, signed, ±16,383 ≈ ±1,365 years)
bits 31-0:  milliseconds (32 bits, unsigned, 0-4,294,967,295 ≈ 49.7 days)
```

Designed for human-scale and calendar-relative durations. Months are kept
separate from absolute time because a "month" has no fixed duration.

---

## 11. Heap Overflow (Domain Objects)

When a domain type value exceeds the NaN-box capacity (significand too large,
scale out of range, etc.), it is promoted to a heap-allocated `WDomainHeap`
struct stored with sub-tag 0xF in the 0x0000 object space.

```c
typedef struct {
    uint8_t domain_type;   // W_DOMAIN_DECIMAL (0), W_DOMAIN_CURRENCY (1),
                           // W_DOMAIN_QUANTITY (2), W_DOMAIN_DURATION (3)
    uint8_t pad[7];        // alignment
    int64_t sig;           // full-precision significand
    int32_t scale;         // scale
    int32_t extra;         // symbol_id (currency), unit_id (quantity), mode (duration)
    int64_t extra2;        // duration mode 1: ms value
} WDomainHeap;  // 32 bytes
```

**Boxing:** `(uint64_t)(uintptr_t)ptr | 0xF` (ptr MUST be 16-byte aligned)

**Type check:** `v >= 0x10 && (v >> 48) == 0 && (v & 0xF) == 0xF`

All arithmetic, comparison, negation, and display operations MUST handle both
inline NaN-boxed values and heap domain objects transparently. The `w_decimal`,
`w_currency`, `w_quantity`, and `w_duration_ns` constructors automatically
select the inline or heap path.

This mirrors V8's Smi → HeapNumber pattern: common values are zero-allocation
inline; overflow values are heap-allocated with full precision.

---

## 12. Type Checking

Type checks are designed for minimal instruction count:

| Check | Method | Instructions |
|-------|--------|:------------:|
| Truthiness | `v > 1` (unsigned) | 1 |
| Nil | `v == 0` | 1 |
| Tagged type | `(v >> 48) == TAG` | 2 |
| Double | `(v - BIAS) <= 0xFFF7...` | 2 |
| String | `(v >> 48) == 0xFFF9 && !(v & 1)` | 3 |
| Symbol | `(v >> 48) == 0xFFF9 && (v & 1)` | 3 |
| Numeric subtype | `(v >> 48) == 0xFFFD && ((v >> 46) & 3) == X` | 4 |
| Packed subtype | `(v >> 48) == 0xFFFE && ((v >> 45) & 7) == X` | 4 |
| Object | `v >= 0x10 && (v >> 48) == 0` | 3 |
| Object sub-tag | `w_is_obj(v) && (v & 0xF) == X` | 4 |

---

## 13. Constants Reference

```c
// Singletons
#define W_NIL           0x0000000000000000ULL
#define W_FALSE         0x0000000000000001ULL
#define W_TRUE          0x0000000000000002ULL
#define W_UNDEF         0x0000000000000003ULL
#define W_MEMO_MISS     0x0000000000000004ULL

// Double encoding
#define W_DOUBLE_BIAS   0x0001000000000000ULL
#define W_BIASED_NAN    0x7FF9000000000000ULL

// Tags (high 16 bits)
#define W_TAG_STRINGSYM 0xFFF9000000000000ULL
#define W_TAG_INT       0xFFFA000000000000ULL
#define W_TAG_INSTANT   0xFFFB000000000000ULL
#define W_TAG_CHAR      0xFFFC000000000000ULL  // also token, lexchar, slice
#define W_TAG_DECIMAL   0xFFFD000000000000ULL  // also currency, quantity
#define W_TAG_PACKED    0xFFFE000000000000ULL
#define W_TAG_DURATION  0xFFFF000000000000ULL

// Masks
#define W_TAG_MASK      0xFFFF000000000000ULL
#define W_PAYLOAD_MASK  0x0000FFFFFFFFFFFFULL

// Int range
#define W_INT48_MAX     ((int64_t)((1ULL << 47) - 1))     //  +140,737,488,355,327
#define W_INT48_MIN     ((int64_t)(-(1LL << 47)))          //  -140,737,488,355,328

// Decimal range (subtype 00)
#define W_DECIMAL_SIG_MAX    ((int64_t)((1ULL << 38) - 1)) //  +274,877,906,943
#define W_DECIMAL_SIG_MIN    ((int64_t)(-(1LL << 38)))
#define W_DECIMAL_SCALE_MAX  63
#define W_DECIMAL_SCALE_MIN  (-64)

// Currency range (subtype 01)
#define W_CURRENCY_SIG_MAX   ((int64_t)((1ULL << 36) - 1)) //  +68,719,476,735
#define W_CURRENCY_SIG_MIN   ((int64_t)(-(1LL << 36)))
#define W_CURRENCY_SCALE_MAX 15
#define W_CURRENCY_SCALE_MIN (-16)

// Quantity range (subtype 11)
#define W_QUANTITY_SIG_MAX   ((int64_t)((1ULL << 30) - 1)) //  +1,073,741,823
#define W_QUANTITY_SIG_MIN   ((int64_t)(-(1LL << 30)))
#define W_QUANTITY_SCALE_MAX 63
#define W_QUANTITY_SCALE_MIN (-64)

// Duration range
#define W_DURATION_NS_MAX    ((int64_t)((1ULL << 46) - 1)) //  +70,368,744,177,663 ns
#define W_DURATION_NS_MIN    ((int64_t)(-(1LL << 46)))
#define W_DURATION_MONTHS_MAX ((int16_t)((1 << 14) - 1))   //  +16,383 months
#define W_DURATION_MONTHS_MIN ((int16_t)(-(1 << 14)))

// Percentage sentinel
#define W_UNIT_PERCENT  0xFF

// Object sub-tags
#define W_SUBTAG_GENERIC  0
#define W_SUBTAG_STRUCT   4
#define W_SUBTAG_HASH     5
#define W_SUBTAG_CLOSURE  6
#define W_SUBTAG_REGEX    7
#define W_SUBTAG_RANGE    8
#define W_SUBTAG_MODULE   9
#define W_SUBTAG_ARRAY    0xA
#define W_SUBTAG_BIGINT   0xB
#define W_SUBTAG_CLASS    0xC
#define W_SUBTAG_UUID     0xD
#define W_SUBTAG_ERROR    0xE
#define W_SUBTAG_DOMAIN   0xF

// Numeric subtypes
#define W_NUMERIC_DECIMAL   0
#define W_NUMERIC_CURRENCY  1
#define W_NUMERIC_QUANTITY  3

// Packed subtypes
#define W_PACKED_COLOR     0
#define W_PACKED_COMPLEX   1
#define W_PACKED_RATIONAL  2
#define W_PACKED_DATE      4
#define W_PACKED_IPV4      5
#define W_PACKED_LOCATION  7

// Domain heap type discriminators
#define W_DOMAIN_DECIMAL   0
#define W_DOMAIN_CURRENCY  1
#define W_DOMAIN_QUANTITY  2
#define W_DOMAIN_DURATION  3
```

---

## 14. Design Rationale

**Why nil = 0?** `calloc`-initialized memory is automatically nil. Zero-filled
arrays are nil-arrays.

**Why objects at 0x0000?** Avoids consuming a tag slot. Frees three tag slots
(0xFFFD, 0xFFFE, 0xFFFF) for domain types.

**Why biased doubles?** The bias of `0x0001` keeps the entire 0x0000 space
for objects. A single add/subtract is cheaper than bit manipulation for
float boxing. NaN normalization means NaN lives in double space with no
special sentinel needed.

**Why separate tags for duration and decimal?** A 3-bit numeric subtype was
considered but rejected — it costs 1 bit across all subtypes. Quantity sig
would drop from 31 to 30 bits (±536M), which barely fits the speed of light
(299,792,458). Duration gets its own tag (0xFFFF) instead.

**Why two duration modes?** Nanosecond mode captures fractional microseconds
for timing workloads. Calendar mode with months keeps months separate from
absolute time because a "month" has no fixed duration. Mode 0 covers benchmarks
and CPU timing (±19.5 hours). Mode 1 covers human-scale durations (±1,365
years plus up to 49.7 days of milliseconds).

**Why heap overflow?** The NaN-box is a fast path. Values exceeding inline
capacity (e.g., `$999,999,999,999.99`, compound units like `m/s²`, durations
mixing months with nanoseconds) promote transparently to heap objects. All
arithmetic dispatches through both paths.

**Why 16-byte alignment for heap objects?** Gives 4 bits for sub-tags in the
low nibble. 15 sub-tags is sufficient for all common heap types. Alignment
is achieved by using `calloc` which on most platforms returns 16-byte-aligned
memory (or using `aligned_alloc`).

**Why Symbol as bit 0?** Shares the 0xFFF9 tag with strings. No separate tag
slot consumed. One bit test distinguishes string from symbol.

**Why Char at 0xFFFC with codepoint at LSB?** `v & 0x7F` extracts ASCII
characters directly. The `is_ascii` flag confirms validity. Most character
operations in lexers hit ASCII — this makes the hot path cheapest.

**Why Percentage is unit_id 0xFF?** Percentage is semantically a quantity
(7.65% = a measurement). Using a sentinel unit_id avoids a separate type
while keeping the percentage identity for display (`%` suffix instead of
unit name).
