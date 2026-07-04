/*
 * wvalue.h — NaN-boxed value encoding for dynamic languages (v3)
 *
 * Standalone, dependency-free C header that packs every value a dynamic
 * language needs into a single uint64_t:
 *
 *   nil, false, true, undef  — singletons in 0x0000 space
 *   heap objects              — 0x0000 space, 16-byte aligned ptr + 4-bit sub-tag
 *   IEEE 754 doubles          — biased (bias = 0x0001) to sit above objects
 *   string / symbol           — 0xFFF9 tag, inline (≤5 bytes) or heap WString*
 *   48-bit signed integers    — 0xFFFA tag, no bias, sign-extended
 *   instants                  — 0xFFFB tag, 48-bit signed Unix ms
 *   codepoint                 — 0xFFFC tag, 21-bit Unicode codepoint + metadata
 *   numeric (4 subtypes)      — 0xFFFD tag: decimal, currency, (reserved), quantity
 *   packed types              — 0xFFFE tag: color, complex, rational, date, ipv4, location
 *   duration                  — 0xFFFF tag: ns mode or months+ms mode
 *
 * Truthiness: v > 1 (nil=0 and false=1 are falsy, everything else truthy).
 * NaN normalizes to canonical qNaN in double space — no separate sentinel.
 *
 * MIT License — use freely in your own language runtime.
 *
 * Copyright (c) 2013–2026 Erik Peterson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#ifndef WVALUE_H
#define WVALUE_H

#include <stdint.h>
#include <string.h>
#include <assert.h>

/* ========================================================================
   Value layout (uint64_t, ordered low to high)

   0x0000_0000_0000_0000                       nil       (singleton)
   0x0000_0000_0000_0001                       false     (singleton)
   0x0000_0000_0000_0002                       true      (singleton)
   0x0000_0000_0000_0003                       undef     (singleton)
   0x0000_0000_0000_0004                       memo miss (internal sentinel)
   0x0000_0000_0000_0005 - 0x0000_0000_0000_000F  reserved sentinels
   0x0000_0000_0000_00x0+                      heap objects (ptr | sub-tag nibble)
   ── biased doubles ────────────────────────────────────────
   0x0001_0000_0000_0000 - 0xFFF8_FFFF_FFFF_FFFF  biased IEEE 754 doubles
   ── tagged values ─────────────────────────────────────────
   0xFFF9_xxxx_xxxx_xxxx                       string / symbol
   0xFFFA_xxxx_xxxx_xxxx                       int     (48-bit signed, no bias)
   0xFFFB_xxxx_xxxx_xxxx                       instant (48-bit signed Unix ms)
   0xFFFC_xxxx_xxxx_xxxx                       char    (21-bit cp + metadata)
   0xFFFD_xxxx_xxxx_xxxx                       numeric (2-bit subtype + payload)
   0xFFFE_xxxx_xxxx_xxxx                       packed  (3-bit subtype + payload)
   0xFFFF_xxxx_xxxx_xxxx                       duration (1-bit mode + payload)

   ---- 0x0000 sub-tags (low nibble of 16-byte-aligned pointer) ----
   nibble 0, ptr == 0   →  nil
   nibble 0, ptr != 0   →  generic object (uint8_t type in struct header)
   nibble 1             →  false  (singleton, not a pointer)
   nibble 2             →  true   (singleton, not a pointer)
   nibble 3             →  undef  (singleton, not a pointer)
   nibble 4             →  struct (user-defined class instance)
   nibble 5             →  hash
   nibble 6             →  closure
   nibble 7             →  regex
   nibble 8             →  range
   nibble 9             →  module
   nibble A             →  array
   nibble B             →  bigint
   nibble C             →  class
   nibble D             →  uuid
   nibble E             →  error
   nibble F             →  domain (heap-overflow currency/quantity/duration)

   ---- String/Symbol (0xFFF9) ----
   bit 0:
     0 → string
     1 → symbol

   bits 1-3 = mode:
     0-5: SSO inline (≤5 bytes at bits 4-43) (length in bits 1-3, 0-5)
     6:   slab (24-bit index at bits 4-27, interned SSO-61 string/symbol)
     7:   heap (transient/large, bits 4-47 = masked pointer to WString* / WSymbol*)

   ---- Numeric (0xFFFD) — 2-bit subtype in payload bits 47-46 ----
   subtype 00: decimal   [39-bit sig (signed)][7-bit scale (signed)]
   subtype 01: currency  [4-bit symbol_id][37-bit sig (signed)][5-bit scale (signed)]
   subtype 10: (reserved)
   subtype 11: quantity  [8-bit unit_id][31-bit sig (signed)][7-bit scale (signed)]

   ---- Packed (0xFFFE) — 3-bit subtype in payload bits 47-45 ----
   000: color      [8R][8G][8B][8A][12 colorspace/flags]
   001: complex    [16 real sig][6 real scale][16 imag sig][6 imag scale]
   010: rational   [22 numerator (signed)][22 denominator (unsigned)]
   011: (reserved)
   100: date       [12 year][4 month][5 day][5 hour][6 min][6 sec][6 tz]
   101: ipv4       [32 address][6 CIDR][6 flags]
   110: (reserved)
   111: location   [1 mode][43 payload]

   ---- Duration (0xFFFF) — 1-bit mode in payload bit 47 ----
   mode 0: [47-bit signed ns] (±19.5 hours, for benchmarks/timing)
   mode 1: [15-bit months (signed)][32-bit ms (unsigned)] (calendar-relative)
   ======================================================================== */

typedef uint64_t WValue;

/* ---- Singleton constants ---- */
#define W_NIL           0x0000000000000000ULL
#define W_FALSE         0x0000000000000001ULL
#define W_TRUE          0x0000000000000002ULL
#define W_UNDEF         0x0000000000000003ULL

/* ---- Internal sentinels ---- */
#define W_MEMO_MISS     0x0000000000000004ULL

/* ---- Double bias ---- */
#define W_DOUBLE_BIAS   0x0001000000000000ULL

/* Biased NaN: all NaN variants normalize to canonical qNaN (0x7FF8...)
   before biasing. Biased = 0x7FF8... + 0x0001... = 0x7FF9...
   NaN lives in double space — no separate sentinel. */
#define W_BIASED_NAN    0x7FF9000000000000ULL

/* ---- Tag constants (high 16 bits) ---- */
#define W_TAG_STRINGSYM 0xFFF9000000000000ULL
#define W_TAG_INT       0xFFFA000000000000ULL
#define W_TAG_INSTANT   0xFFFB000000000000ULL
#define W_TAG_CHAR      0xFFFC000000000000ULL
#define W_TAG_DECIMAL   0xFFFD000000000000ULL  /* also used for currency, quantity */
#define W_TAG_PACKED    0xFFFE000000000000ULL
#define W_TAG_DURATION  0xFFFF000000000000ULL

/* ---- Masks ---- */
#define W_PAYLOAD_MASK  0x0000FFFFFFFFFFFFULL
#define W_TAG_MASK      0xFFFF000000000000ULL

/* ---- INT48 range ---- */
#define W_INT48_MAX  ((int64_t)((1ULL << 47) - 1))
#define W_INT48_MIN  ((int64_t)(-(1LL << 47)))

/* ---- Object sub-tags (low 4 bits of value in 0x0000 space) ---- */
/* Singletons 0-3 and sentinels 4-0xF are NOT objects.
   Objects: value >= 0x10 with top 16 bits == 0. */
/* Phase 6i.2 subtag layout. Frees three slots (2, 3, 0xE) for future
 * promotions; ATOMIC and STRBUF claim previously-cold IPV6/BIGINT slots. */
