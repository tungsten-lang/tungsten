/* prime_sweep — reproducible Int#prime? cutoff benchmark.
 *
 * This intentionally includes runtime.c so the benchmark exercises the exact
 * private trial-division and Montgomery/FJ functions used by Int#prime?. Build
 * and run it from the project root with:
 *
 *   make -C runtime bench-prime-sweep
 *
 * It reports worst-case primes and four input distributions, comparing the
 * former 10,000,000 cutoff with candidate boundaries. Every sampled result is
 * first checked against the production w_prime_test_u64 implementation.
 */
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#include "../../runtime/runtime.c"

#define SAMPLE_COUNT 4096
#define SAMPLE_ROUNDS 20
#define NOINLINE __attribute__((noinline))

typedef int (*PrimeFn)(uint64_t);

static volatile uint64_t samples[SAMPLE_COUNT];
static volatile uint64_t bench_sink;
static uint64_t rng_state = 0x6a09e667f3bcc909ULL;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static uint64_t rng_next(void) {
    uint64_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    rng_state = x;
    return x;
}

static int reciprocal_trial_post_screen(uint32_t n) {
    if (!w_prime_trial_recip32(n)) return 0;
    size_t i = sizeof(W_PRIME_TRIAL_RECIP32) / sizeof(W_PRIME_TRIAL_RECIP32[0]);
    size_t count = sizeof(W_PRIME_TRIAL_DIVISORS) / sizeof(W_PRIME_TRIAL_DIVISORS[0]);
    for (; i < count; i++) {
        uint32_t p = W_PRIME_TRIAL_DIVISORS[i];
        if ((uint64_t)p * p > n) break;
        if (n % p == 0U) return 0;
    }
    return 1;
}

/* Same Tier-1 screen as w_prime_test_u64, with only the boundary selectable. */
static int prime_with_cutoff(uint64_t n, uint64_t cutoff, int reciprocal) {
    if (n < 2ULL) return 0;
    static const uint64_t small[] = {2,3,5,7,11,13,17,19,23,29,31,37};
    for (size_t i = 0; i < sizeof(small) / sizeof(small[0]); i++) {
        if (n == small[i]) return 1;
        if (n % small[i] == 0ULL) return 0;
    }
    if (n < 1681ULL) return 1;

    if (n <= cutoff) {
        if (reciprocal && n <= UINT32_MAX)
            return reciprocal_trial_post_screen((uint32_t)n);
        for (size_t i = 0;
             i < sizeof(W_PRIME_TRIAL_DIVISORS) / sizeof(W_PRIME_TRIAL_DIVISORS[0]);
             i++) {
            uint64_t p = (uint64_t)W_PRIME_TRIAL_DIVISORS[i];
            if (p * p > n) break;
            if (n % p == 0ULL) return 0;
        }
        return 1;
    }
    return w_prime_test_u64_mr(n);
}

#define DEFINE_CUTOFF_WRAPPER(name, cutoff) \
    static NOINLINE int name(uint64_t n) { return prime_with_cutoff(n, cutoff, 1); }
#define DEFINE_DIVIDE_WRAPPER(name, cutoff) \
    static NOINLINE int name(uint64_t n) { return prime_with_cutoff(n, cutoff, 0); }

DEFINE_CUTOFF_WRAPPER(prime_100k,   100000ULL)
DEFINE_CUTOFF_WRAPPER(prime_250k,   250000ULL)
DEFINE_CUTOFF_WRAPPER(prime_500k,   500000ULL)
DEFINE_CUTOFF_WRAPPER(prime_1m,    1000000ULL)
DEFINE_CUTOFF_WRAPPER(prime_2m,    2000000ULL)
DEFINE_CUTOFF_WRAPPER(prime_5m,    5000000ULL)
DEFINE_CUTOFF_WRAPPER(prime_10m,  10000000ULL)
DEFINE_DIVIDE_WRAPPER(prime_1m_divide,   1000000ULL)
DEFINE_DIVIDE_WRAPPER(prime_10m_divide, 10000000ULL)

