/*
 * Benchmark: two-stage table vs direct array for LexChar lookup.
 * Tests with real C source files (ASCII-dominated).
 *
 * cc -O3 -I../../runtime -include w_lexchar_cache.c -o bench_lookup bench_lookup.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

/* Direct array: codepoints[cp] → lexchar metadata */
static uint64_t *direct_table = NULL;

static void build_direct_table(void) {
    direct_table = calloc(0x110000, sizeof(uint64_t));
    for (uint32_t cp = 0; cp < 0x110000; cp++) {
        direct_table[cp] = w_lexchar_cached(cp);
    }
}

static inline uint64_t lookup_direct(uint32_t cp) {
    return direct_table[cp];
}

/* Benchmark: decode UTF-8 + lookup, write LexChars to output */
static volatile int64_t sink;

static long bench_two_stage(const unsigned char *src, long len, int64_t *out, int rounds) {
    long total = 0;
    for (int r = 0; r < rounds; r++) {
        const unsigned char *p = src;
        const unsigned char *end = p + len;
        long idx = 0;
        while (p < end) {
            uint32_t cp;
            if (*p < 0x80) { cp = *p++; }
            else if (*p < 0xE0) { cp = (*p & 0x1F) << 6; cp |= (p[1] & 0x3F); p += 2; }
            else if (*p < 0xF0) { cp = (*p & 0x0F) << 12; cp |= (p[1] & 0x3F) << 6; cp |= (p[2] & 0x3F); p += 3; }
            else { cp = (*p & 0x07) << 18; cp |= (p[1] & 0x3F) << 12; cp |= (p[2] & 0x3F) << 6; cp |= (p[3] & 0x3F); p += 4; }
            out[idx++] = (int64_t)(w_lexchar_cached(cp) | ((uint64_t)cp << 18));
        }
        total += idx;
    }
    return total;
}

static long bench_direct(const unsigned char *src, long len, int64_t *out, int rounds) {
    long total = 0;
    for (int r = 0; r < rounds; r++) {
        const unsigned char *p = src;
        const unsigned char *end = p + len;
        long idx = 0;
        while (p < end) {
            uint32_t cp;
            if (*p < 0x80) { cp = *p++; }
            else if (*p < 0xE0) { cp = (*p & 0x1F) << 6; cp |= (p[1] & 0x3F); p += 2; }
            else if (*p < 0xF0) { cp = (*p & 0x0F) << 12; cp |= (p[1] & 0x3F) << 6; cp |= (p[2] & 0x3F); p += 3; }
            else { cp = (*p & 0x07) << 18; cp |= (p[1] & 0x3F) << 12; cp |= (p[2] & 0x3F) << 6; cp |= (p[3] & 0x3F); p += 4; }
            out[idx++] = (int64_t)(lookup_direct(cp) | ((uint64_t)cp << 18));
        }
        total += idx;
    }
    return total;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "Usage: bench_lookup <file.c> [rounds]\n"); return 1; }
    int rounds = argc > 2 ? atoi(argv[2]) : 20;

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *src = malloc(len);
    fread(src, 1, len, f); fclose(f);

    int64_t *out = malloc(len * sizeof(int64_t));

    /* Build direct table */
    build_direct_table();

    /* Warmup */
    bench_two_stage(src, len, out, 1);
    bench_direct(src, len, out, 1);

    struct timespec t0, t1, t2, t3;

    clock_gettime(CLOCK_MONOTONIC, &t0);
    long total_ts = bench_two_stage(src, len, out, rounds);
    sink = out[0];
    clock_gettime(CLOCK_MONOTONIC, &t1);

    clock_gettime(CLOCK_MONOTONIC, &t2);
    long total_d = bench_direct(src, len, out, rounds);
    sink = out[0];
    clock_gettime(CLOCK_MONOTONIC, &t3);

    double ms_ts = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    double ms_d = (t3.tv_sec - t2.tv_sec) * 1000.0 + (t3.tv_nsec - t2.tv_nsec) / 1e6;

    printf("LexChar Lookup Benchmark\n");
    printf("  File: %s (%ld bytes, %ld chars/round)\n", argv[1], len, total_ts / rounds);
    printf("  Rounds: %d\n\n", rounds);
    printf("  Two-stage (362 KB table):\n");
    printf("    Time:  %.0fms\n", ms_ts);
    printf("    Speed: %.0f MB/sec\n", (double)len * rounds / ms_ts / 1000.0);
    printf("\n");
    printf("  Direct array (8.5 MB table):\n");
    printf("    Time:  %.0fms\n", ms_d);
    printf("    Speed: %.0f MB/sec\n", (double)len * rounds / ms_d / 1000.0);
    printf("\n");
    if (ms_d < ms_ts)
        printf("  Direct is %.1fx faster\n", ms_ts / ms_d);
    else
        printf("  Two-stage is %.1fx faster\n", ms_d / ms_ts);

    free(src); free(out); free(direct_table);
    return 0;
}
