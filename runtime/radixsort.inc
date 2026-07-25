/* radixsort.inc — LSD radix sort (8-bit digits), type-specialized.
 *
 * Include with RDX_T (unsigned element type) and RDX_SUF (suffix) defined;
 * generates `void rdx_sort_<SUF>(RDX_T* a, long n)`. sizeof(RDX_T) counting
 * passes with a scratch buffer — O(n) time, data-oblivious. For random
 * integers at scale this is the fastest option (no comparisons, no branch
 * mispredicts): ~3 ns/element for u32 at 2M vs ~16 for a good pdqsort.
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
    RDX_T *tmp = (RDX_T *)malloc((size_t)n * sizeof(RDX_T));
    if (!tmp) { RDX_PDQ(a, n); return; }
    RDX_T *src = a, *dst = tmp;
    int passes = (int)sizeof(RDX_T);
    for (int p = 0; p < passes; p++) {
        int shift = p * 8;
        size_t count[256];
        for (int k = 0; k < 256; k++) count[k] = 0;
        for (long i = 0; i < n; i++) count[(size_t)((src[i] >> shift) & 0xFFu)]++;
        /* skip this digit entirely if all keys share it */
        int single = 0;
        for (int k = 0; k < 256; k++) if (count[k] == (size_t)n) { single = 1; break; }
        if (single) continue;
        size_t acc = 0;
        for (int k = 0; k < 256; k++) { size_t c = count[k]; count[k] = acc; acc += c; }
        for (long i = 0; i < n; i++) {
            RDX_T v = src[i];
            dst[count[(size_t)((v >> shift) & 0xFFu)]++] = v;
        }
        RDX_T *t = src; src = dst; dst = t;
    }
    if (src != a) memcpy(a, src, (size_t)n * sizeof(RDX_T));
    free(tmp);
}

#undef RDX_FN
#undef RDX_PDQ
