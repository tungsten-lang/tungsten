// Thin C wrapper around mlx-c for Tungsten ccall.
// Exposes minimal nvfp4 quantized matmul surface for hybrid bench.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// Tungsten runtime types — for unwrapping WArray to a raw float*.
#include "runtime.h"

#include "mlx/c/array.h"
#include "mlx/c/io.h"
#include "mlx/c/map.h"
#include "mlx/c/memory.h"
#include "mlx/c/ops.h"
#include "mlx/c/optional.h"
#include "mlx/c/stream.h"
#include "mlx/c/transforms.h"
#include "mlx/c/error.h"

static char g_last_err[1024] = {0};
static void mlxb_err_handler(const char *msg, void *data) {
    (void)data;
    if (msg) {
        strncpy(g_last_err, msg, sizeof(g_last_err) - 1);
        g_last_err[sizeof(g_last_err) - 1] = 0;
    } else {
        g_last_err[0] = 0;
    }
}
static const char *mlxb_last_err(void) {
    return g_last_err[0] ? g_last_err : "(no error message)";
}

static mlx_stream g_stream;
static int g_stream_inited = 0;
static mlx_map_string_to_array g_weights;
static int g_weights_loaded = 0;

void mlxb_init(void) {
    if (!g_stream_inited) {
        mlx_set_error_handler(mlxb_err_handler, NULL, NULL);
        g_stream = mlx_default_gpu_stream_new();
        g_stream_inited = 1;
    }
}

int mlxb_load_safetensors(const char *path) {
    mlxb_init();
    g_weights = mlx_map_string_to_array_new();
    mlx_map_string_to_string meta = mlx_map_string_to_string_new();
    // Load on CPU stream — Load op only has CPU implementation.
    mlx_stream cpu = mlx_default_cpu_stream_new();
    int rc = mlx_load_safetensors(&g_weights, &meta, path, cpu);
    mlx_stream_free(cpu);
    mlx_map_string_to_string_free(meta);
    if (rc != 0) {
        fprintf(stderr, "mlxb_load_safetensors: %s\n", mlxb_last_err());
        return 0;
    }
    // Force-materialize all weight tensors so subsequent matmuls can use them
    // on the GPU (Load::eval_gpu isn't implemented; safetensors load is CPU).
    mlx_map_string_to_array_iterator it = mlx_map_string_to_array_iterator_new(g_weights);
    const char *key = NULL;
    mlx_array val = mlx_array_new();
    while (mlx_map_string_to_array_iterator_next(&key, &val, it) == 0) {
        mlx_array_eval(val);
    }
    mlx_array_free(val);
    mlx_map_string_to_array_iterator_free(it);
    g_weights_loaded = 1;
    return 1;
}

int mlxb_quantized_matmul_nvfp4(
    const char *w_name, const char *s_name,
    float *x_data, int k_dim,
    float *out_f32, int n_rows,
    int batch
) {
    if (!g_weights_loaded) {
        fprintf(stderr, "mlxb: weights not loaded\n");
        return 0;
    }

    mlx_array w_packed = mlx_array_new();
    mlx_array w_scales = mlx_array_new();
    if (mlx_map_string_to_array_get(&w_packed, g_weights, w_name) != 0) {
        fprintf(stderr, "mlxb: tensor '%s' not in safetensors: %s\n", w_name, mlxb_last_err());
        mlx_array_free(w_packed);
        mlx_array_free(w_scales);
        return 0;
    }
    if (mlx_map_string_to_array_get(&w_scales, g_weights, s_name) != 0) {
        fprintf(stderr, "mlxb: tensor '%s' not in safetensors: %s\n", s_name, mlxb_last_err());
        mlx_array_free(w_packed);
        mlx_array_free(w_scales);
        return 0;
    }

    int x_shape[2] = { batch, k_dim };
    mlx_array x = mlx_array_new_data(x_data, x_shape, 2, MLX_FLOAT32);
    mlx_array biases = mlx_array_new();

    mlx_optional_int gs = { .value = 16, .has_value = true };
    mlx_optional_int b  = { .value = 4,  .has_value = true };

    mlx_array y = mlx_array_new();
    int rc = mlx_quantized_matmul(
        &y, x, w_packed, w_scales, biases,
        /*transpose=*/true, gs, b, "nvfp4", g_stream
    );
    if (rc != 0) {
        fprintf(stderr, "mlxb: quantized_matmul failed: %s\n", mlxb_last_err());
        mlx_array_free(w_packed);
        mlx_array_free(w_scales);
        mlx_array_free(x);
        mlx_array_free(biases);
        mlx_array_free(y);
        return 0;
    }

    if (mlx_array_eval(y) != 0) {
        fprintf(stderr, "mlxb: eval failed: %s\n", mlxb_last_err());
        mlx_array_free(w_packed);
        mlx_array_free(w_scales);
        mlx_array_free(x);
        mlx_array_free(biases);
        mlx_array_free(y);
        return 0;
    }

    const float *src = mlx_array_data_float32(y);
    if (src == NULL) {
        fprintf(stderr, "mlxb: y has no f32 data\n");
        mlx_array_free(w_packed);
        mlx_array_free(w_scales);
        mlx_array_free(x);
        mlx_array_free(biases);
        mlx_array_free(y);
        return 0;
    }
    memcpy(out_f32, src, sizeof(float) * (size_t)batch * (size_t)n_rows);

    mlx_array_free(w_packed);
    mlx_array_free(w_scales);
    mlx_array_free(x);
    mlx_array_free(biases);
    mlx_array_free(y);
    return 1;
}

