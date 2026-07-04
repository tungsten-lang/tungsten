// F16 matmul via Metal 4 matmul2d, fused residual (C += A*B^T).
//
// Same shape & layout convention as f16_matmul_m4.metal but uses
// multiply_accumulate mode so the destination is added to instead of
// overwritten — the equivalent of f16_matmul_simd_v2_residual_fc for
// the long-M path.
//
// Strategy: load existing C tile into a cooperative_tensor, then
// matmul2d in accumulate mode adds A*B^T into that tensor, then store
// back. matmul2d's accumulator is float32 throughout, matching the
// f32 residual stream in Lightning.

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

[[max_total_threads_per_threadgroup(128)]]
kernel void f16_matmul_m4_residual(
    tensor<device half,  dextents<int32_t, 2>> A [[buffer(0)]],   // extents (K, M)
    tensor<device half,  dextents<int32_t, 2>> B [[buffer(1)]],   // extents (K, N)
    tensor<device float, dextents<int32_t, 2>> C [[buffer(2)]],   // extents (N, M)
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    constexpr auto desc = matmul2d_descriptor(
        64, 32,
        static_cast<int>(metal::dynamic_extent),
        false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate
    );
    matmul2d<desc, execution_simdgroups<4>> op;

    auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);
    auto mB = B.slice<dynamic_length_v<int32_t>, 32>(0, tgid.y * 32);
    auto mC = C.slice<32, 64>(tgid.y * 32, tgid.x * 64);

    // Load existing C tile into accumulator, run matmul in accumulate mode,
    // store back.
    auto cT = op.get_destination_cooperative_tensor<
                  decltype(A), decltype(A), float>();
    cT.load(mC);
    op.run(mA, mB, cT);
    cT.store(mC);
}