#define W_SUBTAG_GENERIC     0   /* type discriminator in struct header byte */
#define W_SUBTAG_ATOMIC      1   /* Phase 6i.2: was IPV6 (demoted to W_TYPE_IPV6 = 6) */
/* slot 2 free (was MAC; demoted to W_TYPE_MAC = 5) */
/* slot 3 free (was ENCODED; demoted to W_TYPE_ENCODED = 8) */
#define W_SUBTAG_INSTANCE    4   /* user-defined class instance (WObject) */
#define W_SUBTAG_HASH        5
#define W_SUBTAG_CLOSURE     6
#define W_SUBTAG_REGEX       7
#define W_SUBTAG_RANGE       8
#define W_SUBTAG_SMALL_ARRAY 9   /* Phase 6h: own subtag, no type byte */
#define W_SUBTAG_ARRAY       0xA /* WArray; ebits=65 (w64) for polymorphic, else typed */
#define W_SUBTAG_STRBUF      0xB /* Phase 6i.2: was BIGINT (demoted to W_TYPE_BIGINT = 0xB) */
#define W_SUBTAG_CLASS       0xC
#define W_SUBTAG_UUID        0xD
/* slot E free (was ERROR; never used a constructor — no demote needed) */
#define W_SUBTAG_DOMAIN      0xF /* heap-overflow domain types */

/* ---- Domain heap type discriminators (for W_SUBTAG_DOMAIN overflow objects) ---- */
#define W_DOMAIN_DECIMAL   0
#define W_DOMAIN_CURRENCY  1
#define W_DOMAIN_QUANTITY  2
#define W_DOMAIN_DURATION  3

/* ---- Generic object type discriminators (uint8_t in struct header) ---- */
#define W_TYPE_THREAD    1
/* Phase 6i.2: 2 freed (was W_TYPE_ATOMIC — promoted to W_SUBTAG_ATOMIC = 1). */
#define W_TYPE_SOCKET    3
#define W_TYPE_CHANNEL   4
#define W_TYPE_MAC       5  /* Phase 6i.2: demoted from W_SUBTAG_MAC */
#define W_TYPE_IPV6      6  /* Phase 6i.2: demoted from W_SUBTAG_IPV6 */
#define W_TYPE_RESPONSE  7
#define W_TYPE_ENCODED   8  /* Phase 6i.2: demoted from W_SUBTAG_ENCODED (was W_TYPE_STRBUF) */
#define W_TYPE_ROPE      9
/* Phase 6i.1b: 10 freed (was W_TYPE_BOOL_ARRAY — folded into W_SUBTAG_ARRAY ebits=1). */
#define W_TYPE_BIGINT    11 /* Phase 6i.2: demoted from W_SUBTAG_BIGINT (was W_TYPE_TYPED_ARRAY) */
/* Metal compute primitives — defined in runtime/metal.m on darwin,
 * stubbed on other platforms. The Tungsten facade lives in core/metal.w. */
#define W_TYPE_METAL_DEVICE   12
#define W_TYPE_METAL_LIBRARY  13
#define W_TYPE_METAL_PIPELINE 14
#define W_TYPE_METAL_BUFFER   15
#define W_TYPE_METAL_QUEUE    16
/* Memory-mapped file region — File.mmap(path) returns one of these.
 * The data pointer is borrowed; lifetime is tied to .close(). */
#define W_TYPE_MMAP           17
/* Phase 3: BigArray (i64 fields, mmap views, KV caches). SmallArray was
 * promoted to its own subtag in Phase 6h. */
#define W_TYPE_BIG_ARRAY      18
/* Phase 6h freed slot 19 (was W_TYPE_SMALL_ARRAY). Phase 6i.2: claimed by W_TYPE_ERROR. */
#define W_TYPE_ERROR          19  /* Phase 6i.2: demoted from W_SUBTAG_ERROR (which had no constructor) */
/* Metal 4 tensor + MTL4 command primitives (macOS 26+). The MTL4 command
 * stack is parallel to the existing MTLCommandQueue path — Metal 4 features
 * like matmul2d cooperative tensors require argument-table binding which
 * the legacy MTLComputeCommandEncoder doesn't expose. */
#define W_TYPE_METAL_TENSOR        20  /* id<MTLTensor> */
#define W_TYPE_METAL4_QUEUE        21  /* id<MTL4CommandQueue> */
#define W_TYPE_METAL4_ALLOCATOR    22  /* id<MTL4CommandAllocator> */
#define W_TYPE_METAL4_ARGTABLE     23  /* id<MTL4ArgumentTable> */
#define W_TYPE_METAL4_COMPILER     24  /* id<MTL4Compiler> — needed for
                                          compute pipelines that use
                                          cooperative tensors (matmul2d) so
                                          we can set requiredThreadsPerTG. */
/* Windowing — NSWindow + CAMetalLayer + input, defined in runtime/graphics.m
 * on darwin. The Tungsten facade lives in core/graphics.w. */
#define W_TYPE_GFX_WINDOW          25  /* WGfxWindow* (window + layer + input) */
/* USB-HID device — Elgato Stream Deck + dials, defined in runtime/hid_bridge.m
 * on darwin (stubbed elsewhere). Feeds the REPL scrub loop via w_input_poll. */
#define W_TYPE_HID_DEVICE          26  /* WHIDDevice* (IOHIDManager + reader thread) */

/* ---- Numeric subtype (0xFFFD tag, bits 47-46 of payload) ---- */
#define W_NUMERIC_DECIMAL   0
#define W_NUMERIC_CURRENCY  1
/* 2 = reserved */
#define W_NUMERIC_QUANTITY  3

/* ---- Decimal constants (subtype 00: 39-bit sig, 7-bit scale) ---- */
#define W_DECIMAL_SIG_MAX    ((int64_t)((1ULL << 38) - 1))   /* 274,877,906,943 */
#define W_DECIMAL_SIG_MIN    ((int64_t)(-(1LL << 38)))        /* ~11 sig digits */
#define W_DECIMAL_SCALE_MAX  63
#define W_DECIMAL_SCALE_MIN  (-64)

/* ---- Currency constants (subtype 01: 37-bit sig, 5-bit scale) ---- */
#define W_CURRENCY_SIG_MAX   ((int64_t)((1ULL << 36) - 1))   /* 68,719,476,735 */
#define W_CURRENCY_SIG_MIN   ((int64_t)(-(1LL << 36)))        /* ±$687M in cents */
#define W_CURRENCY_SCALE_MAX 15
#define W_CURRENCY_SCALE_MIN (-16)

/* Currency symbol IDs (4-bit, 0-15) */
#define W_CURRENCY_USD  0   /* $ */
#define W_CURRENCY_EUR  1   /* € */
#define W_CURRENCY_GBP  2   /* £ */
#define W_CURRENCY_JPY  3   /* ¥ */
#define W_CURRENCY_INR  4   /* ₹ */
#define W_CURRENCY_CNY  5   /* ¥ (Chinese yuan, distinct from JPY) */
#define W_CURRENCY_KRW  6   /* ₩ */
#define W_CURRENCY_BTC  7   /* ₿ */
#define W_CURRENCY_CHF  8   /* Fr */
#define W_CURRENCY_CAD  9   /* C$ */
#define W_CURRENCY_AUD  10  /* A$ */
#define W_CURRENCY_BRL  11  /* R$ */
#define W_CURRENCY_RUB  12  /* ₽ */
#define W_CURRENCY_THB  13  /* ฿ */
#define W_CURRENCY_PLN  14  /* zł */
/* 15 = reserved */

/* ---- Quantity constants (subtype 11: 31-bit sig, 7-bit scale, 8-bit unit_id) ---- */
#define W_QUANTITY_SIG_MAX   ((int64_t)((1ULL << 30) - 1))   /* 1,073,741,823 */
#define W_QUANTITY_SIG_MIN   ((int64_t)(-(1LL << 30)))        /* ~9 sig digits */
#define W_QUANTITY_SCALE_MAX W_DECIMAL_SCALE_MAX
#define W_QUANTITY_SCALE_MIN W_DECIMAL_SCALE_MIN

