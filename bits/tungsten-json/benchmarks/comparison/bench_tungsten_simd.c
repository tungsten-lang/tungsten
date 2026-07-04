/* Full simdjson-style 16-byte SIMD JSON structural classifier in C.
 *
 * Processes 64 source bytes per iteration:
 *   - 4× vld1q_u8 NEON loads
 *   - vceqq_u8 + vorrq_u8 to compute backslash, quote, structural masks
 *   - Pack 4 16-byte mask vectors into a 64-bit bitmap via vandq + vpaddq
 *   - find_escaped(): simdjson's bit trick to identify chars escaped by
 *     an odd-length backslash run
 *   - prefix_xor(): PMULL polynomial-multiply trick to compute the
 *     in-string bitmap from the unescaped-quote bitmap in parallel
 *   - emit = (structural & ~in_string) | (quote & in_string)
 *   - ctz loop over emit bitmap to write offsets to output
 *
 * Output: one i32 offset per structural char (when not in string) plus
 * one offset per string-open quote. Matches simdjson stage 1 semantics.
 *
 * Includes a parallel benchmark mode (N threads × M jobs each).
 */

#include <arm_neon.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

/* ---- NEON 4×16-byte mask -> 64-bit bitmap ---- */
/* Each input lane is 0xFF (matching) or 0x00. The 64-bit result has bit i
 * set iff lane i (across all 4 input vectors, 0..63) was 0xFF. Adapted
 * from simdjson's NEON to_bitmask. */
