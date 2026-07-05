#include <stdio.h>
#include <time.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    double e = 0.0;
    int rep = 0;
    while (rep < 100000) {
        e = 0.0;
        double factorial = 1.0;
        int i = 0;
        while (i <= 100) {
            e = e + 1.0 / factorial;
            factorial = factorial * (i + 1);
            i++;
        }
        rep++;
    }

    long long result = (long long)(e * 1000000.0);

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%lld\n", result);
    printf("elapsed: %.3fs\n", elapsed);
    return 0;
}
