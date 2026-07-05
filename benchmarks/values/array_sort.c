#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N 2000000

int cmp_int(const void *a, const void *b) {
    int x = *(const int *)a;
    int y = *(const int *)b;
    return (x > y) - (x < y);
}

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    int *arr = malloc(N * sizeof(int));
    unsigned int seed = 42;
    for (int i = 0; i < N; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        arr[i] = (int)seed;
    }

    qsort(arr, N, sizeof(int), cmp_int);

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("first=%d last=%d\n", arr[0], arr[N - 1]);
    printf("elapsed: %.3fs\n", elapsed);

    free(arr);
    return 0;
}