/* Sentinel unit_id for percentage */
#define W_UNIT_PERCENT  0xFF

/* ---- Duration constants ---- */
#define W_DURATION_NS_MAX   ((int64_t)((1ULL << 46) - 1))    /* +70,368,744,177,663 ns */
#define W_DURATION_NS_MIN   ((int64_t)(-(1LL << 46)))         /* ≈ ±19.5 hours */
#define W_DURATION_MONTHS_MAX  ((int16_t)((1 << 14) - 1))    /* +16,383 months */
#define W_DURATION_MONTHS_MIN  ((int16_t)(-(1 << 14)))        /* ≈ ±1,365 years */

/* ---- Packed subtype (0xFFFE tag, bits 47-45 of payload) ---- */
#define W_PACKED_COLOR     0
#define W_PACKED_COMPLEX   1
#define W_PACKED_RATIONAL  2
#define W_PACKED_NODE      3   /* AST slab reference (PR #2: slab-AST migration) */
#define W_PACKED_DATE      4
#define W_PACKED_IPV4      5
#define W_PACKED_BODY      6   /* AST child-list reference (offset+length into g_body_arena) */
#define W_PACKED_LOCATION  7

/* ---- W_PACKED_NODE bit layout (45-bit payload) ----
 *
 * Two-tier encoding distinguished by a prefix bit at the top:
 *
 *   bit 44       tier prefix
 *                  0 = full tier  (8-bit kind, IDs in 32..255 after the
 *                      kind renumber lands; currently 1..138 in transition)
 *                  1 = compact tier (5-bit kind, IDs 0..31; populated by
 *                      subsequent commits — defined here for future use)
 *
 * Full tier (prefix 0) — current encoding:
 *   bits 36..43  kind     (8 bits)
 *   bits 34..35  sclass   (2 bits, SC_2/4/8/16)
 *   bits 32..33  reserved (2 bits — future flags: monomorph, has-sparse, …)
 *   bits  0..31  offset   (32 bits, index into g_node_arena[sclass])
 *
 * Compact tier (prefix 1) — future, no kinds populated yet:
 *   bits 39..43  kind (5 bits, IDs 0..31)
 *   bits  0..38  per-kind 39-bit payload
 *
 * Offsets index into a single per-size-class arena (`g_node_arena[sc]`)
 * that grows by realloc-doubling. Because offsets (not pointers) are
 * stored, in-process realloc preserves all live references — only the
 * arena's base address moves, and the base is read fresh on every
 * access. See `runtime/runtime.h` for the arena struct + helpers.
 *
 * The 11-bit → 8-bit kind shrink lands the foundation for variable-
 * length kind encoding: compact-tier kinds (0..31) get extra payload
 * bits via the prefix discriminator. Today's KIND_* constants (≤138)
 * fit cleanly in 8 bits; the renumber to 32..255 follows in a later
 * commit.
 */
#define W_NODE_PREFIX_BIT      44
#define W_NODE_PREFIX_MASK     (1ULL << W_NODE_PREFIX_BIT)

#define W_NODE_OFFSET_BITS     32
#define W_NODE_RESERVED_BITS   2
#define W_NODE_SCLASS_BITS     2
#define W_NODE_KIND_BITS       8
_Static_assert(W_NODE_OFFSET_BITS + W_NODE_RESERVED_BITS + W_NODE_SCLASS_BITS
             + W_NODE_KIND_BITS + 1 /* prefix */ == 45,
             "W_PACKED_NODE payload must be 45 bits");

#define W_NODE_OFFSET_MASK     ((1ULL << W_NODE_OFFSET_BITS) - 1)
#define W_NODE_SCLASS_MASK     ((1ULL << W_NODE_SCLASS_BITS) - 1)
#define W_NODE_KIND_MASK       ((1ULL << W_NODE_KIND_BITS) - 1)

#define W_NODE_SCLASS_SHIFT    (W_NODE_OFFSET_BITS + W_NODE_RESERVED_BITS)   /* = 34 */
#define W_NODE_KIND_SHIFT      (W_NODE_SCLASS_SHIFT + W_NODE_SCLASS_BITS)    /* = 36 */

/* Compact tier (prefix 1) — encoders/decoders defined for future use;
 * no kinds populated yet, so w_box_node_compact / w_node_compact_payload
 * are unused but reserve the encoding shape. */
#define W_NODE_COMPACT_KIND_BITS    5
#define W_NODE_COMPACT_KIND_SHIFT   39
#define W_NODE_COMPACT_KIND_MASK    ((1ULL << W_NODE_COMPACT_KIND_BITS) - 1)
#define W_NODE_COMPACT_PAYLOAD_BITS 39
#define W_NODE_COMPACT_PAYLOAD_MASK ((1ULL << W_NODE_COMPACT_PAYLOAD_BITS) - 1)

static inline WValue w_box_node(int kind, int sclass, uint64_t off) {
    /* Full-tier slab node. Prefix bit (44) is implicitly 0. */
    return W_TAG_PACKED
         | ((uint64_t)W_PACKED_NODE << 45)
         | ((uint64_t)(kind   & W_NODE_KIND_MASK)   << W_NODE_KIND_SHIFT)
         | ((uint64_t)(sclass & W_NODE_SCLASS_MASK) << W_NODE_SCLASS_SHIFT)
         | (off & W_NODE_OFFSET_MASK);
}
static inline int w_node_kind(WValue v) {
    if (v & W_NODE_PREFIX_MASK) {
        return (int)((v >> W_NODE_COMPACT_KIND_SHIFT) & W_NODE_COMPACT_KIND_MASK);
    }
    return (int)((v >> W_NODE_KIND_SHIFT) & W_NODE_KIND_MASK);
}
static inline int w_node_size_class(WValue v) {
    if (v & W_NODE_PREFIX_MASK) return 0;  /* compact-tier nodes have no sclass */
    return (int)((v >> W_NODE_SCLASS_SHIFT) & W_NODE_SCLASS_MASK);
}
static inline uint64_t w_node_offset(WValue v) {
    return v & W_NODE_OFFSET_MASK;
}

/* Compact-tier encoder/decoder (no kinds populated yet). */
static inline WValue w_box_node_compact(int kind, uint64_t payload) {
    return W_TAG_PACKED
         | ((uint64_t)W_PACKED_NODE << 45)
         | W_NODE_PREFIX_MASK
         | ((uint64_t)(kind & W_NODE_COMPACT_KIND_MASK) << W_NODE_COMPACT_KIND_SHIFT)
         | (payload & W_NODE_COMPACT_PAYLOAD_MASK);
}
static inline uint64_t w_node_compact_payload(WValue v) {
    return v & W_NODE_COMPACT_PAYLOAD_MASK;
}

/* ==== Type checks ==== */

static inline int w_is_nil(WValue v)       { return v == W_NIL; }
static inline int w_is_false(WValue v)     { return v == W_FALSE; }
static inline int w_is_true(WValue v)      { return v == W_TRUE; }
static inline int w_is_bool(WValue v)      { return v == W_FALSE || v == W_TRUE; }
static inline int w_is_undef(WValue v)     { return v == W_UNDEF; }

/* Double check: unsigned subtract wraps singletons/objects past threshold */
static inline int w_is_double(WValue v) {
    return (v - W_DOUBLE_BIAS) <= 0xFFF7FFFFFFFFFFFFULL;
}

/* NaN is a double with a known bit pattern (IEEE 754: NaN != NaN) */
static inline int w_is_nan(WValue v)       { return v == W_BIASED_NAN; }

