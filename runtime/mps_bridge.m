/* runtime/mps_bridge.m — Apple Metal Performance Shaders direct bridge.
 *
 * Skips the MLX layer and dispatches MPSMatrixMultiplication directly.
 * Since MLX is essentially a graph wrapper around MPS, calling MPS
 * directly should match or beat MLX while avoiding its overhead.
 *
 * Build: link with -framework Metal -framework MetalPerformanceShaders
 * via TUNGSTEN_C_INCLUDES (see benchmarks/linalg/tungsten/build_mps_bench.sh).
 */

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>
#include "runtime.h"

/* Singleton device/queue + cached MPS kernel.
 * One MTLDevice per process; the kernel is reusable across shapes,
 * the shape is encoded by MPSMatrixDescriptor instead. */
static id<MTLDevice>       g_mps_device  = nil;
static id<MTLCommandQueue> g_mps_queue   = nil;
static MPSMatrixMultiplication *g_mps_kernel = nil;
static int g_mps_cached_m = -1, g_mps_cached_n = -1, g_mps_cached_k = -1;

static void mpsb_init(int m, int n, int k) {
    if (g_mps_device == nil) {
        g_mps_device = MTLCreateSystemDefaultDevice();
        g_mps_queue  = [g_mps_device newCommandQueue];
    }
    /* Build a fresh kernel only if dimensions changed. MPSMatrixMultiplication
     * doesn't expose its dims back, so we track them ourselves. */
    if (g_mps_kernel == nil ||
        g_mps_cached_m != m || g_mps_cached_n != n || g_mps_cached_k != k) {
        g_mps_kernel = [[MPSMatrixMultiplication alloc]
                        initWithDevice:g_mps_device
                        transposeLeft:NO
                        transposeRight:NO
                        resultRows:(NSUInteger)m
                        resultColumns:(NSUInteger)n
                        interiorColumns:(NSUInteger)k
                        alpha:1.0
                        beta:0.0];
        g_mps_cached_m = m;
        g_mps_cached_n = n;
        g_mps_cached_k = k;
    }
}

/* Wrap a Tungsten f32 typed array as an MTLBuffer with no copy.
 * Apple Silicon's unified memory means the GPU sees the same physical
 * pages the CPU wrote. The buffer is short-lived (one matmul). */
static id<MTLBuffer> mpsb_wrap_f32(WArray *arr, int n_floats) {
    float *base = (float *)arr->slots + arr->start;
    /* Round up to page size for newBufferWithBytesNoCopy. The buffer
     * length is element bytes; the no-copy variant requires a base
     * that's page-aligned (metal_array uses page-aligned allocation,
     * see runtime/runtime.c::w_array_new_aligned). */
    NSUInteger bytes = (NSUInteger)n_floats * sizeof(float);
    return [g_mps_device newBufferWithBytesNoCopy:base
                                            length:bytes
                                           options:MTLResourceStorageModeShared
                                       deallocator:nil];
}

WValue w_mps_sgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    mpsb_init(M, N, K);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    id<MTLBuffer> a_buf = mpsb_wrap_f32(a_arr, M * K);
    id<MTLBuffer> b_buf = mpsb_wrap_f32(b_arr, K * N);
    id<MTLBuffer> c_buf = mpsb_wrap_f32(c_arr, M * N);

    MPSMatrixDescriptor *a_desc = [MPSMatrixDescriptor
        matrixDescriptorWithRows:(NSUInteger)M
                         columns:(NSUInteger)K
                        rowBytes:(NSUInteger)K * sizeof(float)
                        dataType:MPSDataTypeFloat32];
    MPSMatrixDescriptor *b_desc = [MPSMatrixDescriptor
        matrixDescriptorWithRows:(NSUInteger)K
                         columns:(NSUInteger)N
                        rowBytes:(NSUInteger)N * sizeof(float)
                        dataType:MPSDataTypeFloat32];
    MPSMatrixDescriptor *c_desc = [MPSMatrixDescriptor
        matrixDescriptorWithRows:(NSUInteger)M
                         columns:(NSUInteger)N
                        rowBytes:(NSUInteger)N * sizeof(float)
                        dataType:MPSDataTypeFloat32];

    MPSMatrix *a_mat = [[MPSMatrix alloc] initWithBuffer:a_buf descriptor:a_desc];
    MPSMatrix *b_mat = [[MPSMatrix alloc] initWithBuffer:b_buf descriptor:b_desc];
    MPSMatrix *c_mat = [[MPSMatrix alloc] initWithBuffer:c_buf descriptor:c_desc];

    id<MTLCommandBuffer> cmd = [g_mps_queue commandBuffer];
    [g_mps_kernel encodeToCommandBuffer:cmd
                             leftMatrix:a_mat
                            rightMatrix:b_mat
                           resultMatrix:c_mat];
    [cmd commit];
    [cmd waitUntilCompleted];

    return w_int(1);
}

