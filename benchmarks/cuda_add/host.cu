// Host harness for the Tungsten-emitted add_one kernel.
// Build: nvcc -O2 -o cuda_add host.cu
// (paste or #include the compiler-emitted kernel, or compile together with
//  the sibling .cu produced next to a @gpu .w source).

#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>

// Minimal inlined kernel matching Tungsten's CUDA dialect for add_one.
// When testing a freshly emitted file, replace this with #include of that .cu
// (after stripping its own main if any) or compile both translation units.
extern "C" __global__ void add_one(float *x, float *y, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    y[i] = x[i] + 1.0f;
  }
}

#define CHECK(call) do { \
  cudaError_t err = (call); \
  if (err != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, \
            cudaGetErrorString(err)); \
    exit(1); \
  } \
} while (0)

int main() {
  const int n = 8;
  float h_x[8] = {1, 2, 3, 4, 5, 6, 7, 8};
  float h_y[8] = {0};

  float *d_x = nullptr, *d_y = nullptr;
  CHECK(cudaMalloc(&d_x, n * sizeof(float)));
  CHECK(cudaMalloc(&d_y, n * sizeof(float)));
  CHECK(cudaMemcpy(d_x, h_x, n * sizeof(float), cudaMemcpyHostToDevice));

  int block = 256;
  int grid = (n + block - 1) / block;
  add_one<<<grid, block>>>(d_x, d_y, n);
  CHECK(cudaGetLastError());
  CHECK(cudaDeviceSynchronize());
  CHECK(cudaMemcpy(h_y, d_y, n * sizeof(float), cudaMemcpyDeviceToHost));

  int ok = 1;
  for (int i = 0; i < n; i++) {
    float want = h_x[i] + 1.0f;
    if (h_y[i] != want) {
      fprintf(stderr, "mismatch at %d: got %f want %f\n", i, h_y[i], want);
      ok = 0;
    }
  }
  cudaFree(d_x);
  cudaFree(d_y);
  if (!ok) return 1;
  printf("cuda add_one ok\n");
  return 0;
}