static NOINLINE int trial_post_screen(uint64_t n) {
    for (size_t i = 0;
         i < sizeof(W_PRIME_TRIAL_DIVISORS) / sizeof(W_PRIME_TRIAL_DIVISORS[0]);
         i++) {
        uint64_t p = (uint64_t)W_PRIME_TRIAL_DIVISORS[i];
        if (p * p > n) break;
        if (n % p == 0ULL) return 0;
    }
    return 1;
}

static NOINLINE int reciprocal_post_screen(uint64_t n) {
    return reciprocal_trial_post_screen((uint32_t)n);
}

static NOINLINE int fj_post_screen(uint64_t n) {
    return w_prime_test_u64_mr(n);
}

static double bench_once(PrimeFn fn, int rounds) {
    uint64_t start = now_ns();
    uint64_t sink = 0;
    for (int r = 0; r < rounds; r++) {
        for (int i = 0; i < SAMPLE_COUNT; i++) sink += (uint64_t)fn(samples[i]);
    }
    uint64_t elapsed = now_ns() - start;
    bench_sink ^= sink;
    return (double)elapsed / (double)(rounds * SAMPLE_COUNT);
}

static double bench_median(PrimeFn fn, int rounds) {
    double a = bench_once(fn, rounds);
    double b = bench_once(fn, rounds);
    double c = bench_once(fn, rounds);
    if (a > b) { double t = a; a = b; b = t; }
    if (b > c) { double t = b; b = c; c = t; }
    if (a > b) { double t = a; a = b; b = t; }
    return b;
}

static void fill_same(uint64_t n) {
    for (int i = 0; i < SAMPLE_COUNT; i++) samples[i] = n;
}

static void fill_random(uint64_t lo, uint64_t hi) {
    uint64_t span = hi - lo + 1ULL;
    for (int i = 0; i < SAMPLE_COUNT; i++) samples[i] = lo + rng_next() % span;
}

static void fill_coprime30(uint64_t lo, uint64_t hi) {
    uint64_t span = hi - lo + 1ULL;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        uint64_t n;
        do {
            n = lo + rng_next() % span;
        } while ((n & 1ULL) == 0ULL || n % 3ULL == 0ULL || n % 5ULL == 0ULL);
        samples[i] = n;
    }
}

static void fill_primes(uint64_t lo, uint64_t hi) {
    uint64_t span = hi - lo + 1ULL;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        uint64_t n;
        do {
            n = lo + rng_next() % span;
            n |= 1ULL;
            if (n > hi) n -= 2ULL;
        } while (!w_prime_test_u64(n));
        samples[i] = n;
    }
}

static const struct {
    const char *label;
    PrimeFn fn;
} cutoffs[] = {
    {"100k", prime_100k}, {"250k", prime_250k}, {"500k", prime_500k},
    {"1m", prime_1m}, {"2m", prime_2m}, {"5m", prime_5m}, {"10m", prime_10m}
};

static void verify_samples(const char *label) {
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        uint64_t n = samples[i];
        int expected = w_prime_test_u64(n);
        for (size_t j = 0; j < sizeof(cutoffs) / sizeof(cutoffs[0]); j++) {
            int actual = cutoffs[j].fn(n);
            if (actual != expected) {
                fprintf(stderr, "%s mismatch: n=%llu cutoff=%s expected=%d got=%d\n",
                        label, (unsigned long long)n, cutoffs[j].label, expected, actual);
                exit(1);
            }
        }
    }
}

static void verify_changed_range(void) {
    for (uint64_t n = 0; n <= 1000000ULL; n++) {
        int expected = prime_1m_divide(n);
        int actual = w_prime_test_u64(n);
        if (actual != expected) {
            fprintf(stderr, "reciprocal mismatch: n=%llu divide=%d reciprocal=%d\n",
                    (unsigned long long)n, expected, actual);
            exit(1);
        }
    }
    for (uint64_t n = 1000001ULL; n <= 10000000ULL; n++) {
        int expected = prime_10m_divide(n);
        int actual = prime_1m(n);
        if (actual != expected) {
            fprintf(stderr, "cutoff mismatch: n=%llu old=%d new=%d\n",
                    (unsigned long long)n, expected, actual);
            exit(1);
        }
    }
}

