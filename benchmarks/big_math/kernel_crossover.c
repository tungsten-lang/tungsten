/* Forced-kernel crossover sweep for the multiply/square dispatch ladders.
 *
 * Times each ladder rung DIRECTLY (no dispatch) on identical operands so a
 * threshold can be read straight off the crossover, instead of inferred
 * through end-to-end noise. Correctness: every kernel result is checked
 * against GMP's mpn_mul_n before it is timed.
 *
 * Build/run: benchmarks/big_math/run_kernel_crossover.sh [mul|sqr] [sizes]
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <gmp.h>

#include "../../runtime/runtime.c"

static uint64_t xr_state = 0x9E3779B97F4A7C15ULL;
static uint64_t xr_next(void) {
    uint64_t x = xr_state;
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    xr_state = x;
    return x;
}

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

typedef void (*MulKernel)(uint64_t *, const uint64_t *, const uint64_t *,
                          int32_t, uint64_t *);
typedef void (*SqrKernel)(uint64_t *, const uint64_t *, int32_t, uint64_t *);

static volatile uint64_t sink;

static int iters_for(int32_t n) {
    if (n <= 256) return 400;
    if (n <= 512) return 160;
    if (n <= 1024) return 64;
    if (n <= 2048) return 24;
    return 10;
}

/* Best-of-9 forced timings; operands freshly nudged per rep so a kernel
 * cannot win on a value-dependent early-out. */
static double time_mul(MulKernel fn, const uint64_t *a, const uint64_t *b,
                       int32_t n, uint64_t *out, uint64_t *scratch) {
    int iters = iters_for(n);
    double best = 0.0;
    for (int rep = 0; rep < 9; rep++) {
        double t0 = now_ns();
        for (int i = 0; i < iters; i++) {
            fn(out, a, b, n, scratch);
            sink += out[2 * n - 1];
        }
        double per = (now_ns() - t0) / iters;
        if (rep == 0 || per < best) best = per;
    }
    return best;
}

static double time_sqr(SqrKernel fn, const uint64_t *a, int32_t n,
                       uint64_t *out, uint64_t *scratch) {
    int iters = iters_for(n);
    double best = 0.0;
    for (int rep = 0; rep < 9; rep++) {
        double t0 = now_ns();
        for (int i = 0; i < iters; i++) {
            fn(out, a, n, scratch);
            sink += out[2 * n - 1];
        }
        double per = (now_ns() - t0) / iters;
        if (rep == 0 || per < best) best = per;
    }
    return best;
}