static inline int w_is_int(WValue v)       { return (v & W_TAG_MASK) == W_TAG_INT; }
static inline int w_is_instant(WValue v)   { return (v & W_TAG_MASK) == W_TAG_INSTANT; }
static inline int w_is_char(WValue v) {
    return (v & W_TAG_MASK) == W_TAG_CHAR && ((v >> 46) & 0x3) == 3;  /* CHAR subtype */
}
static inline int w_is_token(WValue v) {
    return (v & W_TAG_MASK) == W_TAG_CHAR && ((v >> 46) & 0x3) == 0;  /* TOKEN subtype */
}
static inline int w_is_lexchar(WValue v) {
    return (v & W_TAG_MASK) == W_TAG_CHAR && ((v >> 46) & 0x3) == 1;  /* LEXCHAR subtype */
}
static inline int w_is_slice(WValue v) {
    return (v & W_TAG_MASK) == W_TAG_CHAR && ((v >> 46) & 0x3) == 2;  /* SLICE subtype */
}

/* Numeric tag (0xFFFD) — holds decimal, currency, quantity via 2-bit subtype */
static inline int w_is_numeric_tag(WValue v) { return (v & W_TAG_MASK) == W_TAG_DECIMAL; }
static inline int w_numeric_subtype(WValue v) { return (int)((v >> 46) & 0x3); }

static inline int w_is_decimal(WValue v) {
    return w_is_numeric_tag(v) && w_numeric_subtype(v) == W_NUMERIC_DECIMAL;
}
static inline int w_is_currency(WValue v) {
    return w_is_numeric_tag(v) && w_numeric_subtype(v) == W_NUMERIC_CURRENCY;
}
static inline int w_is_quantity(WValue v) {
    return w_is_numeric_tag(v) && w_numeric_subtype(v) == W_NUMERIC_QUANTITY;
}

/* Duration (0xFFFF) */
static inline int w_is_duration(WValue v) { return (v & W_TAG_MASK) == W_TAG_DURATION; }
static inline int w_duration_mode(WValue v) { return (int)((v >> 47) & 1); }

/* Packed types (0xFFFE) */
static inline int w_is_packed(WValue v)      { return (v & W_TAG_MASK) == W_TAG_PACKED; }
static inline int w_packed_subtype(WValue v) { return (int)((v >> 45) & 0x7); }

static inline int w_is_color(WValue v)       { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_COLOR; }
static inline int w_is_complex(WValue v)     { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_COMPLEX; }
static inline int w_is_rational(WValue v)    { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_RATIONAL; }
static inline int w_is_node(WValue v)        { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_NODE; }
static inline int w_is_date(WValue v)        { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_DATE; }
static inline int w_is_ipv4(WValue v)        { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_IPV4; }
static inline int w_is_location(WValue v)    { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_LOCATION; }
static inline int w_is_body(WValue v)        { return w_is_packed(v) && w_packed_subtype(v) == W_PACKED_BODY; }

/* String/symbol: both under 0xFFF9 tag, distinguished by bit 0 */
static inline int w_is_stringy(WValue v)     { return (v & W_TAG_MASK) == W_TAG_STRINGSYM; }
static inline int w_is_string(WValue v)      { return (v & W_TAG_MASK) == W_TAG_STRINGSYM && !(v & 1); }
static inline int w_is_symbol(WValue v)      { return (v & W_TAG_MASK) == W_TAG_STRINGSYM && (v & 1); }

static inline int w_is_inline(WValue v)      { return w_is_stringy(v) && ((v >> 1) & 7) <= 5; }
static inline int w_is_slab(WValue v)        { return w_is_stringy(v) && ((v >> 1) & 7) == 6; }

static inline int w_is_inline_str(WValue v)  { return w_is_string(v) && ((v >> 1) & 7) <= 5; }
static inline int w_is_inline_sym(WValue v)  { return w_is_symbol(v) && ((v >> 1) & 7) <= 5; }

static inline int w_is_slab_str(WValue v)    { return w_is_string(v) && ((v >> 1) & 7) == 6; }
static inline int w_is_slab_sym(WValue v)    { return w_is_symbol(v) && ((v >> 1) & 7) == 6; }

static inline int w_is_heap_str(WValue v)    { return w_is_string(v) && ((v >> 1) & 7) == 7; }
static inline int w_is_heap_sym(WValue v)    { return w_is_symbol(v) && ((v >> 1) & 7) == 7; }

/* Object space: heap pointers with sub-tags in low nibble.
   Excludes singletons (0-3) and sentinels (4-0xF). */
static inline int w_is_obj(WValue v) {
    return v >= 0x10 && (v >> 48) == 0;
}

/* Object sub-tag checks */
static inline int w_subtag(WValue v)       { return (int)(v & 0xFULL); }
static inline int w_is_array(WValue v)     { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_ARRAY; }
static inline int w_is_hash(WValue v)      { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_HASH; }
static inline int w_is_closure(WValue v)   { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_CLOSURE; }
static inline int w_is_regex(WValue v)     { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_REGEX; }
static inline int w_is_instance(WValue v)  { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_INSTANCE; }
static inline int w_is_class(WValue v)     { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_CLASS; }
static inline int w_is_range(WValue v)     { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_RANGE; }
static inline int w_is_domain_obj(WValue v) { return w_is_obj(v) && w_subtag(v) == W_SUBTAG_DOMAIN; }
/* Phase 6i.2: w_is_ipv6, w_is_mac, w_is_encoded, w_is_bigint moved to runtime.h
 * (they need struct access to read the type byte after demotion). w_is_error
 * removed — never had a constructor; the subtag was free real-estate. */

/* Phase 6i.2: w_is_integer_any moved to runtime.h alongside w_is_bigint
 * (which now needs the WBigint struct visible to read its type byte). */

/* ---- Bigint (heap object) ----
   Variable-width limb array, like multi-byte UTF-8:
   - 1 limb (most values): fits in i48, stays inline
   - N limbs (overflow): heap-allocated, transparent to user code
   Sign is encoded in the sign of length (GMP convention).
   Phase 6i.2: demoted from W_SUBTAG_BIGINT to W_SUBTAG_GENERIC + type byte. */
typedef struct {
    uint8_t  type;      /* W_TYPE_BIGINT */
    uint8_t  _pad[3];   /* align `size` at offset 4 */
    int32_t  size;      /* abs(size) = limb count; sign = number sign; 0 = zero */
    uint32_t cap;       /* allocated limbs */
    uint32_t _pad2;     /* align `limbs` at 8-byte boundary */
    uint64_t limbs[];   /* little-endian: limbs[0] is least significant */
} WBigint;

static inline WBigint *w_as_bigint(WValue v) {
    return (WBigint *)((void *)(uintptr_t)(v & ~0xFULL));
}

/* Generic object type checks (sub-tag 0, type from header byte).
   Concrete checks (w_is_thread etc.) defined in runtime.h after struct defs. */


/* ==== Boxing ==== */

static inline WValue w_box_int(int64_t v) {
    return W_TAG_INT | ((uint64_t)v & W_PAYLOAD_MASK);
}

static inline WValue w_box_double(double d) {
    uint64_t bits;
    memcpy(&bits, &d, sizeof(double));
    /* Normalize all NaN variants to canonical qNaN before biasing */
    if (__builtin_expect(
            (bits & 0x7FF0000000000000ULL) == 0x7FF0000000000000ULL &&
            (bits & 0x000FFFFFFFFFFFFFULL) != 0, 0)) {
        bits = 0x7FF8000000000000ULL;
    }
    return bits + W_DOUBLE_BIAS;
}

static inline WValue w_box_ptr(void *ptr, int subtag) {
#ifndef NDEBUG
    assert(((uintptr_t)ptr & 0xF) == 0 && "w_box_ptr: pointer must be 16-byte aligned");
#endif
    return ((uint64_t)(uintptr_t)ptr & ~0xFULL) | (uint64_t)subtag;
}

static inline WValue w_box_symbol_from_str(WValue str) {
    return str | 1;
}

static inline WValue w_box_inline_str(const void *data, size_t len) {
    uint64_t v = W_TAG_STRINGSYM | ((uint64_t)len << 1);
    const uint8_t *bytes = (const uint8_t *)data;
    for (size_t i = 0; i < len; i++) {
        v |= ((uint64_t)bytes[i]) << (4 + 8 * i);
    }
    return v;
}

