#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    int n = 1000000;
    char *is_prime = malloc(n + 1);
    memset(is_prime, 1, n + 1);
    is_prime[0] = 0;
    is_prime[1] = 0;

    int i = 2;
    while ((long long)i * i <= n) {
        if (is_prime[i]) {
            int j = i * i;
            while (j <= n) {
                is_prime[j] = 0;
                j += i;
            }
        }
        i++;
    }

    int count = 0;
    for (int k = 0; k <= n; k++) {
        if (is_prime[k]) count++;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%d\n", count);
    printf("elapsed: %.3fs\n", elapsed);
    free(is_prime);
    return 0;
}