static void check_against_gmp(const char *label, const uint64_t *got,
                              const uint64_t *a, const uint64_t *b,
                              int32_t n) {
    uint64_t *want = (uint64_t *)malloc((size_t)2 * n * sizeof(uint64_t));
    mpn_mul_n((mp_ptr)want, (mp_srcptr)a, (mp_srcptr)b, n);
    for (int32_t i = 0; i < 2 * n; i++) {
        if (got[i] != want[i]) {
            fprintf(stderr, "%s WRONG at n=%d limb=%d\n", label, n, i);
            exit(1);
        }
    }
    free(want);
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "both";
    static const int32_t mul_sizes[] = {384, 448, 512, 640, 768, 1024,
                                        1280, 1536, 2048, 3072, 4096};
    static const int32_t sqr_sizes[] = {256, 320, 384, 392, 448, 512, 560,
                                        616, 704, 768, 1024, 1536, 2048,
                                        3072, 4096};

    if (strcmp(mode, "mul") == 0 || strcmp(mode, "both") == 0) {
        printf("MUL forced kernels (ns/op, best of 9)\n");
        printf("%6s %12s %12s %12s %12s\n", "limbs", "toom2", "toom3",
               "toom4", "toom6");
        static const int32_t mul_lo_sizes[] = {128, 192, 256, 320, 368,
                                               384, 416, 448, 512, 640,
                                               768, 1024};
        for (size_t si = 0;
             si < sizeof(mul_lo_sizes) / sizeof(mul_lo_sizes[0]); si++) {
            int32_t n = mul_lo_sizes[si];
            uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
            uint64_t *b = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
            uint64_t *out =
                (uint64_t *)calloc((size_t)2 * n + 4, sizeof(uint64_t));
            uint64_t *scratch =
                (uint64_t *)calloc((size_t)n * 128 + 4096, sizeof(uint64_t));
            for (int32_t i = 0; i < n; i++) a[i] = xr_next();
            for (int32_t i = 0; i < n; i++) b[i] = xr_next();
            a[n - 1] |= 1ULL << 63;
            b[n - 1] |= 1ULL << 63;
            bn_toom2(out, a, b, n, scratch);
            check_against_gmp("toom2", out, a, b, n);
            bn_toom3(out, a, b, n, scratch);
            check_against_gmp("toom3", out, a, b, n);
            bn_toom4(out, a, b, n, scratch);
            check_against_gmp("toom4", out, a, b, n);
            bn_toom6(out, a, b, n, scratch);
            check_against_gmp("toom6", out, a, b, n);
            double t2 = time_mul(bn_toom2, a, b, n, out, scratch);
            double t3 = time_mul(bn_toom3, a, b, n, out, scratch);
            double t4 = time_mul(bn_toom4, a, b, n, out, scratch);
            double t6 = time_mul(bn_toom6, a, b, n, out, scratch);
            printf("%6d %12.1f %12.1f %12.1f %12.1f\n", n, t2, t3, t4, t6);
            free(a); free(b); free(out); free(scratch);
        }
        printf("\nMUL high band (ns/op, best of 9)\n");
        printf("%6s %12s %12s %8s\n", "limbs", "toom4", "toom6", "t6/t4");
        for (size_t si = 0; si < sizeof(mul_sizes) / sizeof(mul_sizes[0]);
             si++) {
            int32_t n = mul_sizes[si];
            uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
            uint64_t *b = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
            uint64_t *out =
                (uint64_t *)calloc((size_t)2 * n + 4, sizeof(uint64_t));
            uint64_t *scratch =
                (uint64_t *)calloc((size_t)n * 128 + 4096, sizeof(uint64_t));
            for (int32_t i = 0; i < n; i++) a[i] = xr_next();
            for (int32_t i = 0; i < n; i++) b[i] = xr_next();
            a[n - 1] |= 1ULL << 63;
            b[n - 1] |= 1ULL << 63;
            bn_toom4(out, a, b, n, scratch);
            check_against_gmp("toom4", out, a, b, n);
            bn_toom6(out, a, b, n, scratch);
            check_against_gmp("toom6", out, a, b, n);
            double t4 = time_mul(bn_toom4, a, b, n, out, scratch);
            double t6 = time_mul(bn_toom6, a, b, n, out, scratch);
            printf("%6d %12.1f %12.1f %8.3f\n", n, t4, t6, t6 / t4);
            free(a); free(b); free(out); free(scratch);
        }
    }

    if (strcmp(mode, "sqr") == 0 || strcmp(mode, "both") == 0) {
        printf("\nSQR forced kernels (ns/op, best of 9)\n");
        printf("%6s %12s %12s %12s %12s\n", "limbs", "kara_sq", "toom3_sq",
               "toom4_sq", "toom6_sq");
        for (size_t si = 0; si < sizeof(sqr_sizes) / sizeof(sqr_sizes[0]);
             si++) {
            int32_t n = sqr_sizes[si];
            uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
            uint64_t *out =
                (uint64_t *)calloc((size_t)2 * n + 4, sizeof(uint64_t));
            uint64_t *scratch =
                (uint64_t *)calloc((size_t)n * 128 + 4096, sizeof(uint64_t));
            for (int32_t i = 0; i < n; i++) a[i] = xr_next();
            a[n - 1] |= 1ULL << 63;
            bn_kara_sq(out, a, n, scratch);
            check_against_gmp("kara_sq", out, a, a, n);
            bn_toom3_sq(out, a, n, scratch);
            check_against_gmp("toom3_sq", out, a, a, n);
            bn_toom4_sq(out, a, n, scratch);
            check_against_gmp("toom4_sq", out, a, a, n);
            bn_toom6_sq(out, a, n, scratch);
            check_against_gmp("toom6_sq", out, a, a, n);
            double tk = time_sqr(bn_kara_sq, a, n, out, scratch);
            double t3 = time_sqr(bn_toom3_sq, a, n, out, scratch);
            double t4 = time_sqr(bn_toom4_sq, a, n, out, scratch);
            double t6 = time_sqr(bn_toom6_sq, a, n, out, scratch);
            printf("%6d %12.1f %12.1f %12.1f %12.1f\n", n, tk, t3, t4, t6);
            free(a); free(out); free(scratch);
        }
    }

    printf("\nsink=%llu\n", (unsigned long long)sink);
    return 0;
}
