#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <gmp.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    mpz_t a, b, tmp;
    mpz_init_set_ui(a, 0);
    mpz_init_set_ui(b, 1);
    mpz_init(tmp);

    for (int i = 0; i < 100000; i++) {
        mpz_set(tmp, b);
        mpz_add(b, a, b);
        mpz_set(a, tmp);
    }

    char *str = mpz_get_str(NULL, 10, b);
    int digits = 0;
    while (str[digits] != '\0') digits++;

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%d\n", digits);
    printf("elapsed: %.3fs\n", elapsed);

    free(str);
    mpz_clear(a);
    mpz_clear(b);
    mpz_clear(tmp);
    return 0;
}
