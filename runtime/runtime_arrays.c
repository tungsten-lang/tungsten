#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef __aarch64__
#include <arm_neon.h>
#endif
#define die w_rt_die
#define dief w_rt_dief
#define die_as w_rt_die_as
#define w_raise_error_named w_rt_raise_error_named
#define as_str w_rt_as_str
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#define w_string_ascii_p w_rt_string_ascii_p
#define w_string_compare w_rt_string_compare
#define w_utf8_index_width w_rt_utf8_index_width
#define w_allocprof w_rt_allocprof
#define w_arr_park (*w_rt_arr_park_ptr())
#define as_numeric_double w_rt_as_numeric_double
#define cmp_numeric_double w_rt_cmp_numeric_double
#define w_math_to_double w_rt_math_to_double
#define is_quantity_any w_rt_is_quantity_any
#define bn_pool_run_tasks w_rt_bn_pool_run_tasks
#define w_hash_key_eq w_rt_hash_key_eq
#define w_hash_value_fast w_rt_hash_value_fast
#define w_ic_string_size w_rt_ic_string_size
#define w_method_dispatch w_rt_method_dispatch
#define w_value_compare w_rt_value_compare
#define BN_POOL_TASKS_MAX 16
#define BN_TOOM_POOL_SPIN 32768
#endif

/* ---- Typed Array — packed integer array or float array ----
 * WTypedArray was merged into WArray. These helpers take WArray *
 * and cast `slots` to uint8_t * (or wider) per ebits for the packed reads.
 * The polymorphic w64 case (ebits=65) still uses the WValue-major access
 * pattern through casting, since WArray.slots is declared `WValue *`. */


static inline int array_ebits_valid(int64_t bits) {
    switch (bits) {
        case 1:
        case 4:
        case -4:
        case 8:
        case 108:
        case 16:
        case 116:
        case 32:
        case 33:
        case 64:
        case 65:
        case 66:
        case -16:
        case -32:
        case -64:
        case -104:
        case -108:
        case -109:
        case -116:
            return 1;
        default:
            return 0;
    }
}

/* Public, non-inline wrapper so other translation units (metal.m) can size a
 * typed element without duplicating the ebits→bits table. */
int64_t w_array_storage_bits(int64_t bits) {
    return array_storage_bits(bits);
}


/* w64 polymorphic arrays store raw WValue bits in 64-bit slots. Push/pop/
 * shift skip the w_as_int / w_int conversions used for integer arrays. */
static inline int array_is_wvalue(const WArray *a) {
    return a->ebits == 65;
}

static inline int64_t array_byte_size(int64_t bits, int64_t count) {
    bits = array_storage_bits(bits);
    if (bits == 1) return (count + 7) / 8;
    if (bits == 4) return (count + 1) / 2;
    return count * (bits / 8);
}

/* Capacity policy for append/unshift growth. Arrays below 16K elements double
 * so compiler-sized and ordinary application arrays keep their low allocation
 * count. Beyond that, 1.25x substantially reduces retained slack for arrays
 * whose final size is not a power of two. The 16K knee came from the full
 * threshold sweep in bench_array_growth plus the production-path A/B; the
 * benchmark override keeps the alternatives reproducible via
 * `make -C runtime bench-array-push-ab`. */
#ifndef W_ARRAY_QUARTER_GROWTH
#define W_ARRAY_QUARTER_GROWTH 1
#endif
#ifndef W_ARRAY_QUARTER_GROWTH_THRESHOLD
#define W_ARRAY_QUARTER_GROWTH_THRESHOLD 16384
#endif
#ifndef W_ARRAY_GROWTH_NUMERATOR
#define W_ARRAY_GROWTH_NUMERATOR 5
#endif
#ifndef W_ARRAY_GROWTH_DENOMINATOR
#define W_ARRAY_GROWTH_DENOMINATOR 4
#endif
static inline int32_t array_next_capacity(int32_t cap) {
    if (cap <= 0) return 8;
    if (cap >= INT32_MAX)
        w_raise(w_string("typed array capacity exceeds INT32_MAX — use BigArray"));
    int64_t next;
#if W_ARRAY_QUARTER_GROWTH
    if (cap < W_ARRAY_QUARTER_GROWTH_THRESHOLD)
        next = (int64_t)cap * 2;
    else {
        int64_t extra_numerator =
            W_ARRAY_GROWTH_NUMERATOR - W_ARRAY_GROWTH_DENOMINATOR;
        next = (int64_t)cap +
               ((int64_t)cap * extra_numerator +
                W_ARRAY_GROWTH_DENOMINATOR - 1) /
               W_ARRAY_GROWTH_DENOMINATOR;
    }
#else
    next = (int64_t)cap * 2;
#endif
    if (next > INT32_MAX) next = INT32_MAX;
    return (int32_t)next;
}

static size_t array_page_allocation_size(int64_t bits, int64_t count) {
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) page = 4096;
    size_t bytes = (size_t)array_byte_size(bits, count);
    return (bytes + (size_t)page - 1) & ~((size_t)page - 1);
}

static void array_release_slots(WValue *slots, int64_t bits, int64_t cap,
                                uint8_t flags) {
    if (slots == NULL || (flags & W_FLAG_OWNED) == 0 ||
        (flags & (W_FLAG_VIEW | W_FLAG_INLINE)))
        return;
    if (flags & W_FLAG_PAGE_ALIGNED) {
        munmap(slots, array_page_allocation_size(bits, cap));
    } else {
        free(slots);
    }
}

static inline uint64_t array_read(WArray *a, int64_t i) {
    uint8_t *bytes = (uint8_t *)a->slots;
    switch (array_storage_bits(a->ebits)) {
        case 1:  return (bytes[i >> 3] >> (i & 7)) & 1;
        case 4:  { uint8_t b = bytes[i >> 1]; return (i & 1) ? (b >> 4) : (b & 0xF); }
        case 8:  return bytes[i];
        case 16: return ((uint16_t *)bytes)[i];
        case 32: return ((uint32_t *)bytes)[i];
        case 64: return ((uint64_t *)bytes)[i];
        default: return 0;
    }
}

static inline void array_write(WArray *a, int64_t i, uint64_t val) {
    uint8_t *bytes = (uint8_t *)a->slots;
    switch (array_storage_bits(a->ebits)) {
        case 1:  { uint8_t mask = (uint8_t)(1u << (i & 7));
                   if (val & 1) bytes[i >> 3] |=  mask;
                   else         bytes[i >> 3] &= (uint8_t)~mask; }
                 break;
        case 4:  if (i & 1) bytes[i >> 1] = (bytes[i >> 1] & 0x0F) | ((uint8_t)(val & 0xF) << 4);
                 else       bytes[i >> 1] = (bytes[i >> 1] & 0xF0) | (uint8_t)(val & 0xF);
                 break;
        case 8:  bytes[i] = (uint8_t)val; break;
        case 16: ((uint16_t *)bytes)[i] = (uint16_t)val; break;
        case 32: ((uint32_t *)bytes)[i] = (uint32_t)val; break;
        case 64: ((uint64_t *)bytes)[i] = val; break;
    }
}

/* IEEE half (f16, ebits -16) <-> float. On aarch64 the __fp16 cast is a
 * single fcvt; elsewhere a portable RNE bit implementation keeps the same
 * results. Both directions round-trip through f32 (as bf16 does) so all
 * platforms agree on double-rounding edge cases. */
static inline float w_half_bits_to_float(uint16_t h) {
#if defined(__aarch64__)
    __fp16 hv;
    memcpy(&hv, &h, sizeof(hv));
    return (float)hv;
#else
    uint32_t sign = (uint32_t)(h & 0x8000u) << 16;
    uint32_t exp = (h >> 10) & 0x1Fu;
    uint32_t man = h & 0x3FFu;
    uint32_t bits;
    if (exp == 0) {
        if (man == 0) {
            bits = sign;
        } else {
            int shift = 0;
            while ((man & 0x400u) == 0) {
                man <<= 1;
                shift++;
            }
            man &= 0x3FFu;
            bits = sign | ((uint32_t)(113 - shift) << 23) | (man << 13);
        }
    } else if (exp == 0x1Fu) {
        bits = sign | 0x7F800000u | (man << 13);
    } else {
        bits = sign | ((exp + 112u) << 23) | (man << 13);
    }
    float f;
    memcpy(&f, &bits, sizeof(f));
    return f;
#endif
}

static inline uint16_t w_half_bits_from_float(float f) {
#if defined(__aarch64__)
    __fp16 hv = (__fp16)f;
    uint16_t h;
    memcpy(&h, &hv, sizeof(h));
    return h;
#else
    uint32_t bits;
    memcpy(&bits, &f, sizeof(bits));
    uint32_t sign = (bits >> 16) & 0x8000u;
    uint32_t fexp = (bits >> 23) & 0xFFu;
    uint32_t man = bits & 0x7FFFFFu;
    if (fexp == 0xFFu)
        return (uint16_t)(sign | 0x7C00u | (man ? (0x200u | (man >> 13)) : 0));
    int32_t exp = (int32_t)fexp - 112;
    if (exp >= 0x1F) return (uint16_t)(sign | 0x7C00u);
    if (exp <= 0) {
        if (exp < -10) return (uint16_t)sign;
        man |= 0x800000u;
        uint32_t shift = (uint32_t)(14 - exp);
        uint32_t out = man >> shift;
        uint32_t rem = man & ((1u << shift) - 1u);
        uint32_t halfway = 1u << (shift - 1);
        if (rem > halfway || (rem == halfway && (out & 1u))) out++;
        return (uint16_t)(sign | out);
    }
    uint32_t out = ((uint32_t)exp << 10) | (man >> 13);
    uint32_t rem = man & 0x1FFFu;
    if (rem > 0x1000u || (rem == 0x1000u && (out & 1u))) out++;
    return (uint16_t)(sign | out);
#endif
}

static inline double array_read_float(WArray *a, int64_t i) {
    uint8_t *bytes = (uint8_t *)a->slots;
    if (a->ebits == -32) return (double)((float *)bytes)[i];
    if (a->ebits == -116) {
        uint32_t bits = (uint32_t)((uint16_t *)bytes)[i] << 16;
        float f;
        memcpy(&f, &bits, sizeof(float));
        return (double)f;
    }
    if (a->ebits == -16) return (double)w_half_bits_to_float(((uint16_t *)bytes)[i]);
    return ((double *)bytes)[i];
}

static inline int64_t array_read_signed(WArray *a, int64_t i);

/* Load element at logical index `i` (relative to start),
 * decoded into a WValue per the array's ebits. After the W_SUBTAG_ARRAY
 * merge, dispatch iterators (each/map/etc.) can no longer read slots[i]
 * as raw WValues — for u8/u16/u32/u64/f32/f64 arrays the bytes are packed
 * and need ebits-aware extraction + boxing. Polymorphic w64 (ebits==65)
 * keeps the fast-path: slots[i] IS the WValue. Non-inline so it's reachable
 * via forward declaration from w_method_dispatch up the file. */
static WValue array_slot_load_decoded(WArray *a, int64_t i) {
    int64_t abs_idx = a->start + i;
    if (__builtin_expect(a->ebits == 65, 1)) {
        return a->slots[abs_idx];
    }
    if (array_is_float(a)) {
        return w_float(array_read_float(a, abs_idx));
    }
    if (array_is_signed_int(a)) {
        return w_int(array_read_signed(a, abs_idx));
    }
    /* ebits=1 (BoolArray) yields W_TRUE/W_FALSE so iteration
     * matches user expectation that bools, not ints, come out. */
    if (a->ebits == 1) {
        return array_read(a, abs_idx) ? W_TRUE : W_FALSE;
    }
    /* Unsigned 64-bit elements may exceed INT64_MAX and the immediate i48
     * payload.  Converting through int64_t makes u64::MAX indistinguishable
     * from -1; retain the full unsigned value in a WBigint instead.  Narrower
     * unsigned element widths still fit w_int's signed input exactly. */
    uint64_t raw = array_read(a, abs_idx);
    if (a->ebits == 64 && raw > INT64_MAX) {
        return w_u64(raw);
    }
    return w_int((int64_t)raw);
}

static inline void array_write_float(WArray *a, int64_t i, double val) {
    uint8_t *bytes = (uint8_t *)a->slots;
    if (a->ebits == -32) {
        ((float *)bytes)[i] = (float)val;
        return;
    }
    if (a->ebits == -116) {
        float f = (float)val;
        uint32_t bits;
        memcpy(&bits, &f, sizeof(uint32_t));
        bits += 0x7FFFu + ((bits >> 16) & 1u);
        ((uint16_t *)bytes)[i] = (uint16_t)(bits >> 16);
        return;
    }
    if (a->ebits == -16) {
        ((uint16_t *)bytes)[i] = w_half_bits_from_float((float)val);
        return;
    }
    ((double *)bytes)[i] = val;
}

static inline void array_write_boxed(WArray *a, int64_t i, WValue val) {
    if (__builtin_expect(a->ebits == 65, 1)) {
        a->slots[i] = val;
    } else if (array_is_float(a)) {
        array_write_float(a, i, as_numeric_double(val));
    } else if (a->ebits == 1) {
        array_write(a, i, (val == W_NIL || val == W_FALSE) ? 0 : 1);
    } else {
        array_write(a, i, (uint64_t)w_to_i64(val));
    }
}

WValue w_array_new(int64_t element_bits, int64_t cap) {
    if (cap > INT32_MAX) {
        w_raise(w_string("typed array: cap exceeds INT32_MAX — use BigArray for >2^31 elements"));
    }
    int32_t actual_cap = (int32_t)(cap > 0 ? cap : 8);
    int64_t byte_size = array_byte_size(element_bits, actual_cap);
    WArray *a = w_arr_park;
    if (a != NULL) {
        w_arr_park = NULL;
        if (a->ebits == (int8_t)element_bits && a->cap == actual_cap) {
            a->flags = W_FLAG_OWNED;
            a->_pad[0] = 0;
            a->gc_flags = 0;
            a->start = 0;
            a->size = 0;
            memset(a->slots, 0, (size_t)byte_size);
            w_gc_on_array(a, sizeof(WArray) + (size_t)byte_size);
            return w_box_array(a);
        }
        free(a->slots);
        free(a);
    }
    w_allocprof(W_ALLOCPROF_ARR, byte_size);
    a = calloc(1, sizeof(WArray));
    a->flags = W_FLAG_OWNED;
    a->ebits = (int8_t)element_bits;
    a->start = 0;
    a->size = 0;
    a->cap = actual_cap;
    a->slots = calloc(1, (size_t)byte_size);
    w_gc_on_array(a, sizeof(WArray) + (size_t)byte_size);
    return w_box_array(a);
}

WValue w_array_new_uninit(int64_t element_bits, int64_t cap) {
    if (cap > INT32_MAX) {
        w_raise(w_string("typed array: cap exceeds INT32_MAX — use BigArray for >2^31 elements"));
    }
    int32_t actual_cap = (int32_t)(cap > 0 ? cap : 8);
    WArray *a = w_arr_park;
    if (a != NULL) {
        w_arr_park = NULL;
        if (a->ebits == (int8_t)element_bits && a->cap == actual_cap) {
            a->flags = W_FLAG_OWNED;
            a->_pad[0] = 0;
            a->gc_flags = 0;
            a->start = 0;
            a->size = 0;
            w_gc_on_array(a, sizeof(WArray) + (size_t)array_byte_size(element_bits, actual_cap));
            return w_box_array(a);
        }
        free(a->slots);
        free(a);
    }
    int64_t bsz = array_byte_size(element_bits, actual_cap);
    w_allocprof(W_ALLOCPROF_ARR, bsz);
    a = calloc(1, sizeof(WArray));   /* header stays zeroed (cheap, fixed size) */
    a->flags = W_FLAG_OWNED;
    a->ebits = (int8_t)element_bits;
    a->start = 0;
    a->size = 0;
    a->cap = actual_cap;
    a->slots = malloc((size_t)bsz);
    if (element_bits == 65 && bsz > 0) memset(a->slots, 0, (size_t)bsz);
    w_gc_on_array(a, sizeof(WArray) + (size_t)bsz);
    return w_box_array(a);
}

WValue w_array_new_inline(int64_t element_bits, int64_t n) {
    if (n < 0 || n > INT32_MAX) {
        w_raise(w_string("typed array: size exceeds INT32_MAX — use BigArray for >2^31 elements"));
    }
    int64_t cap = n > 0 ? n : 8;
    size_t payload = (size_t)array_byte_size(element_bits, cap);
#ifndef W_ARRAY_INLINE_MAX_PAYLOAD
#if defined(__APPLE__)
#define W_ARRAY_INLINE_MAX_PAYLOAD (16u * 1024u)
#else
#define W_ARRAY_INLINE_MAX_PAYLOAD SIZE_MAX
#endif
#endif
    if (payload > W_ARRAY_INLINE_MAX_PAYLOAD) {
        WValue value = w_array_new_uninit(element_bits, cap);
        w_as_array(value)->size = (int32_t)n;
        return value;
    }
    w_allocprof(W_ALLOCPROF_ARR, (long long)payload);
    size_t slot_offset = (sizeof(WArray) + 15u) & ~(size_t)15u;
    WArray *a = malloc(slot_offset + payload);
    memset(a, 0, sizeof(WArray));
    a->flags = W_FLAG_OWNED | W_FLAG_INLINE;
    a->ebits = (int8_t)element_bits;
    a->start = 0;
    a->size = (int32_t)n;
    a->cap = (int32_t)cap;
    a->slots = (WValue *)((uint8_t *)a + slot_offset);
    if (__builtin_expect(g_gc_track && element_bits == 65 && payload > 0, 0)) {
        memset(a->slots, 0, payload);
    }
    w_gc_on_array(a, slot_offset + payload);
    return w_box_array(a);
}

/* One-generation bootstrap ABI: an already-built stage compiler still emits
 * the former internal spelling while it compiles the stage containing the
 * shorter name. New lowering never references this wrapper. */
WValue w_array_new_inline_uninit_sized(int64_t element_bits, int64_t n) {
    return w_array_new_inline(element_bits, n);
}

/* Typed-array parameter guard for the native-fn boundary.
 *
 * A top-level fn declared `-> f(a) (i64[]) i64` compiles its body against an
 * 8-byte element stride, but the argument crosses as a bare WValue handle —
 * LLVM sees `i64` either way. When the caller's element type is statically
 * known, lowering rejects a mismatch outright (E_LOWER_TYPED_ARG_MISMATCH).
 * When it is NOT known (the array arrived from an untyped fn return, a
 * collection, or a block), nothing before this guard notices that the callee
 * is about to stride 8 bytes through 4-byte slots — it writes past the end of
 * the allocation and corrupts whatever follows, with no crash at the call.
 *
 * Deliberately permissive: only a genuine STORAGE-WIDTH mismatch, or mixing a
 * polymorphic w64 array with a typed one, is rejected. Same-width differences
 * (u64[] vs i64[], f32[] vs u32[]) reinterpret bits but keep the stride, so
 * they stay legal and cost nothing here.
 *
 * want_bits is the declared element's storage width in bits; want_poly is 1
 * when the declaration is the polymorphic w64 tier. `site_v` is a WValue
 * String the compiler pre-builds naming the function, the parameter and the
 * declared type — assembling it here would mean decoding NaN-boxed strings,
 * which inline-mode Strings have no stable pointer for. Anything that is not
 * one of the three array tiers passes through untouched: this guard is about
 * element width, not about type-checking the handle. */

/* The callee body indexes a WArray: a W_TAG_ARRAY box over the i32
 * start/size header with `slots` at offset 16. A BigArray (the i64-field tier
 * that Mmap#as_u8 and the other mmap views return) is boxed and laid out
 * differently, so passing one straight through made the callee read its header
 * as a WArray and segfault. Hand the callee a zero-copy WArray view of the same
 * elements instead: writes reach the BigArray's storage, and push/grow on the
 * view raise as on any view. Views are cached per thread by source, so a loop
 * passing the same BigArray allocates one header; every hit refreshes it,
 * since an owned BigArray may have grown or moved since. An evicted view is
 * left alive (the callee may have kept it). */
#define W_PARAM_VIEW_CACHE 16
static __thread struct { WBigArray *src; WArray *view; }
    w_param_view_cache[W_PARAM_VIEW_CACHE];

static WValue w_big_array_param_view(WValue arr, WValue site_v) {
    WBigArray *b = (WBigArray *)w_as_ptr(arr);
    if (b->start < 0 || b->size < 0 || b->start > INT32_MAX ||
        b->size > (int64_t)INT32_MAX - b->start) {
        w_raise(w_str_concat(site_v, w_string(
            ", but received a BigArray with more than INT32_MAX elements, "
            "which a typed-array parameter cannot view")));
    }
    size_t h = ((uintptr_t)b >> 4) & (W_PARAM_VIEW_CACHE - 1);
    WArray *a = w_param_view_cache[h].src == b ? w_param_view_cache[h].view : NULL;
    if (!a) {
        a = calloc(1, sizeof(WArray));
        w_param_view_cache[h].src = b;
        w_param_view_cache[h].view = a;
    }
    a->flags = W_FLAG_VIEW;
    a->ebits = (int8_t)b->ebits;
    a->start = (int32_t)b->start;
    a->size = (int32_t)b->size;
    a->cap = (int32_t)(b->start + b->size);
    a->slots = (WValue *)b->slots;
    return w_box_array(a);
}

static __attribute__((noinline)) WValue w_check_array_ebits_slow(WValue arr, int64_t want_bits, int64_t want_poly,
                           WValue site_v) {
    int64_t got_ebits;
    if (w_is_array(arr)) {
        got_ebits = (int64_t)(w_as_array(arr))->ebits;
    } else if (w_is_small_array(arr)) {
        got_ebits = (int64_t)((WSmallArray *)w_as_ptr(arr))->ebits;
    } else if (w_is_big_array(arr)) {
        /* WBigArray keeps the signed ebits code in a uint8_t (f64's -64 is
         * stored as 192); read it back the way WArray's int8_t holds it. */
        got_ebits = (int64_t)(int8_t)((WBigArray *)w_as_ptr(arr))->ebits;
    } else {
        return arr;
    }
    int got_poly = (got_ebits == 65);
    int64_t got_bits = array_storage_bits(got_ebits);
    if (got_poly == (want_poly != 0) && got_bits == want_bits) {
        if (w_is_big_array(arr)) return w_big_array_param_view(arr, site_v);
        return arr;
    }

    char tail[224];
    if (got_poly) {
        snprintf(tail, sizeof(tail),
                 ", but received a polymorphic Array — w64 slots hold boxed "
                 "WValues, not raw %lld-bit elements",
                 (long long)want_bits);
    } else if (want_poly) {
        snprintf(tail, sizeof(tail),
                 ", but received a typed array with %lld-bit elements",
                 (long long)got_bits);
    } else {
        snprintf(tail, sizeof(tail),
                 ", but received one with %lld-bit elements — the callee would "
                 "stride %lld bytes through %lld-byte slots and write past the "
                 "end of the allocation",
                 (long long)got_bits, (long long)(want_bits / 8),
                 (long long)(got_bits / 8));
    }
    w_raise(w_str_concat(site_v, w_string(tail)));
    return arr;
}

/* Ordinary WArray arguments are overwhelmingly the common boundary case.
 * Keep success leaf-sized: diagnostic formatting and BigArray-view creation
 * belong to the cold path and must not impose their stack frame per argument. */
WValue w_check_array_ebits(WValue arr, int64_t want_bits, int64_t want_poly,
                           WValue site_v) {
    if (w_is_array(arr)) {
        /* Canonical valid ebits codes, indexed as an unsigned byte.  Bit 7
         * distinguishes boxed WValues from raw 64-bit storage.  Unknown
         * codes retain the complete compatibility check in the slow path. */
        static const uint8_t widths[256] = {
            [1] = 1, [4] = 4, [(uint8_t)-4] = 4,
            [8] = 8, [108] = 8, [16] = 16, [116] = 16,
            [32] = 32, [33] = 32, [64] = 64, [66] = 64,
            [65] = 128 | 64,
            [(uint8_t)-16] = 16, [(uint8_t)-32] = 32,
            [(uint8_t)-64] = 64, [(uint8_t)-116] = 16,
            [(uint8_t)-108] = 8, [(uint8_t)-109] = 8,
            [(uint8_t)-104] = 4
        };
        unsigned code = widths[(uint8_t)w_as_array(arr)->ebits];
        if (code && (code & 127) == want_bits &&
            (code >> 7) == (want_poly != 0))
            return arr;
    }
    return w_check_array_ebits_slow(arr, want_bits, want_poly, site_v);
}

/* (#68) page-aligned typed-array allocation. Required for the
 * Metal noCopy buffer wrap (`newBufferWithBytesNoCopy:`) to actually
 * succeed — Apple's API rejects non-page-aligned pointers and our
 * default calloc-backed slots are only 16-byte aligned. mmap is the
 * cleanest portable path: kernel hands back a page-aligned region
 * that's zero-initialized for free.
 *
 * size = cap = N (no growth — these are sized-to-fit GPU-side buffers
 * where the user fills via `arr[i] =`, not `.push`). If the user does
 * push beyond cap, the standard grow path realloc()s into a fresh
 * heap block, breaking GPU binding — the runtime can't detect this
 * silently, so it's a known sharp edge until lifetime guards land. */
WValue w_array_new_aligned(WValue element_bits_v, WValue size_v) {
    int64_t element_bits = w_as_int(element_bits_v);
    int64_t size = w_as_int(size_v);
    if (size > INT32_MAX) {
        w_raise(w_string("aligned typed array: size exceeds INT32_MAX"));
    }
    if (size <= 0) {
        w_raise(w_string("aligned typed array: size must be positive"));
    }
    int64_t byte_size = array_byte_size(element_bits, size);
    if (byte_size <= 0) {
        w_raise(w_string("aligned typed array: zero-byte allocation"));
    }
    /* Round up to page size — mmap requires page-multiple length too. */
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) page = 4096;
    int64_t alloc_size = (byte_size + page - 1) & ~(page - 1);
    w_allocprof(W_ALLOCPROF_ALIGNED, alloc_size);
    void *base = mmap(NULL, (size_t)alloc_size,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == MAP_FAILED) {
        w_raise(w_string("aligned typed array: mmap failed"));
    }
    WArray *a = calloc(1, sizeof(WArray));
    a->flags = W_FLAG_OWNED | W_FLAG_PAGE_ALIGNED;
    a->ebits = (int8_t)element_bits;
    a->start = 0;
    a->size = (int32_t)size;
    a->cap = (int32_t)size;
    a->slots = (WValue *)base;
    w_gc_on_array(a, sizeof(WArray) + (size_t)alloc_size);
    return w_box_array(a);
}



WValue w_array_view_raw(uint8_t *data, int64_t element_bits, int64_t length) {
    if (length > INT32_MAX) {
        w_raise(w_string("typed array view: length exceeds INT32_MAX — use BigArray.view"));
    }
    WArray *a = calloc(1, sizeof(WArray));
    a->flags = W_FLAG_VIEW;     /* not owned — push/grow raises */
    a->ebits = (int8_t)element_bits;
    a->start = 0;
    a->size = (int32_t)length;
    a->cap = (int32_t)length;
    a->slots = (WValue *)data;
    w_gc_on_array(a, sizeof(WArray));
    return w_box_array(a);
}

WValue w_array_reuse_or_new(WValue *slot, int64_t element_bits, int64_t cap) {
    WValue v = *slot;
    if (v != W_NIL) {
        WArray *a = w_as_array(v);
        if (a->ebits == (int8_t)element_bits && a->cap >= cap) {
            a->_pad[0] = 0;
            a->start = 0;
            a->size = 0;
            return v;
        }
    }
    v = w_array_new(element_bits, cap);
    *slot = v;
    w_gc_register_reuse_slot(slot);
    return v;
}

static int w_array_has_views(WValue parent);
static void w_array_detach_view(WValue arr);

