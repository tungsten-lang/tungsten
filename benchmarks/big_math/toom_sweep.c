#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../../runtime/runtime.c"

static volatile uint64_t sweep_sink;

typedef enum {
    ALG_SCHOOL,
    ALG_TOOM2,
    ALG_TOOM3,
    ALG_TOOM4,
    ALG_NTT,
    ALG_LADDER,
    ALG_DISPATCH
} SweepAlg;

typedef struct {
    int32_t start;
    int32_t end;
    int32_t step;
} SweepRange;

static int sweep_reps = 3;
static int sweep_include_ntt = 0;

static double sweep_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static uint64_t sweep_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static uint64_t *sweep_limbs(int32_t n, uint64_t seed) {
    uint64_t *limbs = (uint64_t *)calloc((size_t)n, sizeof(uint64_t));
    if (!limbs) die("out of memory allocating sweep limbs");
    uint64_t state = seed;
    for (int32_t i = 0; i < n; i++) limbs[i] = sweep_rng(&state);
    limbs[0] |= 1ULL;
    limbs[n - 1] |= 1ULL << 63;
    return limbs;
}

static int sweep_iters(int32_t n) {
    if (n <= 16) return 4000;
    if (n <= 32) return 2500;
    if (n <= 64) return 1400;
    if (n <= 128) return 700;
    if (n <= 256) return 300;
    if (n <= 512) return 120;
    if (n <= 1024) return 50;
    return 20;
}

static int sweep_alg_valid(SweepAlg alg, int32_t n) {
    switch (alg) {
    case ALG_TOOM3:
        return n >= 2;
    case ALG_TOOM4:
        return n >= 3;
    case ALG_NTT:
        return sweep_include_ntt;
    default:
        return 1;
    }
}

static size_t sweep_scratch_len(int32_t n) {
    size_t dispatch_need = bn_scratch_need(n);
    size_t forced_need = (size_t)n * 128U + 4096U;
    return dispatch_need > forced_need ? dispatch_need : forced_need;
}

static void sweep_run_alg(SweepAlg alg, uint64_t *out, const uint64_t *a,
                          const uint64_t *b, int32_t n, uint64_t *scratch) {
    switch (alg) {
    case ALG_SCHOOL:
        bigint_mul_schoolbook_into(out, a, n, b, n);
        break;
    case ALG_TOOM2:
        bn_toom2(out, a, b, n, scratch);
        break;
    case ALG_TOOM3:
        bn_toom3(out, a, b, n, scratch);
        break;
    case ALG_TOOM4:
        bn_toom4(out, a, b, n, scratch);
        break;
    case ALG_NTT:
        bn_ntt_mul(out, a, b, n);
        break;
    case ALG_LADDER:
        bn_mul_eq(out, a, b, n, scratch);
        break;
    case ALG_DISPATCH:
        bigint_mul_dispatch(out, a, n, b, n);
        break;
    }
}

static void sweep_check(const char *name, const uint64_t *got, const uint64_t *want, int32_t n) {
    for (int32_t i = 0; i < 2 * n; i++) {
        if (got[i] != want[i]) {
            fprintf(stderr, "%s mismatch at n=%d limb=%d\n", name, n, i);
            exit(1);
        }
    }
}

static double sweep_time_alg_once(SweepAlg alg, const uint64_t *a0, const uint64_t *b,
                                  const uint64_t *ref, int32_t n, int iters, const char *name) {
    if (!sweep_alg_valid(alg, n)) return -1.0;

    uint64_t *a = (uint64_t *)malloc((size_t)n * sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)2 * n + 4U, sizeof(uint64_t));
    uint64_t *scratch = (uint64_t *)calloc(sweep_scratch_len(n), sizeof(uint64_t));
    if (!a || !out || !scratch) die("out of memory in Toom sweep");

    memcpy(a, a0, (size_t)n * sizeof(uint64_t));
    sweep_run_alg(alg, out, a, b, n, scratch);
    sweep_check(name, out, ref, n);

    uint64_t saved = a[0];
    double start = sweep_now();
    for (int i = 0; i < iters; i++) {
        a[0] = saved + (uint64_t)i;
        sweep_run_alg(alg, out, a, b, n, scratch);
        sweep_sink ^= out[(unsigned)i % ((unsigned)n * 2U)];
    }
    double elapsed = sweep_now() - start;
    free(scratch);
    free(out);
    free(a);
    return elapsed * 1e9 / (double)iters;
}

static double sweep_time_alg(SweepAlg alg, const uint64_t *a0, const uint64_t *b,
                             const uint64_t *ref, int32_t n, int iters, const char *name) {
    double best = sweep_time_alg_once(alg, a0, b, ref, n, iters, name);
    if (best < 0.0) return best;
    for (int i = 1; i < sweep_reps; i++) {
        double next = sweep_time_alg_once(alg, a0, b, ref, n, iters, name);
        if (next < best) best = next;
    }
    return best;
}

