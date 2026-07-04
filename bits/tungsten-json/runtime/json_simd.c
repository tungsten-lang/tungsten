/* tungsten-json: 16-byte SIMD JSON structural classifier.
 *
 * simdjson-style stage-1 classifier: processes 64 source bytes per
 * iteration, identifies structural characters AND tracks JSON string
 * state (in-string vs out-of-string) IN PARALLEL via the PMULL
 * polynomial-multiply prefix-XOR trick.
 *
 * Output: one i32 offset per structural character (when not in string)
 * plus one offset per string-OPEN quote. Matches simdjson stage 1
 * semantics. The downstream parser walks the offsets and identifies
 * number/keyword positions by looking between consecutive structurals.
 *
 * This implementation reimplements simdjson's algorithms (find_escaped
 * bit trick, prefix_xor via vmull_p64, vandq+vpaddq movemask). simdjson
 * is dual-licensed Apache 2.0 / MIT; we use the algorithms under MIT.
 * See https://github.com/simdjson/simdjson for the original source.
 *
 * Throughput on a 205 MB pretty-printed JSON file (Apple M3 Max):
 *   single-thread:  ~5300 MB/s  (vs simdjson's 5755 MB/s)
 *   16 threads:    ~52000 MB/s  (vs simdjson's 60000 MB/s)
 *
 * Build: this file is currently compiled into the core runtime archive
 * by `bin/tungsten build`. The long-term plan is for each bit to have
 * its own runtime archive that gets LTO-linked alongside core when the
 * bit is loaded, at which point this file will be picked up
 * automatically by the bit's own build infrastructure rather than by
 * core's. For now, the build system finds it via a hard-coded include
 * from `runtime/runtime.c`.
 */

#include <stdint.h>
#include <stddef.h>

#ifdef __aarch64__
#include <arm_neon.h>

/* Convert 4 NEON byte masks (each lane 0xFF or 0) to a 64-bit bitmap.
 * Each input vector contributes 16 bits; result has bit i = 1 iff lane
 * i (across all 4 vectors, 0..63) was 0xFF. */
static inline uint64_t w_neon_to_bitmask4(uint8x16_t t0, uint8x16_t t1,
                                            uint8x16_t t2, uint8x16_t t3) {
    static const uint8_t bit_mask_arr[16] = {
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
    };
    uint8x16_t bit_mask = vld1q_u8(bit_mask_arr);
    t0 = vandq_u8(t0, bit_mask);
    t1 = vandq_u8(t1, bit_mask);
    t2 = vandq_u8(t2, bit_mask);
    t3 = vandq_u8(t3, bit_mask);
    uint8x16_t sum0 = vpaddq_u8(t0, t1);
    uint8x16_t sum1 = vpaddq_u8(t2, t3);
    sum0 = vpaddq_u8(sum0, sum1);
    sum0 = vpaddq_u8(sum0, sum0);
    return vgetq_lane_u64(vreinterpretq_u64_u8(sum0), 0);
}

/* Parallel prefix XOR of a 64-bit bitmap via polynomial multiply.
 * Bit i of result = XOR of bits 0..i of input. Used to compute the
 * in-string bitmap from the unescaped-quote bitmap in a single op. */
__attribute__((target("crypto")))
static inline uint64_t w_prefix_xor(uint64_t bitmap) {
    poly64x1_t a = vcreate_p64(bitmap);
    poly64x1_t ones = vcreate_p64(~0ULL);
    poly128_t r = vmull_p64(a, ones);
    return (uint64_t)vgetq_lane_u64(vreinterpretq_u64_p128(r), 0);
}

/* simdjson's bit trick to identify which characters are escaped by an
 * odd-length backslash run. Carries state across blocks via *prev_escaped. */