static inline WValue w_box_inline_sym(const void *data, size_t len) {
    return w_box_inline_str(data, len) | 1;
}

/* ---- Mode 6: Slab strings and symbols (24-bit index, 6-61 byte SSO) ---- */
static inline WValue w_box_slab_str(uint32_t index) {
    return W_TAG_STRINGSYM | (6ULL << 1) | (((uint64_t)index & 0xFFFFFF) << 4);
}

static inline WValue w_box_slab_sym(uint32_t index) {
    return W_TAG_STRINGSYM | (6ULL << 1) | (((uint64_t)index & 0xFFFFFF) << 4) | 1;
}

static inline uint32_t w_as_slab_index(WValue v) {
    return (uint32_t)((v >> 4) & 0xFFFFFF);
}

/* ---- Mode 7: Heap string (WString pointer, transient/large) ---- */
struct WString;
static inline WValue w_box_heap_str(struct WString *ws) {
    return W_TAG_STRINGSYM | (7ULL << 1) | ((uint64_t)(uintptr_t)ws & 0x0000FFFFFFFFFFF0ULL);
}

static inline WValue w_box_heap_sym(struct WString *ws) {
    return W_TAG_STRINGSYM | (7ULL << 1) | ((uint64_t)(uintptr_t)ws & 0x0000FFFFFFFFFFF0ULL) | 1;
}



static inline WValue w_box_instant(int64_t unix_ms) {
    return W_TAG_INSTANT | ((uint64_t)unix_ms & W_PAYLOAD_MASK);
}

/* ---- Decimal boxing (subtype 00) ----
   Payload: [2 sub=00][39-bit sig][7-bit scale]
   bits 47-46: subtype (00)
   bits 45-7:  sig (39 bits, signed)
   bits 6-0:   scale (7 bits, signed) */

static inline int w_decimal_fits(int64_t sig, int scale) {
    return sig >= W_DECIMAL_SIG_MIN && sig <= W_DECIMAL_SIG_MAX &&
           scale >= W_DECIMAL_SCALE_MIN && scale <= W_DECIMAL_SCALE_MAX;
}

static inline WValue w_box_decimal(int64_t sig, int scale) {
    uint64_t s = (uint64_t)sig & 0x7FFFFFFFFFULL;     /* 39-bit significand */
    uint64_t sc = (uint64_t)scale & 0x7FULL;           /* 7-bit scale */
    return W_TAG_DECIMAL | (s << 7) | sc;              /* subtype 00 implicit */
}

/* ---- Currency boxing (subtype 01) ----
   Payload: [2 sub=01][4-bit symbol_id][37-bit sig][5-bit scale]
   bits 47-46: subtype (01)
   bits 45-42: symbol_id (4 bits)
   bits 41-5:  sig (37 bits, signed)
   bits 4-0:   scale (5 bits, signed) */

static inline int w_currency_fits(int64_t sig, int scale) {
    return sig >= W_CURRENCY_SIG_MIN && sig <= W_CURRENCY_SIG_MAX &&
           scale >= W_CURRENCY_SCALE_MIN && scale <= W_CURRENCY_SCALE_MAX;
}

static inline WValue w_box_currency(int symbol_id, int64_t sig, int scale) {
    uint64_t sub = 1ULL << 46;
    uint64_t sym = ((uint64_t)symbol_id & 0xFULL) << 42;
    uint64_t s = ((uint64_t)sig & 0x1FFFFFFFFFULL) << 5;  /* 37-bit sig */
    uint64_t sc = (uint64_t)scale & 0x1FULL;               /* 5-bit scale */
    return W_TAG_DECIMAL | sub | sym | s | sc;
}

/* ---- Quantity boxing (subtype 11) ----
   Payload: [2 sub=11][8-bit unit_id][31-bit sig][7-bit scale]
   bits 47-46: subtype (11)
   bits 45-38: unit_id (8 bits)
   bits 37-7:  sig (31 bits, signed)
   bits 6-0:   scale (7 bits, signed) */

static inline int w_quantity_fits(int64_t sig, int scale) {
    return sig >= W_QUANTITY_SIG_MIN && sig <= W_QUANTITY_SIG_MAX &&
           scale >= W_QUANTITY_SCALE_MIN && scale <= W_QUANTITY_SCALE_MAX;
}

static inline WValue w_box_quantity(int unit_id, int64_t sig, int scale) {
    uint64_t sub = 3ULL << 46;
    uint64_t u = ((uint64_t)unit_id & 0xFFULL) << 38;
    uint64_t s = ((uint64_t)sig & 0x7FFFFFFFULL) << 7;    /* 31-bit sig */
    uint64_t sc = (uint64_t)scale & 0x7FULL;               /* 7-bit scale */
    return W_TAG_DECIMAL | sub | u | s | sc;
}

/* ---- Duration boxing (0xFFFF tag) ----
   Mode 0: [bit47=0][47-bit signed ns]
   Mode 1: [bit47=1][15-bit months (signed)][32-bit ms (unsigned)] */

static inline int w_duration_ns_fits(int64_t ns) {
    return ns >= W_DURATION_NS_MIN && ns <= W_DURATION_NS_MAX;
}

static inline WValue w_box_duration_ns(int64_t ns) {
    /* Mode bit 47 = 0, ns in bits 46-0 (47-bit signed) */
    return W_TAG_DURATION | ((uint64_t)ns & 0x7FFFFFFFFFFFULL);
}

static inline WValue w_box_duration_months_ms(int16_t months, uint32_t ms) {
    /* Mode bit 47 = 1, months in bits 46-32, ms in bits 31-0 */
    return W_TAG_DURATION | (1ULL << 47) |
           (((uint64_t)months & 0x7FFFULL) << 32) | (uint64_t)ms;
}

/* ---- Packed type boxing (0xFFFE tag) ----
   Payload: [3-bit subtype][44-bit subtype-specific data]
   bits 47-45: subtype
   bits 44-0:  payload (varies by subtype) */

/* Color: mode bit in bit 0
   Mode 0 (SDR): [8R][8G][8B][8A][11 flags][1 mode=0] in bits 44-0
   Mode 1 (HDR): [10R][10G][10B][10A][3 colorspace][1 mode=1] in bits 44-0 */
static inline int w_color_mode(WValue v) { return (int)(v & 1); }
static inline WValue w_box_color(uint8_t r, uint8_t g, uint8_t b, uint8_t a, uint16_t flags) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_COLOR << 45) |
           ((uint64_t)r << 36) | ((uint64_t)g << 28) | ((uint64_t)b << 20) |
           ((uint64_t)a << 12) | ((flags & 0x7FF) << 1);  /* 11 flags + mode 0 */
}
static inline WValue w_box_color_hdr(uint16_t r, uint16_t g, uint16_t b, uint16_t a, uint8_t cs) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_COLOR << 45) |
           (((uint64_t)r & 0x3FF) << 34) | (((uint64_t)g & 0x3FF) << 24) |
           (((uint64_t)b & 0x3FF) << 14) | (((uint64_t)a & 0x3FF) << 4) |
           (((uint64_t)cs & 0x7) << 1) | 1;  /* 3 colorspace + mode 1 */
}
/* SDR unboxing (mode 0) */
static inline uint8_t w_unbox_color_r(WValue v) { return (uint8_t)((v >> 36) & 0xFF); }
static inline uint8_t w_unbox_color_g(WValue v) { return (uint8_t)((v >> 28) & 0xFF); }
static inline uint8_t w_unbox_color_b(WValue v) { return (uint8_t)((v >> 20) & 0xFF); }
static inline uint8_t w_unbox_color_a(WValue v) { return (uint8_t)((v >> 12) & 0xFF); }
static inline uint16_t w_unbox_color_flags(WValue v) { return (uint16_t)((v >> 1) & 0x7FF); }
/* HDR unboxing (mode 1) */
static inline uint16_t w_unbox_color_hdr_r(WValue v) { return (uint16_t)((v >> 34) & 0x3FF); }
static inline uint16_t w_unbox_color_hdr_g(WValue v) { return (uint16_t)((v >> 24) & 0x3FF); }
static inline uint16_t w_unbox_color_hdr_b(WValue v) { return (uint16_t)((v >> 14) & 0x3FF); }
static inline uint16_t w_unbox_color_hdr_a(WValue v) { return (uint16_t)((v >> 4) & 0x3FF); }
static inline uint8_t w_unbox_color_hdr_cs(WValue v) { return (uint8_t)((v >> 1) & 0x7); }

