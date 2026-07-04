// Phase 2 bakeoff: time llama.cpp's Q8_0 matvec at qwen3 shapes via the
// Metal backend, report effective GB/s. Pairs with the Tungsten kernel
// in bits/tungsten-llama/lib/q8_matvec.w (same shape, same bytes touched).
//
// Build:
//   clang -O3 -I$LLAMA/ggml/include \
//     -L$LLAMA/build/bin -lggml -lggml-base -lggml-metal \
//     -framework Metal -framework Foundation -framework MetalKit \
//     -Wl,-rpath,$LLAMA/build/bin \
//     bits/tungsten-llama/bench/llama_q8_matvec.c -o /tmp/llama_q8_bench
//
// Run:
//   /tmp/llama_q8_bench [K] [N] [iters]
// defaults match qwen3 expert-gate (K=2048, N=768) hot path.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

#include "ggml.h"
#include "ggml-backend.h"
#include "ggml-metal.h"

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int64_t K = (argc > 1) ? atoll(argv[1]) : 2048;
    int64_t N = (argc > 2) ? atoll(argv[2]) : 768;
    int      iters = (argc > 3) ? atoi(argv[3]) : 200;

    if (K % 32 != 0) {
        fprintf(stderr, "K must be a multiple of 32 (Q8_0 block); got %lld\n", (long long)K);
        return 1;
    }

    fprintf(stderr, "shape: W[N=%lld, K=%lld] @ x[K=%lld] -> y[N=%lld]\n",
            (long long)N, (long long)K, (long long)K, (long long)N);

    // Q8_0 weights are stored as blocks of 32 quants + 1 f16 scale = 34 bytes.
    // Total = N * (K/32) * 34 bytes.
    int64_t blocks_per_row = K / 32;
    int64_t weights_bytes = (int64_t)N * blocks_per_row * 34;
    int64_t input_bytes   = (int64_t)K * 4;     // f32
    int64_t output_bytes  = (int64_t)N * 4;     // f32
    int64_t bytes_per_call = weights_bytes + input_bytes + output_bytes;

    fprintf(stderr, "Q8_0 W: %.2f MB; x f32: %.2f KB; y f32: %.2f KB; total per call: %.2f MB\n",
            weights_bytes / 1024.0 / 1024.0,
            input_bytes / 1024.0,
            output_bytes / 1024.0,
            bytes_per_call / 1024.0 / 1024.0);

    // ---- ggml setup ----
    ggml_backend_t backend = ggml_backend_metal_init();
    if (!backend) {
        fprintf(stderr, "ggml_backend_metal_init failed\n");
        return 1;
    }
    fprintf(stderr, "backend: %s\n", ggml_backend_name(backend));

    // Context with no_alloc — backend buffer holds the actual data.
    struct ggml_init_params params = {
        .mem_size   = 1024 * 1024,
        .mem_buffer = NULL,
        .no_alloc   = true,
    };
    struct ggml_context * ctx = ggml_init(params);

    // A: weights, [k=K, n=N]. ggml convention: ne[0]=K cols, ne[1]=N rows.
    struct ggml_tensor * a = ggml_new_tensor_2d(ctx, GGML_TYPE_Q8_0, K, N);
    // B: input vector, [k=K, m=1]. Matvec = batch-1 matmul.
    struct ggml_tensor * b = ggml_new_tensor_2d(ctx, GGML_TYPE_F32,  K, 1);
    struct ggml_tensor * c = ggml_mul_mat(ctx, a, b); // [m=1, n=N]
    ggml_set_name(a, "W"); ggml_set_name(b, "x"); ggml_set_name(c, "y");

    ggml_backend_buffer_t buf = ggml_backend_alloc_ctx_tensors(ctx, backend);
    if (!buf) {
        fprintf(stderr, "ggml_backend_alloc_ctx_tensors failed\n");
        return 1;
    }

    // ---- Initialize weights and input on host, ship to backend ----
    // Q8_0 layout per block: int16 d (f16 scale) + 32 int8 quants = 34 bytes.
    // Pattern: scale = 1.0 (f16 = 0x3C00), every quant = 1. Then dequantized
    // weight = 1.0 everywhere; with x = 1.0 the result y[m] = K for all m.
    int64_t total_blocks = N * blocks_per_row;
    uint8_t * w_host = (uint8_t *)malloc((size_t)total_blocks * 34);
    for (int64_t blk = 0; blk < total_blocks; blk++) {
        uint8_t * p = w_host + blk * 34;
        // f16 scale 1.0 = 0x3C00, little-endian: bytes [0x00, 0x3C]
        p[0] = 0x00; p[1] = 0x3C;
        for (int j = 0; j < 32; j++) {
            ((int8_t *)(p + 2))[j] = 1;
        }
    }
    ggml_backend_tensor_set(a, w_host, 0, (size_t)total_blocks * 34);
    free(w_host);

    float * x_host = (float *)malloc((size_t)K * sizeof(float));
    for (int64_t i = 0; i < K; i++) x_host[i] = 1.0f;
    ggml_backend_tensor_set(b, x_host, 0, (size_t)K * sizeof(float));
    free(x_host);

    // ---- Build graph ----
    struct ggml_cgraph * gf = ggml_new_graph(ctx);
    ggml_build_forward_expand(gf, c);

    // ---- Warmup ----
    for (int i = 0; i < 5; i++) ggml_backend_graph_compute(backend, gf);

    // ---- Sanity-check the result ----
    float * y_host = (float *)malloc((size_t)N * sizeof(float));
    ggml_backend_tensor_get(c, y_host, 0, (size_t)N * sizeof(float));
    int correct = 1;
    float expected = (float)K;
    for (int64_t i = 0; i < N; i++) {
        if (fabsf(y_host[i] - expected) > 1e-3f) {
            fprintf(stderr, "MISMATCH y[%lld] = %g, expected %g\n",
                    (long long)i, y_host[i], expected);
            correct = 0;
            break;
        }
    }
    free(y_host);
    if (!correct) {
        fprintf(stderr, "correctness check failed — aborting bench\n");
        return 1;
    }
    fprintf(stderr, "correctness ok (y[m] == K = %g for all m)\n", expected);

    // ---- Benchmark ----
    double t0 = now_seconds();
    for (int i = 0; i < iters; i++) {
        ggml_backend_graph_compute(backend, gf);
    }
    double t1 = now_seconds();

    double elapsed = t1 - t0;
    double per_call_ms = elapsed * 1000.0 / iters;
    double gb_per_s = (double)bytes_per_call * iters / elapsed / 1e9;

    fprintf(stderr, "iters=%d  total=%.3f s  per-call=%.3f ms  GB/s=%.2f\n",
            iters, elapsed, per_call_ms, gb_per_s);
    printf("llama.cpp K=%lld N=%lld per_call_ms=%.3f gb_per_s=%.2f\n",
           (long long)K, (long long)N, per_call_ms, gb_per_s);

    ggml_backend_buffer_free(buf);
    ggml_free(ctx);
    ggml_backend_free(backend);
    return 0;
}
