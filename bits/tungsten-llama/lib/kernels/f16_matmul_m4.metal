// F16 matmul via Metal 4 mpp::tensor_ops::matmul2d cooperative tensors.
//
// Project convention: B stored as N×K (transpose_right=true).
// Apple tensor convention: extents are (innermost, outermost). For row-major
// data the innermost dimension varies fastest in memory, so for shape MxK
// row-major: extents = (K, M).
// The kernel takes tensor params bound via MTL4ArgumentTable from host —
// see core/metal.w `metal4_argtable_set_tensor` and `metal_tensor_2d`.
//
// Pipeline must be built via metal4_pipeline (NOT metal_pipeline) so
// MTL4ComputePipelineDescriptor.requiredThreadsPerThreadgroup is set —
// cooperative tensors require this.
//
// Tile: 64x32 (m_tile=64 rows × n_tile=32 cols), 4 SIMD-groups (128 threads).
// Dispatch: ((M+63)/64, (N+31)/32, 1) threadgroups × (128, 1, 1) threads.

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

kernel void f16_matmul_m4(
    tensor<device half,  dextents<int32_t, 2>> A [[buffer(0)]],   // extents (K, M)
    tensor<device half,  dextents<int32_t, 2>> B [[buffer(1)]],   // extents (K, N)
    tensor<device float, dextents<int32_t, 2>> C [[buffer(2)]],   // extents (N, M)
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    constexpr auto desc = matmul2d_descriptor(
        64, 32,
        static_cast<int>(metal::dynamic_extent),
        false, true, false  // NT — B has N as outermost, K as innermost
    );
    matmul2d<desc, execution_simdgroups<4>> op;

    // tgid.x = M tile, tgid.y = N tile.
    // slice<innermost_extent, outermost_extent>(innermost_off, outermost_off).
    auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);  // full K, 64 rows of M
    auto mB = B.slice<dynamic_length_v<int32_t>, 32>(0, tgid.y * 32);  // full K, 32 rows of N
    auto mC = C.slice<32, 64>(tgid.y * 32, tgid.x * 64);                // 32 cols of N × 64 rows of M
    op.run(mA, mB, mC);
}
