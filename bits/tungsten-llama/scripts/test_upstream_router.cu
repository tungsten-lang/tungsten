// NVIDIA execution gate for the standalone CUDA router port; no weights.
// The reference follows Tungsten's original 512-thread Metal algorithm.
// This is within-CUDA parity, not cross-vendor transcendental bit identity.
#include "../lib/kernels/qwen4_fn/router_softmax_topk10_warp.cu"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static void cuda_ok(cudaError_t status, const char *expression) {
  if (status != cudaSuccess) {
    fprintf(stderr, "%s: %s\n", expression, cudaGetErrorString(status));
    exit(1);
  }
}
#define CUDA_OK(call) cuda_ok((call), #call)

__global__ void reference_router(const float *logits, int32_t *ids, float *weights) {
  __shared__ float reduce[512], probs[512], chosen[10];
  __shared__ int indices[512], winners[10];
  unsigned lane = threadIdx.x;
  uint64_t row = blockIdx.x;
  float logit = logits[row * 512 + lane];
  reduce[lane] = logit;
  __syncthreads();
  for (int stride = 256; stride; stride >>= 1) {
    if (lane < stride) reduce[lane] = fmaxf(reduce[lane], reduce[lane + stride]);
    __syncthreads();
  }
  float max_logit = reduce[0];
  __syncthreads();
  float e = expf(logit - max_logit);
  reduce[lane] = e;
  __syncthreads();
  for (int stride = 256; stride; stride >>= 1) {
    if (lane < stride) reduce[lane] = reduce[lane] + reduce[lane + stride];
    __syncthreads();
  }
  float sum = reduce[0];
  __syncthreads();
  probs[lane] = e / sum;
  __syncthreads();
  for (int k = 0; k < 10; ++k) {
    reduce[lane] = probs[lane]; indices[lane] = lane;
    __syncthreads();
    for (int stride = 256; stride; stride >>= 1) {
      if (lane < stride &&
          (reduce[lane + stride] > reduce[lane] ||
           (reduce[lane + stride] == reduce[lane] && indices[lane + stride] < indices[lane]))) {
        reduce[lane] = reduce[lane + stride]; indices[lane] = indices[lane + stride];
      }
      __syncthreads();
    }
    if (lane == 0) { chosen[k] = reduce[0]; winners[k] = indices[0]; }
    __syncthreads();
    if (int(lane) == winners[k]) probs[lane] = -1.e30f;
    __syncthreads();
  }
  if (lane == 0) {
    float sum_chosen = 0.f;
    for (int k = 0; k < 10; ++k) sum_chosen += chosen[k];
    for (int k = 0; k < 10; ++k) {
      ids[row * 10 + k] = winners[k]; weights[row * 10 + k] = chosen[k] / sum_chosen;
    }
  }
}

static float random_value(uint32_t &state) {
  state = state * 1664525u + 1013904223u;
  return float(int(state >> 8) - 8388608) / 1048576.f;
}
static void same(const void *ref, const void *candidate, size_t bytes,
                 int rows, int pattern, const char *label) {
  if (memcmp(ref, candidate, bytes)) {
    fprintf(stderr, "FAIL: %s rows=%d pattern=%d\n", label, rows, pattern);
    exit(1);
  }
}