int mlxb_tensor_count(void) {
    if (!g_weights_loaded) return -1;
    int n = 0;
    mlx_map_string_to_array_iterator it = mlx_map_string_to_array_iterator_new(g_weights);
    const char *key = NULL;
    mlx_array val = mlx_array_new();
    while (mlx_map_string_to_array_iterator_next(&key, &val, it) == 0) n++;
    mlx_array_free(val);
    mlx_map_string_to_array_iterator_free(it);
    return n;
}

// Copy a Tungsten string WValue into a caller-provided null-terminated buffer.
static const char *wv_to_cstr(WValue v, char *buf, size_t buf_size) {
    char tmp[6];
    const char *s = NULL;
    size_t len = 0;
    w_str_data(v, tmp, &s, &len);
    if (len >= buf_size) len = buf_size - 1;
    memcpy(buf, s, len);
    buf[len] = 0;
    return buf;
}

// WValue-friendly wrapper. x_wv and out_wv are Tungsten f32 typed arrays.
// Tungsten ccall hands us the WValue (uint64_t) directly.
WValue w_mlxb_quantized_matmul_nvfp4(
    WValue w_name_wv, WValue s_name_wv,
    WValue x_wv, WValue k_dim_wv,
    WValue out_wv, WValue n_rows_wv,
    WValue batch_wv
) {
    char w_name_buf[256], s_name_buf[256];
    const char *w_name = wv_to_cstr(w_name_wv, w_name_buf, sizeof(w_name_buf));
    const char *s_name = wv_to_cstr(s_name_wv, s_name_buf, sizeof(s_name_buf));
    WArray *x_arr   = (WArray *)w_as_ptr(x_wv);
    WArray *out_arr = (WArray *)w_as_ptr(out_wv);
    // Tungsten ccall passes ints as boxed WValues — unbox with w_as_int.
    int k_dim  = (int)w_as_int(k_dim_wv);
    int n_rows = (int)w_as_int(n_rows_wv);
    int batch  = (int)w_as_int(batch_wv);
    // f32[N] creates size=0, capacity=N. Bump size so out[i] reads work.
    int64_t total_out = (int64_t)batch * (int64_t)n_rows;
    if (out_arr->size < total_out) out_arr->size = total_out;
    float *x_data   = (float *)x_arr->slots   + x_arr->start;
    float *out_data = (float *)out_arr->slots + out_arr->start;
    int rc = mlxb_quantized_matmul_nvfp4(w_name, s_name, x_data, k_dim, out_data, n_rows, batch);
    return rc ? w_int(1) : w_int(0);
}

WValue w_mlxb_load_safetensors(WValue path_wv) {
    char path_buf[1024];
    const char *path = wv_to_cstr(path_wv, path_buf, sizeof(path_buf));
    return mlxb_load_safetensors(path) ? w_int(1) : w_int(0);
}

WValue w_mlxb_tensor_count(void) {
    return w_int(mlxb_tensor_count());
}

