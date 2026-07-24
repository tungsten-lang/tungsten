#include <stdio.h>
#include <time.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    long long sum = 0;
    for (int n = 1; n <= 1000000; n++) {
        long long x = n;
        int steps = 0;
        while (x != 1) {
            if (x % 2 == 0)
                x = x / 2;
            else
                x = 3 * x + 1;
            steps++;
        }
        sum += steps;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%lld\n", sum);
    printf("elapsed: %.3fs\n", elapsed);
    return 0;
}
