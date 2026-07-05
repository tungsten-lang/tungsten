// cuBLAS sgemm benchmark — mirrors benchmarks/linalg/tungsten/matmul_accelerate.w
//
// For each N in {128, 256, 512, 1024, 2048, 4096}:
//   - allocate A, B, C as N×N column-major float arrays on the GPU
//   - warmup: one sgemm to amortize CUDA context + kernel JIT
//   - timed: 10 sgemm calls, synchronize, divide
//   - report: best-of-3 trial wall time, GFLOPS = 2*N^3 / time / 1e9
//
// Build:
//   gcc -O3 -o matmul_cublas matmul_cublas.c \
//       -I/usr/local/cuda/include \
//       -L/usr/local/cuda/lib64 -lcublas -lcudart
//
// Run:
//   ./matmul_cublas
//
// Output format matches matmul_accelerate.w so we can paste both in results.md.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <cuda_runtime.h>
#include <cublas_v2.h>

#define CHECK_CUDA(call) do { \
    cudaError_t e = (call); \
    if (e != cudaSuccess) { \
        fprintf(stderr, "CUDA error %s at %s:%d\n", cudaGetErrorString(e), __FILE__, __LINE__); \
        exit(1); \
    } \
} while (0)

#define CHECK_CUBLAS(call) do { \
    cublasStatus_t s = (call); \
    if (s != CUBLAS_STATUS_SUCCESS) { \
        fprintf(stderr, "cuBLAS error %d at %s:%d\n", (int)s, __FILE__, __LINE__); \
        exit(1); \
    } \
} while (0)

static double now_seconds(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void bench_one(cublasHandle_t handle, int N, int iters) {
    size_t bytes = (size_t)N * N * sizeof(float);

    float *hA = (float *)malloc(bytes);
    float *hB = (float *)malloc(bytes);
    for (int i = 0; i < N * N; i++) {
        hA[i] = (float)((i * 37) % 17) * 0.1f;
        hB[i] = (float)((i * 53) % 19) * 0.1f;
    }

    float *dA, *dB, *dC;
    CHECK_CUDA(cudaMalloc(&dA, bytes));
    CHECK_CUDA(cudaMalloc(&dB, bytes));
    CHECK_CUDA(cudaMalloc(&dC, bytes));
    CHECK_CUDA(cudaMemcpy(dA, hA, bytes, cudaMemcpyHostToDevice));
    CHECK_CUDA(cudaMemcpy(dB, hB, bytes, cudaMemcpyHostToDevice));

    const float alpha = 1.0f;
    const float beta = 0.0f;

    // Warmup: amortize cuBLAS init + kernel JIT / autotuner.
    CHECK_CUBLAS(cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N,
                             N, N, N,
                             &alpha, dA, N, dB, N,
                             &beta,  dC, N));
    CHECK_CUDA(cudaDeviceSynchronize());

    // Best-of-3 timed trials.
    double best_total = 1e30;
    for (int trial = 0; trial < 3; trial++) {
        double t0 = now_seconds();
        for (int it = 0; it < iters; it++) {
            CHECK_CUBLAS(cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N,
                                     N, N, N,
                                     &alpha, dA, N, dB, N,
                                     &beta,  dC, N));
        }
        CHECK_CUDA(cudaDeviceSynchronize());
        double dt = now_seconds() - t0;
        if (dt < best_total) best_total = dt;
    }

    double per_call_ms = (best_total / iters) * 1000.0;
    double flops = 2.0 * (double)N * (double)N * (double)N;
    double gflops = flops * iters / best_total / 1e9;

    printf("N=%-5d  iters=%-4d  best=%8.3f ms total  %7.3f ms/call  %8.1f GFLOPS\n",
           N, iters, best_total * 1000.0, per_call_ms, gflops);

    CHECK_CUDA(cudaFree(dA));
    CHECK_CUDA(cudaFree(dB));
    CHECK_CUDA(cudaFree(dC));
    free(hA);
    free(hB);
}

int main(int argc, char **argv) {
    int device = 0;
    CHECK_CUDA(cudaSetDevice(device));

    cudaDeviceProp prop;
    CHECK_CUDA(cudaGetDeviceProperties(&prop, device));
    printf("Device 0: %s  (SM %d.%d, %.1f GB)\n",
           prop.name, prop.major, prop.minor,
           prop.totalGlobalMem / 1e9);

    int driver_ver, runtime_ver;
    CHECK_CUDA(cudaDriverGetVersion(&driver_ver));
    CHECK_CUDA(cudaRuntimeGetVersion(&runtime_ver));
    printf("CUDA driver %d.%d  runtime %d.%d\n",
           driver_ver / 1000, (driver_ver % 100) / 10,
           runtime_ver / 1000, (runtime_ver % 100) / 10);

    cublasHandle_t handle;
    CHECK_CUBLAS(cublasCreate(&handle));

    // Match the sizes in matmul_accelerate.w; iteration counts scale ~1/N^3
    // so total work-per-N is roughly constant, with a floor for tiny matmuls.
    int sizes[]  = { 128, 256, 512, 1024, 2048, 4096 };
    int iters[]  = { 200, 100, 50,  20,   10,   3   };
    int n = sizeof(sizes) / sizeof(sizes[0]);

    for (int i = 0; i < n; i++) {
        bench_one(handle, sizes[i], iters[i]);
    }

    cublasDestroy(handle);
    return 0;
}
