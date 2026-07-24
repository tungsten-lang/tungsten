#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <gmp.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    mpz_t num, den, g, tmp;
    mpz_init_set_ui(num, 0);
    mpz_init_set_ui(den, 1);
    mpz_init(g);
    mpz_init(tmp);

    for (int i = 1; i <= 3000; i++) {
        /* num/den + 1/i = (num*i + den) / (den*i) */
        mpz_mul_ui(num, num, i);
        mpz_add(num, num, den);
        mpz_mul_ui(den, den, i);
        /* GCD reduce */
        mpz_gcd(g, num, den);
        mpz_divexact(num, num, g);
        mpz_divexact(den, den, g);
    }

    char *str = mpz_get_str(NULL, 10, num);
    int digits = 0;
    while (str[digits] != '\0') digits++;

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%d\n", digits);
    printf("elapsed: %.3fs\n", elapsed);

    free(str);
    mpz_clear(num);
    mpz_clear(den);
    mpz_clear(g);
    mpz_clear(tmp);
    return 0;
}