WValue w_array_push(WValue arr, WValue val) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        int32_t idx = a->start + a->size;
        if (__builtin_expect(a->ebits == 65 && idx < a->cap && (a->flags & W_FLAG_OWNED), 1)) {
            a->slots[idx] = val;
            a->size++;
            return arr;
        }
    }
    if (w_is_body(arr)) {
        w_raise_error_named("FrozenError", "push: cannot mutate an AST body reference (immutable once frozen)");
    }
    WArray *a = w_as_array(arr);
    if ((a->flags & W_FLAG_OWNED) == 0) {
        if ((a->flags & W_FLAG_VIEW) == 0)
            w_raise(w_string("typed array push: cannot grow a borrowed view"));
        w_array_detach_view(arr);
    }
    int64_t bits = array_storage_bits(a->ebits);
    if (a->start + a->size >= a->cap) {
        int has_views = w_array_has_views(arr);
        /* Compaction changes storage offsets. Keep them stable while a
         * zero-copy view exists; otherwise reclaim the deque prefix first. */
        if (a->start > 0 && !has_views) {
            if (bits >= 8) {
                int64_t live_bytes = array_byte_size(a->ebits, a->size);
                int64_t start_bytes = array_byte_size(a->ebits, a->start);
                memmove(a->slots, (uint8_t *)a->slots + start_bytes,
                        (size_t)live_bytes);
            } else {
                for (int64_t j = 0; j < a->size; j++) {
                    uint64_t value = array_read(a, a->start + j);
                    array_write(a, j, value);
                }
            }
            a->start = 0;
        }
        if (a->start + a->size >= a->cap) {
            int64_t new_cap = array_next_capacity(a->cap);
            size_t new_bytes = (size_t)array_byte_size(a->ebits, new_cap);
            WValue *old_slots = a->slots;
            int32_t old_cap = a->cap;
            uint8_t old_flags = a->flags;
            uint8_t *new_data;

            w_allocprof(W_ALLOCPROF_GROW, new_bytes);
            if (!has_views && !(old_flags & (W_FLAG_INLINE | W_FLAG_PAGE_ALIGNED))) {
                new_data = realloc(old_slots, new_bytes);
                if (!new_data) die("typed array realloc failed");
            } else {
                new_data = malloc(new_bytes);
                if (!new_data) die("typed array allocation failed");
                int64_t copy_count = has_views ? old_cap : a->size;
                memcpy(new_data, old_slots,
                       (size_t)array_byte_size(a->ebits, copy_count));
                a->slots = (WValue *)new_data;
                w_views_after_realloc(arr, old_slots, (WValue *)new_data);
                array_release_slots(old_slots, a->ebits, old_cap, old_flags);
            }
            a->slots = (WValue *)new_data;
            a->flags &= (uint8_t)~(W_FLAG_INLINE | W_FLAG_PAGE_ALIGNED);
            a->cap = (int32_t)new_cap;
        }
    }
    array_write_boxed(a, a->start + a->size, val);
    a->size++;
    return arr;
}

/* Elementwise dot-prefix operators — `.+ .- .* ./` lift their
 * scalar counterparts over a typed array. Lhs is always an array; rhs is
 * either an array (elementwise pair) or a scalar (broadcast). Returns a
 * NEW array with same ebits and size as lhs. Mismatched sizes raise.
 *
 * Dispatch by ebits flavor: WValue (w64), float (-32/-64), or integer
 * (4/8/16/32/64). The polymorphic w64 case treats both sides as boxed
 * WValues and runs the corresponding scalar binary op (w_add/w_sub/etc.)
 * on each pair — slow but correct fallback for `[1, 2.5, "three"] .+ 1`.
 *
 * A SIMD pass will rewrite the float and 32-bit-integer paths to use
 * NEON/AVX intrinsics. The scalar loops here are the correctness baseline
 * those vectorized variants will be measured against.
 */
typedef enum {
    ELT_OP_ADD, ELT_OP_SUB, ELT_OP_MUL, ELT_OP_DIV,
    ELT_OP_BOR, ELT_OP_BAND, ELT_OP_BXOR, ELT_OP_SHL, ELT_OP_SHR
} EltOp;

static inline double elt_apply_double(EltOp op, double a, double b) {
    switch (op) {
        case ELT_OP_ADD: return a + b;
        case ELT_OP_SUB: return a - b;
        case ELT_OP_MUL: return a * b;
        case ELT_OP_DIV: return b == 0.0 ? 0.0 : a / b;
        /* Bitwise / shift on float arrays: coerce both sides to int64,
         * apply, return as int (caller stores via array_write_float
         * which round-trips back to float). Matches NumPy's elementwise
         * bitwise behavior on float dtypes (raises) — but Tungsten is
         * permissive and lossy here. */
        case ELT_OP_BOR:  return (double)((int64_t)a | (int64_t)b);
        case ELT_OP_BAND: return (double)((int64_t)a & (int64_t)b);
        case ELT_OP_BXOR: return (double)((int64_t)a ^ (int64_t)b);
        case ELT_OP_SHL:  return (double)((int64_t)a << (int64_t)b);
        case ELT_OP_SHR:  return (double)((int64_t)a >> (int64_t)b);
    }
    return 0.0;
}
static inline int64_t elt_apply_int(EltOp op, int64_t a, int64_t b) {
    switch (op) {
        case ELT_OP_ADD:  return a + b;
        case ELT_OP_SUB:  return a - b;
        case ELT_OP_MUL:  return a * b;
        case ELT_OP_DIV:  return b == 0 ? 0 : a / b;
        case ELT_OP_BOR:  return a | b;
        case ELT_OP_BAND: return a & b;
        case ELT_OP_BXOR: return a ^ b;
        case ELT_OP_SHL:  return a << b;
        case ELT_OP_SHR:  return a >> b;
    }
    return 0;
}

static inline int elt_op_is_float_arith(EltOp op) {
    return op == ELT_OP_ADD || op == ELT_OP_SUB || op == ELT_OP_MUL || op == ELT_OP_DIV;
}

static inline float elt_apply_f32_scalar(EltOp op, float a, float b) {
    switch (op) {
        case ELT_OP_ADD: return a + b;
        case ELT_OP_SUB: return a - b;
        case ELT_OP_MUL: return a * b;
        case ELT_OP_DIV: return b == 0.0f ? 0.0f : a / b;
        default: return (float)elt_apply_double(op, (double)a, (double)b);
    }
}

static inline double elt_apply_f64_scalar(EltOp op, double a, double b) {
    switch (op) {
        case ELT_OP_ADD: return a + b;
        case ELT_OP_SUB: return a - b;
        case ELT_OP_MUL: return a * b;
        case ELT_OP_DIV: return b == 0.0 ? 0.0 : a / b;
        default: return elt_apply_double(op, a, b);
    }
}

#ifdef __aarch64__
static inline float32x4_t elt_apply_f32x4(EltOp op, float32x4_t a, float32x4_t b) {
    switch (op) {
        case ELT_OP_ADD: return vaddq_f32(a, b);
        case ELT_OP_SUB: return vsubq_f32(a, b);
        case ELT_OP_MUL: return vmulq_f32(a, b);
        case ELT_OP_DIV: {
            float32x4_t q = vdivq_f32(a, b);
            uint32x4_t z = vceqq_f32(b, vdupq_n_f32(0.0f));
            return vbslq_f32(z, vdupq_n_f32(0.0f), q);
        }
        default: return a;
    }
}

static inline float64x2_t elt_apply_f64x2(EltOp op, float64x2_t a, float64x2_t b) {
    switch (op) {
        case ELT_OP_ADD: return vaddq_f64(a, b);
        case ELT_OP_SUB: return vsubq_f64(a, b);
        case ELT_OP_MUL: return vmulq_f64(a, b);
        case ELT_OP_DIV: {
            float64x2_t q = vdivq_f64(a, b);
            uint64x2_t z = vceqq_f64(b, vdupq_n_f64(0.0));
            return vbslq_f64(z, vdupq_n_f64(0.0), q);
        }
        default: return a;
    }
}

static inline uint8x16_t elt_apply_u8x16(EltOp op, uint8x16_t a, uint8x16_t b) {
    switch (op) {
        case ELT_OP_ADD:  return vaddq_u8(a, b);
        case ELT_OP_SUB:  return vsubq_u8(a, b);
        case ELT_OP_MUL:  return vmulq_u8(a, b);
        case ELT_OP_BOR:  return vorrq_u8(a, b);
        case ELT_OP_BAND: return vandq_u8(a, b);
        case ELT_OP_BXOR: return veorq_u8(a, b);
        default: return a;
    }
}

/* i32 x4 NEON: add/sub/mul + bitwise. (No integer vector divide in NEON —
 * DIV stays on the scalar loop.) Signed and unsigned share the same
 * two's-complement add/sub/mul bit patterns, so one path serves i32/u32. */
static inline int32x4_t elt_apply_s32x4(EltOp op, int32x4_t a, int32x4_t b) {
    switch (op) {
        case ELT_OP_ADD:  return vaddq_s32(a, b);
        case ELT_OP_SUB:  return vsubq_s32(a, b);
        case ELT_OP_MUL:  return vmulq_s32(a, b);
        case ELT_OP_BOR:  return vorrq_s32(a, b);
        case ELT_OP_BAND: return vandq_s32(a, b);
        case ELT_OP_BXOR: return veorq_s32(a, b);
        default: return a;
    }
}

/* i64 x2 NEON: add/sub + bitwise are single instructions; there is no
 * vmulq_s64, so 64-bit multiply is done lane-wise (still vector load/store,
 * scalar multiply — avoids the header-reload overhead of the generic loop). */
static inline int64x2_t elt_apply_s64x2(EltOp op, int64x2_t a, int64x2_t b) {
    switch (op) {
        case ELT_OP_ADD:  return vaddq_s64(a, b);
        case ELT_OP_SUB:  return vsubq_s64(a, b);
        case ELT_OP_MUL: {
            int64_t a0 = vgetq_lane_s64(a, 0), a1 = vgetq_lane_s64(a, 1);
            int64_t b0 = vgetq_lane_s64(b, 0), b1 = vgetq_lane_s64(b, 1);
            int64x2_t r = vdupq_n_s64(a0 * b0);
            return vsetq_lane_s64(a1 * b1, r, 1);
        }
        case ELT_OP_BOR:  return vorrq_s64(a, b);
        case ELT_OP_BAND: return vandq_s64(a, b);
        case ELT_OP_BXOR: return veorq_s64(a, b);
        default: return a;
    }
}
#endif

/* Ops the i32/i64 NEON path handles (add/sub/mul + bitwise; not div/shift). */
static inline int elt_op_is_int_simd(EltOp op) {
    return op == ELT_OP_ADD || op == ELT_OP_SUB || op == ELT_OP_MUL ||
           op == ELT_OP_BOR || op == ELT_OP_BAND || op == ELT_OP_BXOR;
}

static inline int elt_op_is_i8_simd(EltOp op) {
    return op == ELT_OP_ADD || op == ELT_OP_SUB || op == ELT_OP_MUL ||
           op == ELT_OP_BOR || op == ELT_OP_BAND || op == ELT_OP_BXOR;
}

static int array_elementwise_i8_fast(WArray *la, WArray *ra, WArray *out,
                                     int rhs_is_array, int64_t scalar, EltOp op) {
    if ((la->ebits != 8 && la->ebits != 108) || !elt_op_is_i8_simd(op)) return 0;
    if (rhs_is_array && (ra == NULL || ra->ebits != la->ebits)) return 0;

    uint8_t *lp = (uint8_t *)la->slots + la->start;
    uint8_t *rp = rhs_is_array ? ((uint8_t *)ra->slots + ra->start) : NULL;
    uint8_t *dst = (uint8_t *)out->slots;
    uint8_t s = (uint8_t)scalar;
    int32_t i = 0;
    int32_t n = la->size;
#ifdef __aarch64__
    if (n >= 16) {
        uint8x16_t sv = vdupq_n_u8(s);
        int32_t end = n - 16;
        while (i <= end) {
            uint8x16_t a = vld1q_u8(lp + i);
            uint8x16_t b = rhs_is_array ? vld1q_u8(rp + i) : sv;
            vst1q_u8(dst + i, elt_apply_u8x16(op, a, b));
            i += 16;
        }
    }
#endif
    while (i < n) {
        uint8_t b = rhs_is_array ? rp[i] : s;
        switch (op) {
            case ELT_OP_ADD:  dst[i] = (uint8_t)(lp[i] + b); break;
            case ELT_OP_SUB:  dst[i] = (uint8_t)(lp[i] - b); break;
            case ELT_OP_MUL:  dst[i] = (uint8_t)(lp[i] * b); break;
            case ELT_OP_BOR:  dst[i] = (uint8_t)(lp[i] | b); break;
            case ELT_OP_BAND: dst[i] = (uint8_t)(lp[i] & b); break;
            case ELT_OP_BXOR: dst[i] = (uint8_t)(lp[i] ^ b); break;
            default:          dst[i] = lp[i]; break;
        }
        i++;
    }
    return 1;
}

/* i32/i64 NEON fast path (Gap G). Mirrors the i8 and float fast paths for the
 * 32- and 64-bit signed/unsigned integer tiers, which previously fell to the
 * generic scalar loop (~20x slower than autovectorized C). Handles add/sub/mul
 * and bitwise or/and/xor; DIV/SHL/SHR return 0 (caller keeps the scalar loop).
 * Requires contiguous storage and, for the array-array case, matching width. */
static int array_elementwise_i32_i64_fast(WArray *la, WArray *ra, WArray *out,
                                          int rhs_is_array, int64_t scalar, EltOp op) {
#ifdef __aarch64__
    int64_t sbits = array_storage_bits(la->ebits);
    if ((sbits != 32 && sbits != 64) || !elt_op_is_int_simd(op)) return 0;
    if (rhs_is_array && (ra == NULL || array_storage_bits(ra->ebits) != sbits)) return 0;
    int32_t n = la->size;

    if (sbits == 32) {
        const int32_t *lp = (const int32_t *)la->slots + la->start;
        const int32_t *rp = rhs_is_array ? (const int32_t *)ra->slots + ra->start : NULL;
        int32_t *dst = (int32_t *)out->slots;   /* out->start == 0 (fresh buffer) */
        int32x4_t sv = vdupq_n_s32((int32_t)scalar);
        int32_t i = 0, end = n - 4;
        while (i <= end) {
            int32x4_t a = vld1q_s32(lp + i);
            int32x4_t b = rhs_is_array ? vld1q_s32(rp + i) : sv;
            vst1q_s32(dst + i, elt_apply_s32x4(op, a, b));
            i += 4;
        }
        for (; i < n; i++) {
            int32_t a = lp[i], b = rhs_is_array ? rp[i] : (int32_t)scalar;
            dst[i] = (int32_t)elt_apply_int(op, a, b);
        }
        return 1;
    }

    /* sbits == 64 */
    const int64_t *lp = (const int64_t *)la->slots + la->start;
    const int64_t *rp = rhs_is_array ? (const int64_t *)ra->slots + ra->start : NULL;
    int64_t *dst = (int64_t *)out->slots;
    int64x2_t sv = vdupq_n_s64(scalar);
    int32_t i = 0, end = n - 2;
    while (i <= end) {
        int64x2_t a = vld1q_s64(lp + i);
        int64x2_t b = rhs_is_array ? vld1q_s64(rp + i) : sv;
        vst1q_s64(dst + i, elt_apply_s64x2(op, a, b));
        i += 2;
    }
    for (; i < n; i++) {
        int64_t a = lp[i], b = rhs_is_array ? rp[i] : scalar;
        dst[i] = elt_apply_int(op, a, b);
    }
    return 1;
#else
    (void)la; (void)ra; (void)out; (void)rhs_is_array; (void)scalar; (void)op;
    return 0;
#endif
}

/* One clean, unrollable loop per operation. The op is switched OUTSIDE the
 * loop and the pointers are `restrict`/`const`, so clang's auto-vectorizer +
 * interleave pass generate the same 4x-unrolled SIMD as hand-written C
 * (ldp/stp q, fmul.2d x4). This replaced hand-coded NEON intrinsics, which the
 * vectorizer treats as opaque and never unrolls — and it auto-ports to AVX on
 * x86. Divide guards against /0 branchlessly (compute quotient, select 0) so
 * the guard doesn't block vectorization. */
#define ELTWISE_FLOAT_BODY(T)                                                   \
    do {                                                                        \
        const T *restrict lp = (const T *)la->slots + la->start;                \
        T *restrict dst = (T *)out->slots;                                      \
        if (rhs_is_array) {                                                     \
            const T *restrict rp = (const T *)ra->slots + ra->start;            \
            switch (op) {                                                       \
                case ELT_OP_ADD: for (int32_t i=0;i<n;i++) dst[i]=lp[i]+rp[i]; break; \
                case ELT_OP_SUB: for (int32_t i=0;i<n;i++) dst[i]=lp[i]-rp[i]; break; \
                case ELT_OP_MUL: for (int32_t i=0;i<n;i++) dst[i]=lp[i]*rp[i]; break; \
                case ELT_OP_DIV: for (int32_t i=0;i<n;i++){ T q=lp[i]/rp[i]; dst[i]=(rp[i]==(T)0)?(T)0:q; } break; \
                default: return 0;                                             \
            }                                                                   \
        } else {                                                                \
            T s = (T)scalar;                                                    \
            switch (op) {                                                       \
                case ELT_OP_ADD: for (int32_t i=0;i<n;i++) dst[i]=lp[i]+s; break; \
                case ELT_OP_SUB: for (int32_t i=0;i<n;i++) dst[i]=lp[i]-s; break; \
                case ELT_OP_MUL: for (int32_t i=0;i<n;i++) dst[i]=lp[i]*s; break; \
                case ELT_OP_DIV: for (int32_t i=0;i<n;i++){ T q=lp[i]/s; dst[i]=(s==(T)0)?(T)0:q; } break; \
                default: return 0;                                             \
            }                                                                   \
        }                                                                       \
        return 1;                                                               \
    } while (0)

static int array_elementwise_float_fast(WArray *la, WArray *ra, WArray *out,
                                        int rhs_is_array, double scalar, EltOp op) {
    if (!elt_op_is_float_arith(op)) return 0;
    if (rhs_is_array && (ra == NULL || ra->ebits != la->ebits)) return 0;

    int32_t n = la->size;
    if (la->ebits == -32) { ELTWISE_FLOAT_BODY(float); }
    if (la->ebits == -64) { ELTWISE_FLOAT_BODY(double); }

    if (la->ebits == -116 || la->ebits == -16) {
        int32_t i = 0;
        while (i < n) {
            double a = array_read_float(la, la->start + i);
            double b = rhs_is_array ? array_read_float(ra, ra->start + i) : scalar;
            array_write_float(out, i, elt_apply_double(op, a, b));
            i++;
        }
        return 1;
    }

    return 0;
}

/* Core elementwise op. If out_v is W_NIL a fresh result buffer is allocated
 * (value semantics); otherwise the caller-supplied buffer is written in place
 * (the `## reuse` fast path — no per-call allocation). A supplied buffer must
 * have matching ebits and capacity >= la->size; the reuse wrapper guarantees
 * this. */
static WValue array_elementwise_into(WValue out_v, WValue lhs, WValue rhs, EltOp op) {
    WArray *la = w_as_array(lhs);
    int8_t eb = la->ebits;
    int32_t n = la->size;
    if (out_v == W_NIL) {
        /* Allocate the result buffer up front: same ebits, same size. Every
         * element is written below, so skip the calloc zeroing for whole-byte
         * element tiers (bool=1/i4=4 keep the zeroed allocator — a partial
         * trailing byte would otherwise be left undefined). */
        int64_t out_sbits = array_storage_bits(eb);
        out_v = (out_sbits >= 8) ? w_array_new_uninit(eb, n) : w_array_new(eb, n);
    }
    WArray *out = w_as_array(out_v);
    out->start = 0;
    out->size = n;
    int rhs_is_array = w_is_array(rhs);
    WArray *ra = NULL;
    if (rhs_is_array) {
        ra = w_as_array(rhs);
        if (ra->size != n) {
            w_raise(w_string("elementwise op: lhs.size != rhs.size"));
            return W_NIL;
        }
    }
    /* Float fast path: pre-coerce scalar once. */
    if (array_is_float(la)) {
        double scalar = 0.0;
        if (!rhs_is_array) scalar = cmp_numeric_double(rhs);  /* int/double/decimal → double (float array) */
        if (array_elementwise_float_fast(la, ra, out, rhs_is_array, scalar, op)) {
            return out_v;
        }
        for (int32_t i = 0; i < n; i++) {
            double a = array_read_float(la, la->start + i);
            double b = rhs_is_array ? array_read_float(ra, ra->start + i) : scalar;
            array_write_float(out, i, elt_apply_double(op, a, b));
        }
        return out_v;
    }
    /* w64 (polymorphic WValue): dispatch to scalar binop on each pair.
     * Used when the array literal carries arbitrary types. */
    if (eb == 65) {
        for (int32_t i = 0; i < n; i++) {
            WValue a = (WValue)array_read(la, la->start + i);
            WValue b = rhs_is_array ? (WValue)array_read(ra, ra->start + i) : rhs;
            WValue r;
            switch (op) {
                case ELT_OP_ADD:  r = w_add_fast(a, b); break;
                case ELT_OP_SUB:  r = w_sub_fast(a, b); break;
                case ELT_OP_MUL:  r = w_mul_fast(a, b); break;
                case ELT_OP_DIV:  r = w_div(a, b); break;
                case ELT_OP_BOR:  r = w_bit_or(a, b); break;
                case ELT_OP_BAND: r = w_bit_and(a, b); break;
                case ELT_OP_BXOR: r = w_bit_xor(a, b); break;
                case ELT_OP_SHL:  r = w_int(w_as_int(a) << w_as_int(b)); break;
                case ELT_OP_SHR:  r = w_int(w_as_int(a) >> w_as_int(b)); break;
                default:          r = W_NIL;
            }
            array_write(out, i, (uint64_t)r);
        }
        return out_v;
    }
    /* Integer path: read raw, apply, write back. Width-truncates on store. */
    int64_t scalar_i = 0;
    if (!rhs_is_array) scalar_i = w_as_int(rhs);
    if (array_elementwise_i8_fast(la, ra, out, rhs_is_array, scalar_i, op)) {
        return out_v;
    }
    if (array_elementwise_i32_i64_fast(la, ra, out, rhs_is_array, scalar_i, op)) {
        return out_v;
    }
    int lhs_signed = array_is_signed_int(la);
    int rhs_signed = rhs_is_array && array_is_signed_int(ra);
    for (int32_t i = 0; i < n; i++) {
        int64_t a = lhs_signed ? array_read_signed(la, la->start + i) : (int64_t)array_read(la, la->start + i);
        int64_t b = rhs_is_array
            ? (rhs_signed ? array_read_signed(ra, ra->start + i) : (int64_t)array_read(ra, ra->start + i))
            : scalar_i;
        array_write(out, i, (uint64_t)elt_apply_int(op, a, b));
    }
    return out_v;
}

/* Value-semantics wrapper: fresh result buffer each call. */
static WValue array_elementwise(WValue lhs, WValue rhs, EltOp op) {
    return array_elementwise_into(W_NIL, lhs, rhs, op);
}

/* ---- Fused elementwise lowering support (compiler/lib/lowering/ops.w) ----
 * The compiler fuses trees of float elementwise ops (.+ .- .* ./ and array
 * sin/cos/sqrt) into one loop over raw f64 buffers. These two helpers give
 * that loop allocation and size semantics identical to the kernels above. */

WValue w_array_new_uninit_sized(int64_t element_bits, int64_t n) {
    WValue v = w_array_new_uninit(element_bits, n);
    WArray *a = w_as_array(v);
    a->size = (int32_t)n;
    return v;
}

/* Boxed numeric array → typed float buffer (Array#to_f32/to_f64; the
 * `%f32[…]`/`%f64[…]` literals desugar through these). Elements coerce
 * through as_numeric_double, so ints, decimals, and raw floats all land. */
static WValue array_to_float_typed(WValue arr, int64_t element_bits) {
    if (!w_is_array(arr)) dief("to_f32/to_f64 expects an array");
    WArray *a = w_as_array(arr);
    int64_t n = a->size;
    WValue out = w_array_new(element_bits, n > 0 ? n : 8);
    WArray *o = w_as_array(out);
    for (int64_t i = 0; i < n; i++) {
        double d;
        if (a->ebits == 65) d = as_numeric_double(((WValue *)a->slots)[a->start + i]);
        else if (array_is_float(a)) d = array_read_float(a, a->start + i);
        else dief("to_f32/to_f64: unsupported source element type");
        array_write_float(o, i, d);
    }
    o->size = (int32_t)n;
    return out;
}

WValue w_array_to_f64(WValue arr) { return array_to_float_typed(arr, -64); }
WValue w_array_to_f32(WValue arr) { return array_to_float_typed(arr, -32); }

WValue w_elementwise_size_check(WValue lhs, WValue rhs) {
    WArray *la = w_as_array(lhs);
    WArray *ra = w_as_array(rhs);
    if (ra->size != la->size) {
        w_raise(w_string("elementwise op: lhs.size != rhs.size"));
    }
    return W_NIL;
}

/* ---- Fused elementwise auto-parallelization ----
 *
 * The compiler outlines each fused loop body into a worker
 *     int64_t __w_fuse_worker_N(int64_t blk, int64_t lo, int64_t hi)
 * (blk = raw pointer to an i64 arg block: [out WValue, leaf-array WValues...,
 * scalar f64 bit patterns...]) and gates on size at the site: below the
 * threshold the loop runs inline single-core; at/above it,
 * w_fused_parallel_run partitions [0, n) across OS threads.
 *
 * Thresholds are from the measured persistent-pool sweep in
 * doc/scientific-computing/fusion.md. Cheap arithmetic and libm-heavy trees
 * use separate ladders because worker wake cost and per-element work move
 * both crossovers substantially. Env overrides: TUNGSTEN_FUSED_MT_MIN,
 * TUNGSTEN_FUSED_HEAVY_MT_MIN, TUNGSTEN_FUSED_T8_MIN,
 * TUNGSTEN_FUSED_HEAVY_T8_MIN, and TUNGSTEN_FUSED_THREADS (<=1 disables
 * threading entirely). */

typedef int64_t (*WFusedWorkerFn)(int64_t blk, int64_t lo, int64_t hi);

static int64_t w_fused_mt_min_v = -1;
static int64_t w_fused_heavy_mt_min_v = -1;
static int64_t w_fused_t8_min_v = -1;
static int64_t w_fused_heavy_t8_min_v = -1;
static int64_t w_fused_max_threads_v = -1;
static pthread_once_t w_fused_thresholds_once = PTHREAD_ONCE_INIT;

static void w_fused_init_thresholds(void) {
    const char *e;
    int64_t mt_min = 8192, heavy_mt_min = 4096;
    int64_t t8_min = 2097152, heavy_t8_min = 131072, max_t = 8;
    if ((e = getenv("TUNGSTEN_FUSED_MT_MIN")) && *e) {
        mt_min = strtoll(e, NULL, 10);
        heavy_mt_min = mt_min;
    }
    if ((e = getenv("TUNGSTEN_FUSED_HEAVY_MT_MIN")) && *e)
        heavy_mt_min = strtoll(e, NULL, 10);
    if ((e = getenv("TUNGSTEN_FUSED_T8_MIN")) && *e) {
        t8_min = strtoll(e, NULL, 10);
        heavy_t8_min = t8_min;
    }
    if ((e = getenv("TUNGSTEN_FUSED_HEAVY_T8_MIN")) && *e)
        heavy_t8_min = strtoll(e, NULL, 10);
    if ((e = getenv("TUNGSTEN_FUSED_THREADS")) && *e) max_t = strtoll(e, NULL, 10);
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpu > 0 && max_t > ncpu) max_t = ncpu;
    if (max_t > 16) max_t = 16;
    if (max_t < 1) max_t = 1;
    w_fused_t8_min_v = t8_min;
    w_fused_heavy_t8_min_v = heavy_t8_min;
    w_fused_max_threads_v = max_t;
    /* max_t <= 1 disables the parallel path entirely (should_mt never fires) */
    w_fused_mt_min_v = (max_t <= 1) ? INT64_MAX : mt_min;
    w_fused_heavy_mt_min_v = (max_t <= 1) ? INT64_MAX : heavy_mt_min;
}

/* ## reuse on a fused expression: per-site persistent output buffer.
 * Same user-assertion contract as `f64[n] ## reuse` — the caller promises
 * the previous result from this site is dead. Keeps the output base stable,
 * which kills the per-execution calloc + fault-in on CPU and lets the GPU
 * tier cache its zero-copy wrap. */
WValue w_fused_out_reuse_or_new(WValue *slot, int64_t element_bits, int64_t n) {
    WValue v = *slot;
    if (v != W_NIL) {
        WArray *a = w_as_array(v);
        if (a->ebits == (int8_t)element_bits && a->cap >= n) {
            a->start = 0;
            a->size = (int32_t)n;
            return v;
        }
    }
    v = w_array_new_uninit_sized(element_bits, n);
    *slot = v;
    return v;
}

/* Compiler-proven unique fused destination. Unlike the explicit ## reuse
 * site slot, ownership travels in the value currently bound to the local.
 * Fail closed at runtime for a changed representation, element width, view,
 * or insufficient capacity; the ordinary fresh allocation remains correct. */
WValue w_fused_out_reuse_value_or_new(WValue old, int64_t element_bits,
                                      int64_t n) {
    if (old != W_NIL && w_is_array(old)) {
        WArray *a = w_as_array(old);
        if ((a->flags & W_FLAG_OWNED) && a->ebits == (int8_t)element_bits &&
            a->cap >= n) {
            a->start = 0;
            a->size = (int32_t)n;
            return old;
        }
    }
    return w_array_new_uninit_sized(element_bits, n);
}

int64_t w_fused_should_mt(int64_t n, int64_t work_class) {
    pthread_once(&w_fused_thresholds_once, w_fused_init_thresholds);
    int64_t threshold = work_class ? w_fused_heavy_mt_min_v
                                   : w_fused_mt_min_v;
    return n >= threshold ? 1 : 0;
}

typedef struct {
    WFusedWorkerFn fn;
    int64_t blk, lo, hi;
} WFusedPart;

static _Thread_local int w_fused_parallel_depth;

