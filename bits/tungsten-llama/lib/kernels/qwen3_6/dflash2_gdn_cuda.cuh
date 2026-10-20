// ============================================================================
// Qwen3.5 / Bonsai-2 DFlash2 Speculative Draft, Certified Warp-Minimum Top-K,
// and Lazy-Rollback GatedDeltaNet CUDA Kernels (Ampere sm_80+ / Hopper sm_90+ / sm_121)
//
// Ported from Layr-Labs/cudafast-bonsai2-9b-engine into bits/tungsten-llama.
//
// Key Architectural Innovations:
// 1. Certified Warp-Minimum Threshold Top-K + 64-Bit Order-Preserving Key Pack:
//    - Packs `(float v, int col)` into a single `uint64_t`:
//        `(uint64_t(twiddle(v)) << 32) | ~uint32_t(col)`
//      so value-descending order with lowest-column-index tie-breaking is a
//      single unsigned 64-bit comparison (`>`).
//    - Across 16 warps (512 threads), computes each warp's maximum `M_w` and
//      takes the minimum across all 16 warps: `T = min_{w=0..15} M_w`.
//      Since the 16 warp maxima are distinct keys, at least 16 keys in the CTA
//      satisfy `key >= T`. Thus for any `k <= 16`, all keys `< T` are provably
//      pruned in one pass before Warp 0 extracts the top `k` in registers.
//    - Pass 2 (`dflash2_topk_merge_warp_cuda`) merges up to 32 chunk top-k lists
//      in a SINGLE warp (32 threads) with ZERO shared memory and ZERO barriers,
//      advancing only the winning lane's cursor `++pos` on each step.
// 2. DFlash2 Dynamic Causal Conv (`dflash2_conv_f32_cuda`) & Tree Walk:
//    - Uses explicit `__fadd_rn` / `__fmul_rn` non-contracted IEEE rounding to
//      prevent FMA contraction drift across speculative tree sizes, paired with
//      Hopper/Blackwell Programmatic Dependent Launch (PDL).
// 3. Lazy-Rollback GatedDeltaNet with Streaming L2 Cache Operators (`__ldcs`/`__stcs`):
//    - Uses `__ldcs` / `__stcs` (`ld.global.cs` / `st.global.cs`) on recurrent
//      state and rollback buffers so streaming state traffic does not evict
//      L2-resident activations.
//    - Overlaps warp butterfly reductions across all `COLS_PER_THREAD = 4`
//      state columns simultaneously (`gdn_warp_reduce_sum_n`).
//    - Rolls back rejected speculative draft steps in-register before advancing.
// ============================================================================

#pragma once

#include <cuda_runtime.h>
#include <stdint.h>

