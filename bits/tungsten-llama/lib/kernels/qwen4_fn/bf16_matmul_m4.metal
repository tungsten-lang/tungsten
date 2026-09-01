// BF16 matmul on the M5 Neural Accelerators (Metal 4 matmul2d cooperative
// tensors) — the bfloat twin of f16_matmul_m4. B (weights) binds the
// checkpoint's bf16 tensors zero-copy; A is bf16-staged activations
// (f32 -> bf16 is a truncation). C accumulates f32.
// Tile 64x32, 4 simdgroups; dispatch ((M+63)/64, (N+31)/32, 1) x (128,1,1).
// Pipeline must be built via metal4_pipeline.

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

kernel void bf16_matmul_m4(
    tensor<device bfloat, dextents<int32_t, 2>> A [[buffer(0)]],   // extents (K, M)
    tensor<device bfloat, dextents<int32_t, 2>> B [[buffer(1)]],   // extents (K, N)
    tensor<device float,  dextents<int32_t, 2>> C [[buffer(2)]],   // extents (N, M)
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    constexpr auto desc = matmul2d_descriptor(
        64, 32,
        static_cast<int>(metal::dynamic_extent),
        false, true, false);
    matmul2d<desc, execution_simdgroups<4>> op;
    auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);
    auto mB = B.slice<dynamic_length_v<int32_t>, 32>(0, tgid.y * 32);
    auto mC = C.slice<32, 64>(tgid.y * 32, tgid.x * 64);
    op.run(mA, mB, mC);
}
