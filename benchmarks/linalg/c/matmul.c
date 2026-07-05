// Naive triple-loop N×N f32 matmul, row-major. Compile with:
//   clang -O3 -march=native -ffast-math -o matmul matmul.c
// Reports median of K iterations as wall-clock ms and GFLOPS.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void matmul(const float *A, const float *B, float *C, int N) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            float acc = 0.0f;
            for (int k = 0; k < N; k++) {
                acc += A[i * N + k] * B[k * N + j];
            }
            C[i * N + j] = acc;
        }
    }
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    int N = argc > 1 ? atoi(argv[1]) : 256;
    int K = argc > 2 ? atoi(argv[2]) : 100;
    if (N <= 0 || K <= 0) { fprintf(stderr, "usage: %s [N=256] [K=100]\n", argv[0]); return 1; }

    size_t bytes = (size_t)N * N * sizeof(float);
    float *A = aligned_alloc(64, bytes);
    float *B = aligned_alloc(64, bytes);
    float *C = aligned_alloc(64, bytes);
    if (!A || !B || !C) { fprintf(stderr, "alloc failed\n"); return 1; }

    // Deterministic-ish fill so different runs match.
    for (int i = 0; i < N * N; i++) {
        A[i] = (float)((i * 31 + 7) % 17) / 17.0f;
        B[i] = (float)((i * 13 + 3) % 19) / 19.0f;
    }

    // Warm up.
    matmul(A, B, C, N);

    double *times = malloc(K * sizeof(double));
    for (int k = 0; k < K; k++) {
        double t0 = now_ms();
        matmul(A, B, C, N);
        times[k] = now_ms() - t0;
    }
    qsort(times, K, sizeof(double), cmp_double);
    double median_ms = times[K / 2];

    // 2·N³ flops per matmul.
    double flops = 2.0 * N * N * N;
    double gflops = flops / (median_ms * 1e6);

    // Anti-DCE: print C[0] to keep the work.
    fprintf(stderr, "C[0] = %f\n", C[0]);
    printf("{\"impl\":\"c-naive\",\"N\":%d,\"K\":%d,\"median_ms\":%.4f,\"gflops\":%.2f}\n",
           N, K, median_ms, gflops);

    free(A); free(B); free(C); free(times);
    return 0;
}