/* ============================================================================
 * MPSGraph path — newer API. Likely the same one MLX uses internally;
 * exposes auto-selected best kernel per (shape, dtype, hardware).
 * ========================================================================= */

static MPSGraph             *g_mpsg_graph    = nil;
static MPSGraphTensor       *g_mpsg_a_t      = nil;
static MPSGraphTensor       *g_mpsg_b_t      = nil;
static MPSGraphTensor       *g_mpsg_c_t      = nil;
static int g_mpsg_cached_m = -1, g_mpsg_cached_n = -1, g_mpsg_cached_k = -1;

static void mpsg_init(int m, int n, int k) {
    if (g_mps_device == nil) {
        g_mps_device = MTLCreateSystemDefaultDevice();
        g_mps_queue  = [g_mps_device newCommandQueue];
    }
    if (g_mpsg_graph != nil &&
        g_mpsg_cached_m == m && g_mpsg_cached_n == n && g_mpsg_cached_k == k) {
        return;
    }
    g_mpsg_graph = [[MPSGraph alloc] init];
    g_mpsg_a_t = [g_mpsg_graph placeholderWithShape:@[@(m), @(k)]
                                            dataType:MPSDataTypeFloat32
                                                name:@"A"];
    g_mpsg_b_t = [g_mpsg_graph placeholderWithShape:@[@(k), @(n)]
                                            dataType:MPSDataTypeFloat32
                                                name:@"B"];
    g_mpsg_c_t = [g_mpsg_graph matrixMultiplicationWithPrimaryTensor:g_mpsg_a_t
                                                     secondaryTensor:g_mpsg_b_t
                                                                name:@"C"];
    g_mpsg_cached_m = m;
    g_mpsg_cached_n = n;
    g_mpsg_cached_k = k;
}

WValue w_mpsg_sgemm_nn(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv
) {
    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);

    mpsg_init(M, N, K);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    id<MTLBuffer> a_buf = mpsb_wrap_f32(a_arr, M * K);
    id<MTLBuffer> b_buf = mpsb_wrap_f32(b_arr, K * N);
    id<MTLBuffer> c_buf = mpsb_wrap_f32(c_arr, M * N);

    MPSGraphTensorData *a_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:a_buf
                                              shape:@[@(M), @(K)]
                                           dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *b_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:b_buf
                                              shape:@[@(K), @(N)]
                                           dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *c_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:c_buf
                                              shape:@[@(M), @(N)]
                                           dataType:MPSDataTypeFloat32];

    NSDictionary *feeds = @{g_mpsg_a_t: a_data, g_mpsg_b_t: b_data};
    NSDictionary *results = @{g_mpsg_c_t: c_data};

    /* runWithMTLCommandQueue creates its own MPSCommandBuffer internally
     * and waits for completion. Simpler than wrapping MTLCommandBuffer
     * in MPSCommandBuffer ourselves. */
    [g_mpsg_graph runWithMTLCommandQueue:g_mps_queue
                                   feeds:feeds
                       targetOperations:nil
                      resultsDictionary:results];

    return w_int(1);
}

/* MPSGraph batch: K identical matmul ops in the same command buffer.
 * MPSGraph won't dedup because each call has its own MPSGraphTensorData. */
