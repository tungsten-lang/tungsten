// Fused silu*mul over 8 expert slots in a single dispatch. Replaces
// 8 separate silu_mul dispatches with one — saves 7 GPU command-buffer
// commands per layer × 48 layers = 336 dispatches per token.
//
// Grid: TOP_K * EXPERT_FFN threads. tid encodes (slot, i) as
// tid = slot * EXPERT_FFN + i. Each thread reads its own (hg, hu)
// element and writes its own h element.

#include <metal_stdlib>
using namespace metal;

kernel void silu_mul_8(
  device float *hg0 [[buffer(0)]],
  device float *hu0 [[buffer(1)]],
  device float *h0  [[buffer(2)]],
  device float *hg1 [[buffer(3)]],
  device float *hu1 [[buffer(4)]],
  device float *h1  [[buffer(5)]],
  device float *hg2 [[buffer(6)]],
  device float *hu2 [[buffer(7)]],
  device float *h2  [[buffer(8)]],
  device float *hg3 [[buffer(9)]],
  device float *hu3 [[buffer(10)]],
  device float *h3  [[buffer(11)]],
  device float *hg4 [[buffer(12)]],
  device float *hu4 [[buffer(13)]],
  device float *h4  [[buffer(14)]],
  device float *hg5 [[buffer(15)]],
  device float *hu5 [[buffer(16)]],
  device float *h5  [[buffer(17)]],
  device float *hg6 [[buffer(18)]],
  device float *hu6 [[buffer(19)]],
  device float *h6  [[buffer(20)]],
  device float *hg7 [[buffer(21)]],
  device float *hu7 [[buffer(22)]],
  device float *h7  [[buffer(23)]],
  constant int &n   [[buffer(24)]],
  uint tid [[thread_position_in_grid]]
) {
  int slot = int(tid) / n;
  int i = int(tid) % n;
  if (slot >= 8) return;

  device float *hg;
  device float *hu;
  device float *h;
  switch (slot) {
    case 0: hg = hg0; hu = hu0; h = h0; break;
    case 1: hg = hg1; hu = hu1; h = h1; break;
    case 2: hg = hg2; hu = hu2; h = h2; break;
    case 3: hg = hg3; hu = hu3; h = h3; break;
    case 4: hg = hg4; hu = hu4; h = h4; break;
    case 5: hg = hg5; hu = hu5; h = h5; break;
    case 6: hg = hg6; hu = hu6; h = h6; break;
    case 7: hg = hg7; hu = hu7; h = h7; break;
  }

  float g = hg[i];
  float u = hu[i];
  // SiLU(x) = x * sigmoid(x) = x / (1 + exp(-x))
  float sg = g / (1.0f + exp(-g));
  h[i] = sg * u;
}