static inline uint64_t to_bitmask4(uint8x16_t t0, uint8x16_t t1,
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

/* ---- prefix XOR via PMULL ---- */
/* Polynomial multiply (mod 2) of `bitmap` × all_ones gives a 64-bit value
 * where bit i = parity of (bitmap[0] ^ bitmap[1] ^ ... ^ bitmap[i]).
 * That's the in-string bitmap: bit i = 1 if there are an odd number of
 * unescaped quotes at positions 0..i.
 * Requires the AES/crypto NEON extension for vmull_p64. */
__attribute__((target("crypto")))
static inline uint64_t prefix_xor(uint64_t bitmap) {
    poly64x1_t a = vcreate_p64(bitmap);
    poly64x1_t ones = vcreate_p64(~0ULL);
    poly128_t r = vmull_p64(a, ones);
    return (uint64_t)vgetq_lane_u64(vreinterpretq_u64_p128(r), 0);
}

/* ---- find_escaped (simdjson bit trick) ---- */
/* For each backslash, determine whether it escapes the next character,
 * accounting for runs of multiple backslashes (only odd-length runs leave
 * a trailing escape). Carries state across blocks via *prev_escaped. */
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

/* ---- per-block 64-byte classifier ---- */
static inline uint64_t classify_block_64(const uint8_t *src,
                                          uint64_t *prev_in_string,
                                          uint64_t *prev_escaped) {
    uint8x16_t v0 = vld1q_u8(src + 0);
    uint8x16_t v1 = vld1q_u8(src + 16);
    uint8x16_t v2 = vld1q_u8(src + 32);
    uint8x16_t v3 = vld1q_u8(src + 48);

    /* backslash bitmap */
    uint8x16_t bs_v = vdupq_n_u8('\\');
    uint64_t backslash = to_bitmask4(
        vceqq_u8(v0, bs_v), vceqq_u8(v1, bs_v),
        vceqq_u8(v2, bs_v), vceqq_u8(v3, bs_v));

    /* quote bitmap */
    uint8x16_t q_v = vdupq_n_u8('"');
    uint64_t quote_raw = to_bitmask4(
        vceqq_u8(v0, q_v), vceqq_u8(v1, q_v),
        vceqq_u8(v2, q_v), vceqq_u8(v3, q_v));

    /* structural bitmap: { } [ ] , : (combine via vorrq before bitmask) */
    #define STRUCT_OF(v) \
        vorrq_u8( \
            vorrq_u8( \
                vorrq_u8(vceqq_u8((v), vdupq_n_u8('{')), vceqq_u8((v), vdupq_n_u8('}'))), \
                vorrq_u8(vceqq_u8((v), vdupq_n_u8('[')), vceqq_u8((v), vdupq_n_u8(']'))) \
            ), \
            vorrq_u8(vceqq_u8((v), vdupq_n_u8(',')), vceqq_u8((v), vdupq_n_u8(':'))) \
        )
    uint64_t structural = to_bitmask4(STRUCT_OF(v0), STRUCT_OF(v1),
                                       STRUCT_OF(v2), STRUCT_OF(v3));
    #undef STRUCT_OF

    /* find escaped chars and filter quotes */
    uint64_t escaped = find_escaped(backslash, prev_escaped);
    uint64_t quote = quote_raw & ~escaped;

    /* parallel prefix-XOR via PMULL */
    uint64_t in_string = prefix_xor(quote) ^ *prev_in_string;

    /* save carry: state at end of this block (sign bit of in_string) */
    *prev_in_string = (uint64_t)((int64_t)in_string >> 63);

    /* emit positions: structural outside string + quote-opens
     * Quote-open: quote position where in_string AT that position == 1
     * (because the quote toggles 0->1) */
    return (structural & ~in_string) | (quote & in_string);
}

/* ---- main classifier loop ---- */
static size_t json_simd_classify(const uint8_t *src, size_t len, uint32_t *out) {
    size_t out_idx = 0;
    uint64_t prev_in_string = 0;
    uint64_t prev_escaped = 0;

    size_t pos = 0;
    while (pos + 64 <= len) {
        uint64_t emit = classify_block_64(src + pos, &prev_in_string, &prev_escaped);
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
    return out_idx;
}

/* ---- bench driver ---- */
static double mb_per_sec(size_t bytes, int jobs, double ms) {
    if (ms <= 0) ms = 1;
    return (double)bytes * jobs * 1000.0 / ms / 1000000.0;
}

typedef struct {
    const uint8_t *src;
    size_t len;
    int jobs;
    uint32_t *out;
} thread_arg_t;

static void *thread_run(void *p) {
    thread_arg_t *a = (thread_arg_t *)p;
    uint32_t *out_local = malloc(a->len * sizeof(uint32_t));
    for (int i = 0; i < a->jobs; i++) {
        json_simd_classify(a->src, a->len, out_local);
    }
    free(out_local);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <file.json> [total_jobs] [threads]\n", argv[0]);
        return 1;
    }
    int total_jobs = (argc >= 3) ? atoi(argv[2]) : 64;
    int threads    = (argc >= 4) ? atoi(argv[3]) : 1;

    int fd = open(argv[1], O_RDONLY);
    struct stat st;
    fstat(fd, &st);
    size_t len = st.st_size;
    uint8_t *src = mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, 0);
    if (src == MAP_FAILED) { perror("mmap"); return 1; }

    /* Allocate big enough out buffer */
    uint32_t *out = malloc(len * sizeof(uint32_t));

    printf("Tungsten SIMD JSON classifier — %s\n", argv[1]);
    printf("  bytes:   %zu\n", len);
    printf("  jobs:    %d\n", total_jobs);
    printf("  threads: %d\n", threads);

    /* Warm + correctness sanity: emit count */
    size_t count = json_simd_classify(src, len, out);
    printf("  emitted: %zu offsets per round\n", count);

    /* ---- Single-thread baseline ---- */
    {
        double t0 = now_ms();
        for (int r = 0; r < total_jobs; r++) {
            json_simd_classify(src, len, out);
        }
        double t1 = now_ms();
        double ms = t1 - t0;
        printf("  Single-thread:    %7.0f ms  %7.0f MB/sec\n",
               ms, mb_per_sec(len, total_jobs, ms));
    }

    /* ---- Parallel ---- */
    if (threads > 1) {
        int per_thread = (total_jobs + threads - 1) / threads;
        pthread_t *tids = malloc(threads * sizeof(pthread_t));
        thread_arg_t *args = malloc(threads * sizeof(thread_arg_t));

        double t0 = now_ms();
        for (int t = 0; t < threads; t++) {
            args[t].src = src;
            args[t].len = len;
            args[t].jobs = per_thread;
            args[t].out = out;
            pthread_create(&tids[t], NULL, thread_run, &args[t]);
        }
        for (int t = 0; t < threads; t++) pthread_join(tids[t], NULL);
        double t1 = now_ms();
        double ms = t1 - t0;
        int actual_jobs = per_thread * threads;
        printf("  Parallel:         %7.0f ms  %7.0f MB/sec\n",
               ms, mb_per_sec(len, actual_jobs, ms));

        free(tids);
        free(args);
    }

    munmap(src, len);
    close(fd);
    free(out);
    return 0;
}
