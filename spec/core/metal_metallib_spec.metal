#include <metal_stdlib>
using namespace metal;

kernel void metallib_smoke(device int *output [[buffer(0)]],
                           uint tid [[thread_position_in_grid]]) {
    output[tid] = (int)tid * 3 + 7;
}