static void w_fused_part_run(void *p) {
    WFusedPart *a = (WFusedPart *)p;
    w_fused_parallel_depth++;
    a->fn(a->blk, a->lo, a->hi);
    w_fused_parallel_depth--;
}

static void *w_fused_part_main(void *p) {
    w_fused_part_run(p);
    return NULL;
}

int64_t w_fused_parallel_run(int64_t fn_addr, int64_t blk, int64_t n,
                             int64_t work_class) {
    pthread_once(&w_fused_thresholds_once, w_fused_init_thresholds);
    WFusedWorkerFn fn = (WFusedWorkerFn)(uintptr_t)fn_addr;
    /* A fused dispatch reached from one of our own workers must stay inline:
     * submitting recursively would either deadlock on the occupied pool or
     * multiply the active thread count. */
    if (w_fused_parallel_depth) {
        fn(blk, 0, n);
        return 0;
    }
    int64_t t8_min = work_class ? w_fused_heavy_t8_min_v
                                : w_fused_t8_min_v;
    int64_t nt = (n >= t8_min) ? 8 : 4;
    if (nt > w_fused_max_threads_v) nt = w_fused_max_threads_v;
    if (nt <= 1 || n < nt) {
        fn(blk, 0, n);
        return 0;
    }
    pthread_t th[16];
    WFusedPart parts[16];
    for (int64_t t = 0; t < nt; t++) {
        parts[t].fn = fn;
        parts[t].blk = blk;
        parts[t].lo = n * t / nt;
        parts[t].hi = n * (t + 1) / nt;
    }
    /* Reuse the runtime's tuned persistent arithmetic pool. Its submit lock
     * is nonblocking, so an independent concurrent caller falls back to the
     * local pthread path instead of serializing behind another operation.
     * Larger opt-in thread counts keep the old path because the shared pool
     * is deliberately sized to its widest regular consumer. */
    if (nt <= BN_POOL_TASKS_MAX) {
        void *args[BN_POOL_TASKS_MAX];
        for (int64_t t = 0; t < nt; t++) args[t] = &parts[t];
        bn_pool_run_tasks(w_fused_part_run, args, (int)nt,
                          BN_TOOM_POOL_SPIN);
        return 0;
    }
    /* Partition 0 runs on the calling thread — one fewer spawn. */
    for (int64_t t = 1; t < nt; t++) {
        if (pthread_create(&th[t], NULL, w_fused_part_main, &parts[t]) != 0) {
            /* Spawn failure: run the remainder inline. */
            for (int64_t u = t; u < nt; u++) w_fused_part_run(&parts[u]);
            nt = t;
            break;
        }
    }
    w_fused_part_run(&parts[0]);
    for (int64_t t = 1; t < nt; t++) pthread_join(th[t], NULL);
    return 0;
}

/* Destination-reuse wrapper. `*slot` holds the array currently bound to the
 * assignment target (or W_NIL the first time). If it is an owned array with
 * matching ebits and enough capacity it is written in place — no allocation.
 * Otherwise a fresh buffer is made and stored back into the slot. This backs
 * automatic reuse of a reassigned loop target (`c = a .* b`), where the prior
 * `c` is dead. NOTE: only sound when the prior `c` is not aliased by another
 * live binding — the lowering must gate on that (see assignment lowering). */
static WValue array_elementwise_reuse(WValue *slot, WValue lhs, WValue rhs, EltOp op) {
    WArray *la = w_as_array(lhs);
    WValue dst = *slot;
    WValue out;
    if (dst != W_NIL && w_is_array(dst)) {
        WArray *d = w_as_array(dst);
        if ((d->flags & W_FLAG_OWNED) && d->ebits == la->ebits && d->cap >= la->size) {
            out = array_elementwise_into(dst, lhs, rhs, op);  /* in place */
            *slot = out;
            return out;
        }
    }
    out = array_elementwise_into(W_NIL, lhs, rhs, op);
    *slot = out;
    w_gc_register_reuse_slot(slot);
    return out;
}

WValue w_array_add_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_ADD); }
WValue w_array_sub_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_SUB); }
WValue w_array_mul_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_MUL); }
WValue w_array_div_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_DIV); }
WValue w_array_bor_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_BOR); }
WValue w_array_band_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_BAND); }
WValue w_array_bxor_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_BXOR); }
WValue w_array_shl_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_SHL); }
WValue w_array_shr_elem_reuse(WValue *slot, WValue lhs, WValue rhs) { return array_elementwise_reuse(slot, lhs, rhs, ELT_OP_SHR); }

WValue w_array_add_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_ADD); }
WValue w_array_sub_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_SUB); }
WValue w_array_mul_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_MUL); }
WValue w_array_div_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_DIV); }
WValue w_array_bor_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_BOR); }
WValue w_array_band_elem(WValue lhs, WValue rhs) { return array_elementwise(lhs, rhs, ELT_OP_BAND); }
WValue w_array_bxor_elem(WValue lhs, WValue rhs) { return array_elementwise(lhs, rhs, ELT_OP_BXOR); }
WValue w_array_shl_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_SHL); }
WValue w_array_shr_elem(WValue lhs, WValue rhs)  { return array_elementwise(lhs, rhs, ELT_OP_SHR); }

/* arr[from..to] / arr[from...to] — zero-copy slice view via
 * the Range-indexing sugar. Wraps `w_array_view` after
 * resolving the inclusive/exclusive bound and computing the length.
 *  - Negative indices wrap from the end.
 *  - Out-of-range bounds clamp to the live window.
 *  - Empty / inverted range (lo > hi+1) returns a zero-element view. */
/* Forward decl: defined below near the other w_big_array_* helpers so
 * the polymorphic w_array_view_range can route into the BigArray path. */
WValue w_big_array_view_range(WValue arr, WValue from_v, WValue to_v, WValue exclusive_v);

/* `str[from..to]` / `str[from...to]` — the String arm of the same sugar.
 * Indexing is by CODE POINT so it agrees with the scalar subscript
 * (w_string_idx_raw) rather than with the byte-exact `slice(start, len)`.
 * Bound resolution mirrors the Array rule above: negative indices wrap from
 * the end, out-of-range bounds clamp to the live window, and an empty or
 * inverted range yields "". Strings are immutable, so this is a copy, not a
 * view. The interpreter ccalls this same helper, so both engines agree. */
WValue w_string_slice_range(WValue str, WValue from_v, WValue to_v,
                            WValue exclusive_v) {
    if (w_is_rope(str)) str = w_rope_flatten(str);
    char sbuf[6];
    const char *s;
    size_t blen;
    w_str_data(str, sbuf, &s, &blen);

    /* ASCII content (each representation's ASCII bit): byte == code point,
     * so the bounds arithmetic below needs no walk at all. */
    int ascii = w_string_ascii_p(str);
    int64_t n;
    if (ascii) {
        n = (int64_t)blen;
    } else {
        n = 0;
        for (size_t p = 0; p < blen; ) {
            p += w_utf8_index_width(s + p, blen - p);
            n++;
        }
    }

    int64_t from = w_as_int(from_v);
    int     excl = w_truthy(exclusive_v);
    int64_t to;
    if (w_is_nil(to_v)) {
        /* Right-unbounded (`str[n..]`): run through the end. The exclusive
         * bound skips the inclusive adjustment below. */
        to   = n;
        excl = 1;
    } else {
        to = w_as_int(to_v);
        if (to < 0) to += n;
    }
    if (from < 0) from += n;
    if (from < 0) from = 0;
    if (!excl) to += 1;          /* inclusive → exclusive end */
    if (to > n) to = n;
    if (to < from) to = from;
    if (to == from) return w_string("");

    size_t bstart, bend;
    if (ascii) {
        bstart = (size_t)from;
        bend   = (size_t)to;
    } else {
        size_t p = 0;
        int64_t k = 0;
        while (p < blen && k < from) { p += w_utf8_index_width(s + p, blen - p); k++; }
        bstart = p;
        while (p < blen && k < to)   { p += w_utf8_index_width(s + p, blen - p); k++; }
        bend = p;
    }
    size_t len = bend - bstart;
    if (ascii) return w_string_n_known_ascii(s + bstart, len, 1);
    return w_string_n(s + bstart, len);
}

WValue w_array_view_range(WValue arr, WValue from_v, WValue to_v, WValue exclusive_v) {
    /* Polymorphic dispatch — Array, BigArray and String all lower
     * `recv[a..b]` to this entry point. Route on the tag so neither the
     * BigArray header nor a String/Symbol WValue is reinterpreted as a
     * WArray. Anything else (a packed Range, a Hash, an object) would be a
     * wild pointer dereference, so it raises instead. */
    if (w_is_big_array(arr)) {
        return w_big_array_view_range(arr, from_v, to_v, exclusive_v);
    }
    if (w_is_stringy(arr) || w_is_rope(arr)) {
        /* Symbols share the string tag but not the byte-view layout; slice
         * their printed name, as w_ic_string_size does. */
        WValue sv = w_is_symbol(arr) ? w_to_s(arr) : arr;
        return w_string_slice_range(sv, from_v, to_v, exclusive_v);
    }
    if (!w_is_array(arr)) {
        char msg[128];
        snprintf(msg, sizeof(msg), "[]: cannot slice a %s with a range",
                 as_str(__w_type(arr)));
        w_raise(w_string(msg));
        return W_NIL;
    }
    WArray *src = w_as_array(arr);
    int64_t from = w_as_int(from_v);
    int     excl = (exclusive_v == W_TRUE);
    int64_t to;
    if (w_is_nil(to_v)) {
        /* Right-unbounded range (`arr[n..]`): slice through the end. Use an
         * exclusive size bound so the `!excl` adjustment below is skipped. */
        to   = src->size;
        excl = 1;
    } else {
        to = w_as_int(to_v);
        if (to < 0) to = src->size + to;
    }
    if (from < 0) from = src->size + from;
    if (from < 0) from = 0;
    if (!excl) to += 1;          /* inclusive → exclusive end */
    if (to > src->size) to = src->size;
    int64_t len = to - from;
    if (len < 0) len = 0;
    return w_array_view(arr, w_int(from), w_int(len));
}

/* ---- View registry (Option B for view↔realloc safety) ----
 *
 * When a parent array grows past its current capacity, w_array_push
 * allocates a fresh `slots` buffer and rebinds parent->slots. Every
 * view created beforehand stores an interior pointer into the OLD
 * buffer — without intervention those views dangle.
 *
 * The registry, keyed by the parent's boxed WValue, holds the set of
 * live views and each one's byte-offset from the parent's slots base
 * at registration time. When the parent reallocs, we walk the view
 * list and rewrite each `view->slots` to `new_slots + offset`. Views
 * of views are handled recursively — when an intermediate view's
 * slots changes, its own registered sub-views are walked with the new
 * offsets propagated.
 *
 * Implementation notes:
 *  - Side table rather than a `views` field on WArray — keeps WArray
 *    at its tuned 24 bytes; only arrays that are actually parented
 *    pay any cost.
 *  - WValue keys (not raw WArray*) so the same handle the rest of the
 *    runtime uses identifies the parent; subtag-uniform.
 *  - SmallArray skips the registry: stack-resident, never grows.
 *  - BigArray needs the same treatment in a follow-up — its growth
 *    path is in w_big_array_push and would mirror this hook.
 *  - No GC today, so entries persist for the program's lifetime.
 *    That's fine: bounded by the number of arrays a program creates.
 */

#define W_VIEW_BUCKETS 64

typedef struct WViewEntry {
    WValue   view;            /* boxed view WValue */
    intptr_t offset_bytes;    /* view->slots − parent->slots at register time */
} WViewEntry;

typedef struct WViewNode {
    WValue            parent;
    WViewEntry       *entries;
    int32_t           count;
    int32_t           cap;
    struct WViewNode *next;   /* hash-collision chain */
} WViewNode;

static WViewNode *w_view_table[W_VIEW_BUCKETS] = {0};

static inline size_t w_view_bucket(WValue v) {
    return ((uintptr_t)v >> 4) & (W_VIEW_BUCKETS - 1);
}

static WViewNode *w_view_find(WValue parent) {
    for (WViewNode *n = w_view_table[w_view_bucket(parent)]; n; n = n->next) {
        if (n->parent == parent) return n;
    }
    return NULL;
}

static int g_any_views_registered = 0;

static int w_array_has_views(WValue parent) {
    if (__builtin_expect(!g_any_views_registered, 1)) return 0;
    WViewNode *node = w_view_find(parent);
    return node != NULL && node->count > 0;
}

static WViewNode *w_view_find_or_create(WValue parent) {
    WViewNode *n = w_view_find(parent);
    if (n) return n;
    n = (WViewNode *)calloc(1, sizeof(WViewNode));
    n->parent  = parent;
    n->cap     = 4;
    n->entries = (WViewEntry *)calloc((size_t)n->cap, sizeof(WViewEntry));
    size_t b = w_view_bucket(parent);
    n->next = w_view_table[b];
    w_view_table[b] = n;
    return n;
}

/* Reverse-lookup: which parent owns this view? Used to flatten slice-of-slice
 * to slice-of-root: when a caller asks for a view of an existing view, the
 * new view registers against the original parent so all views are siblings
 * with offsets measured from the same buffer. */
static WValue w_view_find_root(WValue maybe_view) {
    for (int b = 0; b < W_VIEW_BUCKETS; b++) {
        for (WViewNode *n = w_view_table[b]; n; n = n->next) {
            for (int32_t i = 0; i < n->count; i++) {
                if (n->entries[i].view == maybe_view) return n->parent;
            }
        }
    }
    return W_NIL;
}

void w_register_view(WValue parent, WValue view) {
    g_any_views_registered = 1;
    /* If `parent` is itself a view, flatten: attach the new view to the
     * original owner so we never build deep view chains. */
    WArray *parent_arr = w_as_array(parent);
    if (parent_arr->flags & W_FLAG_VIEW) {
        WValue root = w_view_find_root(parent);
        if (root != W_NIL) parent = root;
    }

    WArray *p = w_as_array(parent);
    WArray *v = w_as_array(view);
    WViewNode *n = w_view_find_or_create(parent);
    if (n->count == n->cap) {
        n->cap *= 2;
        n->entries = (WViewEntry *)realloc(n->entries,
                                           (size_t)n->cap * sizeof(WViewEntry));
    }
    n->entries[n->count].view         = view;
    n->entries[n->count].offset_bytes = (uint8_t *)v->slots - (uint8_t *)p->slots;
    n->count++;
}

W_RT_INTERNAL void w_rt_register_string_view(WValue str_parent, WValue view) {
    if (!w_is_heap_str(str_parent) || !w_is_array(view)) return;
    g_any_views_registered = 1;
    WViewNode *n = w_view_find_or_create(str_parent);
    if (n->count == n->cap) {
        n->cap *= 2;
        n->entries = (WViewEntry *)realloc(n->entries,
                                           (size_t)n->cap * sizeof(WViewEntry));
    }
    n->entries[n->count].view = view;
    n->entries[n->count].offset_bytes = 0;
    n->count++;
}

W_RT_INTERNAL int w_rt_gc_propagate_views(WGCRootVisitor mark_fn, void *ctx) {
    if (!g_any_views_registered) return 0;
    int added = 0;
    for (int b = 0; b < W_VIEW_BUCKETS; b++) {
        for (WViewNode *n = w_view_table[b]; n; n = n->next) {
            if (w_gc_is_live_marked(n->parent)) continue;
            for (int32_t i = 0; i < n->count; i++) {
                if (w_gc_is_live_marked(n->entries[i].view)) {
                    mark_fn(n->parent, ctx);
                    added = 1;
                    break;
                }
            }
        }
    }
    return added;
}

W_RT_INTERNAL void w_rt_gc_prune_views(void) {
    if (!g_any_views_registered) return;
    for (int b = 0; b < W_VIEW_BUCKETS; b++) {
        WViewNode **link = &w_view_table[b];
        while (*link) {
            WViewNode *n = *link;
            int32_t w = 0;
            for (int32_t i = 0; i < n->count; i++) {
                if (w_gc_is_live_marked(n->entries[i].view)) {
                    n->entries[w++] = n->entries[i];
                }
            }
            n->count = w;
            if (n->count == 0 && !w_gc_is_live_marked(n->parent)) {
                *link = n->next;
                free(n->entries);
                free(n);
            } else {
                link = &n->next;
            }
        }
    }
}

static void w_view_unregister(WValue view) {
    if (!g_any_views_registered) return;
    for (int b = 0; b < W_VIEW_BUCKETS; b++) {
        for (WViewNode *n = w_view_table[b]; n; n = n->next) {
            for (int32_t i = 0; i < n->count; i++) {
                if (n->entries[i].view == view) {
                    n->entries[i] = n->entries[n->count - 1];
                    n->count--;
                    return;
                }
            }
        }
    }
}

/* Growing a borrowed view (`a.slice(0, n)` then `push`) detaches it: its
 * elements move into fresh owned storage, so the push cannot write past the
 * window into the parent's (or a string's) bytes. Writes through the view
 * stop aliasing the parent from this point on. */
static void w_array_detach_view(WValue arr) {
    WArray *a = w_as_array(arr);
    WArray old = *a;
    int64_t cap = a->size < 4 ? 8 : (int64_t)a->size * 2;
    if (cap > INT32_MAX) cap = INT32_MAX;
    uint8_t *data = calloc(1, (size_t)array_byte_size(a->ebits, cap));
    if (!data) die("typed array allocation failed");
    w_allocprof(W_ALLOCPROF_GROW, array_byte_size(a->ebits, cap));
    w_view_unregister(arr);
    a->slots = (WValue *)data;
    a->start = 0;
    a->cap = (int32_t)cap;
    if (array_storage_bits(a->ebits) >= 8) {
        memcpy(data, (uint8_t *)old.slots + array_byte_size(old.ebits, old.start),
               (size_t)array_byte_size(old.ebits, old.size));
    } else {
        for (int64_t j = 0; j < old.size; j++)
            array_write(a, j, array_read(&old, old.start + j));
    }
    a->flags = (uint8_t)((a->flags & ~(W_FLAG_VIEW | W_FLAG_INLINE | W_FLAG_PAGE_ALIGNED)) | W_FLAG_OWNED);
}

/* Walk every view registered against `parent`, rewriting their `slots`
 * to point into the new buffer at the same byte-offset. Recurses so
 * sub-views (views of views) are updated through the intermediate's
 * new base. */
void w_views_after_realloc(WValue parent, WValue *old_slots, WValue *new_slots) {
    (void)old_slots;
    WViewNode *n = w_view_find(parent);
    if (!n) return;
    for (int32_t i = 0; i < n->count; i++) {
        WValue   view_val = n->entries[i].view;
        WArray  *view     = w_as_array(view_val);
        WValue  *view_old = view->slots;
        WValue  *view_new = (WValue *)((uint8_t *)new_slots + n->entries[i].offset_bytes);
        view->slots = view_new;
        w_views_after_realloc(view_val, view_old, view_new);
    }
}

/* arr.slice_view(start, len) — zero-copy slice view.
 *
 * Returns a typed-array view sharing the parent's `slots` buffer with
 * `start = original_start + lo` and `size = len`. View semantics:
 *  - Mutations through the view affect the parent (Rust-style aliasing).
 *  - W_FLAG_VIEW is set, so push/grow on the view raise.
 *  - Parent realloc (w_array_push past cap) walks the view registry
 *    and updates each view's slots pointer to track the new buffer.
 *  - Out-of-range start/len gets clamped to the parent's live window.
 *
 * The plan's `arr[3..7]` ergonomic syntax requires bigger lowering /
 * runtime-dispatch surgery (range objects need to be recognized at the
 * `[]` callsite); this method form is the explicit-opt-in entry point
 * the user can already call today.
 */
WValue w_array_view(WValue arr, WValue lo_v, WValue len_v) {
    WArray *src = w_as_array(arr);
    int64_t lo  = w_as_int(lo_v);
    int64_t len = w_as_int(len_v);
    if (lo < 0) lo = src->size + lo;
    if (lo < 0) lo = 0;
    if (lo > src->size) lo = src->size;
    if (len < 0) len = 0;
    if (lo + len > src->size) len = src->size - lo;
    /* Reuse w_array_view: same heap struct, W_FLAG_VIEW set,
     * `slots` ptr offset to the live window. */
    int8_t eb = src->ebits;
    int64_t abs_bits = array_storage_bits(eb);
    WValue view_val;
    if (abs_bits == 4) {
        if ((src->start + lo) & 1) {
            w_raise(w_string("arr.slice_view: 4-bit slice on odd-nibble boundary not supported"));
            return W_NIL;
        }
        view_val = w_array_view_raw((uint8_t *)src->slots + ((int64_t)src->start + lo) / 2, eb, len);
    } else if (abs_bits == 1) {
        if ((src->start + lo) & 7) {
            w_raise(w_string("arr.slice_view: u1 slice must align on a byte boundary"));
            return W_NIL;
        }
        view_val = w_array_view_raw((uint8_t *)src->slots + ((int64_t)src->start + lo) / 8, eb, len);
    } else {
        view_val = w_array_view_raw((uint8_t *)src->slots + ((int64_t)src->start + lo) * (abs_bits / 8), eb, len);
    }
    w_as_array(view_val)->_pad[0] = src->_pad[0];
    w_register_view(arr, view_val);
    return view_val;
}

/* arr.view(other_ebits) — zero-copy reinterpret view.
 *
 * Returns a typed-array view over the same `slots` buffer with a new
 * element type. Length = total_bytes / target_size_bytes. Raises on
 * partial element (e.g. f32[3] = 12 bytes viewed as i64 = 8 B/element →
 * 1 element + 4-byte tail; tail is undefined, so we refuse to silently
 * truncate).
 *
 * The returned view borrows the parent's storage — caller is responsible
 * for keeping the parent alive (W_FLAG_VIEW makes push/grow on the view
 * raise). Mutations through the view are visible through the parent and
 * vice versa.
 */
WValue w_array_reinterpret(WValue arr, int64_t target_ebits) {
    if (!w_is_array(arr)) {
        w_raise(w_string("arr.view: receiver must be an array"));
    }
    WArray *src = w_as_array(arr);
    int8_t src_ebits = src->ebits;
    int64_t src_abs  = array_storage_bits(src_ebits);
    int64_t tgt_abs  = array_storage_bits(target_ebits);
    if (src_abs == 0 || tgt_abs == 0) {
        w_raise(w_string("arr.view: invalid element-bits code"));
    }
    /* Byte budget for the source live range (not including the slots before
     * `start` — the view starts where the source's logical data starts). */
    int64_t src_byte_count;
    if (src_abs == 4) {
        src_byte_count = ((int64_t)src->size + 1) / 2;
    } else {
        src_byte_count = (int64_t)src->size * (src_abs / 8);
    }
    int64_t tgt_byte_size;
    if (tgt_abs == 4) {
        /* 4-bit target is awkward — we'd need to know whether the byte
         * count is odd. Ban for now; revisit when there's a real caller. */
        w_raise(w_string("arr.view: 4-bit target reinterpret not yet supported"));
        return W_NIL;
    }
    tgt_byte_size = tgt_abs / 8;
    if (src_byte_count % tgt_byte_size != 0) {
        w_raise(w_string("arr.view: source byte count does not divide evenly by target element size (E_VIEW_PARTIAL_ELEMENT)"));
    }
    int64_t tgt_length = src_byte_count / tgt_byte_size;
    /* Compute the byte-offset of `start` in the source so the view points
     * at the live data, not the pre-shift slots. */
    int64_t start_bytes;
    if (src_abs == 4) {
        start_bytes = (int64_t)src->start / 2;  /* nibble shifts must be even at view boundaries */
        if ((src->start & 1) != 0) {
            w_raise(w_string("arr.view: source start is on an odd nibble — reinterpret would mis-align"));
        }
    } else {
        start_bytes = (int64_t)src->start * (src_abs / 8);
    }
    return w_array_view_raw((uint8_t *)src->slots + start_bytes, target_ebits, tgt_length);
}

/* T[N] constructor semantic — same allocation as
 * w_array_new but with size==cap so reads from `f32[N]` see N
 * zero-initialized slots instead of an empty buffer that the caller has
 * to bump per write. The plan calls this out explicitly: T[N] is the
 * "fixed-size buffer, ready to read" form; Array.new(ebits, cap: N)
 * is the "cap N, size 0, push N times" form when callers really want it. */
WValue w_array_zeros(int64_t element_bits, int64_t length) {
    if (length > INT32_MAX) {
        w_raise(w_string("typed array zeros: length exceeds INT32_MAX — use BigArray for >2^31 elements"));
    }
    WValue v = w_array_new(element_bits, length);
    WArray *a = w_as_array(v);
    a->size = (int32_t)(length > 0 ? length : 0);
    return v;
}

/* arr.fill(value) — broadcast `value` to every live slot.
 * Uses memset when the byte pattern is zero or the storage is 8-bit and
 * the value fits in a byte; otherwise falls back to a tight typed loop.
 * Returns the array for chaining. Operates in-place on owned storage;
 * raises if called on a borrowed view (would mutate caller-owned bytes
 * the view doesn't own). */
WValue w_array_fill(WValue arr, WValue val) {
    WArray *a = w_as_array(arr);
    if ((a->flags & W_FLAG_OWNED) == 0) {
        w_raise(w_string("typed array fill: cannot mutate a borrowed view"));
    }
    int64_t bits = array_storage_bits(a->ebits);
    if (a->size == 0) return arr;
    /* w64 stores raw WValues — no encoding, just splat the bit pattern. */
    if (array_is_wvalue(a)) {
        uint64_t *p = (uint64_t *)a->slots + a->start;
        for (int32_t i = 0; i < a->size; i++) p[i] = (uint64_t)val;
        return arr;
    }
    /* Float fill: convert once, then splat — keeps the as_numeric_double
     * path out of the inner loop. */
    if (array_is_float(a)) {
        double d = as_numeric_double(val);
        if (a->ebits == -32) {
            float f = (float)d;
            float *p = (float *)a->slots + a->start;
            for (int32_t i = 0; i < a->size; i++) p[i] = f;
        } else {
            double *p = (double *)a->slots + a->start;
            for (int32_t i = 0; i < a->size; i++) p[i] = d;
        }
        return arr;
    }
    /* Integer fill: encode once, choose memset for 0 or 8-bit byte
     * patterns, otherwise typed loop. */
    int64_t encoded = w_to_i64(val);
    if (bits == 8) {
        memset((uint8_t *)a->slots + a->start, (int)(encoded & 0xFF), (size_t)a->size);
        return arr;
    }
    if (encoded == 0) {
        memset((uint8_t *)a->slots + (int64_t)a->start * (bits / 8), 0,
               (size_t)((int64_t)a->size * (bits / 8)));
        return arr;
    }
    for (int32_t i = 0; i < a->size; i++) {
        array_write(a, a->start + i, (uint64_t)encoded);
    }
    return arr;
}

WValue w_array_new_filled(WValue size_v, WValue fill) {
    if (__builtin_expect(w_is_int(size_v), 1)) {
        int64_t size = w_as_int(size_v);
        if (__builtin_expect((uint64_t)size <= (uint64_t)INT32_MAX, 1)) {
            WValue arr = w_array_new_inline(65, size);
            WValue *slots = w_as_array(arr)->slots;
            if (fill == 0) {
                memset(slots, 0, (size_t)size * sizeof(WValue));
            } else {
                for (int64_t i = 0; i < size; i++) slots[i] = fill;
            }
            return arr;
        }
    }
    if (!w_is_int(size_v) && !w_is_bigint(size_v)) {
        w_raise(w_string("Array.new size must be an Integer"));
    }
    int64_t size = w_numeric_to_i64(size_v);
    if (size < 0) {
        w_raise(w_string("Array.new size must be non-negative"));
    }
    if (size > INT32_MAX) {
        w_raise(w_string("Array.new size exceeds INT32_MAX — use BigArray"));
    }
    WValue arr = w_array_new_inline(65, size);
    WValue *slots = w_as_array(arr)->slots;
    if (fill == 0) {
        memset(slots, 0, (size_t)size * sizeof(WValue));
    } else {
        for (int64_t i = 0; i < size; i++) slots[i] = fill;
    }
    return arr;
}

WValue w_array_pop(WValue arr) {
    WArray *a = w_as_array(arr);
    if (a->size == 0) return W_NIL;
    a->size--;
    return array_slot_load_decoded(a, a->size);
}

WValue w_array_shift(WValue arr) {
    WArray *a = w_as_array(arr);
    if (a->size == 0) return W_NIL;
    WValue result = array_slot_load_decoded(a, 0);
    a->start++;
    a->size--;
    return result;
}