static inline uint64_t w_find_escaped(uint64_t backslash, uint64_t *prev_escaped) {
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

/* Process 64 source bytes, returning the emit bitmap (positions to
 * write to the output offset array). Updates the in-string and escape
 * carry state for the next block. */
__attribute__((target("crypto")))
static inline uint64_t w_classify_block_64(const uint8_t *src,
                                             uint64_t *prev_in_string,
                                             uint64_t *prev_escaped) {
    uint8x16_t v0 = vld1q_u8(src + 0);
    uint8x16_t v1 = vld1q_u8(src + 16);
    uint8x16_t v2 = vld1q_u8(src + 32);
    uint8x16_t v3 = vld1q_u8(src + 48);

    uint8x16_t bs_v = vdupq_n_u8('\\');
    uint64_t backslash = w_neon_to_bitmask4(
        vceqq_u8(v0, bs_v), vceqq_u8(v1, bs_v),
        vceqq_u8(v2, bs_v), vceqq_u8(v3, bs_v));

    uint8x16_t q_v = vdupq_n_u8('"');
    uint64_t quote_raw = w_neon_to_bitmask4(
        vceqq_u8(v0, q_v), vceqq_u8(v1, q_v),
        vceqq_u8(v2, q_v), vceqq_u8(v3, q_v));

    #define W_STRUCT_OF(v) \
        vorrq_u8( \
            vorrq_u8( \
                vorrq_u8(vceqq_u8((v), vdupq_n_u8('{')), vceqq_u8((v), vdupq_n_u8('}'))), \
                vorrq_u8(vceqq_u8((v), vdupq_n_u8('[')), vceqq_u8((v), vdupq_n_u8(']'))) \
            ), \
            vorrq_u8(vceqq_u8((v), vdupq_n_u8(',')), vceqq_u8((v), vdupq_n_u8(':'))) \
        )
    uint64_t structural = w_neon_to_bitmask4(W_STRUCT_OF(v0), W_STRUCT_OF(v1),
                                               W_STRUCT_OF(v2), W_STRUCT_OF(v3));
    #undef W_STRUCT_OF

    uint64_t escaped = w_find_escaped(backslash, prev_escaped);
    uint64_t quote = quote_raw & ~escaped;
    uint64_t in_string = w_prefix_xor(quote) ^ *prev_in_string;
    *prev_in_string = (uint64_t)((int64_t)in_string >> 63);

    return (structural & ~in_string) | (quote & in_string);
}

/* Main classifier entry point. Takes a raw byte pointer + length and an
 * i32 output buffer. Returns the count of offsets emitted. */
int64_t w_json_simd_classify(int64_t src_ptr, int64_t src_len, int64_t out_ptr) {
    const uint8_t *src = (const uint8_t *)(uintptr_t)src_ptr;
    uint32_t *out = (uint32_t *)(uintptr_t)out_ptr;
    size_t len = (size_t)src_len;
    size_t out_idx = 0;
    uint64_t prev_in_string = 0;
    uint64_t prev_escaped = 0;

    size_t pos = 0;
    while (pos + 64 <= len) {
        uint64_t emit = w_classify_block_64(src + pos, &prev_in_string, &prev_escaped);
        while (emit) {
            int bit = __builtin_ctzll(emit);
            out[out_idx++] = (uint32_t)(pos + bit);
            emit &= emit - 1;
        }
        pos += 64;
    }

    /* Tail: byte-by-byte scalar for the last <64 bytes */
    int in_string = (int)(prev_in_string & 1);
    int after_bs  = (int)(prev_escaped & 1);
    while (pos < len) {
        uint8_t b = src[pos];
        if (in_string) {
            if (after_bs) {
                after_bs = 0;
            } else if (b == '\\') {
                after_bs = 1;
            } else if (b == '"') {
                in_string = 0;
            }
        } else {
            if (b == '"') {
                in_string = 1;
                out[out_idx++] = (uint32_t)pos;
            } else if (b == '{' || b == '}' || b == '['
                    || b == ']' || b == ',' || b == ':') {
                out[out_idx++] = (uint32_t)pos;
            }
        }
        pos++;
    }
    return (int64_t)out_idx;
}

#else  /* x86 / non-aarch64 — scalar fallback with identical semantics. */

int64_t w_json_simd_classify(int64_t src_ptr, int64_t src_len, int64_t out_ptr) {
    const uint8_t *src = (const uint8_t *)(uintptr_t)src_ptr;
    uint32_t *out = (uint32_t *)(uintptr_t)out_ptr;
    size_t len = (size_t)src_len;
    size_t out_idx = 0;
    int in_string = 0, after_bs = 0;
    for (size_t pos = 0; pos < len; pos++) {
        uint8_t b = src[pos];
        if (in_string) {
            if (after_bs) after_bs = 0;
            else if (b == '\\') after_bs = 1;
            else if (b == '"') in_string = 0;
        } else {
            if (b == '"') {
                in_string = 1;
                out[out_idx++] = (uint32_t)pos;
            } else if (b == '{' || b == '}' || b == '['
                    || b == ']' || b == ',' || b == ':') {
                out[out_idx++] = (uint32_t)pos;
            }
        }
    }
    return (int64_t)out_idx;
}

#endif
