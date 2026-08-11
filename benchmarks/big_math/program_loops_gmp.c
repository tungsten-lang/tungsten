/* Program-level bignum loops — the destination-reusing GMP half of E3.
 * Same workloads and checksums as program_loops.w; every loop reuses its
 * mpz destinations the way idiomatic GMP code does.
 * Output: <workload>\t<n>\t<ns_per_iter>\t<checksum> */
#include <gmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static unsigned long checksum(const mpz_t v) {
    mpz_t m;
    mpz_init(m);
    mpz_mod_ui(m, v, 1000000007UL);
    unsigned long c = mpz_get_ui(m);
    mpz_clear(m);
    return c;
}

static void bench_accumulate(long n) {
    mpz_t r;
    mpz_init(r);
    mpz_set_ui(r, 1);
    mpz_mul_2exp(r, r, 4096);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) mpz_add_ui(r, r, (unsigned long)i);
    double t1 = now_sec();
    printf("accumulate\t%ld\t%.1f\t%lu\n", n, (t1 - t0) * 1e9 / (double)n,
           checksum(r));
    mpz_clear(r);
}

static void bench_mulchain(long n) {
    mpz_t r;
    mpz_init_set_ui(r, 1);
    double t0 = now_sec();
    for (long i = 2; i <= n; i++) mpz_mul_ui(r, r, (unsigned long)i);
    double t1 = now_sec();
    printf("mulchain\t%ld\t%.1f\t%lu\n", n, (t1 - t0) * 1e9 / (double)n,
           checksum(r));
    mpz_clear(r);
}

static void bench_addchain(long n) {
    mpz_t a, b;
    mpz_init_set_ui(a, 0);
    mpz_init_set_ui(b, 1);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_add(a, a, b);
        mpz_swap(a, b);
    }
    double t1 = now_sec();
    printf("addchain\t%ld\t%.1f\t%lu\n", n, (t1 - t0) * 1e9 / (double)n,
           checksum(b));
    mpz_clear(a);
    mpz_clear(b);
}

static void bench_subchain(long n) {
    mpz_t r;
    mpz_init_set_ui(r, 0);
    mpz_setbit(r, 65536);
    unsigned long probe = 0;
    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_sub_ui(r, r, (unsigned long)i);
        probe = mpz_tstbit(r, 0);
    }
    double t1 = now_sec();
    printf("subchain\t%ld\t%.1f\t%lu\n", n,
           (t1 - t0) * 1e9 / (double)n, checksum(r) + probe);
    mpz_clear(r);
}

static void bench_divchain(long n) {
    mpz_t r;
    mpz_init_set_ui(r, 0);
    mpz_setbit(r, 65536);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) mpz_tdiv_q_ui(r, r, 3UL);
    double t1 = now_sec();
    printf("divchain\t%ld\t%.1f\t%lu\n", n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clear(r);
}

static void bench_modchain(long n, unsigned long limbs) {
    mpz_t r, bump, divisor;
    mpz_inits(r, bump, divisor, NULL);
    mpz_set_ui(r, 1);
    mpz_mul_2exp(r, r, 8191UL);
    mpz_add_ui(r, r, 123456789UL);
    mpz_set_ui(bump, 1);
    mpz_mul_2exp(bump, bump, limbs * 64UL - 1UL);
    mpz_add_ui(bump, bump, 987654321UL);
    mpz_set_ui(divisor, 1);
    mpz_mul_2exp(divisor, divisor, 63);
    mpz_add_ui(divisor, divisor, 29UL);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_add(r, r, bump);
        mpz_tdiv_r(r, r, divisor);
    }
    double t1 = now_sec();
    printf("modchain%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(r, bump, divisor, NULL);
}

static void bench_sqrchain(long n, unsigned long limbs) {
    mpz_t r, bump, divisor;
    mpz_inits(r, bump, divisor, NULL);
    mpz_set_ui(r, 1);
    mpz_mul_2exp(r, r, 8191UL);
    mpz_add_ui(r, r, 123456789UL);
    mpz_set_ui(bump, 1);
    mpz_mul_2exp(bump, bump, limbs * 64UL - 1UL);
    mpz_add_ui(bump, bump, 987654321UL);
    mpz_set_ui(divisor, 1);
    mpz_mul_2exp(divisor, divisor, 63);
    mpz_add_ui(divisor, divisor, 29UL);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_add(r, r, bump);
        mpz_tdiv_r(r, r, divisor);
        mpz_mul(r, r, r);
    }
    double t1 = now_sec();
    printf("sqrchain%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(r, bump, divisor, NULL);
}