/* Complex: [16 real sig][6 real scale][16 imag sig][6 imag scale] in bits 44-0 */
static inline WValue w_box_complex(int16_t real_sig, int real_scale,
                                    int16_t imag_sig, int imag_scale) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_COMPLEX << 45) |
           (((uint64_t)real_sig & 0xFFFF) << 28) | (((uint64_t)real_scale & 0x3F) << 22) |
           (((uint64_t)imag_sig & 0xFFFF) << 6) | ((uint64_t)imag_scale & 0x3F);
}
static inline int16_t w_unbox_complex_real_sig(WValue v) { return (int16_t)((v >> 28) & 0xFFFF); }
static inline int w_unbox_complex_real_scale(WValue v) { return ((int8_t)(((v >> 22) & 0x3F) << 2)) >> 2; }
static inline int16_t w_unbox_complex_imag_sig(WValue v) { return (int16_t)((v >> 6) & 0xFFFF); }
static inline int w_unbox_complex_imag_scale(WValue v) { return ((int8_t)((v & 0x3F) << 2)) >> 2; }

/* Rational: [22 numerator (signed)][22 denominator (unsigned)] in bits 44-0 */
static inline WValue w_box_rational(int32_t num, uint32_t den) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_RATIONAL << 45) |
           (((uint64_t)num & 0x3FFFFF) << 22) | ((uint64_t)den & 0x3FFFFF);
}
static inline int32_t w_unbox_rational_num(WValue v) {
    return ((int32_t)(((v >> 22) & 0x3FFFFF) << 10)) >> 10;
}
static inline uint32_t w_unbox_rational_den(WValue v) { return (uint32_t)(v & 0x3FFFFF); }

/* Date: [12 year][4 month][5 day][5 hour][6 min][6 sec][7 tz] in bits 44-0.
   tz is stored as signed quarter-hours (15-minute units, range -32:00..
   +31:45) so half-hour and :45 zones fit; every real offset lies in
   -12:00..+14:00. The box/unbox API speaks MINUTES — conversion to
   quarters is internal to the encoding. */
static inline WValue w_box_date(int year, int month, int day,
                                 int hour, int min, int sec, int tz_offset_min) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_DATE << 45) |
           (((uint64_t)year & 0xFFF) << 33) | (((uint64_t)month & 0xF) << 29) |
           (((uint64_t)day & 0x1F) << 24) | (((uint64_t)hour & 0x1F) << 19) |
           (((uint64_t)min & 0x3F) << 13) | (((uint64_t)sec & 0x3F) << 7) |
           ((uint64_t)(tz_offset_min / 15) & 0x7F);
}
static inline int w_unbox_date_year(WValue v) {
    return ((int16_t)(((v >> 33) & 0xFFF) << 4)) >> 4;
}
static inline int w_unbox_date_month(WValue v) { return (int)((v >> 29) & 0xF); }
static inline int w_unbox_date_day(WValue v) { return (int)((v >> 24) & 0x1F); }
static inline int w_unbox_date_hour(WValue v) { return (int)((v >> 19) & 0x1F); }
static inline int w_unbox_date_min(WValue v) { return (int)((v >> 13) & 0x3F); }
static inline int w_unbox_date_sec(WValue v) { return (int)((v >> 7) & 0x3F); }
static inline int w_unbox_date_tz(WValue v) {
    return (((int8_t)((v & 0x7F) << 1)) >> 1) * 15;  /* 7-bit signed quarter-hours -> minutes */
}

/* IPv4: [32 address][6 CIDR][6 flags] in bits 44-0 */
static inline WValue w_box_ipv4(uint32_t addr, int cidr, int flags) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_IPV4 << 45) |
           ((uint64_t)addr << 12) | (((uint64_t)cidr & 0x3F) << 6) |
           ((uint64_t)flags & 0x3F);
}
static inline uint32_t w_unbox_ipv4_addr(WValue v) { return (uint32_t)((v >> 12) & 0xFFFFFFFF); }
static inline int w_unbox_ipv4_cidr(WValue v) { return (int)((v >> 6) & 0x3F); }
static inline int w_unbox_ipv4_flags(WValue v) { return (int)(v & 0x3F); }

/* Location: [2 mode][43 payload] in bits 44-0.
 *
 * Mode was originally a single bit (43); bit 44 sat unused above it in
 * every existing value (Point and File mode payloads both top out at
 * 43 bits, bits 42-0), so it costs nothing to fold it into the mode
 * field instead — 2 bits, 4 modes, and both legacy encodings keep
 * their exact old bit patterns (Point = 00, File = 01, bit 44 was
 * always clear).
 *
 *   Mode 00 (Point):       [21 x (signed)][22 y (signed)]
 *   Mode 01 (File):        [14 file_id][18 line][11 col]
 *   Mode 10 (FileOffset):  [14 file_id][29 byte offset]
 *   Mode 11: reserved
 *
 * FileOffset is a single-point byte offset into a file's source text —
 * the low-level payload underneath byte-offset AST spans (:loc/:loc_end
 * each hold one). Line/col for error display are reconstructed lazily
 * from a per-file newline-offset table, not stored — the 18-bit line /
 * 11-bit col fields in File mode cap out on generated or minified
 * sources; a 29-bit offset covers files up to 512 MiB. */
static inline WValue w_box_location_point(int32_t x, int32_t y) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_LOCATION << 45) |
           /* mode 00 = bits 44:43 clear */
           (((uint64_t)x & 0x1FFFFF) << 22) | ((uint64_t)y & 0x3FFFFF);
}
static inline WValue w_box_location_file(int file_id, int line, int col) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_LOCATION << 45) |
           (1ULL << 43) | /* mode 01 */
           (((uint64_t)file_id & 0x3FFF) << 29) |
           (((uint64_t)line & 0x3FFFF) << 11) | ((uint64_t)col & 0x7FF);
}
static inline WValue w_box_location_file_offset(int file_id, uint32_t offset) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_LOCATION << 45) |
           (2ULL << 43) | /* mode 10 */
           (((uint64_t)file_id & 0x3FFF) << 29) |
           ((uint64_t)offset & 0x1FFFFFFF);
}
static inline int w_location_mode(WValue v) { return (int)((v >> 43) & 0x3); }
static inline int32_t w_unbox_location_x(WValue v) {
    return ((int32_t)(((v >> 22) & 0x1FFFFF) << 11)) >> 11;
}
static inline int32_t w_unbox_location_y(WValue v) {
    return ((int32_t)((v & 0x3FFFFF) << 10)) >> 10;
}
static inline int w_unbox_location_file_id(WValue v) { return (int)((v >> 29) & 0x3FFF); }
static inline int w_unbox_location_line(WValue v) { return (int)((v >> 11) & 0x3FFFF); }
static inline int w_unbox_location_col(WValue v) { return (int)(v & 0x7FF); }
/* FileOffset mode shares file_id's bit position with File mode, so
 * w_unbox_location_file_id works on either — no separate accessor. */
static inline uint32_t w_unbox_location_offset(WValue v) { return (uint32_t)(v & 0x1FFFFFFF); }