WValue w_array_unshift(WValue arr, WValue val) {
    // Same three-case deque model as w_array_unshift. Typed arrays
    // add int-vs-float branching and byte-sized storage math.
    WArray *a = w_as_array(arr);
    if ((a->flags & W_FLAG_OWNED) == 0) {
        if ((a->flags & W_FLAG_VIEW) == 0)
            w_raise(w_string("typed array unshift: cannot grow a borrowed view"));
        w_array_detach_view(arr);
    }
    int64_t bits = array_storage_bits(a->ebits);
    // Case 1: O(1) — slot exists before start.
    if (a->start > 0) {
        a->start--;
        array_write_boxed(a, a->start, val);
        a->size++;
        return arr;
    }
    // Case 2: slide forward in-place.
    if (a->size < a->cap) {
        if (bits >= 8) {
            int64_t elt_bytes = array_byte_size(a->ebits, 1);
            int64_t live_bytes = array_byte_size(a->ebits, a->size);
            memmove((uint8_t *)a->slots + elt_bytes, a->slots, live_bytes);
        } else {
            // 4-bit elements: walk backward, copy each into the next slot.
            for (int64_t j = a->size - 1; j >= 0; j--) {
                uint64_t v = array_read(a, j);
                array_write(a, j + 1, v);
            }
        }
        array_write_boxed(a, 0, val);
        a->size++;
        return arr;
    }
    // Case 3: grow, copy elements to positions 1..N, write val at 0.
    int64_t new_cap = array_next_capacity(a->cap);
    w_allocprof(W_ALLOCPROF_GROW, array_byte_size(a->ebits, new_cap));
    uint8_t *new_data = malloc((size_t)array_byte_size(a->ebits, new_cap));
    if (!new_data) die("typed array allocation failed");
    WValue *old_slots = a->slots;
    int32_t old_cap = a->cap;
    uint8_t old_flags = a->flags;
    if (bits >= 8) {
        int64_t elt_bytes = array_byte_size(a->ebits, 1);
        int64_t live_bytes = array_byte_size(a->ebits, a->size);
        memcpy(new_data + elt_bytes, (uint8_t *)a->slots + array_byte_size(a->ebits, a->start), live_bytes);
    } else {
        // 4-bit: copy element-by-element, offset by 1 in the destination.
        WValue *old_data = old_slots;
        int64_t old_start = a->start;
        for (int64_t j = 0; j < a->size; j++) {
            a->slots = old_data;
            uint64_t v = array_read(a, old_start + j);
            a->slots = (WValue *)new_data;
            array_write(a, j + 1, v);
        }
        a->slots = old_data;  // restore so we can free/replace cleanly below
    }
    a->slots = (WValue *)new_data;
    w_views_after_realloc(arr, old_slots, (WValue *)new_data);
    array_release_slots(old_slots, a->ebits, old_cap, old_flags);
    a->flags &= (uint8_t)~(W_FLAG_INLINE | W_FLAG_PAGE_ALIGNED);
    a->cap = (int32_t)new_cap;
    a->start = 0;
    array_write_boxed(a, 0, val);
    a->size++;
    return arr;
}

WValue w_array_get(WValue arr, WValue index) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        int64_t i = w_as_int(index);
        if (i < 0) i += a->size;
        if ((uint64_t)i >= (uint64_t)a->size) return W_NIL;
        if (__builtin_expect(a->ebits == 65, 1)) return a->slots[a->start + i];
        return array_slot_load_decoded(a, i);
    }
    if (w_is_wire_sequence(arr))
        return w_wire_sequence_get(arr, w_as_int(index));
    if (w_is_body(arr)) {
        uint32_t len = w_unbox_body_length(arr);
        int64_t i = w_as_int(index);
        if (i < 0) i += len;
        if (i < 0 || (uint32_t)i >= len) return W_NIL;
        return w_body_arena_get(w_unbox_body_offset(arr), (uint32_t)i);
    }
    if (w_is_range_imm(arr)) {
        int64_t n = w_range_imm_size(arr);
        int64_t i = w_as_int(index);
        if (i < 0) i += n;
        if (i < 0 || i >= n) return W_NIL;
        return w_int(w_range_imm_start(arr) + i);
    }
    w_raise(w_string("expected Array or Range for indexing"));
    return W_NIL;
}

/* Fused subscript-read + machine-int capture: `x = recv[i] ## i64/u64`
 * where recv has no static typed-array identity. The generic path returns
 * a boxed WValue whose fresh bignum box (element > 2^48 from a typed int
 * array) was a dead temporary free-insertion never reclaimed — one leaked
 * bignum per read (2026-07-22). Typed integer arrays load raw here (no box
 * at all); every other receiver — poly arrays, Hash, String, custom []
 * overloads — takes the same dynamic dispatch as before and the same
 * w_to_i64/w_to_u64 coercion (those results are stored or small values, so
 * nothing new is allocated). OOB mirrors the old path exactly: the
 * coercion of W_NIL. */
static WValue w_index_fused_dispatch(WValue recv, WValue idx) {
    /* Shared static cache: same racy-repopulate pattern as the per-callsite
     * caches in generated code. */
    static WInlineCache ic;
    return w_method_call_cached(recv, WN_idx, &idx, 1, &ic);
}

static int w_index_fused_raw(WValue recv, WValue idx, int64_t *out) {
    if (!w_is_body(recv) && w_is_array(recv)) {
        WArray *a = w_as_array(recv);
        if (!array_is_wvalue(a) && !array_is_float(a) && a->ebits != 1) {
            int64_t i = w_as_int(idx);
            if (i < 0) i += a->size;
            if (i < 0 || i >= a->size) return 0;
            *out = array_is_signed_int(a)
                       ? array_read_signed(a, a->start + i)
                       : (int64_t)array_read(a, a->start + i);
            return 1;
        }
    }
    return -1;
}

int64_t w_index_raw_i64(WValue recv, WValue idx) {
    int64_t v;
    int hit = w_index_fused_raw(recv, idx, &v);
    if (hit == 1) return v;
    if (hit == 0) return w_to_i64(W_NIL);
    return w_to_i64(w_index_fused_dispatch(recv, idx));
}

/* Write-side twins (round-3 bug 4, 2026-07-22): `recv[i] = v` where v is a
 * raw machine int and recv has no static typed-array identity. The generic
 * path boxes v (heap bignum past 2^48) only for the typed-array setter to
 * unbox it again — a dead box per write. Typed integer arrays store raw
 * here with w_array_write_at's exact bounds/negative-wrap/size-extension
 * semantics; float, u1, poly, and non-array receivers fall back to box +
 * the same "[]=" dynamic dispatch as before (strict u1 raises, custom
 * overloads, Hash writes all byte-identical). Returns the raw value —
 * assignment-as-expression semantics are `v` on every path, and the
 * compiler types the result :raw_i64/:raw_u64 so statement position never
 * boxes it. */
static void w_index_set_fused_dispatch(WValue recv, WValue idx, WValue val) {
    static WInlineCache ic;
    WValue args[2];
    args[0] = idx;
    args[1] = val;
    w_method_call_cached(recv, WN_idxset, args, 2, &ic);
}

static int w_index_set_fused_raw(WValue recv, WValue idx, int64_t raw) {
    if (!w_is_body(recv) && w_is_array(recv)) {
        WArray *a = w_as_array(recv);
        if (!array_is_wvalue(a) && !array_is_float(a) && a->ebits != 1) {
            int64_t i = w_as_int(idx);
            if (i < 0) i += a->size;
            if (i < 0 || i >= a->cap) return 1;   /* OOB: silent no-op, as w_array_write_at */
            array_write(a, a->start + i, (uint64_t)raw);
            if (i >= a->size) a->size = i + 1;
            return 1;
        }
    }
    return 0;
}

int64_t w_index_set_raw_i64(WValue recv, WValue idx, int64_t raw) {
    if (!w_index_set_fused_raw(recv, idx, raw))
        w_index_set_fused_dispatch(recv, idx, w_int(raw));
    return raw;
}

int64_t w_index_set_raw_u64(WValue recv, WValue idx, int64_t raw) {
    if (!w_index_set_fused_raw(recv, idx, raw))
        w_index_set_fused_dispatch(recv, idx, w_u64((uint64_t)raw));
    return raw;
}

int64_t w_index_raw_u64(WValue recv, WValue idx) {
    int64_t v;
    int hit = w_index_fused_raw(recv, idx, &v);
    if (hit == 1) return v;
    if (hit == 0) return (int64_t)w_to_u64(W_NIL);
    return (int64_t)w_to_u64(w_index_fused_dispatch(recv, idx));
}

/* Raw-index twin of w_array_get, same negative-wrap and nil-on-OOB
 * semantics — emitted when the index is already a raw machine int. */
WValue w_array_get_i64(WValue arr, int64_t i) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        if (i < 0) i += a->size;
        if ((uint64_t)i >= (uint64_t)a->size) return W_NIL;
        if (__builtin_expect(a->ebits == 65, 1)) return a->slots[a->start + i];
        return array_slot_load_decoded(a, i);
    }
    if (w_is_wire_sequence(arr)) return w_wire_sequence_get(arr, i);
    if (w_is_body(arr)) {
        uint32_t len = w_unbox_body_length(arr);
        if (i < 0) i += len;
        if (i < 0 || (uint32_t)i >= len) return W_NIL;
        return w_body_arena_get(w_unbox_body_offset(arr), (uint32_t)i);
    }
    WArray *a = w_as_array(arr);
    if (i < 0) i += a->size;
    if (i < 0 || i >= a->size) return W_NIL;
    return array_slot_load_decoded(a, i);
}

/* Shared core of the `[]=` writers: negative-index normalization, cap
 * bounds, ebits-aware store, and size bump. `arr` is a validated WArray. */
static WValue w_array_write_at(WArray *a, int64_t i, WValue val) {
    if (i < 0) i += a->size;
    if ((uint64_t)i >= (uint64_t)a->cap) return val;
    if (__builtin_expect(a->ebits == 65, 1)) {
        a->slots[a->start + i] = val;
        if (i >= a->size) a->size = i + 1;
        return val;
    }
    if (array_is_float(a)) {
        double boxed = as_numeric_double(val);
        array_write_float(a, a->start + i, boxed);
        if (i >= a->size) a->size = i + 1;
        return w_float(boxed);
    }
    if (a->ebits == 1) {
        /* Bit-packed (u1 / BoolArray): strict — only W_NIL / W_FALSE /
         * int 0 store as 0, only W_TRUE / int 1 store as 1. Anything
         * else (truthy ints like 2, strings, objects, …) raises rather
         * than silently coercing — a u1 cell can't represent them and
         * a quiet truthiness conversion at this layer would mask bugs.
         * BoolArray (or any class that wants relaxed truthiness) can
         * coerce in the wrapper. */
        int bit;
        if (val == W_NIL || val == W_FALSE) {
            bit = 0;
        } else if (val == W_TRUE) {
            bit = 1;
        } else if (w_is_int(val)) {
            int64_t iv = w_as_int(val);
            if (iv == 0) bit = 0;
            else if (iv == 1) bit = 1;
            else w_raise(w_string("invalid argument: u1[] expects 0/1/true/false/nil"));
        } else {
            w_raise(w_string("invalid argument: u1[] expects 0/1/true/false/nil"));
            return val;  /* unreachable; w_raise is no-return */
        }
        array_write(a, a->start + i, (uint64_t)bit);
        if (i >= a->size) a->size = i + 1;
        return val;
    }
    array_write(a, a->start + i, (uint64_t)w_to_i64(val));
    if (i >= a->size) a->size = i + 1;
    return val;
}

WValue w_array_set(WValue arr, WValue index, WValue val) {
    if (__builtin_expect(w_is_array(arr), 1))
        return w_array_write_at(w_as_array(arr), w_as_int(index), val);
    if (w_is_wire_sequence(arr))
        return w_wire_sequence_set(arr, w_as_int(index), val);
    if (w_is_body(arr)) {
        w_raise_error_named("FrozenError", "[]=: cannot mutate an AST body reference (immutable once frozen)");
    }
    return w_array_write_at(w_as_array(arr), w_as_int(index), val);
}

/* Raw-index twin of w_array_set: the compiler emits this for `self[i] = v`
 * with a raw machine-int index inside an Array-tier class method, where self
 * is always a real WArray (never a packed body ref), so the body check and
 * the w_as_int unbox both drop out. Saves the w_int box at the call site too. */
WValue w_array_set_i64(WValue arr, int64_t i, WValue val) {
    if (__builtin_expect(w_is_array(arr), 1))
        return w_array_write_at(w_as_array(arr), i, val);
    if (w_is_wire_sequence(arr)) return w_wire_sequence_set(arr, i, val);
    return w_array_write_at(w_as_array(arr), i, val);
}

/* Unchecked WN_idx / WN_idxset for Array tier. No negative-
 * index normalization, no bounds check. Caller proves bounds. */
WValue w_array_idx(WValue arr, WValue index) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        int64_t i = w_as_int(index);
        if (__builtin_expect(a->ebits == 65, 1)) return a->slots[a->start + i];
        return array_slot_load_decoded(a, i);
    }
    if (w_is_wire_sequence(arr))
        return w_wire_sequence_get(arr, w_as_int(index));
    WArray *a = w_as_array(arr);
    int64_t i = w_as_int(index);
    return array_slot_load_decoded(a, i);
}

/* Raw-index twin of w_array_idx: the compiler emits this when the index is
 * already a raw machine int, saving a w_int box + w_as_int unbox per element
 * in hot array loops (core/array.w method bodies). */
WValue w_array_idx_i64(WValue arr, int64_t i) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        if (__builtin_expect(a->ebits == 65, 1)) return a->slots[a->start + i];
        return array_slot_load_decoded(a, i);
    }
    if (w_is_wire_sequence(arr)) return w_wire_sequence_get(arr, i);
    WArray *a = w_as_array(arr);
    return array_slot_load_decoded(a, i);
}

WValue w_array_idxset(WValue arr, WValue index, WValue val) {
    if (__builtin_expect(w_is_array(arr), 1)) {
        WArray *a = w_as_array(arr);
        int64_t i = w_as_int(index);
        if (__builtin_expect(a->ebits == 65, 1)) {
            a->slots[a->start + i] = val;
            if (i >= a->size) a->size = i + 1;
            return val;
        }
    } else if (w_is_wire_sequence(arr)) {
        return w_wire_sequence_set(arr, w_as_int(index), val);
    }
    WArray *a = w_as_array(arr);
    int64_t i = w_as_int(index);
    if (array_is_wvalue(a)) {
        array_write(a, a->start + i, (uint64_t)val);
    } else if (array_is_float(a)) {
        array_write_float(a, a->start + i, as_numeric_double(val));
    } else if (a->ebits == 1) {
        /* Bit-packed (u1 / BoolArray): strict — only 0/1/true/false/nil
         * are accepted; anything else raises. Same rule as w_array_set. */
        int bit;
        if (val == W_NIL || val == W_FALSE) {
            bit = 0;
        } else if (val == W_TRUE) {
            bit = 1;
        } else if (w_is_int(val)) {
            int64_t iv = w_as_int(val);
            if (iv == 0) bit = 0;
            else if (iv == 1) bit = 1;
            else w_raise(w_string("invalid argument: u1[] expects 0/1/true/false/nil"));
        } else {
            w_raise(w_string("invalid argument: u1[] expects 0/1/true/false/nil"));
            return val;  /* unreachable */
        }
        array_write(a, a->start + i, (uint64_t)bit);
    } else {
        array_write(a, a->start + i, (uint64_t)w_to_i64(val));
    }
    if (i >= a->size) a->size = i + 1;
    return val;
}

/* Raw-typed monomorphization helpers — int64 idx, raw machine val.
 * For float ebits, raw_val carries the IEEE-754 bit pattern (caller
 * reinterprets from double to int64 before the call). */
void w_array_set_unchecked(WValue arr, int64_t i, int64_t raw_val) {
    WArray *a = w_as_array(arr);
    if (array_is_float(a)) {
        double d;
        memcpy(&d, &raw_val, sizeof(double));
        array_write_float(a, a->start + i, d);
    } else {
        array_write(a, a->start + i, (uint64_t)raw_val);
    }
    if (i >= a->size) a->size = (int32_t)(i + 1);
}

int64_t w_array_get_unchecked_raw(WValue arr, int64_t i) {
    WArray *a = w_as_array(arr);
    if (array_is_float(a)) {
        double d = array_read_float(a, a->start + i);
        int64_t bits;
        memcpy(&bits, &d, sizeof(int64_t));
        return bits;
    }
    return (int64_t)array_read(a, a->start + i);
}

WValue w_array_size(WValue arr) {
    if (__builtin_expect(w_is_array(arr), 1))
        return w_int(w_as_array(arr)->size);
    if (w_is_wire_sequence(arr)) return w_int(w_wire_sequence_size(arr));
    if (w_is_body(arr)) return w_int(w_unbox_body_length(arr));
    if (w_is_range_imm(arr)) return w_int(w_range_imm_size(arr));
    w_raise(w_string("expected Array or Range"));
    return W_NIL;
}

/* ---- Big Array (i64 fields) ----
 *
 * Same shape as WArray but every length/cap/start is i64 so the
 * runtime can address >2^32 elements. Used by mmap views (file lengths can
 * exceed 4 GB / 4 G elements once the element type narrows), KV caches,
 * model weights. Subtag W_SUBTAG_GENERIC; class registration is wired separately.
 */
WValue w_big_array_new(int64_t ebits, int64_t cap) {
    if (cap <= 0) cap = 8;
    WBigArray *a = (WBigArray *)calloc(1, sizeof(WBigArray));
    a->type  = W_TYPE_BIG_ARRAY;
    a->flags = W_FLAG_OWNED;
    a->ebits = (uint8_t)(ebits & 0xFF);
    a->start = 0;
    a->size  = 0;
    a->cap   = cap;
    int64_t byte_sz = array_byte_size(ebits, cap);
    a->slots = (uint8_t *)calloc(1, (size_t)byte_sz);
    w_gc_on_big_array(a, sizeof(WBigArray) + (size_t)byte_sz);
    return w_box_ptr(a, W_SUBTAG_GENERIC);
}

WValue w_big_array_view(uint8_t *data, int64_t ebits, int64_t length) {
    WBigArray *a = (WBigArray *)calloc(1, sizeof(WBigArray));
    a->type  = W_TYPE_BIG_ARRAY;
    a->flags = W_FLAG_VIEW;     /* not owned, push/grow rejected */
    a->ebits = (uint8_t)(ebits & 0xFF);
    a->start = 0;
    a->size  = length;
    a->cap   = length;
    a->slots = data;
    w_gc_on_big_array(a, sizeof(WBigArray));
    return w_box_ptr(a, W_SUBTAG_GENERIC);
}

/* BigArray#subview(lo, len) — zero-copy slice. Mirrors w_array_view but
 * keeps the i64 widths the BigArray fields use. Pre-offsets `slots` rather
 * than carrying a non-zero start, so downstream loads (and the
 * metal_buffer_or_wrap_array no-copy path) see a buffer that begins at
 * the slice's byte 0. The parent must outlive the view. */
WValue w_big_array_subview(WValue arr_val, int64_t lo, int64_t len) {
    WBigArray *src = (WBigArray *)w_as_ptr(arr_val);
    if (lo < 0) lo = src->size + lo;
    if (lo < 0) lo = 0;
    if (lo > src->size) lo = src->size;
    if (len < 0) len = 0;
    if (lo + len > src->size) len = src->size - lo;

    int8_t eb = (int8_t)src->ebits;
    int64_t abs_bits = array_storage_bits(eb);
    int64_t base_index = src->start + lo;
    uint8_t *base;
    if (abs_bits == 4) {
        if (base_index & 1) {
            w_raise(w_string("BigArray#subview: 4-bit slice on odd-nibble boundary not supported"));
            return W_NIL;
        }
        base = src->slots + base_index / 2;
    } else if (abs_bits == 1) {
        if (base_index & 7) {
            w_raise(w_string("BigArray#subview: u1 slice must align on a byte boundary"));
            return W_NIL;
        }
        base = src->slots + base_index / 8;
    } else {
        base = src->slots + base_index * (abs_bits / 8);
    }
    return w_big_array_view(base, (int64_t)src->ebits, len);
}

WValue w_big_array_view_range(WValue arr_val, WValue from_v, WValue to_v, WValue exclusive_v) {
    WBigArray *src = (WBigArray *)w_as_ptr(arr_val);
    int64_t from = w_as_int(from_v);
    int64_t to   = w_as_int(to_v);
    int     excl = (exclusive_v == W_TRUE);
    if (from < 0) from = src->size + from;
    if (to   < 0) to   = src->size + to;
    if (from < 0) from = 0;
    if (!excl) to += 1;          /* inclusive → exclusive end */
    if (to > src->size) to = src->size;
    int64_t len = to - from;
    if (len < 0) len = 0;
    return w_big_array_subview(arr_val, from, len);
}

WValue w_big_array_size(WValue arr) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    return w_int(a->size);
}

/* w_big_array_get/set/push: minimal scalar paths. They read/write through
 * the WArray helpers by treating the WBigArray prefix as a transient
 * WArray view — same ebits, same packed-byte layout, same `slots`
 * pointer. The two will later collapse into a single inline op family. */
static inline WArray big_as_typed_view(WBigArray *a) {
    WArray view;
    view.flags = a->flags;
    view.ebits = (int8_t)a->ebits;
    view.start = a->start;
    view.size  = a->size;
    view.cap   = a->cap;
    view.slots = (WValue *)a->slots;
    return view;
}

WValue w_big_array_get(WValue arr, WValue index) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    if (i < 0) i += a->size;
    if (i < 0 || i >= a->size) return W_NIL;
    WArray view = big_as_typed_view(a);
    return array_slot_load_decoded(&view, i);
}

WValue w_big_array_set(WValue arr, WValue index, WValue val) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    if (i < 0) i += a->size;
    if (i < 0 || i >= a->cap) return val;
    WArray view = big_as_typed_view(a);
    if (array_is_wvalue(&view)) {
        array_write(&view, view.start + i, (uint64_t)val);
    } else if (array_is_float(&view)) {
        double boxed = as_numeric_double(val);
        array_write_float(&view, view.start + i, boxed);
    } else {
        array_write(&view, view.start + i, (uint64_t)w_to_i64(val));
    }
    if (i >= a->size) a->size = i + 1;
    return val;
}

/* Unchecked WN_idx / WN_idxset for BigArray tier. */
WValue w_big_array_idx(WValue arr, WValue index) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    WArray view = big_as_typed_view(a);
    return array_slot_load_decoded(&view, i);
}

WValue w_big_array_idxset(WValue arr, WValue index, WValue val) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    WArray view = big_as_typed_view(a);
    if (array_is_wvalue(&view)) {
        array_write(&view, view.start + i, (uint64_t)val);
    } else if (array_is_float(&view)) {
        array_write_float(&view, view.start + i, as_numeric_double(val));
    } else {
        array_write(&view, view.start + i, (uint64_t)w_to_i64(val));
    }
    if (i >= a->size) a->size = i + 1;
    return val;
}

void w_big_array_set_unchecked(WValue arr, int64_t i, int64_t raw_val) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    WArray view = big_as_typed_view(a);
    if (array_is_float(&view)) {
        double d;
        memcpy(&d, &raw_val, sizeof(double));
        array_write_float(&view, view.start + i, d);
    } else {
        array_write(&view, view.start + i, (uint64_t)raw_val);
    }
    if (i >= a->size) a->size = i + 1;
}

int64_t w_big_array_get_unchecked_raw(WValue arr, int64_t i) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    WArray view = big_as_typed_view(a);
    if (array_is_float(&view)) {
        double d = array_read_float(&view, view.start + i);
        int64_t bits;
        memcpy(&bits, &d, sizeof(int64_t));
        return bits;
    }
    return (int64_t)array_read(&view, view.start + i);
}

WValue w_big_array_push(WValue arr, WValue val) {
    WBigArray *a = (WBigArray *)w_as_ptr(arr);
    if ((a->flags & W_FLAG_OWNED) == 0) {
        w_raise(w_string("BigArray push: cannot grow a borrowed view"));
    }
    if (a->start + a->size >= a->cap) {
        int64_t new_cap = a->cap > 0 ? a->cap * 2 : 8;
        uint8_t *nb = (uint8_t *)calloc(1, array_byte_size(a->ebits, new_cap));
        memcpy(nb, a->slots, array_byte_size(a->ebits, a->size));
        a->slots = nb;
        a->cap = new_cap;
        a->start = 0;
    }
    WArray view = big_as_typed_view(a);
    if (array_is_wvalue(&view)) {
        array_write(&view, a->start + a->size, (uint64_t)val);
    } else if (array_is_float(&view)) {
        array_write_float(&view, a->start + a->size, as_numeric_double(val));
    } else {
        array_write(&view, a->start + a->size, (uint64_t)w_to_i64(val));
    }
    a->size++;
    return arr;
}

/* ---- Small Array (frozen, ≤255 elements, packed header) ----
 *
 * Single allocation: 2-byte header followed by inline element bytes. The
 * struct's flexible-array `slots` member lets us treat the payload as
 * packed bytes the same way WArray.data does. Use cases: shapes,
 * strides, top-k indices, scalar arg packs, memoization keys. Frozen at
 * construction — no push, no resize, no shift. */
WValue w_small_array_new(int64_t ebits, int64_t size, int64_t bytes_ptr) {
    if (size < 0 || size > 255) w_raise(w_string("SmallArray size must be 0..255"));
    if (!array_ebits_valid(ebits)) w_raise(w_string("SmallArray has an unsupported element type"));
    int64_t byte_count = array_byte_size(ebits, size);
    size_t alloc_bytes = sizeof(WSmallArray) + (size_t)byte_count + 1u;
    WSmallArray *a = (WSmallArray *)calloc(1, alloc_bytes);
    a->ebits = (uint8_t)ebits;
    a->size  = (uint8_t)size;
    if (bytes_ptr != 0 && byte_count > 0) {
        memcpy(a->slots, (const uint8_t *)(uintptr_t)bytes_ptr, (size_t)byte_count);
    }
    w_gc_on_small_array(a, alloc_bytes);
    return w_box_ptr(a, W_SUBTAG_SMALL_ARRAY);
}

static int64_t small_array_ebits_from_value(WValue value) {
    if (w_is_int(value) || w_is_bigint(value)) {
        int64_t bits = w_numeric_to_i64(value);
        if (array_ebits_valid(bits)) return bits;
        w_raise(w_string("SmallArray has an unsupported element type"));
    }
    if (!w_is_stringy(value)) {
        w_raise(w_string("SmallArray element type must be a Symbol or ebits Integer"));
    }

    const char *name = as_str(value);
    if (strcmp(name, "bool") == 0 || strcmp(name, "u1") == 0) return 1;
    if (strcmp(name, "u4") == 0) return 4;
    if (strcmp(name, "i4") == 0) return -4;
    if (strcmp(name, "u8") == 0) return 8;
    if (strcmp(name, "i8") == 0) return 108;
    if (strcmp(name, "u16") == 0) return 16;
    if (strcmp(name, "i16") == 0) return 116;
    if (strcmp(name, "u32") == 0) return 32;
    if (strcmp(name, "i32") == 0) return 33;
    if (strcmp(name, "u64") == 0) return 64;
    if (strcmp(name, "w64") == 0) return 65;
    if (strcmp(name, "i64") == 0) return 66;
    if (strcmp(name, "f16") == 0) return -16;
    if (strcmp(name, "f32") == 0) return -32;
    if (strcmp(name, "f64") == 0) return -64;
    if (strcmp(name, "f4_e2m1") == 0) return -104;
    if (strcmp(name, "f8_e4m3") == 0) return -108;
    if (strcmp(name, "f8_e5m2") == 0) return -109;
    if (strcmp(name, "bf16") == 0) return -116;

    w_raise(w_string("SmallArray has an unsupported element type"));
    return 0;
}

WValue w_small_array_new_value(WValue ebits_v, WValue size_v) {
    if (!w_is_int(size_v) && !w_is_bigint(size_v)) {
        w_raise(w_string("SmallArray size must be an Integer"));
    }
    int64_t size = w_numeric_to_i64(size_v);
    int64_t ebits = small_array_ebits_from_value(ebits_v);
    return w_small_array_new(ebits, size, 0);
}

/* In-place SmallArray initialize at a caller-provided pointer.
 * Used when the compiler stack-allocates the buffer via LLVM `alloca` and
 * needs the runtime to stamp the WSmallArray header. The caller passes
 * `mem` as an int64-encoded pointer (matches the Tungsten ccall ABI for
 * raw pointers). The caller is responsible for sizing the alloca to
 * `sizeof(WSmallArray) + array_byte_size(ebits, size)` bytes; this fn
 * just writes the header. Returns the boxed WValue. */
WValue w_small_array_init(int64_t mem, int64_t ebits, int64_t size) {
    if (size < 0 || size > 255) w_raise(w_string("SmallArray size must be 0..255"));
    WSmallArray *a = (WSmallArray *)(uintptr_t)mem;
    a->ebits = (uint8_t)ebits;
    a->size  = (uint8_t)size;
    /* slots are NOT zero-filled here: the caller's alloca hands back
     * whatever the previous frame at this depth left behind. Tungsten's
     * `i64[n]` / `SmallArray.new(:i64, n)` are zero-initialised by
     * contract, so the emitter pairs every small_array_alloca with a
     * `store [N x i8] zeroinitializer` before this call (emitter.w,
     * `when :small_array_alloca`). Keeping the zeroing on the emitter
     * side lets SROA/DSE delete it at sites that overwrite every slot;
     * doing it here would be an opaque call LLVM cannot elide. */
    return w_box_ptr(a, W_SUBTAG_SMALL_ARRAY);
}

WValue w_small_array_size(WValue arr) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    return w_int(a->size);
}