// ---------------------------------------------------------------------------
// Tier-2 matmul bridge: wraps Tungsten WArray data as mlx_array views,
// dispatches mlx_matmul on the default GPU stream, eval-forces it, then
// memcpy's the result back into the caller's C array. No MTLBuffer
// ownership yet — mlx_array_new_data accepts a CPU pointer and the unified-
// memory copy across is effectively free on Apple Silicon.
//
// Shape conventions match cblas_sgemm with TRANSA=N, TRANSB=N:
//   A is M×K (row-major), B is K×N, C is M×N.
//
// Tungsten ccall passes ints as boxed WValues — unbox with w_as_int.
WValue w_mlx_sgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    mlxb_init();

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    float *a_data = (float *)a_arr->slots + a_arr->start;
    float *b_data = (float *)b_arr->slots + b_arr->start;
    float *c_data = (float *)c_arr->slots + c_arr->start;

    // f32_array(N) returns size=0, capacity=N. Bump size so callers that
    // read c[i] post-matmul see populated entries.
    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_FLOAT32);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_FLOAT32);
    mlx_array y     = mlx_array_new();

    int rc = mlx_matmul(&y, a_mlx, b_mlx, g_stream);
    if (rc != 0) {
        fprintf(stderr, "w_mlx_sgemm_nn: mlx_matmul failed: %s\n", mlxb_last_err());
        mlx_array_free(a_mlx);
        mlx_array_free(b_mlx);
        mlx_array_free(y);
        return w_int(0);
    }

    if (mlx_array_eval(y) != 0) {
        fprintf(stderr, "w_mlx_sgemm_nn: eval failed: %s\n", mlxb_last_err());
        mlx_array_free(a_mlx);
        mlx_array_free(b_mlx);
        mlx_array_free(y);
        return w_int(0);
    }

    const float *src = mlx_array_data_float32(y);
    if (src == NULL) {
        fprintf(stderr, "w_mlx_sgemm_nn: y has no f32 data\n");
        mlx_array_free(a_mlx);
        mlx_array_free(b_mlx);
        mlx_array_free(y);
        return w_int(0);
    }
    memcpy(c_data, src, sizeof(float) * (size_t)total_c);

    mlx_array_free(a_mlx);
    mlx_array_free(b_mlx);
    mlx_array_free(y);
    return w_int(1);
}

// Schedules K_ITERS independent matmuls (A·B → fresh y each iter) and
// forces a SINGLE eval at the end. This measures MLX's peak throughput:
// no per-call sync, no readback. MLX should pipeline the matmuls onto
// the GPU queue and batch the work into one command-buffer commit.
//
// Reports success/failure as w_int(1)/w_int(0).
WValue w_mlx_sgemm_batch(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv, WValue iters_wv
) {
    (void)c_wv;
    mlxb_init();

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);
    int K_ITERS = (int)w_as_int(iters_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);

    float *a_data = (float *)a_arr->slots + a_arr->start;
    float *b_data = (float *)b_arr->slots + b_arr->start;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_FLOAT32);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_FLOAT32);

    // CHAIN the matmuls so MLX's compute-graph DCE can't fold them.
    // y0 = A·B; y1 = y0·B; y2 = y1·B; ... — each iter consumes the
    // previous output as input, forcing K distinct kernel launches.
    // Note: this measures K serially dependent matmuls (no GPU
    // pipelining between iters), which is exactly what a real K-step
    // matmul-heavy workload looks like — not artificial peak.
    mlx_array y_prev = mlx_array_new();
    int ok = 1;
    if (mlx_matmul(&y_prev, a_mlx, b_mlx, g_stream) != 0) ok = 0;

    for (int i = 1; i < K_ITERS && ok; i++) {
        mlx_array y_next = mlx_array_new();
        if (mlx_matmul(&y_next, y_prev, b_mlx, g_stream) != 0) {
            mlx_array_free(y_next);
            ok = 0;
            break;
        }
        mlx_array_free(y_prev);
        y_prev = y_next;
    }

    // Single eval barrier — forces the full chain.
    if (ok) {
        if (mlx_array_eval(y_prev) != 0) ok = 0;
    }

    mlx_array_free(a_mlx);
    mlx_array_free(b_mlx);
    mlx_array_free(y_prev);

    return w_int(ok);
}