/* ---- Body (subtype 6): AST child-list reference ----
 *
 * A "packed body" is a value-not-pointer reference to a slice of the
 * flat body arena (`g_body_arena` in runtime.c) — the arena-relative
 * analogue of a WArray, for the specific case of AST child lists
 * (:body/:args/:expressions/…), which are always homogeneous w64
 * slots (every frozen array has ebits==65 — see w_ast_freeze_if_array)
 * and, once frozen, are never mutated in place. That means no ebits
 * discriminator, no start/cap distinction, and — critically — no
 * pointer at all: unlike W_SUBTAG_ARRAY's boxed pointer (which needs
 * 16-byte alignment purely so w_box_ptr can steal the low 4 bits for
 * its subtag), an arena-relative offset is just an integer packed
 * directly into the payload, so there's no header and no alignment
 * requirement to satisfy.
 *
 * 45-bit payload, no kind/mode bits needed (one shape only):
 *   [24 offset (in slots)][21 length (element count)]
 *
 * 24-bit offset covers 16,777,216 slots (128 MiB of body-arena
 * payload); 21-bit length covers 2,097,151 elements in a single list.
 * Both are enormous headroom against measured usage (a tungsten.w
 * self-compile needs ~97K slots across ~50K lists, each averaging
 * under 2 elements).
 *
 * `type()` reports "Array" for these values (see __w_type in
 * runtime.c) and `[]`/`.size`/`.each` all work transparently (see
 * w_array_get, w_ic_body_table) — every existing `type(x)=="Array"`
 * check and Enumerable call across the compiler works unchanged,
 * whether a field holds a real WArray or a packed body. `[]=`/`.push`/
 * etc. are NOT supported (raise) — packed bodies are immutable once
 * frozen; a rewrite that needs a different child list constructs a new
 * one, same discipline as node-kind changes. */
#define W_BODY_OFFSET_BITS  24
#define W_BODY_LENGTH_BITS  21
#define W_BODY_OFFSET_MASK  ((1ULL << W_BODY_OFFSET_BITS) - 1)
#define W_BODY_LENGTH_MASK  ((1ULL << W_BODY_LENGTH_BITS) - 1)
static inline WValue w_box_body(uint32_t offset, uint32_t length) {
    return W_TAG_PACKED | ((uint64_t)W_PACKED_BODY << 45) |
           (((uint64_t)offset & W_BODY_OFFSET_MASK) << W_BODY_LENGTH_BITS) |
           ((uint64_t)length & W_BODY_LENGTH_MASK);
}
static inline uint32_t w_unbox_body_offset(WValue v) {
    return (uint32_t)((v >> W_BODY_LENGTH_BITS) & W_BODY_OFFSET_MASK);
}
static inline uint32_t w_unbox_body_length(WValue v) {
    return (uint32_t)(v & W_BODY_LENGTH_MASK);
}

/* ==== Unboxing ==== */

static inline int64_t w_as_int(WValue v) {
    /* Sign-extend from 48 bits (no bias) */
    return ((int64_t)(v << 16)) >> 16;
}

static inline double w_as_double(WValue v) {
    uint64_t bits = v - W_DOUBLE_BIAS;
    double d;
    memcpy(&d, &bits, sizeof(double));
    return d;
}

static inline void *w_as_ptr(WValue v) {
    return (void *)(uintptr_t)(v & ~0xFULL);
}

/* ---- Decimal unboxing (subtype 00) ---- */
static inline int64_t w_unbox_decimal_sig(WValue v) {
    /* 39-bit sig at bits 45-7, sign-extend from bit 38 */
    return ((int64_t)((v >> 7) & 0x7FFFFFFFFFULL) << 25) >> 25;
}

static inline int w_unbox_decimal_scale(WValue v) {
    return ((int8_t)((v & 0x7F) << 1)) >> 1;
}

/* ---- Currency unboxing (subtype 01) ---- */
static inline int w_unbox_currency_symbol(WValue v) {
    return (int)((v >> 42) & 0xF);
}

static inline int64_t w_unbox_currency_sig(WValue v) {
    /* 37-bit sig at bits 41-5, sign-extend from bit 36 */
    return ((int64_t)((v >> 5) & 0x1FFFFFFFFFULL) << 27) >> 27;
}

static inline int w_unbox_currency_scale(WValue v) {
    /* 5-bit scale at bits 4-0, sign-extend from bit 4 */
    return ((int8_t)((v & 0x1F) << 3)) >> 3;
}

/* ---- Quantity unboxing (subtype 11) ---- */
static inline int w_unbox_quantity_unit(WValue v) {
    return (int)((v >> 38) & 0xFF);
}

static inline int64_t w_unbox_quantity_sig(WValue v) {
    /* 31-bit sig at bits 37-7, sign-extend from bit 30 */
    return ((int64_t)((v >> 7) & 0x7FFFFFFFULL) << 33) >> 33;
}

static inline int w_unbox_quantity_scale(WValue v) {
    /* Same layout as decimal: 7-bit scale at bits 6-0 */
    return ((int8_t)((v & 0x7F) << 1)) >> 1;
}

/* ---- Duration unboxing ---- */
static inline int64_t w_unbox_duration_ns(WValue v) {
    /* 47-bit signed ns at bits 46-0, sign-extend from bit 46 */
    return ((int64_t)(v << 17)) >> 17;
}

static inline int16_t w_unbox_duration_months(WValue v) {
    /* 15-bit signed months at bits 46-32 */
    return ((int16_t)(((v >> 32) & 0x7FFF) << 1)) >> 1;
}

static inline uint32_t w_unbox_duration_ms(WValue v) {
    return (uint32_t)(v & 0xFFFFFFFFULL);
}

static inline int64_t w_unbox_instant(WValue v) {
    /* Sign-extend from 48 bits */
    return ((int64_t)(v << 16)) >> 16;
}

/* ---- Inline string helpers ---- */

static inline size_t w_inline_str_len(WValue v) {
    return (size_t)((v >> 1) & 7);
}

/* Extract inline string bytes into buf (must be at least 6 bytes).
   NUL-terminates. Returns length. */
static inline size_t w_inline_str_extract(WValue v, char *buf) {
    size_t len = w_inline_str_len(v);
    for (size_t i = 0; i < len; i++) {
        buf[i] = (char)((v >> (4 + 8 * i)) & 0xFF);
    }
    buf[len] = '\0';
    return len;
}

/* Extract heap string pointer */
static inline struct WString *w_as_heap_str(WValue v) {
    return (struct WString *)(uintptr_t)(v & 0x0000FFFFFFFFFFF0ULL);
}

/* ==== Truthiness ==== */

/* Only nil and false are falsy. Everything else — 0, 0.0, "", [] — is truthy.
   Compiles to a single unsigned compare.
   Runtime version in runtime.h returns int64_t for codegen compat. */
#ifndef TUNGSTEN_RUNTIME_H
static inline int w_truthy(WValue v) {
    return v > W_FALSE;  /* v > 1 (unsigned) */
}
#endif

/* ==== Lexical tag (0xFFFC) — 2-bit subtype ==== */

/* 0xFFFC holds four subtypes via bits 47-46:
   00: Token   — lex-time token descriptor (offset into LexBuffer)
   01: LexChar — lexer-optimized character with classification flags
   10: Slice   — zero-copy buffer reference (lex-time and runtime)
   11: Char    — runtime character with full Unicode metadata */

#define W_TAG_LEXICAL  W_TAG_CHAR  /* alias for readability */
#define W_LEXICAL_TOKEN    0
#define W_LEXICAL_LEXCHAR  1
#define W_LEXICAL_SLICE    2
#define W_LEXICAL_CHAR     3

static inline int w_lexical_subtype(WValue v) { return (int)((v >> 46) & 0x3); }

