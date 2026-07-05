#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N 2000000

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* map: x -> x * 3 + 1, filter: x % 2 == 0, map: x -> x / 2, reduce: sum */
    long long sum = 0;
    for (int x = 0; x < N; x++) {
        long long v = (long long)x * 3 + 1;
        if (v % 2 == 0) {
            sum += v / 2;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%lld\n", sum);
    printf("elapsed: %.3fs\n", elapsed);
    return 0;
}
