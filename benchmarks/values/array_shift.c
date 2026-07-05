#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N 10000000

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    int *a = malloc(N * sizeof(int));
    for (int i = 0; i < N; i++)
        a[i] = i % 10;

    /* shift from a into b: pointer bump (O(1) per shift) */
    int *b = malloc(N * sizeof(int));
    int a_len = N;
    int a_off = 0;
    int b_len = 0;
    while (a_len > 0) {
        b[b_len++] = a[a_off++];
        a_len--;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("length=%d first=%d last=%d\n", b_len, b[0], b[b_len - 1]);
    printf("elapsed: %.3fs\n", elapsed);

    free(a);
    free(b);
    return 0;
}
