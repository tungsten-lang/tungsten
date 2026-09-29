/* High-level f32 GEMM via CBLAS (Accelerate on Apple, OpenBLAS elsewhere). */
#include <stdio.h>
#include <stdlib.h>
#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#else
#include <cblas.h>
#endif
#include <time.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(void) {
    const int n = 512;
    const int k_iters = 8;
    size_t nn = (size_t)n * (size_t)n;
    float *A = aligned_alloc(64, nn * sizeof(float));
    float *B = aligned_alloc(64, nn * sizeof(float));
    float *C = aligned_alloc(64, nn * sizeof(float));
    if (!A || !B || !C) return 1;
    for (size_t i = 0; i < nn; i++) {
        A[i] = (float)((i * 31 + 7) % 17) / 17.0f;
        B[i] = (float)((i * 13 + 3) % 19) / 19.0f;
    }
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                n, n, n, 1.0f, A, n, B, n, 0.0f, C, n);
    double t0 = now_s();
    for (int k = 0; k < k_iters; k++) {
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                    n, n, n, 1.0f, A, n, B, n, 0.0f, C, n);
    }
    double t1 = now_s();
    printf("%d\n", (int)(C[0] * 1000000.0f));
    printf("elapsed: %.9fs\n", t1 - t0);
    free(A); free(B); free(C);
    return 0;
}