static void report_candidate_sweep(const char *label, size_t count) {
    verify_samples(label);
    printf("\n%s\n", label);
    printf("  %-10s %12s\n", "cutoff", "ns/op");
    for (size_t i = 0; i < count; i++) {
        printf("  %-10s %12.1f\n", cutoffs[i].label,
               bench_median(cutoffs[i].fn, SAMPLE_ROUNDS));
    }
}

static void report_selected_vs_old(const char *label) {
    verify_samples(label);
    double selected = bench_median(prime_1m, SAMPLE_ROUNDS);
    double old = bench_median(prime_10m_divide, SAMPLE_ROUNDS);
    printf("\n%s\n", label);
    printf("  %-10s %12s %10s\n", "cutoff", "ns/op", "old/new");
    printf("  %-10s %12.1f %10.2f\n", "1m", selected, old / selected);
    printf("  %-10s %12.1f %10s\n", "10m (old)", old, "-");
}

static void report_reciprocal_vs_divide(const char *label) {
    verify_samples(label);
    double reciprocal = bench_median(prime_1m, SAMPLE_ROUNDS);
    double divide = bench_median(prime_1m_divide, SAMPLE_ROUNDS);
    printf("\n%s\n", label);
    printf("  %-12s %12s %10s\n", "trial", "ns/op", "div/recip");
    printf("  %-12s %12.1f %10.2f\n", "reciprocal", reciprocal, divide / reciprocal);
    printf("  %-12s %12.1f %10s\n", "division", divide, "-");
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    static const struct { const char *label; uint64_t n; } worst[] = {
        {"1e5", 99991ULL}, {"250k", 249989ULL}, {"500k", 499979ULL},
        {"750k", 749993ULL}, {"1e6", 999983ULL},
        {"1e7", 9999991ULL}, {"1e8", 99999989ULL}
    };

    verify_changed_range();

    printf("Int#prime? trial/FJ cutoff sweep (median of 3)\n");
    printf("%-6s %14s %14s %14s %10s\n",
           "prime", "divide ns/op", "recip ns/op", "FJ ns/op", "recip/FJ");
    for (size_t i = 0; i < sizeof(worst) / sizeof(worst[0]); i++) {
        fill_same(worst[i].n);
        double trial = bench_median(trial_post_screen, SAMPLE_ROUNDS);
        double reciprocal = bench_median(reciprocal_post_screen, SAMPLE_ROUNDS);
        double fj = bench_median(fj_post_screen, SAMPLE_ROUNDS);
        printf("%-6s %14.1f %14.1f %14.1f %10.2f\n",
               worst[i].label, trial, reciprocal, fj, reciprocal / fj);
    }

    fill_random(100000ULL, 1000000ULL);
    report_candidate_sweep("random [100k, 1m]", 4);
    report_reciprocal_vs_divide("trial implementation: random [100k, 1m]");

    fill_coprime30(100000ULL, 1000000ULL);
    report_reciprocal_vs_divide("trial implementation: coprime-to-30 [100k, 1m]");

    fill_primes(100000ULL, 1000000ULL);
    report_reciprocal_vs_divide("trial implementation: prime-only [100k, 1m]");

    fill_random(1000001ULL, 10000000ULL);
    report_candidate_sweep("reciprocal cutoff: random [1m, 10m]",
                           sizeof(cutoffs) / sizeof(cutoffs[0]));
    report_selected_vs_old("random [1m, 10m]");

    fill_coprime30(1000001ULL, 10000000ULL);
    report_candidate_sweep("reciprocal cutoff: coprime-to-30 [1m, 10m]",
                           sizeof(cutoffs) / sizeof(cutoffs[0]));
    report_selected_vs_old("coprime-to-30 [1m, 10m]");

    fill_primes(1000001ULL, 10000000ULL);
    report_candidate_sweep("reciprocal cutoff: prime-only [1m, 10m]",
                           sizeof(cutoffs) / sizeof(cutoffs[0]));
    report_selected_vs_old("prime-only [1m, 10m]");

    printf("\ncorrectness: reciprocal/division match exhaustively on [0, 1m]; "
           "1m/FJ and old 10m/division match exhaustively on (1m, 10m]; "
           "all sampled candidates match production\n");
    return bench_sink == UINT64_MAX ? 1 : 0;
}
