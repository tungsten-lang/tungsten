/* 16-byte NEON JSON structural-character classifier prototype.
 *
 * Goal: measure the raw throughput of the simdjson-style approach on
 * Apple Silicon, against our existing 4-byte scalar dispatch baseline,
 * to see if the gap to simdjson is closeable in principle.
 *
 * What it does:
 *   1. Load 16 source bytes into a NEON register.
 *   2. Use vqtbl1q_u8 with a hand-built lookup table to map each byte
 *      to its character class:
 *        bit 0: structural  ({,},[,],',',':')
 *        bit 1: whitespace  (' ', '\t', '\n', '\r')
 *        bit 2: quote       ('"')
 *        bit 3: digit/minus (number start)
 *        bit 4: keyword start ('t', 'f', 'n')
 *   3. Compute an 8-bit "interesting" bitmap (structural bit per byte).
 *   4. ctz the bitmap to find the first interesting position; emit it.
 *
 * Two benchmarks:
 *   - Classifier-only: just compute and ignore the bitmap. Tells us
 *     the upper bound on classifier throughput.
 *   - Classifier + emit offsets: write each interesting byte's offset
 *     into an output array. Tells us the realistic throughput including
 *     the offset emission cost.
 *
 * No JSON correctness — this is purely a microbenchmark of the
 * dispatch model, not a working lexer.
 */

#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

/* Lookup table: index by low nibble of each character.
 * For ASCII, the low nibble doesn't uniquely identify the class, so we
 * actually need TWO tables and combine them — exactly what simdjson does.
 *
 * Table A (low nibble): for each low nibble 0..15, the set of HIGH nibbles
 *                        that combine with it to form an "interesting" char.
 *
 * For JSON's "interesting" set:
 *   { = 0x7B = high 7, low B
 *   } = 0x7D = high 7, low D
 *   [ = 0x5B = high 5, low B
 *   ] = 0x5D = high 5, low D
 *   , = 0x2C = high 2, low C
 *   : = 0x3A = high 3, low A
 *   " = 0x22 = high 2, low 2
 *   space = 0x20 = high 2, low 0
 *   tab = 0x09 = high 0, low 9
 *   nl  = 0x0A = high 0, low A
 *   cr  = 0x0D = high 0, low D
 *
 * For a quick prototype, just classify "structural+whitespace" with a
 * single-table lookup keyed on the BYTE itself (256 entries — too big
 * for a single vqtbl1, requires 16 vqtbl1q_u8 calls). simdjson uses a
 * cleverer two-nibble approach. For this prototype, we use the simpler
 * single-byte branchless test: each byte is "interesting" iff it's in
 * a small bitmask we compute via comparisons. */

/* Build a 16-byte vector mask: lane[i] = 0xFF if byte i is "structural
 * or quote", 0 otherwise. Uses two cmp+or sequences. */
static inline uint8x16_t classify16(uint8x16_t v) {
    /* Structural: { } [ ] , : */
    /* Quote:      " */
    /* Whitespace: ' ' \t \n \r — common, dominant in pretty JSON */
    /* Digit/minus, keyword start: classify into separate bit if needed */

    /* For the prototype, just identify structural+quote: 0x22, 0x2C,
     * 0x3A, 0x5B, 0x5D, 0x7B, 0x7D — 7 distinct bytes.
     *
     * Use vceqq_u8 to test against each, then OR all the results. */
    uint8x16_t m_22 = vceqq_u8(v, vdupq_n_u8(0x22));
    uint8x16_t m_2C = vceqq_u8(v, vdupq_n_u8(0x2C));
    uint8x16_t m_3A = vceqq_u8(v, vdupq_n_u8(0x3A));
    uint8x16_t m_5B = vceqq_u8(v, vdupq_n_u8(0x5B));
    uint8x16_t m_5D = vceqq_u8(v, vdupq_n_u8(0x5D));
    uint8x16_t m_7B = vceqq_u8(v, vdupq_n_u8(0x7B));
    uint8x16_t m_7D = vceqq_u8(v, vdupq_n_u8(0x7D));

    uint8x16_t r = vorrq_u8(m_22, m_2C);
    r = vorrq_u8(r, m_3A);
    r = vorrq_u8(r, m_5B);
    r = vorrq_u8(r, m_5D);
    r = vorrq_u8(r, m_7B);
    r = vorrq_u8(r, m_7D);
    return r;
}