/* ---- Token (subtype 00) ----
   bits 45-38: type   (8 bits, 256 token classes — refined by materialize)
   bits 37-26: length (12 bits, max 4095 bytes per token)
   bits 25-2:  offset (24 bits, max 16MB)
   bit  1:     reserved
   bit  0:     f_line_start (LSB fast-test: this token starts a line)

   The 4-bit `flags` nibble of the original layout was widened into the
   type field. f_sp_before / f_sp_after were dropped because the SIMD
   lexer now emits explicit :SP tokens between non-whitespace tokens;
   the parser can detect whitespace adjacency by checking for an :SP
   token rather than reading a flag bit. */

static inline WValue w_box_token(int flags, int type, int length, int offset) {
    return W_TAG_CHAR | /* subtype 00 implicit */
           (((uint64_t)type & 0xFF) << 38) |
           (((uint64_t)length & 0xFFF) << 26) |
           (((uint64_t)offset & 0xFFFFFF) << 2) |
           ((uint64_t)flags & 0x1);
}
static inline int w_unbox_token_offset(WValue v) { return (int)((v >> 2) & 0xFFFFFF); }
static inline int w_unbox_token_length(WValue v) { return (int)((v >> 26) & 0xFFF); }
static inline int w_unbox_token_type(WValue v)   { return (int)((v >> 38) & 0xFF); }
static inline int w_unbox_token_flags(WValue v)  { return (int)(v & 0x1); }

/* ---- Token Wide compatibility helpers (subtype 00, no flags) ---- */

static inline WValue w_box_token_wide(int type, int length, int offset) {
    return w_box_token(0, type, length, offset);
}
static inline int w_unbox_token_wide_offset(WValue v) { return w_unbox_token_offset(v); }
static inline int w_unbox_token_wide_length(WValue v) { return w_unbox_token_length(v); }
static inline int w_unbox_token_wide_type(WValue v)   { return w_unbox_token_type(v); }

/* ---- LexChar (subtype 01) ----
   bits 45-39: free (7 bits)
   bits 38-18: codepoint (21 bits)
   bits 17-16: utf8_len - 1 (2 bits)
   bits 15-11: category (5 bits)
   bits 10-7:  digit_value (4 bits)
   bits 6-0:   lex_flags (7 bits) — hot-path classification at LSB */

static inline WValue w_box_lexchar(uint32_t codepoint, int utf8_len, int category,
                                    int digit_val, int lex_flags) {
    return W_TAG_CHAR | (1ULL << 46) |
           (((uint64_t)codepoint & 0x1FFFFF) << 18) |
           (((uint64_t)(utf8_len - 1) & 0x3) << 16) |
           (((uint64_t)category & 0x1F) << 11) |
           (((uint64_t)digit_val & 0xF) << 7) |
           ((uint64_t)lex_flags & 0x7F);
}
static inline uint32_t w_lexchar_codepoint(WValue v) { return (uint32_t)((v >> 18) & 0x1FFFFF); }
static inline int w_lexchar_lex_flags(WValue v)      { return (int)(v & 0x7F); }

/* LexChar flag bit positions (at LSB for single-instruction test) */
#define W_LEXFLAG_MAY_COMBINE  (1 << 0)
#define W_LEXFLAG_IS_QUOTE     (1 << 1)
#define W_LEXFLAG_IS_OPERATOR  (1 << 2)
#define W_LEXFLAG_IS_HEX       (1 << 3)
#define W_LEXFLAG_IS_WHITESPACE (1 << 4)
#define W_LEXFLAG_IS_ID_CONTINUE (1 << 5)
#define W_LEXFLAG_IS_ID_START    (1 << 6)

/* ---- Slice (subtype 10) ----
   bits 45-38: free (8 bits)
   bits 37-24: length (14 bits, max 16383 bytes)
   bits 23-0:  offset (24 bits, max 16MB) */

static inline WValue w_box_slice(int length, int offset) {
    return W_TAG_CHAR | (2ULL << 46) |
           (((uint64_t)length & 0x3FFF) << 24) | ((uint64_t)offset & 0xFFFFFF);
}
static inline int w_unbox_slice_offset(WValue v) { return (int)(v & 0xFFFFFF); }
static inline int w_unbox_slice_length(WValue v) { return (int)((v >> 24) & 0x3FFF); }

/* ---- Char (subtype 11) — runtime character ----
   Codepoint at LSB for cheap ASCII extraction: (v & 0x7F).
   bits 45:    emoji
   bits 44:    ascii
   bits 43:    printable
   bits 42-39: digit_value (4 bits, 0xF = not-a-digit)
   bits 38-30: case_delta (9 bits signed)
   bits 29-28: width (2 bits)
   bits 27-23: category (5 bits)
   bits 22-21: utf8_len - 1 (2 bits)
   bits 20-0:  codepoint (21 bits) */

enum WCharCategory {
    W_CAT_LU = 0, W_CAT_LL, W_CAT_LT, W_CAT_LM, W_CAT_LO,
    W_CAT_ND, W_CAT_NL, W_CAT_NO,
    W_CAT_ZS, W_CAT_ZL, W_CAT_ZP,
    W_CAT_MN, W_CAT_MC, W_CAT_ME,
    W_CAT_PC, W_CAT_PD, W_CAT_PS, W_CAT_PE, W_CAT_PI, W_CAT_PF, W_CAT_PO,
    W_CAT_SM, W_CAT_SC, W_CAT_SK, W_CAT_SO,
    W_CAT_CC, W_CAT_CF, W_CAT_CS, W_CAT_CO, W_CAT_CN,
};

/* Char (subtype 11) layout — codepoint in the HIGH bits so raw WValue compare
   orders by codepoint; \d\w\s at the LSB for a single-mask test. See w_box_char.
   [cp 25-45][emoji 24][printable 23][digit_value 19-22][case_delta 10-18]
   [width 8-9][category 3-7][\s 2][\w 1][\d 0] */
static inline uint32_t w_char_codepoint(WValue v) {
    return (uint32_t)((v >> 25) & 0x1FFFFF);
}

/* utf8_len + ascii are derived from the codepoint now (no longer stored). */
static inline int w_char_utf8_len(WValue v) {
    uint32_t cp = w_char_codepoint(v);
    return cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
}

static inline int w_char_category(WValue v) {
    return (int)((v >> 3) & 0x1F);
}

static inline int w_char_width(WValue v) {
    return (int)((v >> 8) & 0x3);
}

static inline int w_char_case_delta(WValue v) {
    return ((int16_t)(((v >> 10) & 0x1FF) << 7)) >> 7;
}

static inline int w_char_digit_value(WValue v) {
    int d = (int)((v >> 19) & 0xF);
    return d == 0xF ? -1 : d;
}

/* Direct flag accessors */
static inline int w_char_is_printable(WValue v) { return (int)((v >> 23) & 1); }
static inline int w_char_is_ascii(WValue v)     { return w_char_codepoint(v) < 0x80; }
static inline int w_char_is_emoji(WValue v)     { return (int)((v >> 24) & 1); }
/* Regex class flags (LSB, single-mask) */
static inline int w_char_re_digit(WValue v)     { return (int)(v & 1); }
static inline int w_char_re_word(WValue v)      { return (int)((v >> 1) & 1); }
static inline int w_char_re_space(WValue v)     { return (int)((v >> 2) & 1); }

/* is_upper dropped as separate flag — derived from category */
static inline int w_char_is_upper(WValue v)     { return w_char_category(v) == W_CAT_LU; }

/* Derived checks */
static inline int w_char_is_combining(WValue v) {
    int cat = w_char_category(v);
    return cat >= W_CAT_MN && cat <= W_CAT_ME;
}
static inline int w_char_is_letter(WValue v)     { return w_char_category(v) <= W_CAT_LO; }
static inline int w_char_is_lower(WValue v)      { return w_char_category(v) == W_CAT_LL; }
static inline int w_char_is_digit(WValue v)      { return w_char_category(v) == W_CAT_ND; }
static inline int w_char_is_whitespace(WValue v) {
    int cat = w_char_category(v);
    return cat >= W_CAT_ZS && cat <= W_CAT_ZP;
}

#endif /* WVALUE_H */
