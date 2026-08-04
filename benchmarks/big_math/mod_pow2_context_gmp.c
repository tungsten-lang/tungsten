/* Public-GMP twin of mod_pow2_context.w. The destination is reused across
 * the loop and reduction uses the public power-of-two remainder API. */
#include <gmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static unsigned long checksum(const mpz_t value) {
    return mpz_fdiv_ui(value, 1000000007UL);
}

static void bench(unsigned long bits, long n) {
    mpz_t r, bump;
    mpz_inits(r, bump, NULL);
    mpz_set_ui(r, 1);
    mpz_mul_2exp(r, r, bits + 1UL);
    mpz_add_ui(r, r, 123456789UL);
    mpz_set_ui(bump, 1);
    mpz_mul_2exp(bump, bump, bits - 1UL);
    mpz_add_ui(bump, bump, 987654321UL);

    double t0 = now_sec();
    for (long i = 0; i < n; i++) {
        mpz_add(r, r, bump);
        mpz_tdiv_r_2exp(r, r, bits);
    }
    double t1 = now_sec();
    printf("modpow2_%lu\t%ld\t%.3f\t%lu\n", bits, n,
           (t1 - t0) * 1e9 / (double)n, checksum(r));
    mpz_clears(r, bump, NULL);
}

int main(int argc, char **argv) {
    const char *workload = argc > 1 ? argv[1] : "modpow2_128";
    long n = argc > 2 ? atol(argv[2]) : 1000000L;
    const char *underscore = strrchr(workload, '_');
    if (!underscore || strncmp(workload, "modpow2_", 8) != 0) return 2;
    unsigned long bits = strtoul(underscore + 1, NULL, 10);
    if (bits == 0) return 2;
    bench(bits, n);
    return 0;
}