// --- Double-precision (f64) MLX matmul ----------------------------------
// Apple Silicon Metal has no native fp64. MLX explicitly throws if you
// route f64 through a GPU stream. Use the CPU stream for f64.
static mlx_stream g_cpu_stream;
static int g_cpu_stream_inited = 0;

WValue w_mlx_dgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    mlxb_init();
    if (!g_cpu_stream_inited) {
        g_cpu_stream = mlx_default_cpu_stream_new();
        g_cpu_stream_inited = 1;
    }

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    double *a_data = (double *)a_arr->slots + a_arr->start;
    double *b_data = (double *)b_arr->slots + b_arr->start;
    double *c_data = (double *)c_arr->slots + c_arr->start;

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_FLOAT64);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_FLOAT64);
    mlx_array y     = mlx_array_new();

    int rc = mlx_matmul(&y, a_mlx, b_mlx, g_cpu_stream);
    if (rc != 0 || mlx_array_eval(y) != 0) {
        fprintf(stderr, "w_mlx_dgemm_nn failed: %s\n", mlxb_last_err());
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    /* MLX may run matmul on CPU stream for f64 (Metal lacks native f64 on
     * Apple Silicon). The eval forces it; readback is still memcpy. */
    const void *src_v = mlx_array_data_float64(y);
    if (src_v == NULL) {
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    memcpy(c_data, src_v, sizeof(double) * (size_t)total_c);

    mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
    return w_int(1);
}

// --- Half-precision (f16) MLX matmul ------------------------------------
// Inputs MUST be f16 arrays (2 bytes/elem). Tungsten can't write f16
// scalars directly, so callers use a conversion kernel up-front.
WValue w_mlx_hgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    mlxb_init();

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    /* f16 = 2 bytes/elem; ptrs are (uint16_t *) views into the slot data. */
    void *a_data = (void *)((uint16_t *)a_arr->slots + a_arr->start);
    void *b_data = (void *)((uint16_t *)b_arr->slots + b_arr->start);
    void *c_data = (void *)((uint16_t *)c_arr->slots + c_arr->start);

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_FLOAT16);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_FLOAT16);
    mlx_array y     = mlx_array_new();

    int rc = mlx_matmul(&y, a_mlx, b_mlx, g_stream);
    if (rc != 0 || mlx_array_eval(y) != 0) {
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    const void *src_v = mlx_array_data_float16(y);
    if (src_v == NULL) {
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    memcpy(c_data, src_v, 2u * (size_t)total_c);

    mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
    return w_int(1);
}

// --- f32 → bf16 array conversion ----------------------------------------
// Writes len bf16 values into dst[] from src[]. Tungsten doesn't have a
// native scalar bf16 type for `arr[i] = value`, so we provide this helper
// so benchmark drivers can populate bf16 inputs without dragging in a
// Metal conversion kernel.
//
// bf16 is the top 16 bits of an IEEE 754 fp32 with round-to-nearest-even.
static inline uint16_t f32_to_bf16(float f) {
    union { float f; uint32_t u; } v = { f };
    uint32_t u = v.u;
    /* RNE: add the rounding bias before truncating. NaN-safe: bumping a
     * NaN by 0x7FFF leaves it a NaN. */
    uint32_t bias = 0x7FFF + ((u >> 16) & 1);
    return (uint16_t)((u + bias) >> 16);
}

WValue w_f32_to_bf16_array(WValue src_wv, WValue dst_wv, WValue len_wv) {
    WArray *src_arr = (WArray *)w_as_ptr(src_wv);
    WArray *dst_arr = (WArray *)w_as_ptr(dst_wv);
    int64_t len = w_as_int(len_wv);

    if (dst_arr->size < len) dst_arr->size = len;

    const float *src = (const float *)src_arr->slots + src_arr->start;
    uint16_t *dst = (uint16_t *)dst_arr->slots + dst_arr->start;

    for (int64_t i = 0; i < len; i++) {
        dst[i] = f32_to_bf16(src[i]);
    }
    return w_int(1);
}

// --- bfloat16 MLX matmul ------------------------------------------------
// Inputs are bf16 (2 bytes/elem, Tungsten ebits=-116).
WValue w_mlx_bgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    mlxb_init();

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    void *a_data = (void *)((uint16_t *)a_arr->slots + a_arr->start);
    void *b_data = (void *)((uint16_t *)b_arr->slots + b_arr->start);
    void *c_data = (void *)((uint16_t *)c_arr->slots + c_arr->start);

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_BFLOAT16);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_BFLOAT16);
    mlx_array y     = mlx_array_new();

    int rc = mlx_matmul(&y, a_mlx, b_mlx, g_stream);
    if (rc != 0 || mlx_array_eval(y) != 0) {
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    const void *src_v = mlx_array_data_bfloat16(y);
    if (src_v == NULL) {
        mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
        return w_int(0);
    }
    memcpy(c_data, src_v, 2u * (size_t)total_c);

    mlx_array_free(a_mlx); mlx_array_free(b_mlx); mlx_array_free(y);
    return w_int(1);
}