WValue w_small_array_get(WValue arr, WValue index) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    if (i < 0) i += a->size;
    if (i < 0 || i >= a->size) return W_NIL;
    /* Reuse WArray.read by overlaying a transient view that points at
     * the inline payload. ebits below 32 use the same scalar code paths. */
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    return array_slot_load_decoded(&view, i);
}

/* Bounds-checked SmallArray set. Negative indices wrap from end (i += size).
 * Out-of-bounds is a silent no-op returning val (matches w_array_set). */
WValue w_small_array_set(WValue arr, WValue index, WValue val) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    if (i < 0) i += a->size;
    if (i < 0 || i >= a->size) return val;
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    if (array_is_wvalue(&view)) {
        array_write(&view, i, (uint64_t)val);
    } else if (array_is_float(&view)) {
        array_write_float(&view, i, as_numeric_double(val));
    } else {
        array_write(&view, i, (uint64_t)w_to_i64(val));
    }
    return val;
}

/* Unchecked SmallArray idx-style accessors for the WN_idx / WN_idxset
 * path. Skip negative-index normalization and bounds check — caller
 * proves the index is in [0, size). val is still a WValue (for the
 * untyped dispatch path). The raw-typed variants below are for
 * monomorphized callsites that already have unboxed values. */
WValue w_small_array_idx(WValue arr, WValue index) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    return array_slot_load_decoded(&view, i);
}

WValue w_small_array_idxset(WValue arr, WValue index, WValue val) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    int64_t i = w_as_int(index);
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    if (array_is_wvalue(&view)) {
        array_write(&view, i, (uint64_t)val);
    } else if (array_is_float(&view)) {
        array_write_float(&view, i, as_numeric_double(val));
    } else {
        array_write(&view, i, (uint64_t)w_to_i64(val));
    }
    return val;
}

/* Raw-typed unchecked accessors for monomorphized callsites. Index is
 * raw int64 (no boxing). For int ebits, raw_val is the integer value;
 * for float ebits, raw_val is the f64/f32 bit pattern reinterpreted as
 * int64 (caller side: raw_val = (int64)(*(uint64_t*)&dbl)). The mono-
 * morphized codegen knows the receiver's ebits at compile time and emits
 * the correct caller-side reinterpret. */
void w_small_array_set_unchecked(WValue arr, int64_t i, int64_t raw_val) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    if (array_is_float(&view)) {
        double d;
        memcpy(&d, &raw_val, sizeof(double));
        array_write_float(&view, i, d);
    } else {
        array_write(&view, i, (uint64_t)raw_val);
    }
}

int64_t w_small_array_get_unchecked(WValue arr, int64_t i) {
    WSmallArray *a = (WSmallArray *)w_as_ptr(arr);
    WArray view;
    view.flags = 0;
    view.ebits = (int8_t)a->ebits;
    view.start = 0;
    view.size  = a->size;
    view.cap   = a->size;
    view.slots = (WValue *)a->slots;
    if (array_is_float(&view)) {
        double d = array_read_float(&view, i);
        int64_t bits;
        memcpy(&bits, &d, sizeof(int64_t));
        return bits;
    }
    return (int64_t)array_read(&view, i);
}

/* i8-index variants: SmallArray's max size is 255, so all valid indices
 * fit in an i8. Monomorphized callsites that have an i8 index can call
 * these directly, eliminating the i8→i64 sext at the call boundary and
 * letting the compiler emit single-byte immediate gep offsets. */
void w_small_array_set_unchecked_i8(WValue arr, int8_t i, int64_t raw_val) {
    w_small_array_set_unchecked(arr, (int64_t)(uint8_t)i, raw_val);
}

int64_t w_small_array_get_unchecked_i8(WValue arr, int8_t i) {
    return w_small_array_get_unchecked(arr, (int64_t)(uint8_t)i);
}

static inline int64_t array_read_signed(WArray *a, int64_t i) {
    uint64_t raw = array_read(a, i);
    int64_t bits = array_storage_bits(a->ebits);
    if (bits >= 64) return (int64_t)raw;
    uint64_t sign = 1ULL << (bits - 1);
    return (int64_t)((raw ^ sign) - sign);
}


static int64_t array_dot_i8_ptr(const uint8_t *ap, const uint8_t *bp, int64_t n,
                                int signed_a, int signed_b) {
    int64_t acc = 0;
    int64_t i = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_DOTPROD)
    /* Drain the 32-bit lanes into the i64 accumulator every DOT_CHUNK
     * iterations (16 elements each; 4 products per lane per iteration).
     * 16384 iterations bound a lane by 4*65025*16384 < 2^32 (u8*u8) and
     * 4*32640*16384 < 2^31 (mixed) — without this the lanes silently
     * wrapped past ~264k elements. */
    enum { W_DOT_CHUNK_ITERS = 16384 };
    if (signed_a && signed_b) {
        while (n - i >= 16) {
            int64_t iters = (n - i) / 16;
            if (iters > W_DOT_CHUNK_ITERS) iters = W_DOT_CHUNK_ITERS;
            int32x4_t vacc = vdupq_n_s32(0);
            const uint8_t *pa = ap + i, *pb = bp + i;
            for (int64_t t = 0; t < iters; t++)
                vacc = vdotq_s32(vacc, vld1q_s8((const int8_t *)(pa + t * 16)),
                                 vld1q_s8((const int8_t *)(pb + t * 16)));
            int32_t tmp[4];
            vst1q_s32(tmp, vacc);
            acc += (int64_t)tmp[0] + (int64_t)tmp[1] + (int64_t)tmp[2] + (int64_t)tmp[3];
            i += iters * 16;
        }
    } else if (!signed_a && !signed_b) {
        while (n - i >= 16) {
            int64_t iters = (n - i) / 16;
            if (iters > W_DOT_CHUNK_ITERS) iters = W_DOT_CHUNK_ITERS;
            uint32x4_t vacc = vdupq_n_u32(0);
            const uint8_t *pa = ap + i, *pb = bp + i;
            for (int64_t t = 0; t < iters; t++)
                vacc = vdotq_u32(vacc, vld1q_u8(pa + t * 16), vld1q_u8(pb + t * 16));
            uint32_t tmp[4];
            vst1q_u32(tmp, vacc);
            acc += (int64_t)((uint64_t)tmp[0] + (uint64_t)tmp[1] + (uint64_t)tmp[2] + (uint64_t)tmp[3]);
            i += iters * 16;
        }
    }
#if defined(__ARM_FEATURE_MATMUL_INT8)
    else {
        /* Mixed sign: USDOT (FEAT_I8MM) takes (u8, s8) — swap so the
         * unsigned operand is first; dot is commutative. */
        const uint8_t *up = signed_a ? bp : ap;
        const int8_t *sp = (const int8_t *)(signed_a ? ap : bp);
        while (n - i >= 16) {
            int64_t iters = (n - i) / 16;
            if (iters > W_DOT_CHUNK_ITERS) iters = W_DOT_CHUNK_ITERS;
            int32x4_t vacc = vdupq_n_s32(0);
            const uint8_t *pu = up + i;
            const int8_t *ps = sp + i;
            for (int64_t t = 0; t < iters; t++)
                vacc = vusdotq_s32(vacc, vld1q_u8(pu + t * 16), vld1q_s8(ps + t * 16));
            int32_t tmp[4];
            vst1q_s32(tmp, vacc);
            acc += (int64_t)tmp[0] + (int64_t)tmp[1] + (int64_t)tmp[2] + (int64_t)tmp[3];
            i += iters * 16;
        }
    }
#endif
#endif
    while (i < n) {
        int av = signed_a ? (int)((const int8_t *)ap)[i] : (int)ap[i];
        int bv = signed_b ? (int)((const int8_t *)bp)[i] : (int)bp[i];
        acc += (int64_t)av * (int64_t)bv;
        i++;
    }
    return acc;
}

static int64_t array_dot_i8_arrays(WArray *a, WArray *b) {
    const uint8_t *ap = (const uint8_t *)a->slots + a->start;
    const uint8_t *bp = (const uint8_t *)b->slots + b->start;
    return array_dot_i8_ptr(ap, bp, a->size, array_is_signed_int(a), array_is_signed_int(b));
}

static int64_t array_matmul_i8_cell_scalar(WArray *a, WArray *b,
                                           int64_t row, int64_t col,
                                           int64_t k, int64_t ncols) {
    const uint8_t *ap = (const uint8_t *)a->slots + a->start + row * k;
    const uint8_t *bp = (const uint8_t *)b->slots + b->start;
    int signed_a = array_is_signed_int(a);
    int signed_b = array_is_signed_int(b);
    int64_t acc = 0;
    for (int64_t kk = 0; kk < k; kk++) {
        int av = signed_a ? (int)((const int8_t *)ap)[kk] : (int)ap[kk];
        uint8_t braw = bp[kk * ncols + col];
        int bv = signed_b ? (int)(int8_t)braw : (int)braw;
        acc += (int64_t)av * (int64_t)bv;
    }
    return acc;
}

static __thread uint8_t *g_i8_matmul_rhs_pack;
static __thread size_t g_i8_matmul_rhs_pack_capacity;

/* Transpose row-major KxN RHS storage to N contiguous K-byte columns once.
 * The old I8MM loop gathered those bytes for every 2x2 output tile, repeating
 * the same strided loads for every pair of lhs rows. */
static const uint8_t *array_matmul_i8_pack_rhs(WArray *b, int64_t k,
                                               int64_t n) {
    size_t needed = (size_t)k * (size_t)n;
    if (needed > g_i8_matmul_rhs_pack_capacity) {
        size_t next = g_i8_matmul_rhs_pack_capacity > 0
                    ? g_i8_matmul_rhs_pack_capacity : 4096;
        while (next < needed) next *= 2;
        uint8_t *grown = realloc(g_i8_matmul_rhs_pack, next);
        if (!grown) die("i8 matmul RHS pack allocation failed");
        g_i8_matmul_rhs_pack = grown;
        g_i8_matmul_rhs_pack_capacity = next;
    }
    const uint8_t *src = (const uint8_t *)b->slots + b->start;
    for (int64_t col = 0; col < n; col++) {
        uint8_t *dst = g_i8_matmul_rhs_pack + col * k;
        for (int64_t row = 0; row < k; row++) dst[row] = src[row * n + col];
    }
    return g_i8_matmul_rhs_pack;
}

static int64_t array_matmul_i8_cell(WArray *a, WArray *b,
                                    const uint8_t *packed_b, int64_t row,
                                    int64_t col, int64_t k, int64_t ncols) {
    if (!packed_b)
        return array_matmul_i8_cell_scalar(a, b, row, col, k, ncols);
    const uint8_t *ap = (const uint8_t *)a->slots + a->start + row * k;
    return array_dot_i8_ptr(ap, packed_b + col * k, k,
                            array_is_signed_int(a), array_is_signed_int(b));
}

static inline double array_read_numeric(WArray *a, int64_t i, int signed_values) {
    if (array_is_float(a)) return array_read_float(a, i);
    if (signed_values) return (double)array_read_signed(a, i);
    return (double)array_read(a, i);
}

static WValue array_minmax_int(WValue arr, int signed_values, int want_max) {
    WArray *a = w_as_array(arr);
    if (a->size == 0) return W_NIL;
    int64_t start = a->start;
    int64_t end = start + a->size;
    if (signed_values) {
        int64_t best = array_read_signed(a, start);
        for (int64_t i = start + 1; i < end; i++) {
            int64_t v = array_read_signed(a, i);
            if (want_max ? (v > best) : (v < best)) best = v;
        }
        return w_int(best);
    }
    uint64_t best = array_read(a, start);
    for (int64_t i = start + 1; i < end; i++) {
        uint64_t v = array_read(a, i);
        if (want_max ? (v > best) : (v < best)) best = v;
    }
    return w_u64(best);
}

#define W_FLOAT_REDUCE_THREAD_MIN_SIZE (1024 * 1024)
#define W_FLOAT_REDUCE_N_THREADS       8

static double array_float_sum_range(WArray *a, int64_t off, int64_t n) {
    double acc = 0.0;
    if (a->ebits == -32) {
        float *p = (float *)a->slots + a->start + off;
        int64_t i = 0;
#ifdef __aarch64__
        if (n >= 16) {
            float32x4_t vacc = vdupq_n_f32(0.0f);
            int64_t end = n - 4;
            while (i <= end) {
                vacc = vaddq_f32(vacc, vld1q_f32(p + i));
                i += 4;
            }
            float tmp[4];
            vst1q_f32(tmp, vacc);
            acc = (double)tmp[0] + (double)tmp[1] + (double)tmp[2] + (double)tmp[3];
        }
#endif
        while (i < n) acc += (double)p[i++];
        return acc;
    }
    if (a->ebits == -116 || a->ebits == -16) {
        for (int64_t i = 0; i < n; i++) acc += array_read_float(a, a->start + off + i);
        return acc;
    }
    double *p = (double *)a->slots + a->start + off;
    int64_t i = 0;
#ifdef __aarch64__
    if (n >= 8) {
        float64x2_t vacc = vdupq_n_f64(0.0);
        int64_t end = n - 2;
        while (i <= end) {
            vacc = vaddq_f64(vacc, vld1q_f64(p + i));
            i += 2;
        }
        double tmp[2];
        vst1q_f64(tmp, vacc);
        acc = tmp[0] + tmp[1];
    }
#endif
    while (i < n) acc += p[i++];
    return acc;
}

static double array_float_sumsq_range(WArray *a, int64_t off, int64_t n) {
    double acc = 0.0;
    if (a->ebits == -32) {
        float *p = (float *)a->slots + a->start + off;
        int64_t i = 0;
#ifdef __aarch64__
        if (n >= 16) {
            float32x4_t vacc = vdupq_n_f32(0.0f);
            int64_t end = n - 4;
            while (i <= end) {
                float32x4_t v = vld1q_f32(p + i);
                vacc = vaddq_f32(vacc, vmulq_f32(v, v));
                i += 4;
            }
            float tmp[4];
            vst1q_f32(tmp, vacc);
            acc = (double)tmp[0] + (double)tmp[1] + (double)tmp[2] + (double)tmp[3];
        }
#endif
        while (i < n) {
            double v = (double)p[i++];
            acc += v * v;
        }
        return acc;
    }
    if (a->ebits == -116 || a->ebits == -16) {
        for (int64_t i = 0; i < n; i++) {
            double v = array_read_float(a, a->start + off + i);
            acc += v * v;
        }
        return acc;
    }
    double *p = (double *)a->slots + a->start + off;
    int64_t i = 0;
#ifdef __aarch64__
    if (n >= 8) {
        float64x2_t vacc = vdupq_n_f64(0.0);
        int64_t end = n - 2;
        while (i <= end) {
            float64x2_t v = vld1q_f64(p + i);
            vacc = vaddq_f64(vacc, vmulq_f64(v, v));
            i += 2;
        }
        double tmp[2];
        vst1q_f64(tmp, vacc);
        acc = tmp[0] + tmp[1];
    }
#endif
    while (i < n) {
        double v = p[i++];
        acc += v * v;
    }
    return acc;
}

static double array_float_dot_range(WArray *a, WArray *b, int64_t off, int64_t n) {
    double acc = 0.0;
    if (a->ebits == -32 && b->ebits == -32) {
        float *ap = (float *)a->slots + a->start + off;
        float *bp = (float *)b->slots + b->start + off;
        int64_t i = 0;
#ifdef __aarch64__
        if (n >= 16) {
            float32x4_t vacc = vdupq_n_f32(0.0f);
            int64_t end = n - 4;
            while (i <= end) {
                vacc = vaddq_f32(vacc, vmulq_f32(vld1q_f32(ap + i), vld1q_f32(bp + i)));
                i += 4;
            }
            float tmp[4];
            vst1q_f32(tmp, vacc);
            acc = (double)tmp[0] + (double)tmp[1] + (double)tmp[2] + (double)tmp[3];
        }
#endif
        while (i < n) acc += (double)ap[i] * (double)bp[i], i++;
        return acc;
    }
    if (a->ebits == -64 && b->ebits == -64) {
        double *ap = (double *)a->slots + a->start + off;
        double *bp = (double *)b->slots + b->start + off;
        int64_t i = 0;
#ifdef __aarch64__
        if (n >= 8) {
            float64x2_t vacc = vdupq_n_f64(0.0);
            int64_t end = n - 2;
            while (i <= end) {
                vacc = vaddq_f64(vacc, vmulq_f64(vld1q_f64(ap + i), vld1q_f64(bp + i)));
                i += 2;
            }
            double tmp[2];
            vst1q_f64(tmp, vacc);
            acc = tmp[0] + tmp[1];
        }
#endif
        while (i < n) acc += ap[i] * bp[i], i++;
        return acc;
    }
    if (a->ebits == -116 && b->ebits == -116) {
        uint16_t *ap = (uint16_t *)a->slots + a->start + off;
        uint16_t *bp = (uint16_t *)b->slots + b->start + off;
        int64_t i = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_BF16)
        if (n >= 16) {
            float32x4_t vacc = vdupq_n_f32(0.0f);
            int64_t end = n - 8;
            while (i <= end) {
                bfloat16x8_t av = vld1q_bf16((const bfloat16_t *)(ap + i));
                bfloat16x8_t bv = vld1q_bf16((const bfloat16_t *)(bp + i));
                vacc = vbfmlalbq_f32(vacc, av, bv);
                vacc = vbfmlaltq_f32(vacc, av, bv);
                i += 8;
            }
            float tmp[4];
            vst1q_f32(tmp, vacc);
            acc = (double)tmp[0] + (double)tmp[1] + (double)tmp[2] + (double)tmp[3];
        }
#endif
        while (i < n) {
            uint32_t ab = (uint32_t)ap[i] << 16;
            uint32_t bb = (uint32_t)bp[i] << 16;
            float af;
            float bf;
            memcpy(&af, &ab, sizeof(float));
            memcpy(&bf, &bb, sizeof(float));
            acc += (double)af * (double)bf;
            i++;
        }
        return acc;
    }
    if (a->ebits == -16 && b->ebits == -16) {
        uint16_t *ap = (uint16_t *)a->slots + a->start + off;
        uint16_t *bp = (uint16_t *)b->slots + b->start + off;
        int64_t i = 0;
#ifdef __aarch64__
        /* Widen halves to f32 lanes (fcvtl/fcvtl2) and fma-accumulate; the
         * base v8 conversion forms need no FP16 arithmetic extension. */
        if (n >= 16) {
            float32x4_t vacc = vdupq_n_f32(0.0f);
            int64_t end = n - 8;
            while (i <= end) {
                float16x8_t av = vld1q_f16((const float16_t *)(ap + i));
                float16x8_t bv = vld1q_f16((const float16_t *)(bp + i));
                vacc = vfmaq_f32(vacc, vcvt_f32_f16(vget_low_f16(av)),
                                 vcvt_f32_f16(vget_low_f16(bv)));
                vacc = vfmaq_f32(vacc, vcvt_high_f32_f16(av), vcvt_high_f32_f16(bv));
                i += 8;
            }
            float tmp[4];
            vst1q_f32(tmp, vacc);
            acc = (double)tmp[0] + (double)tmp[1] + (double)tmp[2] + (double)tmp[3];
        }
#endif
        while (i < n) {
            acc += (double)w_half_bits_to_float(ap[i]) * (double)w_half_bits_to_float(bp[i]);
            i++;
        }
        return acc;
    }
    for (int64_t i = 0; i < n; i++) {
        acc += array_read_float(a, a->start + off + i) * array_read_float(b, b->start + off + i);
    }
    return acc;
}

typedef enum {
    W_FLOAT_REDUCE_SUM,
    W_FLOAT_REDUCE_SUMSQ,
    W_FLOAT_REDUCE_DOT
} WFloatReduceKind;

typedef struct {
    WArray *a;
    WArray *b;
    int64_t off;
    int64_t n;
    WFloatReduceKind kind;
    double result;
} WFloatReduceArgs;

static void *w_float_reduce_worker(void *arg) {
    WFloatReduceArgs *a = (WFloatReduceArgs *)arg;
    if (a->kind == W_FLOAT_REDUCE_SUM) {
        a->result = array_float_sum_range(a->a, a->off, a->n);
    } else if (a->kind == W_FLOAT_REDUCE_SUMSQ) {
        a->result = array_float_sumsq_range(a->a, a->off, a->n);
    } else {
        a->result = array_float_dot_range(a->a, a->b, a->off, a->n);
    }
    return NULL;
}

static double array_float_reduce(WArray *a, WArray *b, WFloatReduceKind kind) {
    int64_t n = a->size;
    if (n < W_FLOAT_REDUCE_THREAD_MIN_SIZE) {
        if (kind == W_FLOAT_REDUCE_SUM) return array_float_sum_range(a, 0, n);
        if (kind == W_FLOAT_REDUCE_SUMSQ) return array_float_sumsq_range(a, 0, n);
        return array_float_dot_range(a, b, 0, n);
    }

    pthread_t threads[W_FLOAT_REDUCE_N_THREADS];
    WFloatReduceArgs args[W_FLOAT_REDUCE_N_THREADS];
    int64_t chunk = n / W_FLOAT_REDUCE_N_THREADS;
    int created = 0;
    for (int i = 0; i < W_FLOAT_REDUCE_N_THREADS; i++) {
        args[i].a = a;
        args[i].b = b;
        args[i].off = i * chunk;
        args[i].n = (i == W_FLOAT_REDUCE_N_THREADS - 1) ? n - i * chunk : chunk;
        args[i].kind = kind;
        args[i].result = 0.0;
        if (pthread_create(&threads[i], NULL, w_float_reduce_worker, &args[i]) != 0) {
            for (int j = 0; j < created; j++) pthread_join(threads[j], NULL);
            if (kind == W_FLOAT_REDUCE_SUM) return array_float_sum_range(a, 0, n);
            if (kind == W_FLOAT_REDUCE_SUMSQ) return array_float_sumsq_range(a, 0, n);
            return array_float_dot_range(a, b, 0, n);
        }
        created++;
    }

    double acc = 0.0;
    for (int i = 0; i < W_FLOAT_REDUCE_N_THREADS; i++) {
        pthread_join(threads[i], NULL);
        acc += args[i].result;
    }
    return acc;
}

static WValue array_minmax_float(WValue arr, int want_max) {
    WArray *a = w_as_array(arr);
    if (a->size == 0) return W_NIL;
    /* NaN is missing data (IEEE-754-2019 minimumNumber/maximumNumber),
       regardless of position: seed from the first non-NaN element so a
       leading NaN cannot poison the reduction — the vmaxnm/vminnm vector
       bodies and the `>`/`<` scalar tails below already skip interior
       NaNs, and the SIMD/tail loops re-reading any skipped leading NaNs
       is harmless for the same reason. An all-NaN array returns NaN. */
    double best = array_read_float(a, a->start);
    if (isnan(best)) {
        int64_t seed_end = a->start + a->size, si = a->start;
        while (isnan(best) && ++si < seed_end) best = array_read_float(a, si);
        if (isnan(best)) return w_float(best);
    }

#ifdef __aarch64__
    if (a->ebits == -32 && a->size >= 16) {
        float *p = (float *)a->slots + a->start;
        int64_t i = 1;
        float32x4_t vbest = vdupq_n_f32((float)best);
        int64_t end = a->size - 4;
        while (i <= end) {
            float32x4_t v = vld1q_f32(p + i);
            vbest = want_max ? vmaxnmq_f32(vbest, v) : vminnmq_f32(vbest, v);
            i += 4;
        }
        float tmp[4];
        vst1q_f32(tmp, vbest);
        for (int j = 0; j < 4; j++) {
            double v = (double)tmp[j];
            if (want_max ? (v > best) : (v < best)) best = v;
        }
        while (i < a->size) {
            double v = (double)p[i++];
            if (want_max ? (v > best) : (v < best)) best = v;
        }
        return w_float(best);
    }
    if (a->ebits == -64 && a->size >= 8) {
        double *p = (double *)a->slots + a->start;
        int64_t i = 1;
        float64x2_t vbest = vdupq_n_f64(best);
        int64_t end = a->size - 2;
        while (i <= end) {
            float64x2_t v = vld1q_f64(p + i);
            vbest = want_max ? vmaxnmq_f64(vbest, v) : vminnmq_f64(vbest, v);
            i += 2;
        }
        double tmp[2];
        vst1q_f64(tmp, vbest);
        for (int j = 0; j < 2; j++) {
            double v = tmp[j];
            if (want_max ? (v > best) : (v < best)) best = v;
        }
        while (i < a->size) {
            double v = p[i++];
            if (want_max ? (v > best) : (v < best)) best = v;
        }
        return w_float(best);
    }
#endif

    int64_t end = a->start + a->size;
    for (int64_t i = a->start + 1; i < end; i++) {
        double v = array_read_float(a, i);
        if (want_max ? (v > best) : (v < best)) best = v;
    }
    return w_float(best);
}

WValue w_array_min_signed(WValue arr) { return array_minmax_int(arr, 1, 0); }
WValue w_array_min_unsigned(WValue arr) { return array_minmax_int(arr, 0, 0); }
WValue w_array_min_float(WValue arr) { return array_minmax_float(arr, 0); }
WValue w_array_max_signed(WValue arr) { return array_minmax_int(arr, 1, 1); }
WValue w_array_max_unsigned(WValue arr) { return array_minmax_int(arr, 0, 1); }
WValue w_array_max_float(WValue arr) { return array_minmax_float(arr, 1); }

WValue w_array_sum_signed(WValue arr) {
    WArray *a = w_as_array(arr);
    __int128 acc = 0;
    int64_t end = a->start + a->size;
    for (int64_t i = a->start; i < end; i++) acc += (__int128)array_read_signed(a, i);
    return w_i128(acc);
}

WValue w_array_sum_unsigned(WValue arr) {
    WArray *a = w_as_array(arr);
    unsigned __int128 acc = 0;
    int64_t end = a->start + a->size;
    for (int64_t i = a->start; i < end; i++) acc += (unsigned __int128)array_read(a, i);
    return w_u128(acc);
}

WValue w_array_sum_float(WValue arr) {
    WArray *a = w_as_array(arr);
    double acc = 0.0;
    int64_t end = a->start + a->size;
    for (int64_t i = a->start; i < end; i++) acc += array_read_float(a, i);
    return w_float(acc);
}

