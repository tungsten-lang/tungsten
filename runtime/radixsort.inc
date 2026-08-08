/* radixsort.inc — LSD radix sort (8-bit digits), type-specialized.
 *
 * Include with RDX_T (unsigned element type) and RDX_SUF (suffix) defined;
 * generates `void rdx_sort_<SUF>(RDX_T* a, long n)`. sizeof(RDX_T) scatter
 * passes with a scratch buffer — O(n) time, data-oblivious. For random
 * integers at scale this is the fastest option (no comparisons, no branch
 * mispredicts): ~3 ns/element for u32 at 2M vs ~16 for a good pdqsort.
 *
 * Every pass's histogram is built in ONE scan over the input, up front.
 * Besides touching the data once instead of sizeof(RDX_T) times, this is
 * what makes trivial-digit skipping actually free: the old per-pass
 * counting scan degenerated on a constant digit into n serialized
 * increments of one hot counter (a ~4-cycle loop-carried dependency per
 * element, per skipped pass) — low-entropy arrays (values ≪ type range,
 * exactly the common case for i64 payloads) sorted ~2x SLOWER than
 * full-range random ones. One scan bumping sizeof(RDX_T) independent
 * tables pipelines, and a pass whose digit is constant is then skipped by
 * one O(1) histogram probe.
 *
 * Guards: a cheap already-sorted early-exit (near-free on random data,
 * turns re-sorting sorted data into one linear scan) and a malloc-failure
 * fallback to pdqsort. Requires pdqsort.inc to have been included first
 * (same RDX_SUF), for the fallback.
 */
#ifndef RDX_COMMON
#define RDX_COMMON
#define RDX_CAT2(a, b) a##b
#define RDX_CAT(a, b) RDX_CAT2(a, b)
#endif

#define RDX_FN(name) RDX_CAT(RDX_CAT(rdx_##name##_, RDX_SUF), )
#define RDX_PDQ RDX_CAT(pdq_sort_, RDX_SUF)

void RDX_FN(sort)(RDX_T *a, long n) {
    if (n < 2) return;
    /* Already non-decreasing? Bails on the first inversion, so this costs ~1
     * comparison on random data but skips all passes on sorted input. */
    long s = 1;
    while (s < n && a[s - 1] <= a[s]) s++;
    if (s == n) return;
    /* Non-increasing? One in-place reverse finishes the job. Same ~1
     * wasted comparison on random data. */
    s = 1;
    while (s < n && a[s - 1] >= a[s]) s++;
    if (s == n) {
        for (long i = 0, j = n - 1; i < j; i++, j--) { RDX_T t = a[i]; a[i] = a[j]; a[j] = t; }
        return;
    }
    RDX_T *tmp = (RDX_T *)malloc((size_t)n * sizeof(RDX_T));
    if (!tmp) { RDX_PDQ(a, n); return; }
    size_t count[sizeof(RDX_T)][256];
    memset(count, 0, sizeof(count));
    for (long i = 0; i < n; i++) {
        RDX_T v = a[i];
        for (int p = 0; p < (int)sizeof(RDX_T); p++)
            count[p][(size_t)((v >> (p * 8)) & 0xFFu)]++;
    }
    RDX_T *src = a, *dst = tmp;
    for (int p = 0; p < (int)sizeof(RDX_T); p++) {
        size_t *cnt = count[p];
        int shift = p * 8;
        /* Constant digit (the histogram puts every key in one bucket)?
         * The pass is the identity permutation — skip it. */
        if (cnt[(size_t)((src[0] >> shift) & 0xFFu)] == (size_t)n) continue;
        size_t acc = 0;
        for (int k = 0; k < 256; k++) { size_t c = cnt[k]; cnt[k] = acc; acc += c; }
        for (long i = 0; i < n; i++) {
            RDX_T v = src[i];
            dst[cnt[(size_t)((v >> shift) & 0xFFu)]++] = v;
        }
        RDX_T *t = src; src = dst; dst = t;
    }
    if (src != a) memcpy(a, src, (size_t)n * sizeof(RDX_T));
    free(tmp);
}

#undef RDX_FN
#undef RDX_PDQ