/* Compute a 16-bit "interesting" bitmap from a 16-byte mask vector
 * (each lane is 0xFF or 0). Uses shrn to compress 16x8 → 8x4 bits per
 * byte, then transfers to a GPR. */
static inline uint64_t mask_to_bitmap(uint8x16_t mask) {
    /* shrn_n_u16 shifts u16 lanes right by N and narrows to u8.
     * Reinterpret 16x8 → 8x16 first. */
    uint8x8_t narrowed = vshrn_n_u16(vreinterpretq_u16_u8(mask), 4);
    return vget_lane_u64(vreinterpret_u64_u8(narrowed), 0);
}

/* Benchmark 1: pure classify, count interesting bytes. */
static uint64_t bench_classify_only(const uint8_t *src, size_t len) {
    uint64_t total = 0;
    size_t pos = 0;
    while (pos + 16 <= len) {
        uint8x16_t v = vld1q_u8(src + pos);
        uint8x16_t mask = classify16(v);
        uint64_t bitmap = mask_to_bitmap(mask);
        total += __builtin_popcountll(bitmap) / 4;  /* 4 bits per byte */
        pos += 16;
    }
    return total;
}

/* Benchmark 2: classify and emit offsets. */
static uint64_t bench_classify_emit(const uint8_t *src, size_t len, uint32_t *out) {
    size_t out_idx = 0;
    size_t pos = 0;
    while (pos + 16 <= len) {
        uint8x16_t v = vld1q_u8(src + pos);
        uint8x16_t mask = classify16(v);
        uint64_t bitmap = mask_to_bitmap(mask);
        /* Each set 4-bit nibble in the bitmap is an interesting byte. */
        while (bitmap) {
            int lane = __builtin_ctzll(bitmap) >> 2;  /* 4 bits per byte */
            out[out_idx++] = (uint32_t)(pos + lane);
            /* Clear this nibble */
            bitmap &= ~((uint64_t)0xF << (lane * 4));
        }
        pos += 16;
    }
    return out_idx;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <file.json> [rounds]\n", argv[0]);
        return 1;
    }
    int rounds = (argc >= 3) ? atoi(argv[2]) : 10;

    int fd = open(argv[1], O_RDONLY);
    struct stat st;
    fstat(fd, &st);
    size_t len = st.st_size;
    uint8_t *src = mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, 0);
    if (src == MAP_FAILED) { perror("mmap"); return 1; }

    /* Output buffer big enough for worst case */
    uint32_t *out = malloc(len * sizeof(uint32_t));

    printf("classifier prototype on %s\n", argv[1]);
    printf("  bytes: %zu  rounds: %d\n", len, rounds);

    /* Warm cache */
    bench_classify_only(src, len);

    /* Benchmark 1: classify only */
    {
        double t0 = now_ms();
        uint64_t total = 0;
        for (int r = 0; r < rounds; r++) total += bench_classify_only(src, len);
        double t1 = now_ms();
        double ms = t1 - t0;
        double mbs = (double)len * rounds * 1000.0 / ms / 1000000.0;
        printf("  classify-only:        %7.0f ms  %7.0f MB/s  (~%llu interesting/round)\n",
               ms, mbs, (unsigned long long)(total / rounds));
    }

    /* Benchmark 2: classify + emit offsets */
    {
        double t0 = now_ms();
        uint64_t total = 0;
        for (int r = 0; r < rounds; r++) total += bench_classify_emit(src, len, out);
        double t1 = now_ms();
        double ms = t1 - t0;
        double mbs = (double)len * rounds * 1000.0 / ms / 1000000.0;
        printf("  classify + emit:      %7.0f ms  %7.0f MB/s  (~%llu offsets/round)\n",
               ms, mbs, (unsigned long long)(total / rounds));
    }

    munmap(src, len);
    close(fd);
    free(out);
    return 0;
}