WValue w_array_fastsum_float(WValue arr) {
    WArray *a = w_as_array(arr);
    if (!array_is_float(a)) {
        w_raise(w_string("fastsum: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    return w_float(array_float_reduce(a, NULL, W_FLOAT_REDUCE_SUM));
}

WValue w_array_sumsq_float(WValue arr) {
    WArray *a = w_as_array(arr);
    if (!array_is_float(a)) {
        w_raise(w_string("sumsq: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    return w_float(array_float_reduce(a, NULL, W_FLOAT_REDUCE_SUMSQ));
}

WValue w_array_dot_i8(WValue lhs, WValue rhs) {
    if (!w_is_array(lhs) || !w_is_array(rhs)) {
        w_raise(w_string("dot: requires two i8[]/u8[] arrays"));
        return W_NIL;
    }
    WArray *a = w_as_array(lhs);
    WArray *b = w_as_array(rhs);
    if (!array_is_byte_int_array(a) || !array_is_byte_int_array(b)) {
        w_raise(w_string("dot: requires i8[]/u8[] arrays"));
        return W_NIL;
    }
    if (a->size != b->size) {
        w_raise(w_string("dot: lhs.size != rhs.size"));
        return W_NIL;
    }
    int64_t acc = array_dot_i8_arrays(a, b);
    return w_int(acc);
}

WValue w_array_dot_float(WValue lhs, WValue rhs) {
    if (!w_is_array(lhs) || !w_is_array(rhs)) {
        w_raise(w_string("dot: requires two float arrays"));
        return W_NIL;
    }
    WArray *a = w_as_array(lhs);
    WArray *b = w_as_array(rhs);
    if (!array_is_float(a) || !array_is_float(b)) {
        w_raise(w_string("dot: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    if (a->size != b->size) {
        w_raise(w_string("dot: lhs.size != rhs.size"));
        return W_NIL;
    }
    return w_float(array_float_reduce(a, b, W_FLOAT_REDUCE_DOT));
}

WValue w_array_matvec_i8(WValue weights_v, WValue x_v, WValue rows_v, WValue cols_v) {
    if (!w_is_array(weights_v) || !w_is_array(x_v)) {
        w_raise(w_string("matvec_i8: requires i8[]/u8[] matrix and vector"));
        return W_NIL;
    }
    WArray *weights = w_as_array(weights_v);
    WArray *x = w_as_array(x_v);
    if (!array_is_byte_int_array(weights) || !array_is_byte_int_array(x)) {
        w_raise(w_string("matvec_i8: requires i8[]/u8[] matrix and vector"));
        return W_NIL;
    }
    int64_t rows = w_as_int(rows_v);
    int64_t cols = w_as_int(cols_v);
    if (rows < 0 || cols < 0 || rows > INT32_MAX || cols > INT32_MAX) {
        w_raise(w_string("matvec_i8: invalid dimensions"));
        return W_NIL;
    }
    if (rows * cols > weights->size || cols > x->size) {
        w_raise(w_string("matvec_i8: dimensions exceed input sizes"));
        return W_NIL;
    }
    WValue out_v = w_array_new(32, rows);
    WArray *out = w_as_array(out_v);
    out->size = (int32_t)rows;
    const uint8_t *base = (const uint8_t *)weights->slots + weights->start;
    const uint8_t *xp = (const uint8_t *)x->slots + x->start;
    for (int64_t r = 0; r < rows; r++) {
        int64_t acc = array_dot_i8_ptr(base + r * cols, xp, cols, array_is_signed_int(weights), array_is_signed_int(x));
        array_write(out, r, (uint32_t)(int32_t)acc);
    }
    return out_v;
}

/* pack_mode is private to the implementation/benchmark translation unit:
 *   0 = retain the historical strided/gathered RHS path
 *   1 = production threshold policy
 *   2 = force one RHS transpose before the output loops
 * The public entry always selects mode 1. Keeping the alternatives behind
 * one implementation makes the threshold sweep compare identical kernels. */
static WValue array_matmul_i8_impl(WValue lhs_v, WValue rhs_v, WValue m_v,
                                   WValue k_v, WValue n_v, int pack_mode) {
    if (!w_is_array(lhs_v) || !w_is_array(rhs_v)) {
        w_raise(w_string("matmul_i8: requires i8[]/u8[] matrices"));
        return W_NIL;
    }
    WArray *a = w_as_array(lhs_v);
    WArray *b = w_as_array(rhs_v);
    if (!array_is_byte_int_array(a) || !array_is_byte_int_array(b)) {
        w_raise(w_string("matmul_i8: requires i8[]/u8[] matrices"));
        return W_NIL;
    }
    int64_t m = w_as_int(m_v);
    int64_t k = w_as_int(k_v);
    int64_t n = w_as_int(n_v);
    if (m < 0 || k < 0 || n < 0 || m > INT32_MAX || k > INT32_MAX || n > INT32_MAX) {
        w_raise(w_string("matmul_i8: invalid dimensions"));
        return W_NIL;
    }
    if (m * k > a->size || k * n > b->size || m * n > INT32_MAX) {
        w_raise(w_string("matmul_i8: dimensions exceed input sizes"));
        return W_NIL;
    }
    WValue out_v = w_array_new_inline(32, m * n);
    WArray *out = w_as_array(out_v);
    const uint8_t *packed_b = NULL;
    /* Packing pays one KxN transpose to replace every output tile's strided
     * RHS gathers. The ARM64 grid crosses over reliably at 16 lhs rows and
     * K>=16 (1.07-1.36x at 16 rows, 1.89x at 32x128x32); eight-row shapes
     * remain 0.83-0.94x. A single output column has no gather pair to save. */
    if (pack_mode == 2 ||
        (pack_mode == 1 && m >= 16 && n >= 2 && k >= 16))
        packed_b = array_matmul_i8_pack_rhs(b, k, n);

    int64_t r = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_MATMUL_INT8)
    if (array_is_signed_int(a) && array_is_signed_int(b)) {
        const int8_t *ap = (const int8_t *)a->slots + a->start;
        const int8_t *bp = (const int8_t *)b->slots + b->start;
        for (; r + 1 < m; r += 2) {
            int64_t c = 0;
            for (; c + 1 < n; c += 2) {
                int32x4_t vacc = vdupq_n_s32(0);
                int64_t kk = 0;
                for (; kk + 7 < k; kk += 8) {
                    int8_t ablock[16];
                    int8_t bblock[16];
                    memcpy(ablock, ap + r * k + kk, 8);
                    memcpy(ablock + 8, ap + (r + 1) * k + kk, 8);
                    if (packed_b) {
                        memcpy(bblock, packed_b + c * k + kk, 8);
                        memcpy(bblock + 8, packed_b + (c + 1) * k + kk, 8);
                    } else {
                        for (int t = 0; t < 8; t++) {
                            bblock[t] = bp[(kk + t) * n + c];
                            bblock[8 + t] = bp[(kk + t) * n + c + 1];
                        }
                    }
                    vacc = vmmlaq_s32(vacc, vld1q_s8(ablock), vld1q_s8(bblock));
                }
                int32_t tmp[4];
                vst1q_s32(tmp, vacc);
                int64_t c00 = tmp[0], c01 = tmp[1], c10 = tmp[2], c11 = tmp[3];
                for (; kk < k; kk++) {
                    int8_t a0 = ap[r * k + kk];
                    int8_t a1 = ap[(r + 1) * k + kk];
                    int8_t b0 = bp[kk * n + c];
                    int8_t b1 = bp[kk * n + c + 1];
                    c00 += (int64_t)a0 * b0;
                    c01 += (int64_t)a0 * b1;
                    c10 += (int64_t)a1 * b0;
                    c11 += (int64_t)a1 * b1;
                }
                array_write(out, r * n + c, (uint32_t)(int32_t)c00);
                array_write(out, r * n + c + 1, (uint32_t)(int32_t)c01);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)c10);
                array_write(out, (r + 1) * n + c + 1, (uint32_t)(int32_t)c11);
            }
            for (; c < n; c++) {
                int64_t acc0 = array_matmul_i8_cell(a, b, packed_b, r, c, k, n);
                int64_t acc1 = array_matmul_i8_cell(a, b, packed_b, r + 1, c, k, n);
                array_write(out, r * n + c, (uint32_t)(int32_t)acc0);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)acc1);
            }
        }
    } else if (!array_is_signed_int(a) && !array_is_signed_int(b)) {
        /* UMMLA: unsigned x unsigned. Lane wrap is congruent mod 2^32 with
         * the scalar int64 path's final i32 truncation, so no chunking. */
        const uint8_t *ap = (const uint8_t *)a->slots + a->start;
        const uint8_t *bp = (const uint8_t *)b->slots + b->start;
        for (; r + 1 < m; r += 2) {
            int64_t c = 0;
            for (; c + 1 < n; c += 2) {
                uint32x4_t vacc = vdupq_n_u32(0);
                int64_t kk = 0;
                for (; kk + 7 < k; kk += 8) {
                    uint8_t ablock[16];
                    uint8_t bblock[16];
                    memcpy(ablock, ap + r * k + kk, 8);
                    memcpy(ablock + 8, ap + (r + 1) * k + kk, 8);
                    if (packed_b) {
                        memcpy(bblock, packed_b + c * k + kk, 8);
                        memcpy(bblock + 8, packed_b + (c + 1) * k + kk, 8);
                    } else {
                        for (int t = 0; t < 8; t++) {
                            bblock[t] = bp[(kk + t) * n + c];
                            bblock[8 + t] = bp[(kk + t) * n + c + 1];
                        }
                    }
                    vacc = vmmlaq_u32(vacc, vld1q_u8(ablock), vld1q_u8(bblock));
                }
                uint32_t tmp[4];
                vst1q_u32(tmp, vacc);
                int64_t c00 = (int64_t)tmp[0], c01 = (int64_t)tmp[1];
                int64_t c10 = (int64_t)tmp[2], c11 = (int64_t)tmp[3];
                for (; kk < k; kk++) {
                    uint8_t a0 = ap[r * k + kk];
                    uint8_t a1 = ap[(r + 1) * k + kk];
                    uint8_t b0 = bp[kk * n + c];
                    uint8_t b1 = bp[kk * n + c + 1];
                    c00 += (int64_t)a0 * b0;
                    c01 += (int64_t)a0 * b1;
                    c10 += (int64_t)a1 * b0;
                    c11 += (int64_t)a1 * b1;
                }
                array_write(out, r * n + c, (uint32_t)(int32_t)c00);
                array_write(out, r * n + c + 1, (uint32_t)(int32_t)c01);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)c10);
                array_write(out, (r + 1) * n + c + 1, (uint32_t)(int32_t)c11);
            }
            for (; c < n; c++) {
                int64_t acc0 = array_matmul_i8_cell(a, b, packed_b, r, c, k, n);
                int64_t acc1 = array_matmul_i8_cell(a, b, packed_b, r + 1, c, k, n);
                array_write(out, r * n + c, (uint32_t)(int32_t)acc0);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)acc1);
            }
        }
    } else {
        /* Mixed sign: USMMLA computes U(2x8) x S(2x8)^T. When A is the
         * signed side, feed B's columns as the unsigned operand and read
         * the 2x2 result tile transposed (u8 activations x s8 weights is
         * the quantized-inference layout either way). */
        int a_signed = array_is_signed_int(a);
        const uint8_t *ap = (const uint8_t *)a->slots + a->start;
        const uint8_t *bp = (const uint8_t *)b->slots + b->start;
        for (; r + 1 < m; r += 2) {
            int64_t c = 0;
            for (; c + 1 < n; c += 2) {
                int32x4_t vacc = vdupq_n_s32(0);
                int64_t kk = 0;
                for (; kk + 7 < k; kk += 8) {
                    uint8_t arows[16];
                    uint8_t bcols[16];
                    memcpy(arows, ap + r * k + kk, 8);
                    memcpy(arows + 8, ap + (r + 1) * k + kk, 8);
                    if (packed_b) {
                        memcpy(bcols, packed_b + c * k + kk, 8);
                        memcpy(bcols + 8, packed_b + (c + 1) * k + kk, 8);
                    } else {
                        for (int t = 0; t < 8; t++) {
                            bcols[t] = bp[(kk + t) * n + c];
                            bcols[8 + t] = bp[(kk + t) * n + c + 1];
                        }
                    }
                    if (a_signed)
                        vacc = vusmmlaq_s32(vacc, vld1q_u8(bcols),
                                            vld1q_s8((const int8_t *)arows));
                    else
                        vacc = vusmmlaq_s32(vacc, vld1q_u8(arows),
                                            vld1q_s8((const int8_t *)bcols));
                }
                int32_t tmp[4];
                vst1q_s32(tmp, vacc);
                int64_t c00, c01, c10, c11;
                if (a_signed) {
                    c00 = tmp[0]; c10 = tmp[1]; c01 = tmp[2]; c11 = tmp[3];
                } else {
                    c00 = tmp[0]; c01 = tmp[1]; c10 = tmp[2]; c11 = tmp[3];
                }
                for (; kk < k; kk++) {
                    int64_t a0 = a_signed ? (int64_t)(int8_t)ap[r * k + kk] : (int64_t)ap[r * k + kk];
                    int64_t a1 = a_signed ? (int64_t)(int8_t)ap[(r + 1) * k + kk] : (int64_t)ap[(r + 1) * k + kk];
                    int64_t b0 = a_signed ? (int64_t)bp[kk * n + c] : (int64_t)(int8_t)bp[kk * n + c];
                    int64_t b1 = a_signed ? (int64_t)bp[kk * n + c + 1] : (int64_t)(int8_t)bp[kk * n + c + 1];
                    c00 += a0 * b0;
                    c01 += a0 * b1;
                    c10 += a1 * b0;
                    c11 += a1 * b1;
                }
                array_write(out, r * n + c, (uint32_t)(int32_t)c00);
                array_write(out, r * n + c + 1, (uint32_t)(int32_t)c01);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)c10);
                array_write(out, (r + 1) * n + c + 1, (uint32_t)(int32_t)c11);
            }
            for (; c < n; c++) {
                int64_t acc0 = array_matmul_i8_cell(a, b, packed_b, r, c, k, n);
                int64_t acc1 = array_matmul_i8_cell(a, b, packed_b, r + 1, c, k, n);
                array_write(out, r * n + c, (uint32_t)(int32_t)acc0);
                array_write(out, (r + 1) * n + c, (uint32_t)(int32_t)acc1);
            }
        }
    }
#endif
    for (; r < m; r++) {
        for (int64_t c = 0; c < n; c++) {
            int64_t acc = array_matmul_i8_cell(a, b, packed_b, r, c, k, n);
            array_write(out, r * n + c, (uint32_t)(int32_t)acc);
        }
    }
    return out_v;
}

WValue w_array_matmul_i8(WValue lhs_v, WValue rhs_v, WValue m_v,
                         WValue k_v, WValue n_v) {
    return array_matmul_i8_impl(lhs_v, rhs_v, m_v, k_v, n_v, 1);
}