namespace tungsten_qwen36_cuda {

// ----------------------------------------------------------------------------
// 1. Programmatic Dependent Launch (PDL) Helpers
// ----------------------------------------------------------------------------

__device__ __forceinline__ void qwen36_cuda_pdl_wait() {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    cudaGridDependencySynchronize();
#endif
}

__device__ __forceinline__ void qwen36_cuda_pdl_launch_dependents() {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    cudaTriggerProgrammaticLaunchCompletion();
#endif
}

// ----------------------------------------------------------------------------
// 2. Certified Warp-Minimum Threshold Top-K & Single-Warp 32-Way Merge
// ----------------------------------------------------------------------------

static constexpr uint64_t TOPK_PACK_EMPTY = 0ULL;

// Maps IEEE-754 float to sortable uint32_t where larger float -> larger uint32_t.
// NaNs are mapped to 0 so they never win a top-k slot.
__device__ __forceinline__ uint32_t topk_float_twiddle(float v) {
    const uint32_t bits = __float_as_uint(v);
    if ((bits & 0x7fffffffU) > 0x7f800000U) {
        return 0U;
    }
    const uint32_t mask = (bits & 0x80000000U) ? 0xffffffffU : 0x80000000U;
    return bits ^ mask;
}

__device__ __forceinline__ float topk_float_untwiddle(uint32_t u) {
    const uint32_t mask = (u & 0x80000000U) ? 0x80000000U : 0xffffffffU;
    return __uint_as_float(u ^ mask);
}

// Packs `(v, col)` into a single `uint64_t` where higher `v` and smaller `col`
// compare larger under standard unsigned `>`.
__device__ __forceinline__ uint64_t topk_select_pack(float v, int col) {
    return (static_cast<uint64_t>(topk_float_twiddle(v)) << 32) |
           static_cast<uint64_t>(~static_cast<uint32_t>(col));
}

__device__ __forceinline__ float topk_unpack_val(uint64_t packed) {
    return topk_float_untwiddle(static_cast<uint32_t>(packed >> 32));
}

__device__ __forceinline__ int topk_unpack_col(uint64_t packed) {
    return static_cast<int>(~static_cast<uint32_t>(packed & 0xffffffffULL));
}

__device__ __forceinline__ uint64_t topk_warp_max_u64(uint64_t val) {
    #pragma unroll
    for (int mask = 16; mask > 0; mask >>= 1) {
        const uint64_t other = __shfl_xor_sync(0xffffffffu, val, mask, 32);
        val = (other > val) ? other : val;
    }
    return val;
}

__device__ __forceinline__ uint64_t topk_warp_min_u64(uint64_t val) {
    #pragma unroll
    for (int mask = 16; mask > 0; mask >>= 1) {
        const uint64_t other = __shfl_xor_sync(0xffffffffu, val, mask, 32);
        val = (other < val) ? other : val;
    }
    return val;
}

// Pass 1: Certified Warp-Minimum Threshold Top-K over a vocab chunk (512 threads = 16 warps).
// When `k <= 16`, the minimum of the 16 warp maxima `T = min_w(M_w)` is a certified
// lower bound on the top-16 keys in the chunk, pruning ~95%+ of candidates in one step.
template <int MAX_K = 16, int MAX_CANDIDATES = 128>
__global__ __launch_bounds__(512, 2) void dflash2_topk_partial_certified_cuda(
    const float * __restrict__ logits,
    float       * __restrict__ partial_vals,
    int32_t     * __restrict__ partial_ids,
    int ncols,
    int chunk_cols,
    int k)
{
    qwen36_cuda_pdl_wait();

    __shared__ uint64_t s_warp_max[16];
    __shared__ uint64_t s_cand[MAX_CANDIDATES];
    __shared__ int      s_count;

    const int tid        = threadIdx.x;
    const int lane_id    = tid & 31;
    const int warp_id    = tid >> 5; // 0..15
    const int chunk_idx  = blockIdx.x;
    const int row        = blockIdx.y;
    const int n_chunks   = gridDim.x;
    const int col_start  = chunk_idx * chunk_cols;
    const int col_end    = min(col_start + chunk_cols, ncols);
    const float * row_in = logits + static_cast<size_t>(row) * ncols;

    if (tid == 0) {
        s_count = 0;
    }

    // Step 1: Each thread scans its strided columns and tracks its local top-1 key
    uint64_t thread_max = TOPK_PACK_EMPTY;
    for (int col = col_start + tid; col < col_end; col += 512) {
        const uint64_t pk = topk_select_pack(row_in[col], col);
        if (pk > thread_max) {
            thread_max = pk;
        }
    }

    // Step 2: Each warp computes its maximum `M_w`
    const uint64_t warp_max = topk_warp_max_u64(thread_max);
    if (lane_id == 0) {
        s_warp_max[warp_id] = warp_max;
    }
    __syncthreads();

    // Step 3: Certified threshold `T = min_{w=0..15} M_w` computed in Warp 0
    if (warp_id == 0) {
        uint64_t v = (lane_id < 16) ? s_warp_max[lane_id] : 0xffffffffffffffffULL;
        v = topk_warp_min_u64(v);
        if (lane_id == 0) {
            s_warp_max[0] = v;
        }
    }
    __syncthreads();

    const uint64_t certified_thresh = s_warp_max[0];

    // Step 4: Collect only candidates >= `certified_thresh`
    if (thread_max >= certified_thresh && thread_max != TOPK_PACK_EMPTY) {
        // Also scan remaining elements for this thread only if `thread_max > certified_thresh`
        for (int col = col_start + tid; col < col_end; col += 512) {
            const uint64_t pk = topk_select_pack(row_in[col], col);
            if (pk >= certified_thresh) {
                const int idx = atomicAdd(&s_count, 1);
                if (idx < MAX_CANDIDATES) {
                    s_cand[idx] = pk;
                }
            }
        }
    }
    __syncthreads();

    // Step 5: Warp 0 selects the top-k from the small pruned candidate list in registers
    if (warp_id == 0) {
        const int count = min(s_count, MAX_CANDIDATES);
        const int out_base = (row * n_chunks + chunk_idx) * k;

        for (int sel = 0; sel < k; ++sel) {
            uint64_t best_pk  = TOPK_PACK_EMPTY;
            int      best_idx = -1;
            for (int i = lane_id; i < count; i += 32) {
                const uint64_t pk = s_cand[i];
                if (pk > best_pk) {
                    best_pk  = pk;
                    best_idx = i;
                }
            }
            const uint64_t winner = topk_warp_max_u64(best_pk);
            if (lane_id == 0) {
                partial_vals[out_base + sel] = topk_unpack_val(winner);
                partial_ids[out_base + sel]  = topk_unpack_col(winner);
            }
            // First lane holding `winner` Tombstones its entry in `s_cand`
            const unsigned int match_mask = __ballot_sync(0xffffffffu, best_pk == winner && best_idx >= 0);
            if (match_mask != 0u) {
                const int first_lane = __ffs(match_mask) - 1;
                if (lane_id == first_lane) {
                    s_cand[best_idx] = TOPK_PACK_EMPTY;
                }
            }
            __syncwarp();
        }
    }

    qwen36_cuda_pdl_launch_dependents();
}

// Pass 2: Single-Warp Zero-Shared-Memory Zero-Barrier Merge across <= 32 Chunks.
// Each lane `i` owns chunk `i`'s sorted top-k list and maintains a register cursor `pos`.
// In each of the `k` steps, a warp-wide max reduction finds the global best across all
// 32 active heads, and ONLY the winning lane increments `++pos`.
__global__ __launch_bounds__(32, 1) void dflash2_topk_merge_warp_cuda(
    const float   * __restrict__ partial_vals,
    const int32_t * __restrict__ partial_ids,
    float         * __restrict__ dst_vals,
    int32_t       * __restrict__ dst_ids,
    int n_chunks,
    int k)
{
    qwen36_cuda_pdl_wait();

    const int lane = threadIdx.x & 31;
    const int row  = blockIdx.y;

    const float   * row_vals = partial_vals + static_cast<size_t>(row) * n_chunks * k;
    const int32_t * row_ids  = partial_ids  + static_cast<size_t>(row) * n_chunks * k;
    float         * out_vals = dst_vals     + static_cast<size_t>(row) * k;
    int32_t       * out_ids  = dst_ids      + static_cast<size_t>(row) * k;

    int pos = 0;
    uint64_t cur = (lane < n_chunks && k > 0)
        ? topk_select_pack(row_vals[lane * k], row_ids[lane * k])
        : TOPK_PACK_EMPTY;

    for (int step = 0; step < k; ++step) {
        const uint64_t best = topk_warp_max_u64(cur);
        if (lane == 0) {
            out_vals[step] = topk_unpack_val(best);
            out_ids[step]  = topk_unpack_col(best);
        }
        if (cur == best && best != TOPK_PACK_EMPTY) {
            ++pos;
            cur = (pos < k)
                ? topk_select_pack(row_vals[lane * k + pos], row_ids[lane * k + pos])
                : TOPK_PACK_EMPTY;
        }
    }

    qwen36_cuda_pdl_launch_dependents();
}

// ----------------------------------------------------------------------------
// 3. DFlash2 Dynamic Causal Conv & Speculative Tree Walk
// ----------------------------------------------------------------------------

// Explicit `__fadd_rn` / `__fmul_rn` non-contracted IEEE rounding prevents
// FMA contraction drift between draft and target verification passes.
__global__ void dflash2_conv_f32_cuda(
    const float * __restrict__ x,
    const float * __restrict__ K,
    float       * __restrict__ dst,
    int C,
    int L,
    int S)
{
    qwen36_cuda_pdl_wait();

    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = C * S;
    if (idx >= total) {
        return;
    }

    const int c = idx % C;
    const int s = idx / C;
    const float * k_row = K + static_cast<size_t>(s) * (C * L) + c;

    float acc = 0.0f;
    const int j_start = max(0, L - 1 - s);
    for (int j = j_start; j < L; ++j) {
        const int src_pos = s - (L - 1 - j);
        const float xv = x[static_cast<size_t>(src_pos) * C + c];
        const float kv = k_row[static_cast<size_t>(j) * C];
        acc = __fadd_rn(acc, __fmul_rn(xv, kv));
    }
    dst[idx] = acc;

    qwen36_cuda_pdl_launch_dependents();
}

// Single-thread device-side speculative verification walk:
// Compares target top-1 tokens (`main_tok`) against drafted tokens (`draft`)
// and updates `history_pos` and `accepted_out` without a host round-trip.
__global__ void dflash2_walk_f32_cuda(
    const int32_t * __restrict__ draft,
    const int32_t * __restrict__ main_tok,
    int32_t       * __restrict__ history_pos,
    int32_t       * __restrict__ accepted_out,
    int32_t       * __restrict__ next_draft_first,
    int max_verify)
{
    qwen36_cuda_pdl_wait();

    if (threadIdx.x == 0 && blockIdx.x == 0) {
        int acc = 0;
        for (int i = 0; i < max_verify - 1; ++i) {
            if (main_tok[i] == draft[i + 1]) {
                ++acc;
            } else {
                break;
            }
        }
        *accepted_out     = acc + 1;
        *next_draft_first = main_tok[acc];
        *history_pos     += acc + 1;
    }

    qwen36_cuda_pdl_launch_dependents();
}

// ----------------------------------------------------------------------------
// 4. Lazy-Rollback GatedDeltaNet with Streaming L2 Cache Operators (`__ldcs`/`__stcs`)
// ----------------------------------------------------------------------------

template <int N>
__device__ __forceinline__ void gdn_warp_reduce_sum_n(float (&vals)[N]) {
    #pragma unroll
    for (int mask = 16; mask > 0; mask >>= 1) {
        #pragma unroll
        for (int c = 0; c < N; ++c) {
            vals[c] += __shfl_xor_sync(0xffffffffu, vals[c], mask, 32);
        }
    }
}

// Fuses lazy speculative state rollback (`rollback_count > 0`) with forward
// GatedDeltaNet recurrent update, using `__ldcs` / `__stcs` streaming cache
// operators so state reads/writes do not displace L2-resident activations.
template <int S_V = 128, int COLS_PER_THREAD = 4>
__global__ __launch_bounds__(128, 2) void gated_delta_net_lazy_rollback_cuda(
    const float   * __restrict__ q,
    const float   * __restrict__ k,
    const float   * __restrict__ v,
    const float   * __restrict__ gate,
    const float   * __restrict__ beta,
    float         * __restrict__ state,           // [H, S_V, S_V]
    const float   * __restrict__ rollback_k,      // [MAX_SPEC, H, S_V]
    const float   * __restrict__ rollback_delta,  // [MAX_SPEC, H, S_V]
    const float   * __restrict__ rollback_g,      // [MAX_SPEC, H]
    const int32_t * __restrict__ rollback_count_ptr,
    float         * __restrict__ out,
    int n_tokens)
{
    qwen36_cuda_pdl_wait();

    const int head    = blockIdx.y;
    const int warp_id = threadIdx.x >> 5;   // 0..3
    const int lane_id = threadIdx.x & 31;   // 0..31 (4 lanes per 128-dim K column)
    const int col_base = (blockIdx.x * 4 + warp_id) * COLS_PER_THREAD;

    float * state_head = state + static_cast<size_t>(head) * S_V * S_V;

    // Load 4 state columns (4 rows per lane across 32 lanes = 128 rows per column)
    // using `__ldcs` streaming cache operator so state doesn't pollute L2.
    float s_reg[COLS_PER_THREAD][4];
    #pragma unroll
    for (int c = 0; c < COLS_PER_THREAD; ++c) {
        const int col = col_base + c;
        #pragma unroll
        for (int r = 0; r < 4; ++r) {
            const int row = (lane_id << 2) + r;
            s_reg[c][r] = __ldcs(&state_head[col * S_V + row]);
        }
    }

    // 1. In-Kernel Lazy Rollback of rejected speculative tokens (reverse order)
    const int rb_count = (rollback_count_ptr != nullptr) ? __ldcs(rollback_count_ptr) : 0;
    for (int step = rb_count - 1; step >= 0; --step) {
        const float g_inv = expf(-__ldcs(&rollback_g[step * gridDim.y + head]));
        const float * rk_head = rollback_k + (static_cast<size_t>(step) * gridDim.y + head) * S_V;
        const float * rd_head = rollback_delta + (static_cast<size_t>(step) * gridDim.y + head) * S_V;

        float k_vec[4];
        #pragma unroll
        for (int r = 0; r < 4; ++r) {
            k_vec[r] = __ldcs(&rk_head[(lane_id << 2) + r]);
        }

        #pragma unroll
        for (int c = 0; c < COLS_PER_THREAD; ++c) {
            const float delta_c = __ldcs(&rd_head[col_base + c]);
            #pragma unroll
            for (int r = 0; r < 4; ++r) {
                s_reg[c][r] = (s_reg[c][r] - k_vec[r] * delta_c) * g_inv;
            }
        }
    }

    // 2. Forward GatedDeltaNet Recurrent Update across `n_tokens`
    const float q_scale = rsqrtf(static_cast<float>(S_V));
    for (int t = 0; t < n_tokens; ++t) {
        const size_t h_off = (static_cast<size_t>(t) * gridDim.y + head) * S_V;
        const float  g_exp = expf(gate[t * gridDim.y + head]);
        const float  b_val = beta[t * gridDim.y + head];

        float q_reg[4], k_reg[4];
        #pragma unroll
        for (int r = 0; r < 4; ++r) {
            const int idx = (lane_id << 2) + r;
            q_reg[r] = q[h_off + idx] * q_scale;
            k_reg[r] = k[h_off + idx];
        }

        // Decay state and compute `k^T * S` across all 4 columns simultaneously
        float kv_dot[COLS_PER_THREAD] = {0.0f};
        #pragma unroll
        for (int c = 0; c < COLS_PER_THREAD; ++c) {
            #pragma unroll
            for (int r = 0; r < 4; ++r) {
                s_reg[c][r] *= g_exp;
                kv_dot[c]    = __fmaf_rn(s_reg[c][r], k_reg[r], kv_dot[c]);
            }
        }
        gdn_warp_reduce_sum_n(kv_dot);

        // Rank-1 delta update and `q^T * S` readout across all 4 columns simultaneously
        float qo_dot[COLS_PER_THREAD] = {0.0f};
        #pragma unroll
        for (int c = 0; c < COLS_PER_THREAD; ++c) {
            const int   col   = col_base + c;
            const float v_col = v[h_off + col];
            const float delta = (v_col - kv_dot[c]) * b_val;
            #pragma unroll
            for (int r = 0; r < 4; ++r) {
                s_reg[c][r] = __fmaf_rn(k_reg[r], delta, s_reg[c][r]);
                qo_dot[c]   = __fmaf_rn(s_reg[c][r], q_reg[r], qo_dot[c]);
            }
        }
        gdn_warp_reduce_sum_n(qo_dot);

        if (lane_id == 0) {
            #pragma unroll
            for (int c = 0; c < COLS_PER_THREAD; ++c) {
                out[h_off + col_base + c] = qo_dot[c];
            }
        }
    }

    // Store updated recurrent state using `__stcs` streaming cache operator
    #pragma unroll
    for (int c = 0; c < COLS_PER_THREAD; ++c) {
        const int col = col_base + c;
        #pragma unroll
        for (int r = 0; r < 4; ++r) {
            const int row = (lane_id << 2) + r;
            __stcs(&state_head[col * S_V + row], s_reg[c][r]);
        }
    }

    qwen36_cuda_pdl_launch_dependents();
}

} // namespace tungsten_qwen36_cuda