int main() {
  cudaDeviceProp props{};
  CUDA_OK(cudaGetDeviceProperties(&props, 0));
  fprintf(stderr, "CUDA device: %s, sm_%d%d\n", props.name, props.major, props.minor);
  float *dx, *rw, *cw, *sw;
  int32_t *ri, *ci, *si;
  CUDA_OK(cudaMalloc(&dx, 1024 * 512 * sizeof(float)));
  CUDA_OK(cudaMalloc(&rw, 1024 * 10 * sizeof(float)));
  CUDA_OK(cudaMalloc(&cw, 1024 * 10 * sizeof(float)));
  CUDA_OK(cudaMalloc(&ri, 1024 * 10 * sizeof(int32_t)));
  CUDA_OK(cudaMalloc(&ci, 1024 * 10 * sizeof(int32_t)));
  CUDA_OK(cudaMalloc(&sw, 10 * sizeof(float)));
  CUDA_OK(cudaMalloc(&si, 10 * sizeof(int32_t)));
  size_t compared = 0;
  for (int rows : {1,2,3,7,8,9,16,32,64,128,1024}) {
    std::vector<float> x(rows * 512), hw(rows * 10), gw(rows * 10);
    std::vector<int32_t> hi(rows * 10), gi(rows * 10);
    for (int pattern = 0; pattern < 6; ++pattern) {
      uint32_t state = 1009u + rows * 41u + pattern;
      for (int t = 0; t < rows; ++t) for (int i = 0; i < 512; ++i) {
        float v = random_value(state);
        if (pattern == 1) v = 0;
        if (pattern == 2) v = float((i * 17 + t) % 19) - 9;
        if (pattern == 3) v = i == 511 ? 1000.f : -1000.f;
        if (pattern == 4) v = 1.f + float(i % 31) * 0x1p-23f;
        if (pattern == 5) v = i % 7 == 0 ? 0x1p120f : -0x1p120f;
        x[t * 512 + i] = v;
      }
      CUDA_OK(cudaMemcpy(dx, x.data(), x.size()*sizeof(float), cudaMemcpyHostToDevice));
      CUDA_OK(cudaMemset(ci, 0xcd, rows*40)); CUDA_OK(cudaMemset(cw, 0xcd, rows*40));
      void *reference_args[] = {&dx, &ri, &rw};
      void *candidate_args[] = {&dx, &ci, &cw};
      CUDA_OK(cudaLaunchKernel((const void *)reference_router, dim3(rows), dim3(512), reference_args, 0, nullptr));
      CUDA_OK(cudaLaunchKernel((const void *)router_softmax_topk10_multi_warp, dim3(rows), dim3(32), candidate_args, 0, nullptr));
      CUDA_OK(cudaDeviceSynchronize());
      CUDA_OK(cudaMemcpy(hi.data(), ri, rows*40, cudaMemcpyDeviceToHost));
      CUDA_OK(cudaMemcpy(gi.data(), ci, rows*40, cudaMemcpyDeviceToHost));
      CUDA_OK(cudaMemcpy(hw.data(), rw, rows*40, cudaMemcpyDeviceToHost));
      CUDA_OK(cudaMemcpy(gw.data(), cw, rows*40, cudaMemcpyDeviceToHost));
      same(hi.data(), gi.data(), rows*40, rows, pattern, "IDs");
      same(hw.data(), gw.data(), rows*40, rows, pattern, "weights");
      compared += rows * 80;
      // Batch placement must not change a row's route.
      for (int t : {0, rows - 1}) {
        float *row_logits = dx + t*512;
        void *single_args[] = {&row_logits, &si, &sw};
        CUDA_OK(cudaLaunchKernel((const void *)router_softmax_topk10_multi_warp, dim3(1), dim3(32), single_args, 0, nullptr));
        CUDA_OK(cudaDeviceSynchronize());
        int32_t single_ids[10]; float single_weights[10];
        CUDA_OK(cudaMemcpy(single_ids, si, 40, cudaMemcpyDeviceToHost));
        CUDA_OK(cudaMemcpy(single_weights, sw, 40, cudaMemcpyDeviceToHost));
        same(hi.data()+t*10, single_ids, 40, rows, pattern, "single-row IDs");
        same(hw.data()+t*10, single_weights, 40, rows, pattern, "single-row weights");
        compared += 80;
      }
    }
  }
  CUDA_OK(cudaFree(dx)); CUDA_OK(cudaFree(rw)); CUDA_OK(cudaFree(cw));
  CUDA_OK(cudaFree(ri)); CUDA_OK(cudaFree(ci)); CUDA_OK(cudaFree(sw)); CUDA_OK(cudaFree(si));
  printf("{\"passed\":true,\"compared_bytes\":%zu,\"backend\":\"cuda\"}\n", compared);
}
