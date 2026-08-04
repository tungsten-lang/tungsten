#include <gmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double monotonic_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static unsigned long checksum(const mpz_t value) {
    return mpz_fdiv_ui(value, 1000000007UL);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s and|or|xor|shift LIMBS ITERATIONS\n", argv[0]);
        return 2;
    }
    const char *workload = argv[1];
    int limbs = atoi(argv[2]);
    long iterations = atol(argv[3]);
    if (limbs < 2 || iterations <= 0) return 2;

    mpz_t r, mask;
    mpz_inits(r, mask, NULL);
    mp_bitcnt_t top = (mp_bitcnt_t)limbs * 64U - 1U;
    mpz_set_ui(r, UINT64_C(0x123456789abcdef));
    mpz_setbit(r, top);
    mpz_setbit(r, top - 1U);
    mpz_set_ui(mask, UINT64_C(0xf0f0f0f0f0f0f0f));
    mpz_setbit(mask, top);
    mpz_setbit(mask, top - 2U);

    double start = monotonic_seconds();
    if (strcmp(workload, "and") == 0) {
        for (long i = 0; i < iterations; i++) mpz_and(r, r, mask);
    } else if (strcmp(workload, "or") == 0) {
        for (long i = 0; i < iterations; i++) mpz_ior(r, r, mask);
    } else if (strcmp(workload, "xor") == 0) {
        for (long i = 0; i < iterations; i++) mpz_xor(r, r, mask);
    } else if (strcmp(workload, "shift") == 0) {
        for (long i = 0; i < iterations; i++) {
            mpz_mul_2exp(r, r, 13U);
            mpz_fdiv_q_2exp(r, r, 13U);
        }
    } else {
        fprintf(stderr, "unknown workload: %s\n", workload);
        return 2;
    }
    double elapsed = monotonic_seconds() - start;
    printf("compound\t%s\t%d\t%ld\t%.9f\t%lu\n", workload, limbs,
           iterations, elapsed * 1e9 / (double)iterations, checksum(r));
    mpz_clears(r, mask, NULL);
    return 0;
}