WValue w_array_cross_float(WValue lhs, WValue rhs) {
    if (!w_is_array(lhs) || !w_is_array(rhs)) {
        w_raise(w_string("cross: requires two float arrays"));
        return W_NIL;
    }
    WArray *a = w_as_array(lhs);
    WArray *b = w_as_array(rhs);
    if (!array_is_float(a) || !array_is_float(b)) {
        w_raise(w_string("cross: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    if (a->size != 3 || b->size != 3) {
        w_raise(w_string("cross: requires length-3 arrays"));
        return W_NIL;
    }

    double ax = array_read_float(a, a->start);
    double ay = array_read_float(a, a->start + 1);
    double az = array_read_float(a, a->start + 2);
    double bx = array_read_float(b, b->start);
    double by = array_read_float(b, b->start + 1);
    double bz = array_read_float(b, b->start + 2);

    WValue out_v = w_array_new(a->ebits, 3);
    WArray *out = w_as_array(out_v);
    out->size = 3;
    array_write_float(out, 0, ay * bz - az * by);
    array_write_float(out, 1, az * bx - ax * bz);
    array_write_float(out, 2, ax * by - ay * bx);
    return out_v;
}

WValue w_array_scale_float(WValue arr, WValue scalar) {
    WArray *a = w_as_array(arr);
    if (!array_is_float(a)) {
        w_raise(w_string("scale: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    WValue out_v = w_array_new(a->ebits, a->size);
    WArray *out = w_as_array(out_v);
    out->size = a->size;
    double s = as_numeric_double(scalar);
    if (!array_elementwise_float_fast(a, NULL, out, 0, s, ELT_OP_MUL)) {
        for (int64_t i = 0; i < a->size; i++) {
            array_write_float(out, i, array_read_float(a, a->start + i) * s);
        }
    }
    return out_v;
}

WValue w_array_scale_float_bang(WValue arr, WValue scalar) {
    WArray *a = w_as_array(arr);
    if (!array_is_float(a)) {
        w_raise(w_string("scale!: requires f32[], f64[], bf16[], or f16[]"));
        return W_NIL;
    }
    double s = as_numeric_double(scalar);
    if (a->ebits == -32) {
        float *p = (float *)a->slots + a->start;
        float sf = (float)s;
        int64_t i = 0;
#ifdef __aarch64__
        if (a->size >= 16) {
            float32x4_t sv = vdupq_n_f32(sf);
            int64_t end = a->size - 4;
            while (i <= end) {
                vst1q_f32(p + i, vmulq_f32(vld1q_f32(p + i), sv));
                i += 4;
            }
        }
#endif
        while (i < a->size) p[i++] *= sf;
        return arr;
    }
    if (a->ebits == -116 || a->ebits == -16) {
        int64_t i = 0;
        while (i < a->size) {
            double v = array_read_float(a, a->start + i);
            array_write_float(a, a->start + i, v * s);
            i++;
        }
        return arr;
    }
    double *p = (double *)a->slots + a->start;
    int64_t i = 0;
#ifdef __aarch64__
    if (a->size >= 8) {
        float64x2_t sv = vdupq_n_f64(s);
        int64_t end = a->size - 2;
        while (i <= end) {
            vst1q_f64(p + i, vmulq_f64(vld1q_f64(p + i), sv));
            i += 2;
        }
    }
#endif
    while (i < a->size) p[i++] *= s;
    return arr;
}

/* ---------------------------------------------------------------------
 * Interleaved complex f64 kernels (core/numeric/complex_array.w).
 *
 * Buffers are f64 typed arrays of length 2N holding (re, im) pairs — the
 * layout FCMLA wants: one 128-bit vector = one complex. FEAT_FCMA's
 * rotate-0 + rotate-90 pair computes a full complex multiply-accumulate:
 *   rot0:  dst.re += a.re*b.re ; dst.im += a.re*b.im
 *   rot90: dst.re -= a.im*b.im ; dst.im += a.im*b.re
 * The conjugate dot uses rot0 + rot270 (conj(a)*b). Scalar fallbacks keep
 * non-FCMA targets correct and serve as the differential oracle.
 * ------------------------------------------------------------------- */

static WArray *carr_pair_arg(WValue v, const char *who) {
    if (!w_is_array(v)) w_raise(w_string("complex array kernel: expected f64[] backing"));
    WArray *a = w_as_array(v);
    if (a->ebits != -64) w_raise(w_string("complex array kernel: backing must be f64[]"));
    if (a->size & 1) w_raise(w_string("complex array kernel: odd backing length"));
    (void)who;
    return a;
}

WValue w_carr_mul_f64(WValue a_v, WValue b_v) {
    WArray *a = carr_pair_arg(a_v, "mul");
    WArray *b = carr_pair_arg(b_v, "mul");
    if (a->size != b->size) w_raise(w_string("complex array mul: size mismatch"));
    int64_t n2 = a->size;
    WValue out_v = w_array_new(-64, n2);
    WArray *out = w_as_array(out_v);
    out->size = (int32_t)n2;
    const double *ap = (const double *)a->slots + a->start;
    const double *bp = (const double *)b->slots + b->start;
    double *op = (double *)out->slots + out->start;
    int64_t i = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_COMPLEX)
    for (; i + 4 <= n2; i += 4) {
        float64x2_t a0 = vld1q_f64(ap + i), a1 = vld1q_f64(ap + i + 2);
        float64x2_t b0 = vld1q_f64(bp + i), b1 = vld1q_f64(bp + i + 2);
        float64x2_t r0 = vcmlaq_rot90_f64(vcmlaq_f64(vdupq_n_f64(0.0), a0, b0), a0, b0);
        float64x2_t r1 = vcmlaq_rot90_f64(vcmlaq_f64(vdupq_n_f64(0.0), a1, b1), a1, b1);
        vst1q_f64(op + i, r0);
        vst1q_f64(op + i + 2, r1);
    }
#endif
    for (; i < n2; i += 2) {
        double ar = ap[i], ai = ap[i + 1], br = bp[i], bi = bp[i + 1];
        op[i] = ar * br - ai * bi;
        op[i + 1] = ar * bi + ai * br;
    }
    return out_v;
}

WValue w_carr_conj_dot_f64(WValue a_v, WValue b_v) {
    WArray *a = carr_pair_arg(a_v, "conj_dot");
    WArray *b = carr_pair_arg(b_v, "conj_dot");
    if (a->size != b->size) w_raise(w_string("complex array conj_dot: size mismatch"));
    int64_t n2 = a->size;
    const double *ap = (const double *)a->slots + a->start;
    const double *bp = (const double *)b->slots + b->start;
    double acc_re = 0.0, acc_im = 0.0;
    int64_t i = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_COMPLEX)
    float64x2_t acc = vdupq_n_f64(0.0);
    for (; i + 2 <= n2; i += 2) {
        float64x2_t av = vld1q_f64(ap + i);
        float64x2_t bv = vld1q_f64(bp + i);
        acc = vcmlaq_rot270_f64(vcmlaq_f64(acc, av, bv), av, bv);
    }
    acc_re = vgetq_lane_f64(acc, 0);
    acc_im = vgetq_lane_f64(acc, 1);
#endif
    for (; i < n2; i += 2) {
        double ar = ap[i], ai = ap[i + 1], br = bp[i], bi = bp[i + 1];
        acc_re += ar * br + ai * bi;
        acc_im += ar * bi - ai * br;
    }
    WValue out_v = w_array_new(-64, 2);
    WArray *out = w_as_array(out_v);
    out->size = 2;
    double *op = (double *)out->slots + out->start;
    op[0] = acc_re;
    op[1] = acc_im;
    return out_v;
}

WValue w_carr_scale_f64(WValue a_v, WValue re_v, WValue im_v) {
    WArray *a = carr_pair_arg(a_v, "scale");
    double sr = w_math_to_double(re_v);
    double si = w_math_to_double(im_v);
    int64_t n2 = a->size;
    WValue out_v = w_array_new(-64, n2);
    WArray *out = w_as_array(out_v);
    out->size = (int32_t)n2;
    const double *ap = (const double *)a->slots + a->start;
    double *op = (double *)out->slots + out->start;
    int64_t i = 0;
#if defined(__aarch64__) && defined(__ARM_FEATURE_COMPLEX)
    double spair[2] = {sr, si};
    float64x2_t sv = vld1q_f64(spair);
    for (; i + 2 <= n2; i += 2) {
        float64x2_t av = vld1q_f64(ap + i);
        vst1q_f64(op + i, vcmlaq_rot90_f64(vcmlaq_f64(vdupq_n_f64(0.0), av, sv), av, sv));
    }
#endif
    for (; i < n2; i += 2) {
        double ar = ap[i], ai = ap[i + 1];
        op[i] = ar * sr - ai * si;
        op[i + 1] = ar * si + ai * sr;
    }
    return out_v;
}

/* ---------------------------------------------------------------------
 * BLAS bridge — Apple Accelerate framework
 *
 * Provides direct cblas_sgemm / cblas_dgemm dispatch for f32[] / f64[]
 * typed arrays. The wrapper extracts raw float pointers from the WArray
 * `slots` storage and hands them to Accelerate. No nanbox / unbox round-
 * trip, no Tungsten dispatch overhead — the entire matmul body executes
 * inside Accelerate's AMX-tuned kernel.
 *
 * Tungsten call site:
 *   ccall("w_blas_sgemm_nn", a_wval, b_wval, c_wval, m, n, k)
 *   ccall("w_blas_dgemm_nn", a_wval, b_wval, c_wval, m, n, k)
 *
 * Computes C = A · B (no transpose, row-major) where A is M×K, B is K×N,
 * C is M×N. Returns the C wval.
 * --------------------------------------------------------------------- */
/* Real implementations live in runtime/blas_bridge.c, linked (with
 * -framework Accelerate) only when the IR references @w_blas_ — the same
 * conditional-bridge scheme as metal.m. These WEAK stubs stand in
 * otherwise (and on non-Apple platforms). */
__attribute__((weak)) WValue w_blas_sgemm_nn(WValue a, WValue b, WValue c, WValue m, WValue n, WValue k) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    w_raise(w_string("blas_sgemm: BLAS bridge not linked (program references no w_blas_ call) or platform without Accelerate"));
    return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgemm_nn(WValue a, WValue b, WValue c, WValue m, WValue n, WValue k) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    w_raise(w_string("blas_dgemm: BLAS bridge not linked (program references no w_blas_ call) or platform without Accelerate"));
    return W_NIL;
}
__attribute__((weak)) WValue w_blas_sgemm_view(WValue a, WValue b, WValue c,
                                               WValue m, WValue n, WValue k,
                                               WValue ao, WValue bo, WValue ta, WValue tb) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    (void)ao; (void)bo; (void)ta; (void)tb;
    w_raise(w_string("blas_sgemm_view: BLAS bridge not linked or no CBLAS"));
    return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgemm_view(WValue a, WValue b, WValue c,
                                               WValue m, WValue n, WValue k,
                                               WValue ao, WValue bo, WValue ta, WValue tb) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    (void)ao; (void)bo; (void)ta; (void)tb;
    w_raise(w_string("blas_dgemm_view: BLAS bridge not linked or no CBLAS"));
    return W_NIL;
}
__attribute__((weak)) WValue w_blas_sgemm_view_scaled(WValue a, WValue b, WValue c,
                                                      WValue m, WValue n, WValue k,
                                                      WValue ao, WValue bo, WValue co,
                                                      WValue ta, WValue tb,
                                                      WValue alpha, WValue beta) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    (void)ao; (void)bo; (void)co; (void)ta; (void)tb; (void)alpha; (void)beta;
    w_raise(w_string("blas_sgemm_view_scaled: BLAS bridge not linked or no CBLAS"));
    return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgemm_view_scaled(WValue a, WValue b, WValue c,
                                                      WValue m, WValue n, WValue k,
                                                      WValue ao, WValue bo, WValue co,
                                                      WValue ta, WValue tb,
                                                      WValue alpha, WValue beta) {
    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k;
    (void)ao; (void)bo; (void)co; (void)ta; (void)tb; (void)alpha; (void)beta;
    w_raise(w_string("blas_dgemm_view_scaled: BLAS bridge not linked or no CBLAS"));
    return W_NIL;
}
/* vDSP reductions + elementwise transcendentals — real impls in blas_bridge.c. */
__attribute__((weak)) WValue w_blas_sum_f32(WValue a, WValue n) {
    (void)a; (void)n; w_raise(w_string("blas_sum: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_reduce_view(WValue dt, WValue a, WValue off, WValue n, WValue kind) {
    (void)dt; (void)a; (void)off; (void)n; (void)kind;
    w_raise(w_string("blas_reduce_view: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_reduce_last(WValue dt, WValue a, WValue o, WValue off, WValue rows, WValue cols, WValue kind) {
    (void)dt; (void)a; (void)o; (void)off; (void)rows; (void)cols; (void)kind;
    w_raise(w_string("blas_reduce_last: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dot_f32(WValue a, WValue b, WValue n) {
    (void)a; (void)b; (void)n; w_raise(w_string("blas_dot: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_sumsq_f32(WValue a, WValue n) {
    (void)a; (void)n; w_raise(w_string("blas_sumsq: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vsin_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vsin: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vcos_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vcos: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vexp_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vexp: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vtanh_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vtanh: BLAS bridge not linked or no Accelerate")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vlog_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vlog: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vsqrt_f32(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vsqrt: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vsin_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vsin_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vcos_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vcos_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vexp_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vexp_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vlog_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vlog_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vsqrt_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vsqrt_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vtan_f64(WValue a, WValue o, WValue n) {
    (void)a; (void)o; (void)n; w_raise(w_string("blas_vtan_f64: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_unary_view(WValue dt, WValue a, WValue o, WValue off, WValue n, WValue kind) {
    (void)dt; (void)a; (void)o; (void)off; (void)n; (void)kind;
    w_raise(w_string("blas_unary_view: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_saxpy(WValue a, WValue x, WValue y, WValue n) {
    (void)a; (void)x; (void)y; (void)n; w_raise(w_string("saxpy: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_sgemv_n(WValue a, WValue x, WValue y, WValue m, WValue n) {
    (void)a; (void)x; (void)y; (void)m; (void)n; w_raise(w_string("sgemv: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dot_f64(WValue a, WValue b, WValue n) {
    (void)a; (void)b; (void)n; w_raise(w_string("ddot: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_norm_f64(WValue a, WValue n) {
    (void)a; (void)n; w_raise(w_string("dnrm2: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_daxpy(WValue alpha, WValue x, WValue y, WValue n) {
    (void)alpha; (void)x; (void)y; (void)n; w_raise(w_string("daxpy: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dscal(WValue alpha, WValue x, WValue n) {
    (void)alpha; (void)x; (void)n; w_raise(w_string("dscal: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgemv_n(WValue a, WValue x, WValue y, WValue m, WValue n) {
    (void)a; (void)x; (void)y; (void)m; (void)n; w_raise(w_string("dgemv: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dsymv_upper(WValue a, WValue x, WValue y, WValue n) {
    (void)a; (void)x; (void)y; (void)n; w_raise(w_string("dsymv: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dsyrk_upper(WValue a, WValue c, WValue n, WValue k, WValue alpha, WValue beta) {
    (void)a; (void)c; (void)n; (void)k; (void)alpha; (void)beta;
    w_raise(w_string("dsyrk: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dtrsm_left_lower(WValue a, WValue b, WValue m, WValue n, WValue alpha) {
    (void)a; (void)b; (void)m; (void)n; (void)alpha;
    w_raise(w_string("dtrsm: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgeqrf_qr(WValue a, WValue q, WValue r, WValue m, WValue n) {
    (void)a; (void)q; (void)r; (void)m; (void)n;
    w_raise(w_string("dgeqrf_qr: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgeqrf_factor(WValue a, WValue tau, WValue m, WValue n) {
    (void)a; (void)tau; (void)m; (void)n;
    w_raise(w_string("dgeqrf_factor: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgeqrf_solve(WValue a, WValue tau, WValue b, WValue m, WValue n, WValue nrhs) {
    (void)a; (void)tau; (void)b; (void)m; (void)n; (void)nrhs;
    w_raise(w_string("dgeqrf_solve: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dsyev_values(WValue a, WValue w, WValue n) {
    (void)a; (void)w; (void)n; w_raise(w_string("dsyev_values: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgesdd_values(WValue a, WValue s, WValue m, WValue n) {
    (void)a; (void)s; (void)m; (void)n; w_raise(w_string("dgesdd_values: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgesdd_thin(WValue a, WValue s, WValue u, WValue vt, WValue m, WValue n) {
    (void)a; (void)s; (void)u; (void)vt; (void)m; (void)n;
    w_raise(w_string("dgesdd_thin: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgelsy(WValue a, WValue b, WValue m, WValue n) {
    (void)a; (void)b; (void)m; (void)n; w_raise(w_string("dgelsy: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgetrf_rowmajor(WValue a, WValue piv, WValue n) {
    (void)a; (void)piv; (void)n; w_raise(w_string("dgetrf_rowmajor: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgetrs_rowmajor(WValue a, WValue piv, WValue b, WValue n) {
    (void)a; (void)piv; (void)b; (void)n; w_raise(w_string("dgetrs_rowmajor: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgetrs_many_rowmajor(WValue a, WValue piv, WValue b, WValue n, WValue nrhs) {
    (void)a; (void)piv; (void)b; (void)n; (void)nrhs;
    w_raise(w_string("dgetrs_many_rowmajor: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dpotrf_lower(WValue a, WValue n) {
    (void)a; (void)n; w_raise(w_string("dpotrf_lower: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dpotrs_rowmajor(WValue a, WValue b, WValue n, WValue nrhs) {
    (void)a; (void)b; (void)n; (void)nrhs;
    w_raise(w_string("dpotrs_rowmajor: LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vadd_f32(WValue a, WValue b, WValue o, WValue n) {
    (void)a; (void)b; (void)o; (void)n; w_raise(w_string("vadd: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vmul_f32(WValue a, WValue b, WValue o, WValue n) {
    (void)a; (void)b; (void)o; (void)n; w_raise(w_string("vmul: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vsmul_f32(WValue a, WValue s, WValue o, WValue n) {
    (void)a; (void)s; (void)o; (void)n; w_raise(w_string("vsmul: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_vfill_f32(WValue o, WValue s, WValue n) {
    (void)o; (void)s; (void)n; w_raise(w_string("vfill: BLAS bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgesv(WValue a, WValue b, WValue n) {
    (void)a; (void)b; (void)n; w_raise(w_string("dgesv: BLAS/LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dpotrf(WValue a, WValue n) {
    (void)a; (void)n; w_raise(w_string("dpotrf: BLAS/LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_dgeev(WValue a, WValue wr, WValue wi, WValue n) {
    (void)a; (void)wr; (void)wi; (void)n;
    w_raise(w_string("dgeev: BLAS/LAPACK bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_blas_fft_f32(WValue re, WValue im, WValue n, WValue inv) {
    (void)re; (void)im; (void)n; (void)inv;
    w_raise(w_string("fft_f32: BLAS bridge not linked (vDSP FFT is macOS Accelerate)"));
    return W_NIL;
}

/* ---- SparseBLAS / Sparse Solvers weak stubs (strong in sparse_bridge.c) ---- */
__attribute__((weak)) WValue w_sparse_spmv_f32(WValue rows, WValue cols,
    WValue indptr, WValue indices, WValue data, WValue x, WValue y) {
    (void)rows; (void)cols; (void)indptr; (void)indices; (void)data; (void)x; (void)y;
    w_raise(w_string("sparse_spmv: SparseBLAS bridge not linked (macOS Accelerate Sparse/BLAS)"));
    return W_NIL;
}
__attribute__((weak)) WValue w_sparse_solve_qr_f64(WValue rows, WValue cols,
    WValue row, WValue col, WValue data, WValue b, WValue x) {
    (void)rows; (void)cols; (void)row; (void)col; (void)data; (void)b; (void)x;
    w_raise(w_string("sparse_solve_qr: Sparse Solvers bridge not linked (macOS Accelerate Sparse/Solve)"));
    return W_NIL;
}
__attribute__((weak)) WValue w_sparse_solve_chol_f64(WValue n,
    WValue row, WValue col, WValue data, WValue b, WValue x) {
    (void)n; (void)row; (void)col; (void)data; (void)b; (void)x;
    w_raise(w_string("sparse_solve_chol: Sparse Solvers bridge not linked (macOS Accelerate Sparse/Solve)"));
    return W_NIL;
}

/* ---- Scientific I/O (strong in sci_io_native.c when linked) ---- */
__attribute__((weak)) WValue w_sci_fits_f32_be(WValue path, WValue off, WValue n) {
    (void)path; (void)off; (void)n;
    w_raise(w_string("SciIO FITS f32: link runtime/sci_io_native.c"));
    return W_NIL;
}
__attribute__((weak)) WValue w_sci_mat_level5_ok(WValue path) {
    (void)path; return w_int(0);
}
__attribute__((weak)) WValue w_sci_hdf5_write_f32_1d(WValue p, WValue d) {
    (void)p; (void)d; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_hdf5_read_f32_1d(WValue p) {
    (void)p; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_netcdf_write_f32_1d(WValue p, WValue d) {
    (void)p; (void)d; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_netcdf_read_f32_1d(WValue p) {
    (void)p; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_hdf5_write_datasets(WValue p, WValue n, WValue a) {
    (void)p;(void)n;(void)a; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_hdf5_list(WValue p) {
    (void)p; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_hdf5_read_named(WValue p, WValue n) {
    (void)p;(void)n; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_parquet_write_f32(WValue p, WValue n, WValue a) {
    (void)p;(void)n;(void)a; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_parquet_read_f32(WValue p, WValue n) {
    (void)p;(void)n; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_zarr_write_f32_1d(WValue d, WValue a) {
    (void)d;(void)a; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}
__attribute__((weak)) WValue w_sci_zarr_read_f32_1d(WValue d) {
    (void)d; w_raise(w_string("SciIO: link sci_io_native.c")); return W_NIL;
}



/* ---- CUDA host bridge weak stubs (strong defs in cuda_bridge.cu) ---- */
__attribute__((weak)) WValue w_cuda_available(void) { return w_int(0); }
__attribute__((weak)) WValue w_cuda_device_count(void) { return w_int(0); }
__attribute__((weak)) WValue w_cuda_malloc(WValue n) {
    (void)n; w_raise(w_string("cuda_malloc: CUDA bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_cuda_free(WValue p) {
    (void)p; w_raise(w_string("cuda_free: CUDA bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_cuda_memcpy_h2d(WValue d, WValue s, WValue n) {
    (void)d; (void)s; (void)n; w_raise(w_string("cuda_memcpy_h2d: CUDA bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_cuda_memcpy_d2h(WValue d, WValue s, WValue n) {
    (void)d; (void)s; (void)n; w_raise(w_string("cuda_memcpy_d2h: CUDA bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_cuda_synchronize(void) {
    w_raise(w_string("cuda_synchronize: CUDA bridge not linked")); return W_NIL;
}
__attribute__((weak)) WValue w_cuda_device_name(WValue i) {
    (void)i; return w_string("no-cuda");
}
__attribute__((weak)) WValue w_cuda_launch(WValue name, WValue gx, WValue gy, WValue gz,
                                           WValue bx, WValue by, WValue bz, WValue args) {
    (void)name; (void)gx; (void)gy; (void)gz; (void)bx; (void)by; (void)bz; (void)args;
    w_raise(w_string("cuda_launch: CUDA bridge not linked")); return W_NIL;
}

/* ---------------------------------------------------------------------
 * Mat4 × Mat4 SIMD kernel — ARM NEON `<4 x float>` path.
 *
 * The right tool for fixed-size 4×4 f32 matmul. Accelerate's cblas_sgemm
 * has ~20-100 ns of per-call overhead that dominates at N=4 (whose entire
 * useful work is 128 flops, i.e. ~40 ns). NEON-resident SIMD with broadcast-
 * fma keeps the operands in 4 vector registers and produces the result in
 * 4 vector stores. Expected: ~10-30 ns per Mat4 × Mat4, ~5-15 GFLOPS at
 * this size class — 3-5× over the cblas dispatch floor.
 *
 * Row-major convention: A[i, k] = a[i*4 + k]. Compute
 *   C[i, :] = sum_k A[i, k] * B[k, :]
 * by loading each row of B once as a <4 x float>, then for each of the 4
 * rows of A doing 4 broadcast-fma's.
 *
 * Tungsten call: ccall("w_mat4_mul_f32", a_wval, b_wval, c_wval)
 * Returns c_wval. All three must be f32-typed WArrays of length 16.
 * --------------------------------------------------------------------- */
#ifdef __aarch64__
WValue w_mat4_mul_f32(WValue a_wval, WValue b_wval, WValue c_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;

    /* Load all 4 rows of B as <4 x float>. */
    float32x4_t b0 = vld1q_f32(Bp);
    float32x4_t b1 = vld1q_f32(Bp + 4);
    float32x4_t b2 = vld1q_f32(Bp + 8);
    float32x4_t b3 = vld1q_f32(Bp + 12);

    /* For each row of A, broadcast-fma against the rows of B. */
    for (int i = 0; i < 4; i++) {
        const float *Ai = Ap + i * 4;
        float32x4_t row = vmulq_n_f32(b0, Ai[0]);
        row = vmlaq_n_f32(row, b1, Ai[1]);
        row = vmlaq_n_f32(row, b2, Ai[2]);
        row = vmlaq_n_f32(row, b3, Ai[3]);
        vst1q_f32(Cp + i * 4, row);
    }
    return c_wval;
}

/* Vec4 helpers — single-instruction componentwise ops for callers who
 * want the SIMD path explicitly. */
WValue w_vec4_add_f32(WValue a_wval, WValue b_wval, WValue out_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *o = w_as_array(out_wval);
    float32x4_t va = vld1q_f32((const float *)a->slots + a->start);
    float32x4_t vb = vld1q_f32((const float *)b->slots + b->start);
    vst1q_f32((float *)o->slots + o->start, vaddq_f32(va, vb));
    return out_wval;
}

WValue w_vec4_mul_f32(WValue a_wval, WValue b_wval, WValue out_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *o = w_as_array(out_wval);
    float32x4_t va = vld1q_f32((const float *)a->slots + a->start);
    float32x4_t vb = vld1q_f32((const float *)b->slots + b->start);
    vst1q_f32((float *)o->slots + o->start, vmulq_f32(va, vb));
    return out_wval;
}

WValue w_vec4_dot_f32(WValue a_wval, WValue b_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    float32x4_t va = vld1q_f32((const float *)a->slots + a->start);
    float32x4_t vb = vld1q_f32((const float *)b->slots + b->start);
    float32x4_t prod = vmulq_f32(va, vb);
    float dot = vaddvq_f32(prod);
    return w_float((double)dot);
}
/* Batched 4x4 f32 multiply: C[i] = A[i] * B[i] for `count` consecutive
 * 16-float blocks. One ccall amortizes the per-call dispatch floor
 * (~20-100 ns) across the whole batch — the win the single-matrix NEON
 * kernel documents, extended to bulk small-matrix workloads. */
WValue w_mat4_mul_batch_f32(WValue a_wval, WValue b_wval, WValue c_wval, WValue count_w) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    int64_t count = w_as_int(count_w);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    for (int64_t t = 0; t < count; t++) {
        const float *Abase = Ap + t * 16;
        const float *Bbase = Bp + t * 16;
        float *Cbase = Cp + t * 16;
        float32x4_t b0 = vld1q_f32(Bbase);
        float32x4_t b1 = vld1q_f32(Bbase + 4);
        float32x4_t b2 = vld1q_f32(Bbase + 8);
        float32x4_t b3 = vld1q_f32(Bbase + 12);
        for (int i = 0; i < 4; i++) {
            const float *Ai = Abase + i * 4;
            float32x4_t row = vmulq_n_f32(b0, Ai[0]);
            row = vmlaq_n_f32(row, b1, Ai[1]);
            row = vmlaq_n_f32(row, b2, Ai[2]);
            row = vmlaq_n_f32(row, b3, Ai[3]);
            vst1q_f32(Cbase + i * 4, row);
        }
    }
    return c_wval;
}

#else
/* Portable scalar fallbacks: bit-identical shape contract with the NEON
 * versions (row-major 4x4 / length-4 f32 WArrays), so non-aarch64 builds
 * run correctly instead of raising. Any autovectorizer will do fine on
 * these fixed-trip loops; the NEON path above stays the fast lane. */
WValue w_mat4_mul_f32(WValue a_wval, WValue b_wval, WValue c_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            float acc = 0.0f;
            for (int k = 0; k < 4; k++)
                acc += Ap[i * 4 + k] * Bp[k * 4 + j];
            Cp[i * 4 + j] = acc;
        }
    }
    return c_wval;
}
WValue w_vec4_add_f32(WValue a_wval, WValue b_wval, WValue c_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    for (int i = 0; i < 4; i++) Cp[i] = Ap[i] + Bp[i];
    return c_wval;
}
WValue w_vec4_mul_f32(WValue a_wval, WValue b_wval, WValue c_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    for (int i = 0; i < 4; i++) Cp[i] = Ap[i] * Bp[i];
    return c_wval;
}
WValue w_vec4_dot_f32(WValue a_wval, WValue b_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float dot = 0.0f;
    for (int i = 0; i < 4; i++) dot += Ap[i] * Bp[i];
    return w_float((double)dot);
}
WValue w_mat4_mul_batch_f32(WValue a_wval, WValue b_wval, WValue c_wval, WValue count_w) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    int64_t count = w_as_int(count_w);
    const float *Ap = (const float *)a->slots + a->start;
    const float *Bp = (const float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    for (int64_t t = 0; t < count; t++) {
        const float *Abase = Ap + t * 16;
        const float *Bbase = Bp + t * 16;
        float *Cbase = Cp + t * 16;
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                float acc = 0.0f;
                for (int k = 0; k < 4; k++)
                    acc += Abase[i * 4 + k] * Bbase[k * 4 + j];
                Cbase[i * 4 + j] = acc;
            }
        }
    }
    return c_wval;
}
#endif

/* Dirt-simple global measurement counters for perf forensics from .w code:
 * w_probe_counter_add(slot, v) accumulates, w_probe_counter_take(slot)
 * returns and clears. 16 slots, no threading guarantees — a profiling aid,
 * not an API. */
static int64_t w_probe_counters[16];
WValue w_probe_counter_add(WValue slot_w, WValue v_w) {
    int64_t slot = w_as_int(slot_w);
    if (slot >= 0 && slot < 16) w_probe_counters[slot] += w_as_int(v_w);
    return W_NIL;
}
WValue w_probe_counter_take(WValue slot_w) {
    int64_t slot = w_as_int(slot_w);
    int64_t v = 0;
    if (slot >= 0 && slot < 16) { v = w_probe_counters[slot]; w_probe_counters[slot] = 0; }
    return w_int(v);
}

typedef enum {
    ARRAY_MAP_COS,
    ARRAY_MAP_SIN,
    ARRAY_MAP_SQRT,
    ARRAY_MAP_EXP,
    ARRAY_MAP_LOG,
    ARRAY_MAP_TAN
} ArrayMapOp;

static WValue array_map_f64(WValue arr, int signed_values, ArrayMapOp op) {
    WArray *src = w_as_array(arr);
    WValue result = w_array_new_inline(-64, src->size);
    WArray *dst = w_as_array(result);
    double *out = (double *)dst->slots;

#if defined(__APPLE__)
    /* vForce amortizes its call overhead by roughly 32 elements on current
     * Apple Silicon. Feed f64 input directly; other numeric tiers convert
     * once into the result buffer and then transform it in place. */
    if (src->size >= 32) {
        WValue input = arr;
        if (src->ebits != -64) {
            for (int32_t i = 0; i < src->size; i++)
                out[i] = array_read_numeric(src, src->start + i,
                                            signed_values);
            input = result;
        }
        WValue size = w_int(src->size);
        switch (op) {
            case ARRAY_MAP_COS:  return w_blas_vcos_f64(input, result, size);
            case ARRAY_MAP_SIN:  return w_blas_vsin_f64(input, result, size);
            case ARRAY_MAP_SQRT: return w_blas_vsqrt_f64(input, result, size);
            case ARRAY_MAP_EXP:  return w_blas_vexp_f64(input, result, size);
            case ARRAY_MAP_LOG:  return w_blas_vlog_f64(input, result, size);
            case ARRAY_MAP_TAN:  return w_blas_vtan_f64(input, result, size);
        }
    }
#endif

    int64_t src_end = src->start + src->size;
    int64_t j = 0;
#define W_ARRAY_MAP_LOOP(fn)                                                   \
    do {                                                                       \
        for (int64_t i = src->start; i < src_end; i++)                         \
            out[j++] = fn(array_read_numeric(src, i, signed_values));           \
    } while (0)
    switch (op) {
        case ARRAY_MAP_COS:  W_ARRAY_MAP_LOOP(cos); break;
        case ARRAY_MAP_SIN:  W_ARRAY_MAP_LOOP(sin); break;
        case ARRAY_MAP_SQRT: W_ARRAY_MAP_LOOP(sqrt); break;
        case ARRAY_MAP_EXP:  W_ARRAY_MAP_LOOP(exp); break;
        case ARRAY_MAP_LOG:  W_ARRAY_MAP_LOOP(log); break;
        case ARRAY_MAP_TAN:  W_ARRAY_MAP_LOOP(tan); break;
    }
#undef W_ARRAY_MAP_LOOP
    return result;
}

WValue w_array_cos_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_COS); }
WValue w_array_cos_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_COS); }
WValue w_array_cos_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_COS); }
WValue w_array_sin_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_SIN); }
WValue w_array_sin_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_SIN); }
WValue w_array_sin_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_SIN); }
WValue w_array_sqrt_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_SQRT); }
WValue w_array_sqrt_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_SQRT); }
WValue w_array_sqrt_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_SQRT); }
WValue w_array_exp_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_EXP); }
WValue w_array_exp_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_EXP); }
WValue w_array_exp_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_EXP); }
WValue w_array_log_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_LOG); }
WValue w_array_log_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_LOG); }
WValue w_array_log_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_LOG); }
WValue w_array_tan_signed(WValue arr) { return array_map_f64(arr, 1, ARRAY_MAP_TAN); }
WValue w_array_tan_unsigned(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_TAN); }
WValue w_array_tan_float(WValue arr) { return array_map_f64(arr, 0, ARRAY_MAP_TAN); }

/* pdqsort — pattern-defeating quicksort, type-specialized for integer typed
 * arrays. Replaces the old qsort-with-callback path: inlined comparisons +
 * branchless block partitioning make it ~4x faster on random data. The
 * kernels compare raw storage bits as unsigned; signed and float element
 * types are mapped onto unsigned order around the kernel call (see
 * w_ta_sign_flip and the w_ta_f*_enc key transforms below). */
#define PDQ_T uint8_t
#define PDQ_SUF u8
#include "pdqsort.inc"
#undef PDQ_T
#undef PDQ_SUF
#define PDQ_T uint16_t
#define PDQ_SUF u16
#include "pdqsort.inc"
#undef PDQ_T
#undef PDQ_SUF
#define PDQ_T uint32_t
#define PDQ_SUF u32
#include "pdqsort.inc"
#undef PDQ_T
#undef PDQ_SUF
#define PDQ_T uint64_t
#define PDQ_SUF u64
#include "pdqsort.inc"
#undef PDQ_T
#undef PDQ_SUF

/* ipnsort — instruction-parallel network sort (the algorithm behind Rust's
 * sort_unstable), type-specialized like pdqsort above. Exposed as Array#ipnsort
 * for callers who want it explicitly; faster than pdqsort on random data via a
 * branchless cyclic Lomuto partition + Batcher-network small-sort. */
#define IPN_T uint8_t
#define IPN_SUF u8
#include "ipnsort.inc"
#undef IPN_T
#undef IPN_SUF
#define IPN_T uint16_t
#define IPN_SUF u16
#include "ipnsort.inc"
#undef IPN_T
#undef IPN_SUF
#define IPN_T uint32_t
#define IPN_SUF u32
#include "ipnsort.inc"
#undef IPN_T
#undef IPN_SUF
#define IPN_T uint64_t
#define IPN_SUF u64
#include "ipnsort.inc"
#undef IPN_T
#undef IPN_SUF

/* LSD radix — O(n), the fastest sort for large integer arrays. Array#sort
 * routes here above RADIX_THRESHOLD elements; below it, pdqsort's lower
 * constant factor + pattern-adaptivity win. */
#define RDX_T uint8_t
#define RDX_SUF u8
#include "radixsort.inc"
#undef RDX_T
#undef RDX_SUF
#define RDX_T uint16_t
#define RDX_SUF u16
#include "radixsort.inc"
#undef RDX_T
#undef RDX_SUF
#define RDX_T uint32_t
#define RDX_SUF u32
#include "radixsort.inc"
#undef RDX_T
#undef RDX_SUF
#define RDX_T uint64_t
#define RDX_SUF u64
#include "radixsort.inc"
#undef RDX_T
#undef RDX_SUF

/* Comparison→radix crossover, per storage width. LSD radix does one
 * histogram scan plus up to sizeof(T) scatter passes, so its break-even
 * against the comparison kernels scales with element width: measured on
 * random data (kernel-only harness, Apple Silicon) the crossover sits near
 * n=64 for u8 and near n=2k for u64. The old single RADIX_THRESHOLD of 256
 * put 64-bit arrays on radix ~8x too early and 8-bit arrays ~4x too late. */
static inline int w_ta_use_radix(int64_t storage_bits, int64_t n) {
    switch (storage_bits) {
        case 8:  return n >= 64;
        case 16: return n >= 128;
        case 32: return n >= 512;
        default: return n >= 1024 && n <= 1048576;
    }
}

/* Signed typed arrays ride the unsigned kernels through a sign-bit flip:
 * XOR of the sign bit maps two's-complement order onto unsigned order, and
 * the flip is its own inverse. Two linear passes — noise next to the sort
 * itself — and every kernel (pdq/radix/ipn/tim/ska/wolf) inherits signed
 * correctness from this one place. */
static void w_ta_sign_flip(void *slots, int64_t storage_bits, int64_t n) {
    int64_t i;
    switch (storage_bits) {
        case 8:  { uint8_t  *p = (uint8_t *)slots;  for (i = 0; i < n; i++) p[i] ^= 0x80u; break; }
        case 16: { uint16_t *p = (uint16_t *)slots; for (i = 0; i < n; i++) p[i] ^= 0x8000u; break; }
        case 32: { uint32_t *p = (uint32_t *)slots; for (i = 0; i < n; i++) p[i] ^= 0x80000000u; break; }
        case 64: { uint64_t *p = (uint64_t *)slots; for (i = 0; i < n; i++) p[i] ^= 0x8000000000000000ULL; break; }
    }
}

/* IEEE-754 total-order keys: XOR all bits of a negative, only the sign bit
 * of a non-negative — a monotone bijection from float order onto unsigned
 * integer order, so float arrays ride the same integer kernels. The decode
 * mask mirrors the encode: the encoded sign bit records which mask was
 * applied. Deterministic NaN placement falls out (-NaN first, +NaN last),
 * where the old qsort comparator — for which NaN "equals" everything —
 * left NaNs stranded wherever the pivots happened to put them. */
static void w_ta_f32_enc(uint32_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x80000000u) ? 0xFFFFFFFFu : 0x80000000u; }
static void w_ta_f32_dec(uint32_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x80000000u) ? 0x80000000u : 0xFFFFFFFFu; }
static void w_ta_f64_enc(uint64_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x8000000000000000ULL) ? 0xFFFFFFFFFFFFFFFFULL : 0x8000000000000000ULL; }
static void w_ta_f64_dec(uint64_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x8000000000000000ULL) ? 0x8000000000000000ULL : 0xFFFFFFFFFFFFFFFFULL; }
static void w_ta_f16_enc(uint16_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x8000u) ? 0xFFFFu : 0x8000u; }
static void w_ta_f16_dec(uint16_t *p, int64_t n) { for (int64_t i = 0; i < n; i++) p[i] ^= (p[i] & 0x8000u) ? 0x8000u : 0xFFFFu; }

/* Bottom-up stable mergesort over raw WValue slots ordered by
 * w_value_compare — Array#stable_sort's fallback for mixed polymorphic
 * arrays, where qsort could reorder distinguishable elements that compare
 * equal (2 vs 2.0). Ties keep the left (earlier) run's element. O(n)
 * scratch; on OOM falls back to qsort — order still correct, stability
 * no longer guaranteed. */
static void w_stable_merge_wvalues(WValue *a, int64_t n) {
    if (n < 2) return;
    WValue *tmp = (WValue *)malloc((size_t)n * sizeof(WValue));
    if (!tmp) { qsort(a, (size_t)n, sizeof(WValue), w_value_compare); return; }
    WValue *src = a, *dst = tmp;
    for (int64_t width = 1; width < n; width *= 2) {
        for (int64_t left = 0; left < n; left += width * 2) {
            int64_t mid = left + width; if (mid > n) mid = n;
            int64_t right = left + width * 2; if (right > n) right = n;
            int64_t i = left, j = mid, k = left;
            while (i < mid && j < right)
                dst[k++] = (w_value_compare(&src[i], &src[j]) <= 0) ? src[i++] : src[j++];
            while (i < mid) dst[k++] = src[i++];
            while (j < right) dst[k++] = src[j++];
        }
        WValue *t = src; src = dst; dst = t;
    }
    if (src != a) memcpy(a, src, (size_t)n * sizeof(WValue));
    free(tmp);
}

typedef struct {
    uint64_t key;
    WValue val;
} WStrSortItem;

static inline void w_str_raw_ptr_len(WValue v, char buf6[6], const char **out_s, size_t *out_len) {
    size_t mode = (v >> 1) & 7;
    if (mode <= 5) {
        uint64_t pay = v >> 4;
        memcpy(buf6, &pay, 6);
        *out_s = buf6;
        *out_len = mode;
    } else if (mode == 6) {
        uint32_t idx = (uint32_t)((v >> 4) & 0xFFFFFF);
        const uint8_t *slot = g_string_slab.base + ((size_t)idx << 5);
        *out_s = (const char *)(slot + W_SLAB_DATA_OFFSET);
        size_t cached = (size_t)((v >> 28) & 0x3F);
        *out_len = cached ? cached : slot[1];
    } else {
        WString *ws = w_as_heap_str(v);
        *out_s = ws->data;
        *out_len = w_heap_string_len(ws);
    }
}

static void w_sort_strings_radix(WValue *slots, int64_t sz, int stable) {
    int64_t s = 1;
    while (s < sz && w_string_compare(slots[s - 1], slots[s]) <= 0) s++;
    if (s == sz) return;

    int pooled = 0;
    size_t need_bytes = (size_t)sz * 2 * sizeof(WStrSortItem);
    WStrSortItem *buf = (WStrSortItem *)rdx_scratch_acquire(need_bytes, &pooled);
    if (!buf) {
        if (stable) w_stable_merge_wvalues(slots, sz);
        else qsort(slots, (size_t)sz, sizeof(WValue), w_value_compare);
        return;
    }
    WStrSortItem *items = buf;
    WStrSortItem *tmp = buf + sz;

    char b0[6], b1[6], b2[6];
    const char *p0, *p1, *p2;
    size_t l0, l1, l2;
    w_str_raw_ptr_len(slots[0], b0, &p0, &l0);
    w_str_raw_ptr_len(slots[sz - 1], b1, &p1, &l1);
    w_str_raw_ptr_len(slots[sz >> 1], b2, &p2, &l2);
    size_t cp = l0 < l1 ? l0 : l1;
    if (l2 < cp) cp = l2;
    if (cp > 64) cp = 64;
    size_t k_cp = 0;
    while (k_cp < cp && p0[k_cp] == p1[k_cp] && p0[k_cp] == p2[k_cp]) k_cp++;
    cp = k_cp;

    size_t count[8][256];
rebuild_keys:
    memset(count, 0, sizeof(count));
    for (int64_t i = 0; i < sz; i++) {
        WValue v = slots[i];
        char ibuf[6];
        const char *ptr;
        size_t len;
        w_str_raw_ptr_len(v, ibuf, &ptr, &len);
        if (cp > 0) {
            if (len < cp || memcmp(ptr, p0, cp) != 0) {
                cp = 0;
                goto rebuild_keys;
            }
        }
        size_t rem = len - cp;
        const uint8_t *p = (const uint8_t *)ptr + cp;
        uint64_t k = 0;
        if (rem >= 8) {
            memcpy(&k, p, 8);
            k = __builtin_bswap64(k);
        } else {
            switch (rem) {
                case 7: k |= (uint64_t)p[6] << 8;  /* fallthrough */
                case 6: k |= (uint64_t)p[5] << 16; /* fallthrough */
                case 5: k |= (uint64_t)p[4] << 24; /* fallthrough */
                case 4: { uint32_t hi; memcpy(&hi, p, 4); k |= (uint64_t)__builtin_bswap32(hi) << 32; break; }
                case 3: k |= (uint64_t)p[2] << 40; /* fallthrough */
                case 2: k |= (uint64_t)p[1] << 48; /* fallthrough */
                case 1: k |= (uint64_t)p[0] << 56; break;
                default: break;
            }
        }
        items[i].key = k;
        items[i].val = v;
        count[0][k & 0xFFu]++;
        count[1][(k >> 8) & 0xFFu]++;
        count[2][(k >> 16) & 0xFFu]++;
        count[3][(k >> 24) & 0xFFu]++;
        count[4][(k >> 32) & 0xFFu]++;
        count[5][(k >> 40) & 0xFFu]++;
        count[6][(k >> 48) & 0xFFu]++;
        count[7][(k >> 56) & 0xFFu]++;
    }

    WStrSortItem *src = items, *dst = tmp;
    for (int pass = 0; pass < 8; pass++) {
        size_t *cnt = count[pass];
        int shift = pass * 8;
        if (cnt[(size_t)((src[0].key >> shift) & 0xFFu)] == (size_t)sz) continue;
        size_t acc = 0;
        for (int b = 0; b < 256; b++) { size_t c = cnt[b]; cnt[b] = acc; acc += c; }
        int64_t i = 0;
        for (; i + 4 <= sz; i += 4) {
            WStrSortItem x0 = src[i];
            WStrSortItem x1 = src[i + 1];
            WStrSortItem x2 = src[i + 2];
            WStrSortItem x3 = src[i + 3];
            dst[cnt[(size_t)((x0.key >> shift) & 0xFFu)]++] = x0;
            dst[cnt[(size_t)((x1.key >> shift) & 0xFFu)]++] = x1;
            dst[cnt[(size_t)((x2.key >> shift) & 0xFFu)]++] = x2;
            dst[cnt[(size_t)((x3.key >> shift) & 0xFFu)]++] = x3;
        }
        for (; i < sz; i++) {
            WStrSortItem x = src[i];
            dst[cnt[(size_t)((x.key >> shift) & 0xFFu)]++] = x;
        }
        WStrSortItem *t = src; src = dst; dst = t;
    }

    for (int64_t i = 0; i < sz; i++) slots[i] = src[i].val;

    int64_t i = 0;
    while (i + 1 < sz) {
        if (__builtin_expect(src[i].key == src[i + 1].key, 0)) {
            int64_t r_start = i;
            uint64_t rk = src[i].key;
            int has_diff_val = (src[i].val != src[i + 1].val);
            i += 2;
            while (i < sz && src[i].key == rk) {
                if (src[i].val != src[r_start].val) has_diff_val = 1;
                i++;
            }
            if (has_diff_val) {
                int64_t r_len = i - r_start;
                if (r_len <= 16) {
                    for (int64_t a = r_start + 1; a < i; a++) {
                        WValue v = slots[a];
                        int64_t b = a - 1;
                        while (b >= r_start && w_string_compare(slots[b], v) > 0) {
                            slots[b + 1] = slots[b];
                            b--;
                        }
                        slots[b + 1] = v;
                    }
                } else if (stable) {
                    w_stable_merge_wvalues(slots + r_start, r_len);
                } else {
                    qsort(slots + r_start, (size_t)r_len, sizeof(WValue), w_value_compare);
                }
            }
        } else {
            i++;
        }
    }

    rdx_scratch_release(buf, pooled);
}

static WValue w_array_sort_impl(WValue arr, int stable) {
    WArray *src = w_as_array(arr);
    int64_t bits = array_storage_bits(src->ebits);
    WValue result = (bits >= 8) ? w_array_new_inline(src->ebits, src->size)
                                : w_array_new(src->ebits, src->size);
    WArray *dst = w_as_array(result);
    int64_t nbytes = array_byte_size(src->ebits, src->size);
    int64_t src_off = array_byte_size(src->ebits, src->start);
    memcpy(dst->slots, (uint8_t *)src->slots + src_off, nbytes);
    dst->size = src->size;
    int64_t sz = dst->size;
    if (dst->ebits == 65) {
        WValue *slots = (WValue *)dst->slots;
        if (sz > 1) {
            WValue v0 = slots[0];
            int all_int = 0, all_dbl = 0, all_dec = 0, all_str = 0;
            int min_sc = 100, max_sc = -100;
            if (w_is_int(v0)) {
                all_int = 1;
                for (int64_t i = 1; i < sz; i++) {
                    if (__builtin_expect(!w_is_int(slots[i]), 0)) { all_int = 0; break; }
                }
            } else if (w_is_double(v0)) {
                all_dbl = 1;
                for (int64_t i = 1; i < sz; i++) {
                    if (__builtin_expect(!w_is_double(slots[i]), 0)) { all_dbl = 0; break; }
                }
            } else if ((v0 & (W_TAG_MASK | 1)) == W_TAG_STRINGSYM) {
                all_str = 1;
                for (int64_t i = 1; i < sz; i++) {
                    if (__builtin_expect((slots[i] & (W_TAG_MASK | 1)) != W_TAG_STRINGSYM, 0)) { all_str = 0; break; }
                }
            } else if (w_is_decimal(v0)) {
                all_dec = 1;
                min_sc = max_sc = w_unbox_decimal_scale(v0);
                for (int64_t i = 1; i < sz; i++) {
                    WValue v = slots[i];
                    if (__builtin_expect(!w_is_decimal(v), 0)) { all_dec = 0; break; }
                    int sc = w_unbox_decimal_scale(v);
                    if (sc < min_sc) min_sc = sc;
                    if (sc > max_sc) max_sc = sc;
                }
            }
            if (all_int) {
                uint64_t *u = (uint64_t *)slots;
                for (int64_t i = 0; i < sz; i++)
                    u[i] ^= UINT64_C(0x0000800000000000);
                if (w_ta_use_radix(64, sz)) rdx_sort_u64(u, sz); else ipn_sort_u64(u, sz);
                for (int64_t i = 0; i < sz; i++)
                    u[i] ^= UINT64_C(0x0000800000000000);
                return result;
            }
            if (all_dbl) {
                uint64_t *u = (uint64_t *)slots;
                for (int64_t i = 0; i < sz; i++) {
                    uint64_t raw = u[i] - W_DOUBLE_BIAS;
                    u[i] = raw ^ (((uint64_t)((int64_t)raw >> 63)) | 0x8000000000000000ULL);
                }
                if (w_ta_use_radix(64, sz)) rdx_sort_u64(u, sz); else ipn_sort_u64(u, sz);
                for (int64_t i = 0; i < sz; i++) {
                    uint64_t enc = u[i];
                    uint64_t raw = enc ^ ((enc & 0x8000000000000000ULL) ? 0x8000000000000000ULL : 0xFFFFFFFFFFFFFFFFULL);
                    u[i] = raw + W_DOUBLE_BIAS;
                }
                return result;
            }
            if (all_str && sz >= 32) {
                w_sort_strings_radix(slots, sz, stable);
                return result;
            }
            if (all_dec && min_sc == max_sc) {
                uint64_t *u = (uint64_t *)slots;
                for (int64_t i = 0; i < sz; i++)
                    u[i] ^= (UINT64_C(1) << 45);
                if (w_ta_use_radix(64, sz)) rdx_sort_u64(u, sz); else ipn_sort_u64(u, sz);
                for (int64_t i = 0; i < sz; i++)
                    u[i] ^= (UINT64_C(1) << 45);
                return result;
            }
            if (all_dec && max_sc - min_sc <= 7) {
                static const int64_t p10[8] = {
                    1LL, 10LL, 100LL, 1000LL, 10000LL, 100000LL, 1000000LL, 10000000LL
                };
                uint64_t *u = (uint64_t *)slots;
                for (int64_t i = 0; i < sz; i++) {
                    int64_t sig = w_unbox_decimal_sig(slots[i]);
                    int sc = w_unbox_decimal_scale(slots[i]);
                    int dsc = sc - min_sc;
                    int64_t ssig = sig * p10[dsc];
                    u[i] = (((uint64_t)ssig << 3) ^ UINT64_C(0x8000000000000000)) | (uint64_t)dsc;
                }
                if (w_ta_use_radix(64, sz)) rdx_sort_u64(u, sz); else ipn_sort_u64(u, sz);
                for (int64_t i = 0; i < sz; i++) {
                    uint64_t enc = u[i];
                    int64_t ssig = ((int64_t)(enc ^ UINT64_C(0x8000000000000000))) >> 3;
                    if (__builtin_expect((enc & 7u) == 0, 1)) {
                        slots[i] = w_box_decimal(ssig, min_sc);
                    } else {
                        slots[i] = w_decimal(ssig, min_sc);
                    }
                }
                return result;
            }
        }
        if (stable) w_stable_merge_wvalues((WValue *)dst->slots, sz);
        else qsort(dst->slots, dst->size, sizeof(WValue), w_value_compare);
        return result;
    }
    if (array_is_float(dst)) {
        /* f32/f64/bf16 sort as unsigned keys under the total-order transform.
         * (The old path qsort'ed through a callback — and would have read
         * bf16's 2-byte slots as doubles, 4x past the buffer.) */
        if (dst->ebits == -32) {
            uint32_t *p = (uint32_t *)dst->slots;
            w_ta_f32_enc(p, sz);
            if (w_ta_use_radix(32, sz)) rdx_sort_u32(p, sz); else pdq_sort_u32(p, sz);
            w_ta_f32_dec(p, sz);
        } else if (dst->ebits == -116 || dst->ebits == -16) {
            uint16_t *p = (uint16_t *)dst->slots;
            w_ta_f16_enc(p, sz);
            if (w_ta_use_radix(16, sz)) rdx_sort_u16(p, sz); else pdq_sort_u16(p, sz);
            w_ta_f16_dec(p, sz);
        } else {
            uint64_t *p = (uint64_t *)dst->slots;
            w_ta_f64_enc(p, sz);
            if (w_ta_use_radix(64, sz)) rdx_sort_u64(p, sz); else ipn_sort_u64(p, sz);
            w_ta_f64_dec(p, sz);
        }
        return result;
    }
    int use_radix = w_ta_use_radix(bits, sz);
    int is_signed = array_is_signed_int(dst);
    if (is_signed) w_ta_sign_flip(dst->slots, bits, sz);
    switch (bits) {
        case 8:  if (use_radix) rdx_sort_u8((uint8_t *)dst->slots, sz);   else pdq_sort_u8((uint8_t *)dst->slots, sz); break;
        case 16: if (use_radix) rdx_sort_u16((uint16_t *)dst->slots, sz); else pdq_sort_u16((uint16_t *)dst->slots, sz); break;
        case 32: if (use_radix) rdx_sort_u32((uint32_t *)dst->slots, sz); else pdq_sort_u32((uint32_t *)dst->slots, sz); break;
        /* 64-bit's comparison tier is ipnsort, not pdqsort: measured in situ
         * it matches pdq at n<128 and pulls ahead everywhere above. */
        case 64: if (use_radix) rdx_sort_u64((uint64_t *)dst->slots, sz); else ipn_sort_u64((uint64_t *)dst->slots, sz); break;
        case 4: {
            uint8_t *tmp = malloc(dst->size);
            /* i4: two's-complement order at nibble width — same flip, 4-bit sign. */
            uint8_t nibble_flip = (dst->ebits == -4) ? 0x8u : 0x0u;
            for (int64_t j = 0; j < dst->size; j++) tmp[j] = (uint8_t)((array_read(dst, j) & 0xFu) ^ nibble_flip);
            if (use_radix) rdx_sort_u8(tmp, sz); else pdq_sort_u8(tmp, sz);
            for (int64_t j = 0; j < dst->size; j++) array_write(dst, j, (uint64_t)(tmp[j] ^ nibble_flip));
            free(tmp);
            break;
        }
    }
    if (is_signed) w_ta_sign_flip(dst->slots, bits, sz);
    return result;
}

WValue w_array_sort(WValue arr) { return w_array_sort_impl(arr, 0); }

/* Array#stable_sort — sorted copy where elements that compare equal keep
 * their input order. Typed and homogeneous-boxed arrays share sort's
 * width-tuned kernel selection unchanged: equal elements there are
 * indistinguishable values (and the radix tiers are stable by
 * construction), so those fast paths are stability-safe as-is. Only the
 * mixed polymorphic fallback differs — stable mergesort instead of qsort. */
WValue w_array_stable_sort(WValue arr) { return w_array_sort_impl(arr, 1); }

/* Array#ipnsort — explicit instruction-parallel network sort. Same integer
 * typed-array semantics as w_array_sort's comparison tier (per-width
 * specialization, signed types via the sign flip), but always ipnsort — no
 * radix crossover. w64, float, and 4-bit arrays fall back to w_array_sort,
 * which owns those tiers. */
WValue w_array_ipnsort(WValue arr) {
    WArray *src = w_as_array(arr);
    if (src->ebits == 65 || array_is_float(src) || array_storage_bits(src->ebits) == 4) {
        return w_array_sort(arr);
    }
    WValue result = w_array_new_inline(src->ebits, src->size);
    WArray *dst = w_as_array(result);
    int64_t nbytes = array_byte_size(src->ebits, src->size);
    int64_t src_off = array_byte_size(src->ebits, src->start);
    memcpy(dst->slots, (uint8_t *)src->slots + src_off, nbytes);
    dst->size = src->size;
    int64_t sz = dst->size;
    int64_t bits = array_storage_bits(dst->ebits);
    int is_signed = array_is_signed_int(dst);
    if (is_signed) w_ta_sign_flip(dst->slots, bits, sz);
    switch (bits) {
        case 8:  ipn_sort_u8((uint8_t *)dst->slots, sz);   break;
        case 16: ipn_sort_u16((uint16_t *)dst->slots, sz); break;
        case 32: ipn_sort_u32((uint32_t *)dst->slots, sz); break;
        case 64: ipn_sort_u64((uint64_t *)dst->slots, sz); break;
    }
    if (is_signed) w_ta_sign_flip(dst->slots, bits, sz);
    return result;
}

/* Counting sort for integer arrays over a bounded range. Three passes: find
 * (or take) [lo,hi], tally counts[v-lo], then write values back in order.
 * O(n + range) — a big win when the value range is tight relative to n.
 * Falls back to w_array_sort for float/non-int arrays, out-of-range values
 * (explicit range), or a range too large to be worth the counts array. */
static WValue w_array_csort_impl(WValue arr, int64_t lo, int64_t hi, int auto_range) {
    WArray *src = w_as_array(arr);
    if (array_is_float(src)) return w_array_sort(arr);
    int64_t n = src->size;
    WValue result = w_array_new(src->ebits, n);
    WArray *dst = w_as_array(result);
    dst->size = n;
    int is_w64 = (dst->ebits == 65);
    if (n <= 1) {
        if (n == 1) {
            WValue e = array_slot_load_decoded(src, 0);
            if (is_w64) dst->slots[0] = e;
            else if (w_is_int(e)) array_write(dst, 0, (uint64_t)w_as_int(e));
            else { free(w_as_ptr(result)); return w_array_sort(arr); }
        }
        return result;
    }
    /* Pass 1: validate integers and (auto) find range or (explicit) bounds-check. */
    if (auto_range) { lo = INT64_MAX; hi = INT64_MIN; }
    int fallback = 0;
    for (int64_t i = 0; i < n; i++) {
        WValue e = array_slot_load_decoded(src, i);
        if (!w_is_int(e)) { fallback = 1; break; }
        int64_t v = w_as_int(e);
        if (auto_range) { if (v < lo) lo = v; if (v > hi) hi = v; }
        else if (v < lo || v > hi) { fallback = 1; break; }
    }
    if (fallback || hi < lo) return w_array_sort(arr);
    uint64_t range = (uint64_t)(hi - lo) + 1;
    /* Counting sort is only viable when the range is comparable to n; a
     * sparse range would allocate (and zero) an enormous counts array. The
     * old floor of 1MB let a 64-element array with a 64k range pay ~900
     * ns/elem zeroing counts nobody used — 4096 keeps the small-n floor
     * proportionate while still admitting every n>=range/4 workload. */
    if (range > (uint64_t)n * 4 + 4096) return w_array_sort(arr);
    int64_t *counts = (int64_t *)calloc((size_t)range, sizeof(int64_t));
    if (!counts) return w_array_sort(arr);
    for (int64_t i = 0; i < n; i++)
        counts[w_as_int(array_slot_load_decoded(src, i)) - lo]++;
    int64_t idx = 0;
    for (uint64_t b = 0; b < range; b++) {
        int64_t val = lo + (int64_t)b, c = counts[b];
        for (int64_t k = 0; k < c; k++) {
            if (is_w64) dst->slots[idx] = w_int(val);
            else array_write(dst, idx, (uint64_t)val);
            idx++;
        }
    }
    free(counts);
    return result;
}
WValue w_array_csort(WValue arr) { return w_array_csort_impl(arr, 0, 0, 1); }
WValue w_array_csort_range(WValue arr, WValue lo, WValue hi) {
    return w_array_csort_impl(arr, w_as_int(lo), w_as_int(hi), 0);
}

/* Explicit alternative sort algorithms — Array#tsort / #skasort / #wolfsort.
 * Integer typed arrays only (storage-width kernels, signed element types via
 * the sign flip — matching Array#sort); float/generic arrays fall back to
 * Array#sort. timsort is stable + adaptive to near-sorted data; skasort is
 * an in-place MSD radix; wolfsort is a distribution+pdqsort hybrid. All
 * templated per element width. */
#define TIM_T uint8_t
#define TIM_SUF u8
#include "timsort.inc"
#undef TIM_T
#undef TIM_SUF
#define TIM_T uint16_t
#define TIM_SUF u16
#include "timsort.inc"
#undef TIM_T
#undef TIM_SUF
#define TIM_T uint32_t
#define TIM_SUF u32
#include "timsort.inc"
#undef TIM_T
#undef TIM_SUF
#define TIM_T uint64_t
#define TIM_SUF u64
#include "timsort.inc"
#undef TIM_T
#undef TIM_SUF

#define SKA_T uint8_t
#define SKA_SUF u8
#include "skasort.inc"
#undef SKA_T
#undef SKA_SUF
#define SKA_T uint16_t
#define SKA_SUF u16
#include "skasort.inc"
#undef SKA_T
#undef SKA_SUF
#define SKA_T uint32_t
#define SKA_SUF u32
#include "skasort.inc"
#undef SKA_T
#undef SKA_SUF
#define SKA_T uint64_t
#define SKA_SUF u64
#include "skasort.inc"
#undef SKA_T
#undef SKA_SUF

#define WOLF_T uint8_t
#define WOLF_SUF u8
#include "wolfsort.inc"
#undef WOLF_T
#undef WOLF_SUF
#define WOLF_T uint16_t
#define WOLF_SUF u16
#include "wolfsort.inc"
#undef WOLF_T
#undef WOLF_SUF
#define WOLF_T uint32_t
#define WOLF_SUF u32
#include "wolfsort.inc"
#undef WOLF_T
#undef WOLF_SUF
#define WOLF_T uint64_t
#define WOLF_SUF u64
#include "wolfsort.inc"
#undef WOLF_T
#undef WOLF_SUF

#define DEFINE_ARRAY_ALGO_SORT(fname, algo)                                     \
WValue fname(WValue arr) {                                                       \
    WArray *src = w_as_array(arr);                                       \
    if (array_is_float(src) || src->ebits == 65) return w_array_sort(arr);       \
    WValue result = w_array_new(src->ebits, src->size);                          \
    WArray *dst = w_as_array(result);                                    \
    int64_t nbytes = array_byte_size(src->ebits, src->size);                     \
    int64_t src_off = array_byte_size(src->ebits, src->start);                   \
    memcpy(dst->slots, (uint8_t *)src->slots + src_off, nbytes);                 \
    dst->size = src->size;                                                       \
    int64_t bits_ = array_storage_bits(dst->ebits);                              \
    int is_signed_ = array_is_signed_int(dst);                                   \
    if (is_signed_) w_ta_sign_flip(dst->slots, bits_, dst->size);                \
    switch (bits_) {                                                             \
        case 8:  algo##_u8((uint8_t *)dst->slots, dst->size); break;             \
        case 16: algo##_u16((uint16_t *)dst->slots, dst->size); break;           \
        case 32: algo##_u32((uint32_t *)dst->slots, dst->size); break;           \
        case 64: algo##_u64((uint64_t *)dst->slots, dst->size); break;           \
        case 4: {                                                                \
            uint8_t *tmp = malloc(dst->size);                                    \
            uint8_t nf_ = (dst->ebits == -4) ? 0x8u : 0x0u;                      \
            for (int64_t j = 0; j < dst->size; j++) tmp[j] = (uint8_t)((array_read(dst, j) & 0xFu) ^ nf_); \
            algo##_u8(tmp, dst->size);                                           \
            for (int64_t j = 0; j < dst->size; j++) array_write(dst, j, (uint64_t)(tmp[j] ^ nf_)); \
            free(tmp);                                                           \
            break;                                                               \
        }                                                                        \
    }                                                                            \
    if (is_signed_) w_ta_sign_flip(dst->slots, bits_, dst->size);                \
    return result;                                                               \
}
DEFINE_ARRAY_ALGO_SORT(w_array_tsort, tim_sort)
DEFINE_ARRAY_ALGO_SORT(w_array_skasort, ska_sort)
DEFINE_ARRAY_ALGO_SORT(w_array_wolfsort, wolf_sort)
#undef DEFINE_ARRAY_ALGO_SORT

/* Comparator sort — sign of the block's verdict for a pair. Ruby-style
 * contract: the block returns negative/zero/positive (any Int, or a Float
 * whose sign is used). Mirrors the Ruby engine's
 * Runtime::Builtins.array_compare, which also rejects non-numeric results
 * loudly instead of mis-sorting. */
static int w_sort_block_sign(WValue block, WValue x, WValue y) {
    WValue v = w_closure_call_2(block, x, y);
    if (w_is_int(v)) {
        int64_t s = w_as_int(v);
        return (s > 0) - (s < 0);
    }
    if (w_is_double(v)) {
        double d = w_as_double(v);
        return (d > 0) - (d < 0);
    }
    w_raise(w_string("sort: comparator block must return a negative/zero/positive number"));
    return 0;
}

/* `arr.sort -> (a, b) …` — stable bottom-up mergesort ordered by the
 * comparator block. The WN_sort IC row routes here whenever the call
 * carries a block; the blockless form keeps w_array_sort's typed qsort
 * fast paths above. Elements are decoded to WValues for the block calls
 * and re-encoded into a fresh array of the receiver's ebits, so typed
 * receivers (u8[], f64[], …) sort into typed results. Twin of the Ruby
 * engine's Runtime::Builtins.array_mergesort_copy. */
WValue w_array_sort_block(WValue arr, WValue block) {
    WArray *sa = w_as_array(arr);
    int64_t n = sa->size;
    WValue result = w_array_new(sa->ebits, n);
    WArray *da = w_as_array(result);
    da->size = sa->size;
    if (n == 0) return result;
    WValue *src = malloc((size_t)n * sizeof(WValue));
    WValue *dst = malloc((size_t)n * sizeof(WValue));
    for (int64_t i = 0; i < n; i++) src[i] = array_slot_load_decoded(sa, i);
    for (int64_t width = 1; width < n; width *= 2) {
        for (int64_t left = 0; left < n; left += width * 2) {
            int64_t mid = left + width;
            if (mid > n) mid = n;
            int64_t right = left + width * 2;
            if (right > n) right = n;
            int64_t i = left, j = mid, k = left;
            while (i < mid && j < right)
                dst[k++] = (w_sort_block_sign(block, src[i], src[j]) <= 0)
                             ? src[i++] : src[j++];
            while (i < mid) dst[k++] = src[i++];
            while (j < right) dst[k++] = src[j++];
        }
        WValue *t = src; src = dst; dst = t;
    }
    for (int64_t i = 0; i < n; i++) w_array_set(result, w_int(i), src[i]);
    free(src);
    free(dst);
    return result;
}

/* Unbiased uniform random integer in [0, limit) drawn from the platform
 * secure RNG (w_secure_random_fill — arc4random on Apple/BSD, getrandom or
 * /dev/urandom on Linux). Rejection-samples the top of the 64-bit range so
 * the modulo is bias-free, exactly like arc4random_uniform. `limit` must be
 * positive; a limit of 0 or 1 always yields 0. */
static uint64_t w_secure_uniform(uint64_t limit) {
    if (limit <= 1) return 0;
    uint64_t min = (uint64_t)(-limit) % limit; /* 2^64 mod limit */
    uint64_t r;
    do {
        w_secure_random_fill((uint8_t *)&r, sizeof(r));
    } while (r < min);
    return r % limit;
}

/* Fisher-Yates shuffle returning a fresh array of the receiver's ebits, so
 * typed receivers (u8[], f64[], …) shuffle into typed results. Elements are
 * decoded to WValues, permuted with the secure unbiased RNG above, then
 * re-encoded — the same decode/operate/re-encode shape as w_array_sort_block.
 * Twin of the Ruby engine's Runtime::Builtins.array_shuffle_copy. There is
 * NO seeded variant: the `random:` custom-RNG option the Ruby builtin accepts
 * is not honored on this path (documented in core/array.w). */
WValue w_array_shuffle(WValue arr) {
    WArray *sa = w_as_array(arr);
    int64_t n = sa->size;
    WValue result = w_array_new(sa->ebits, n);
    WArray *da = w_as_array(result);
    da->size = sa->size;
    if (n == 0) return result;
    WValue *buf = malloc((size_t)n * sizeof(WValue));
    for (int64_t i = 0; i < n; i++) buf[i] = array_slot_load_decoded(sa, i);
    for (int64_t i = n - 1; i > 0; i--) {
        int64_t j = (int64_t)w_secure_uniform((uint64_t)(i + 1));
        WValue t = buf[i];
        buf[i] = buf[j];
        buf[j] = t;
    }
    for (int64_t i = 0; i < n; i++) w_array_set(result, w_int(i), buf[i]);
    free(buf);
    return result;
}

static inline int w_uniq_needs_linear_eq(WValue v) {
    return w_is_array(v) || w_is_hash(v) || w_is_bytes(v) ||
           w_is_instance(v) || w_is_date(v) || is_quantity_any(v) ||
           w_is_ipv6(v) || w_is_mac(v);
}

WValue w_array_uniq(WValue arr) {
    WArray *sa = w_as_array(arr);
    int64_t n = sa->size;
    if (n <= 0) return w_array_new_empty();
    WValue result = w_array_new_inline(65, n);
    WArray *da = w_as_array(result);
    if (n == 1) {
        da->slots[0] = array_slot_load_decoded(sa, 0);
        da->size = 1;
        return result;
    }
    int is_w64 = (sa->ebits == 65);
    WValue *src_slots = sa->slots + sa->start;
    if (n <= 8) {
        int64_t out_len = 0;
        for (int64_t i = 0; i < n; i++) {
            WValue v = is_w64 ? src_slots[i] : array_slot_load_decoded(sa, i);
            int seen = 0;
            if (__builtin_expect(v != W_BIASED_NAN, 1)) {
                for (int64_t j = 0; j < out_len; j++) {
                    WValue k = da->slots[j];
                    if (k == v || (!w_both_ints(k, v) && w_eq(k, v) == W_TRUE)) {
                        seen = 1;
                        break;
                    }
                }
            }
            if (!seen) da->slots[out_len++] = v;
        }
        da->size = (int32_t)out_len;
        return result;
    }
    uint64_t cap = 16;
    while (cap < (uint64_t)n * 2) cap <<= 1;
    uint64_t mask = cap - 1;
    int32_t stack_ht[512];
    int32_t *ht = (cap <= 512) ? stack_ht : (int32_t *)malloc(cap * sizeof(int32_t));
    memset(ht, 0xFF, cap * sizeof(int32_t));

    int64_t out_len = 0;
    int has_instance = 0;
    int64_t i = 0;

    if (is_w64 && w_is_int(src_slots[0])) {
        for (; i < n; i++) {
            WValue v = src_slots[i];
            if (__builtin_expect(!w_is_int(v), 0)) break;
            uint64_t idx = w_hash_splitmix64(v) & mask;
            for (;;) {
                int32_t d = ht[idx];
                if (d < 0) {
                    int32_t new_d = (int32_t)out_len++;
                    ht[idx] = new_d;
                    da->slots[new_d] = v;
                    break;
                }
                if (da->slots[d] == v) break;
                idx = (idx + 1) & mask;
            }
        }
    }

    for (; i < n; i++) {
        WValue v = is_w64 ? src_slots[i] : array_slot_load_decoded(sa, i);
        if (__builtin_expect(v == W_BIASED_NAN, 0)) {
            da->slots[out_len++] = v;
            continue;
        }
        if (__builtin_expect(has_instance || w_uniq_needs_linear_eq(v), 0)) {
            if (w_is_instance(v)) has_instance = 1;
            int seen = 0;
            for (int64_t j = 0; j < out_len; j++) {
                if (w_eq(da->slots[j], v) == W_TRUE) {
                    seen = 1;
                    break;
                }
            }
            if (!seen) {
                int32_t new_d = (int32_t)out_len++;
                da->slots[new_d] = v;
                if (!w_uniq_needs_linear_eq(v)) {
                    uint64_t idx = w_hash_value_fast(v) & mask;
                    while (ht[idx] >= 0) idx = (idx + 1) & mask;
                    ht[idx] = new_d;
                }
            }
            continue;
        }
        uint64_t idx = w_hash_value_fast(v) & mask;
        for (;;) {
            int32_t d = ht[idx];
            if (d < 0) {
                int32_t new_d = (int32_t)out_len++;
                ht[idx] = new_d;
                da->slots[new_d] = v;
                break;
            }
            WValue slot_key = da->slots[d];
            if (__builtin_expect(slot_key == v, 1) ||
                (w_both_ints(slot_key, v) ? 0 : w_hash_key_eq(slot_key, v))) {
                break;
            }
            idx = (idx + 1) & mask;
        }
    }
    if (ht != stack_ht) free(ht);
    da->size = (int32_t)out_len;
    return result;
}

W_RT_INTERNAL WValue w_rt_array_slot_load_decoded(WArray *a, int64_t i) {
    return array_slot_load_decoded(a, i);
}
W_RT_INTERNAL void w_rt_array_release_slots(WValue *slots, int64_t bits, int64_t cap, uint8_t flags) {
    array_release_slots(slots, bits, cap, flags);
}
W_RT_INTERNAL int w_rt_array_has_views(WValue arr) {
    return w_array_has_views(arr);
}
