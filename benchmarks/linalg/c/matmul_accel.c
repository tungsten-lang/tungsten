// Apple Accelerate f32 sgemm matmul. macOS only. Compile with:
//   clang -O3 -DACCELERATE_NEW_LAPACK -framework Accelerate \
//         -o matmul_accel matmul_accel.c
//
// The ACCELERATE_NEW_LAPACK define switches to the new CBLAS headers
// added in macOS 13.3. Without it, cblas_sgemm flags as deprecated.

#define ACCELERATE_NEW_LAPACK 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <Accelerate/Accelerate.h>

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

    for (int i = 0; i < N * N; i++) {
        A[i] = (float)((i * 31 + 7) % 17) / 17.0f;
        B[i] = (float)((i * 13 + 3) % 19) / 19.0f;
    }

    // Warm up Accelerate (first call lazy-initializes some internal state).
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                N, N, N, 1.0f, A, N, B, N, 0.0f, C, N);

    double *times = malloc(K * sizeof(double));
    for (int k = 0; k < K; k++) {
        double t0 = now_ms();
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    N, N, N, 1.0f, A, N, B, N, 0.0f, C, N);
        times[k] = now_ms() - t0;
    }
    qsort(times, K, sizeof(double), cmp_double);
    double median_ms = times[K / 2];
    double gflops = (2.0 * N * N * N) / (median_ms * 1e6);

    fprintf(stderr, "C[0] = %f\n", C[0]);
    printf("{\"impl\":\"c-accelerate\",\"N\":%d,\"K\":%d,\"median_ms\":%.4f,\"gflops\":%.2f}\n",
           N, K, median_ms, gflops);

    free(A); free(B); free(C); free(times);
    return 0;
}