// Variant that skips the device→host copy. Useful for benchmark-style
// timing where the consumer only cares about how long the matmul takes,
// not about reading C back into CPU memory. The eval still synchronizes,
// so wall-clock = pure matmul + dispatch overhead.
WValue w_mlx_sgemm_nn_no_readback(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    (void)c_wv;  // intentionally unused — no copy back
    mlxb_init();

    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);

    float *a_data = (float *)a_arr->slots + a_arr->start;
    float *b_data = (float *)b_arr->slots + b_arr->start;

    int a_shape[2] = { M, K };
    int b_shape[2] = { K, N };

    mlx_array a_mlx = mlx_array_new_data(a_data, a_shape, 2, MLX_FLOAT32);
    mlx_array b_mlx = mlx_array_new_data(b_data, b_shape, 2, MLX_FLOAT32);
    mlx_array y     = mlx_array_new();

    int rc = mlx_matmul(&y, a_mlx, b_mlx, g_stream);
    if (rc == 0) rc = mlx_array_eval(y);

    mlx_array_free(a_mlx);
    mlx_array_free(b_mlx);
    mlx_array_free(y);
    return w_int(rc == 0 ? 1 : 0);
}

// ---- Elementwise / reduce / softmax / fft / rng / eval (opt-in with this TU) ----

#include "mlx/c/fft.h"
#include "mlx/c/random.h"

static float *mlx_f32_slots(WValue wv, int64_t *len_out) {
    WArray *a = (WArray *)w_as_ptr(wv);
    *len_out = (int64_t)a->size;
    if (a->size == 0 && a->cap > 0) *len_out = a->cap; /* f32_array often size=0 */
    return (float *)a->slots + a->start;
}

static void mlx_bump_size(WValue wv, int64_t n) {
    WArray *a = (WArray *)w_as_ptr(wv);
    if (a->size < n) a->size = (int32_t)n;
}

static int mlx_bin_f32(WValue a_wv, WValue b_wv, WValue out_wv, WValue n_wv,
                       int (*op)(mlx_array*, mlx_array, mlx_array, mlx_stream)) {
    mlxb_init();
    int64_t la, lb, lo;
    float *a = mlx_f32_slots(a_wv, &la);
    float *b = mlx_f32_slots(b_wv, &lb);
    float *o = mlx_f32_slots(out_wv, &lo);
    int n = (int)w_as_int(n_wv);
    if (n <= 0) n = (int)(la < lb ? la : lb);
    if (n > lo) n = (int)lo;
    int shape[1] = { n };
    mlx_array A = mlx_array_new_data(a, shape, 1, MLX_FLOAT32);
    mlx_array B = mlx_array_new_data(b, shape, 1, MLX_FLOAT32);
    mlx_array Y = mlx_array_new();
    int rc = op(&Y, A, B, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) memcpy(o, src, sizeof(float) * (size_t)n);
        mlx_bump_size(out_wv, n);
    }
    mlx_array_free(A); mlx_array_free(B); mlx_array_free(Y);
    return rc == 0 ? 1 : 0;
}

static int mlx_unary_f32(WValue a_wv, WValue out_wv, WValue n_wv,
                         int (*op)(mlx_array*, mlx_array, mlx_stream)) {
    mlxb_init();
    int64_t la, lo;
    float *a = mlx_f32_slots(a_wv, &la);
    float *o = mlx_f32_slots(out_wv, &lo);
    int n = (int)w_as_int(n_wv);
    if (n <= 0) n = (int)la;
    if (n > lo) n = (int)lo;
    int shape[1] = { n };
    mlx_array A = mlx_array_new_data(a, shape, 1, MLX_FLOAT32);
    mlx_array Y = mlx_array_new();
    int rc = op(&Y, A, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) memcpy(o, src, sizeof(float) * (size_t)n);
        mlx_bump_size(out_wv, n);
    }
    mlx_array_free(A); mlx_array_free(Y);
    return rc == 0 ? 1 : 0;
}