/* Word-overwrite lanes (E4 stage 3 twin): a retained base times/plus/minus
 * one word, written into a retained destination every pass — idiomatic
 * mpz_*_ui. Matches program_loops.w's wordadd/wordsub/wordmul/wordchain. */
static void word_base_init(mpz_t a, unsigned long limbs) {
    mpz_set_ui(a, 1);
    mpz_mul_2exp(a, a, limbs * 64UL - 8UL);
    mpz_add_ui(a, a, 987654321UL);
}

static void bench_wordadd(long n, unsigned long limbs) {
    mpz_t a, r;
    mpz_inits(a, r, NULL);
    word_base_init(a, limbs);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) mpz_add_ui(r, a, 5UL);
    double t1 = now_sec();
    printf("wordadd%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(a, r, NULL);
}

static void bench_wordsub(long n, unsigned long limbs) {
    mpz_t a, r;
    mpz_inits(a, r, NULL);
    word_base_init(a, limbs);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) mpz_sub_ui(r, a, 7UL);
    double t1 = now_sec();
    printf("wordsub%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(a, r, NULL);
}

static void bench_wordmul(long n, unsigned long limbs) {
    mpz_t a, r;
    mpz_inits(a, r, NULL);
    word_base_init(a, limbs);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) mpz_mul_ui(r, a, 3UL);
    double t1 = now_sec();
    printf("wordmul%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(a, r, NULL);
}

static void bench_wordchain(long n, unsigned long limbs) {
    mpz_t a, r, sum;
    mpz_inits(a, r, sum, NULL);
    word_base_init(a, limbs);
    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_add_ui(r, a, 5UL);
        mpz_sub_ui(a, r, 7UL);
    }
    double t1 = now_sec();
    mpz_add(sum, a, r);
    printf("wordchain%lu\t%ld\t%.1f\t%lu\n", limbs, n,
           (t1 - t0) * 1e9 / (double)n, checksum(sum));
    mpz_clears(a, r, sum, NULL);
}

int main(int argc, char **argv) {
    const char *workload = argc > 1 ? argv[1] : "all";
    long n = argc > 2 ? atol(argv[2]) : 0;
    unsigned long limbs = argc > 3 ? strtoul(argv[3], NULL, 10) : 65UL;
    if (!strcmp(workload, "accumulate") || !strcmp(workload, "all"))
        bench_accumulate(n > 0 ? n : 2000000);
    if (!strcmp(workload, "mulchain") || !strcmp(workload, "all"))
        bench_mulchain(n > 0 ? n : 50000);
    if (!strcmp(workload, "addchain") || !strcmp(workload, "all"))
        bench_addchain(n > 0 ? n : 300000);
    if (!strcmp(workload, "subchain") || !strcmp(workload, "all"))
        bench_subchain(n > 0 ? n : 100000);
    if (!strcmp(workload, "divchain") || !strcmp(workload, "all"))
        bench_divchain(n > 0 ? n : 30000);
    if (!strcmp(workload, "modchain") || !strcmp(workload, "all"))
        bench_modchain(n > 0 ? n : 2000000, limbs);
    if (!strcmp(workload, "sqrchain") || !strcmp(workload, "all"))
        bench_sqrchain(n > 0 ? n : 2000000, limbs);
    if (!strcmp(workload, "wordadd") || !strcmp(workload, "all"))
        bench_wordadd(n > 0 ? n : 2000000, limbs);
    if (!strcmp(workload, "wordsub") || !strcmp(workload, "all"))
        bench_wordsub(n > 0 ? n : 2000000, limbs);
    if (!strcmp(workload, "wordmul") || !strcmp(workload, "all"))
        bench_wordmul(n > 0 ? n : 2000000, limbs);
    if (!strcmp(workload, "wordchain") || !strcmp(workload, "all"))
        bench_wordchain(n > 0 ? n : 2000000, limbs);
    return 0;
}