static const char *best_name(double school, double toom2, double toom3, double toom4, double ntt) {
    const char *name = "school";
    double best = school;
    if (toom2 >= 0.0 && toom2 < best) { best = toom2; name = "toom2"; }
    if (toom3 >= 0.0 && toom3 < best) { best = toom3; name = "toom3"; }
    if (toom4 >= 0.0 && toom4 < best) { best = toom4; name = "toom4"; }
    if (ntt >= 0.0 && ntt < best) { name = "ntt"; }
    return name;
}

static void print_time(double value) {
    if (value < 0.0) printf(" %8s", "NA");
    else printf(" %8.1f", value);
}

static void usage(const char *prog) {
    fprintf(stderr, "usage: %s [--ntt] [--reps N] [START:END[:STEP] | N ...]\n", prog);
}

static int parse_range_arg(const char *arg, SweepRange *range) {
    int a, b, c;
    char tail;
    if (sscanf(arg, "%d:%d:%d%c", &a, &b, &c, &tail) == 3) {
        if (a <= 0 || b <= 0 || c <= 0) return 0;
        range->start = a;
        range->end = b;
        range->step = c;
        return 1;
    }
    if (sscanf(arg, "%d:%d%c", &a, &b, &tail) == 2) {
        if (a <= 0 || b <= 0) return 0;
        range->start = a;
        range->end = b;
        range->step = 1;
        return 1;
    }
    if (sscanf(arg, "%d%c", &a, &tail) == 1) {
        if (a <= 0) return 0;
        range->start = a;
        range->end = a;
        range->step = 1;
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    SweepRange ranges[128];
    size_t range_count = 0;
    const int32_t sizes[] = {
        8, 12, 16, 24, 32, 40, 48, 64, 80, 96, 112, 128,
        144, 160, 176, 192, 224, 256, 288, 320, 352, 384,
        448, 512, 640, 768, 896, 1024, 1280, 1536, 1792, 2048
    };

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--ntt") == 0) {
            sweep_include_ntt = 1;
        } else if (strcmp(argv[i], "--reps") == 0) {
            if (++i >= argc) { usage(argv[0]); return 2; }
            sweep_reps = atoi(argv[i]);
            if (sweep_reps <= 0) { usage(argv[0]); return 2; }
        } else {
            if (range_count >= sizeof(ranges) / sizeof(ranges[0]) || !parse_range_arg(argv[i], &ranges[range_count])) {
                usage(argv[0]);
                return 2;
            }
            range_count++;
        }
    }

    printf("Forced Toom multiply sweep (best of %d, ns/op, equal-length limbs)\n", sweep_reps);
    if (sweep_include_ntt) {
        printf("limbs   school     toom2     toom3     toom4       ntt    ladder  dispatch  best\n");
    } else {
        printf("limbs   school     toom2     toom3     toom4    ladder  dispatch  best\n");
    }

    size_t default_count = sizeof(sizes) / sizeof(sizes[0]);
    size_t total_count = range_count == 0 ? default_count : range_count;
    for (size_t i = 0; i < total_count; i++) {
        int32_t start = range_count == 0 ? sizes[i] : ranges[i].start;
        int32_t end = range_count == 0 ? sizes[i] : ranges[i].end;
        int32_t step = range_count == 0 ? 1 : ranges[i].step;
        if (start > end) {
            int32_t tmp = start;
            start = end;
            end = tmp;
        }

        for (int32_t n = start; n <= end; n += step) {
            int iters = sweep_iters(n);
            uint64_t *a = sweep_limbs(n, 0x123456789abcdef0ULL ^ (uint64_t)n);
            uint64_t *b = sweep_limbs(n, 0xfedcba9876543210ULL ^ (uint64_t)n);
            uint64_t *ref = (uint64_t *)calloc((size_t)2 * n + 4U, sizeof(uint64_t));
            if (!ref) die("out of memory in Toom sweep reference");
            bigint_mul_schoolbook_into(ref, a, n, b, n);

            double school = sweep_time_alg(ALG_SCHOOL, a, b, ref, n, iters, "school");
            double toom2 = sweep_time_alg(ALG_TOOM2, a, b, ref, n, iters, "toom2");
            double toom3 = sweep_time_alg(ALG_TOOM3, a, b, ref, n, iters, "toom3");
            double toom4 = sweep_time_alg(ALG_TOOM4, a, b, ref, n, iters, "toom4");
            double ntt = sweep_time_alg(ALG_NTT, a, b, ref, n, iters, "ntt");
            double ladder = sweep_time_alg(ALG_LADDER, a, b, ref, n, iters, "ladder");
            double dispatch = sweep_time_alg(ALG_DISPATCH, a, b, ref, n, iters, "dispatch");

            printf("%5d", n);
            print_time(school);
            print_time(toom2);
            print_time(toom3);
            print_time(toom4);
            if (sweep_include_ntt) print_time(ntt);
            print_time(ladder);
            print_time(dispatch);
            printf("  %s\n", best_name(school, toom2, toom3, toom4, ntt));
            free(ref);
            free(a);
            free(b);
        }
    }

    printf("sink=%llu\n", (unsigned long long)sweep_sink);
    return 0;
}