WValue w_mlx_add_f32(WValue a, WValue b, WValue o, WValue n) {
    return w_int(mlx_bin_f32(a, b, o, n, mlx_add));
}
WValue w_mlx_mul_f32(WValue a, WValue b, WValue o, WValue n) {
    return w_int(mlx_bin_f32(a, b, o, n, mlx_multiply));
}
WValue w_mlx_sub_f32(WValue a, WValue b, WValue o, WValue n) {
    return w_int(mlx_bin_f32(a, b, o, n, mlx_subtract));
}
WValue w_mlx_div_f32(WValue a, WValue b, WValue o, WValue n) {
    return w_int(mlx_bin_f32(a, b, o, n, mlx_divide));
}
WValue w_mlx_exp_f32(WValue a, WValue o, WValue n) {
    return w_int(mlx_unary_f32(a, o, n, mlx_exp));
}
WValue w_mlx_log_f32(WValue a, WValue o, WValue n) {
    return w_int(mlx_unary_f32(a, o, n, mlx_log));
}
WValue w_mlx_sqrt_f32(WValue a, WValue o, WValue n) {
    return w_int(mlx_unary_f32(a, o, n, mlx_sqrt));
}
WValue w_mlx_tanh_f32(WValue a, WValue o, WValue n) {
    return w_int(mlx_unary_f32(a, o, n, mlx_tanh));
}

WValue w_mlx_sum_f32(WValue a_wv, WValue n_wv) {
    mlxb_init();
    int64_t la; float *a = mlx_f32_slots(a_wv, &la);
    int n = (int)w_as_int(n_wv); if (n <= 0) n = (int)la;
    int shape[1] = { n };
    mlx_array A = mlx_array_new_data(a, shape, 1, MLX_FLOAT32);
    mlx_array Y = mlx_array_new();
    int rc = mlx_sum(&Y, A, false, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    float out = 0.0f;
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) out = src[0];
    }
    mlx_array_free(A); mlx_array_free(Y);
    return w_float((double)out);
}

WValue w_mlx_max_f32(WValue a_wv, WValue n_wv) {
    mlxb_init();
    int64_t la; float *a = mlx_f32_slots(a_wv, &la);
    int n = (int)w_as_int(n_wv); if (n <= 0) n = (int)la;
    int shape[1] = { n };
    mlx_array A = mlx_array_new_data(a, shape, 1, MLX_FLOAT32);
    mlx_array Y = mlx_array_new();
    int rc = mlx_max(&Y, A, false, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    float out = 0.0f;
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) out = src[0];
    }
    mlx_array_free(A); mlx_array_free(Y);
    return w_float((double)out);
}

WValue w_mlx_softmax_rows_f32(WValue a_wv, WValue out_wv, WValue m_wv, WValue n_wv) {
    mlxb_init();
    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int64_t la, lo;
    float *a = mlx_f32_slots(a_wv, &la);
    float *o = mlx_f32_slots(out_wv, &lo);
    int shape[2] = { M, N };
    mlx_array A = mlx_array_new_data(a, shape, 2, MLX_FLOAT32);
    mlx_array Y = mlx_array_new();
    int rc = mlx_softmax_axis(&Y, A, 1, true, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) memcpy(o, src, sizeof(float) * (size_t)M * (size_t)N);
        mlx_bump_size(out_wv, (int64_t)M * N);
    }
    mlx_array_free(A); mlx_array_free(Y);
    return w_int(rc == 0 ? 1 : 0);
}

