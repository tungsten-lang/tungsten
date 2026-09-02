// Dense (bf16 or f16 weights) matmul on the M5 GPU Neural Accelerators
// (mpp::tensor_ops::matmul2d), dispatched from a CLASSIC compute encoder:
// pointer args, in-shader tensor views (see nvfp4_matmul_na.metal).
//
//   C[m,n] (f32) = sum_k A[m,k] * W[n,k]     A: [M][K], W: [N][K] row-major
//
// A and W share one element type (bfloat or half); C accumulates in f32 on
// a cooperative tensor and is stored once. Static K tiles with explicit
// device slices for both operands - the dynamic-extent form
// (`op.run(mA, mB, mC)` over a dynamic_length K) HANGS the GPU from a
// classic encoder (measured 2026-09-02); do not reintroduce it.
//
// Entry points (execution_simdgroups<4>, 128 threads):
//   {bf16,f16}_matmul_na          M 128, N 64, K 128   - prefill chunks >= 128
//   {bf16,f16}_matmul_na_m64      M  64, N 64, K 128   - 64-row chunks
//   {bf16,f16}_matmul_na_k64      M 128, N 64, K  64   - K % 128 != 0 (e.g. 320)
//   {bf16,f16}_matmul_na_m64_k64  M  64, N 64, K  64
// Dispatch (M/MT, N/NT, 1) tg x (128,1,1).
//
// REQUIREMENTS (the cooperative-tensor store does NOT clip to extents):
//   M % MT == 0, N % NT == 0, K % KT == 0.
//
// Args: 0 A, 1 W, 2 C (float*), 3 K(int), 4 M(int), 5 N(int).

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

template <typename T, int MT, int NT, int KT>
static inline void dense_matmul_na_impl(device T *A_ptr, device T *W_ptr, device float *C_ptr,
                                        int K, int M, int N, uint3 tgid) {
    auto A = tensor(A_ptr, dextents<int32_t, 2>(K, M), array<int32_t, 2>{1, K});
    auto W = tensor(W_ptr, dextents<int32_t, 2>(K, N), array<int32_t, 2>{1, K});
    auto C = tensor(C_ptr, dextents<int32_t, 2>(N, M), array<int32_t, 2>{1, N});
    constexpr auto desc = matmul2d_descriptor(
        MT, NT, KT, false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate);
    matmul2d<desc, execution_simdgroups<4>> op;
    auto cT = op.template get_destination_cooperative_tensor<decltype(A), decltype(W), float>();
    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] = 0.0f;
    const int n_k = K / KT;
    for (int kc = 0; kc < n_k; ++kc) {
        auto mA = A.template slice<KT, MT>(kc * KT, tgid.x * MT);
        auto mB = W.template slice<KT, NT>(kc * KT, tgid.y * NT);
        op.run(mA, mB, cT);
    }
    auto mC = C.template slice<NT, MT>(tgid.y * NT, tgid.x * MT);
    cT.store(mC);
}

#define DEF_DENSE_NA(NAME, T, MT, NT, KT)                                      \
[[max_total_threads_per_threadgroup(128)]]                                     \
kernel void NAME(device T *A [[buffer(0)]], device T *W [[buffer(1)]],          \
                 device float *C [[buffer(2)]],                                 \
                 constant int &K [[buffer(3)]], constant int &M [[buffer(4)]],  \
                 constant int &N [[buffer(5)]],                                 \
                 uint3 tgid [[threadgroup_position_in_grid]]) {                 \
    dense_matmul_na_impl<T, MT, NT, KT>(A, W, C, K, M, N, tgid);                \
}

DEF_DENSE_NA(bf16_matmul_na,         bfloat, 128, 64, 128)
DEF_DENSE_NA(bf16_matmul_na_m64,     bfloat,  64, 64, 128)
DEF_DENSE_NA(bf16_matmul_na_k64,     bfloat, 128, 64,  64)
DEF_DENSE_NA(bf16_matmul_na_m64_k64, bfloat,  64, 64,  64)
DEF_DENSE_NA(f16_matmul_na,          half,   128, 64, 128)
DEF_DENSE_NA(f16_matmul_na_m64,      half,    64, 64, 128)
DEF_DENSE_NA(f16_matmul_na_k64,      half,   128, 64,  64)
DEF_DENSE_NA(f16_matmul_na_m64_k64,  half,    64, 64,  64)