WValue w_mpsg_sgemm_batch(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv, WValue iters_wv
) {
    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);
    int ITERS = (int)w_as_int(iters_wv);

    mpsg_init(M, N, K);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    int64_t total_c = (int64_t)M * (int64_t)N;
    if (c_arr->size < total_c) c_arr->size = total_c;

    id<MTLBuffer> a_buf = mpsb_wrap_f32(a_arr, M * K);
    id<MTLBuffer> b_buf = mpsb_wrap_f32(b_arr, K * N);
    id<MTLBuffer> c_buf = mpsb_wrap_f32(c_arr, M * N);

    MPSGraphTensorData *a_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:a_buf
                                              shape:@[@(M), @(K)]
                                           dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *b_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:b_buf
                                              shape:@[@(K), @(N)]
                                           dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *c_data = [[MPSGraphTensorData alloc]
                                  initWithMTLBuffer:c_buf
                                              shape:@[@(M), @(N)]
                                           dataType:MPSDataTypeFloat32];

    NSDictionary *feeds = @{g_mpsg_a_t: a_data, g_mpsg_b_t: b_data};
    NSDictionary *results = @{g_mpsg_c_t: c_data};

    /* Wrap MTLCommandBuffer in MPSCommandBuffer so encodeToCommandBuffer
     * can call its private MPSGraph-specific methods. */
    id<MTLCommandBuffer> mtl_cmd = [g_mps_queue commandBuffer];
    MPSCommandBuffer *mps_cmd = [MPSCommandBuffer commandBufferFromCommandQueue:g_mps_queue];
    (void)mtl_cmd;  /* not used — MPSCommandBuffer creates its own underlying buffer */

    for (int i = 0; i < ITERS; i++) {
        [g_mpsg_graph encodeToCommandBuffer:mps_cmd
                                      feeds:feeds
                           targetOperations:nil
                          resultsDictionary:results
                        executionDescriptor:nil];
    }
    [mps_cmd commit];
    [mps_cmd waitUntilCompleted];

    return w_int(1);
}

/* Batched variant: K_ITERS chained matmuls (C → A_next so MPS can't
 * dedupe), single waitUntilCompleted at the end. Mirrors the MLX-batch
 * benchmark for fair comparison. */
WValue w_mps_sgemm_batch(
    WValue a_wv, WValue b_wv, WValue c_wv,
    WValue m_wv, WValue n_wv, WValue k_wv, WValue iters_wv
) {
    int M = (int)w_as_int(m_wv);
    int N = (int)w_as_int(n_wv);
    int K = (int)w_as_int(k_wv);
    int ITERS = (int)w_as_int(iters_wv);

    /* Chained-form requires M == N == K so the result of one matmul can
     * feed the next. We assume square matmul for this bench. */
    mpsb_init(M, N, K);

    WArray *a_arr = (WArray *)w_as_ptr(a_wv);
    WArray *b_arr = (WArray *)w_as_ptr(b_wv);
    WArray *c_arr = (WArray *)w_as_ptr(c_wv);

    int64_t total = (int64_t)M * (int64_t)N;
    if (c_arr->size < total) c_arr->size = total;

    id<MTLBuffer> a_buf = mpsb_wrap_f32(a_arr, M * K);
    id<MTLBuffer> b_buf = mpsb_wrap_f32(b_arr, K * N);
    id<MTLBuffer> c_buf = mpsb_wrap_f32(c_arr, M * N);

    MPSMatrixDescriptor *desc = [MPSMatrixDescriptor
        matrixDescriptorWithRows:(NSUInteger)M
                         columns:(NSUInteger)N
                        rowBytes:(NSUInteger)N * sizeof(float)
                        dataType:MPSDataTypeFloat32];

    MPSMatrix *a_mat = [[MPSMatrix alloc] initWithBuffer:a_buf descriptor:desc];
    MPSMatrix *b_mat = [[MPSMatrix alloc] initWithBuffer:b_buf descriptor:desc];
    MPSMatrix *c_mat = [[MPSMatrix alloc] initWithBuffer:c_buf descriptor:desc];

    id<MTLCommandBuffer> cmd = [g_mps_queue commandBuffer];

    /* Iter 0: C = A * B */
    [g_mps_kernel encodeToCommandBuffer:cmd
                             leftMatrix:a_mat
                            rightMatrix:b_mat
                           resultMatrix:c_mat];

    /* Iter 1..K-1: C = C * B (chained — prevents dedup) */
    for (int i = 1; i < ITERS; i++) {
        [g_mps_kernel encodeToCommandBuffer:cmd
                                 leftMatrix:c_mat
                                rightMatrix:b_mat
                               resultMatrix:c_mat];
    }

    [cmd commit];
    [cmd waitUntilCompleted];

    return w_int(1);
}