/* Complex FFT: pack re/im into complex64, run mlx_fft_fft, unpack. */
WValue w_mlx_fft_f32(WValue re_wv, WValue im_wv, WValue n_wv, WValue inv_wv) {
    mlxb_init();
    int n = (int)w_as_int(n_wv);
    int inverse = (int)w_as_int(inv_wv);
    int64_t lr, li;
    float *re = mlx_f32_slots(re_wv, &lr);
    float *im = mlx_f32_slots(im_wv, &li);
    if (n <= 0) n = (int)lr;
    /* Build interleaved complex as float[2n] view for complex64 */
    float *packed = (float *)malloc(sizeof(float) * 2 * (size_t)n);
    if (!packed) return w_int(0);
    for (int i = 0; i < n; i++) {
        packed[2 * i] = re[i];
        packed[2 * i + 1] = im[i];
    }
    int shape[1] = { n };
    mlx_array A = mlx_array_new_data(packed, shape, 1, MLX_COMPLEX64);
    mlx_array Y = mlx_array_new();
    int rc;
    if (inverse)
        rc = mlx_fft_ifft(&Y, A, n, -1, MLX_FFT_NORM_ORTHO, g_stream);
    else
        rc = mlx_fft_fft(&Y, A, n, -1, MLX_FFT_NORM_ORTHO, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    if (rc == 0) {
        /* complex64 data as float pairs */
        const float *src = (const float *)mlx_array_data_complex64(Y);
        if (src) {
            for (int i = 0; i < n; i++) {
                re[i] = src[2 * i];
                im[i] = src[2 * i + 1];
            }
        }
        mlx_bump_size(re_wv, n);
        mlx_bump_size(im_wv, n);
    }
    free(packed);
    mlx_array_free(A); mlx_array_free(Y);
    return w_int(rc == 0 ? 1 : 0);
}

WValue w_mlx_random_uniform_f32(WValue out_wv, WValue n_wv, WValue lo_wv, WValue hi_wv, WValue seed_wv) {
    mlxb_init();
    int n = (int)w_as_int(n_wv);
    float lo = (float)w_as_double(lo_wv);
    float hi = (float)w_as_double(hi_wv);
    uint64_t seed = (uint64_t)w_as_int(seed_wv);
    mlx_random_seed(seed);
    int shape[1] = { n };
    mlx_array low = mlx_array_new_float(lo);
    mlx_array high = mlx_array_new_float(hi);
    mlx_array key = mlx_array_new(); /* null key via empty? API says may be null - use key from seed */
    mlx_array key_arr = mlx_array_new();
    mlx_random_key(&key_arr, seed);
    mlx_array Y = mlx_array_new();
    int rc = mlx_random_uniform(&Y, low, high, shape, 1, MLX_FLOAT32, key_arr, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    int64_t lo_len; float *o = mlx_f32_slots(out_wv, &lo_len);
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) memcpy(o, src, sizeof(float) * (size_t)n);
        mlx_bump_size(out_wv, n);
    }
    mlx_array_free(low); mlx_array_free(high); mlx_array_free(key_arr); mlx_array_free(Y);
    (void)key;
    return w_int(rc == 0 ? 1 : 0);
}

WValue w_mlx_random_normal_f32(WValue out_wv, WValue n_wv, WValue mean_wv, WValue std_wv, WValue seed_wv) {
    mlxb_init();
    int n = (int)w_as_int(n_wv);
    float loc = (float)w_as_double(mean_wv);
    float scale = (float)w_as_double(std_wv);
    uint64_t seed = (uint64_t)w_as_int(seed_wv);
    mlx_random_seed(seed);
    int shape[1] = { n };
    mlx_array key_arr = mlx_array_new();
    mlx_random_key(&key_arr, seed);
    mlx_array Y = mlx_array_new();
    int rc = mlx_random_normal(&Y, shape, 1, MLX_FLOAT32, loc, scale, key_arr, g_stream);
    if (rc == 0) rc = mlx_array_eval(Y);
    int64_t lo_len; float *o = mlx_f32_slots(out_wv, &lo_len);
    if (rc == 0) {
        const float *src = mlx_array_data_float32(Y);
        if (src) memcpy(o, src, sizeof(float) * (size_t)n);
        mlx_bump_size(out_wv, n);
    }
    mlx_array_free(key_arr); mlx_array_free(Y);
    return w_int(rc == 0 ? 1 : 0);
}

WValue w_mlx_eval(void) {
    mlxb_init();
    /* no-op graph-wide eval: callers already eval per-op. Placeholder for future. */
    return w_int(1);
}

WValue w_mlx_compile_begin(void) {
    return w_int(1); /* compile graph capture TBD */
}

WValue w_mlx_compile_end(void) {
    return w_int(1);
}
