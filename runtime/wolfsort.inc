/* wolfsort.inc — distribution/comparison hybrid (in the spirit of Igor van den
 * Hoven's wolfsort), type-specialized. Include with WOLF_T (unsigned type) +
 * WOLF_SUF; requires pdqsort.inc included first (same suffix) for the bucket
 * sort. One MSD top-bits distribution pass into scratch, then pdqsort each
 * bucket (disjoint value ranges → concatenation is sorted). Falls back to
 * pdqsort for small n, all-equal, an adverse (one huge bucket) distribution,
 * or OOM. Dominated by LSD radix on fixed-width ints — included for
 * completeness / comparison. */
#ifndef WOLF_COMMON
#define WOLF_COMMON
#define WOLF_CAT2(a, b) a##b
#define WOLF_CAT(a, b) WOLF_CAT2(a, b)
#define WOLF_MIN 256
#endif
#define WOLF_FN(name) WOLF_CAT(WOLF_CAT(wolf_##name##_, WOLF_SUF), )
#define WOLF_PDQ WOLF_CAT(pdq_sort_, WOLF_SUF)

void WOLF_FN(sort)(WOLF_T *a, long n) {
    if (n < WOLF_MIN) { WOLF_PDQ(a, n); return; }
    WOLF_T mn = a[0], mx = a[0];
    for (long i = 1; i < n; i++) { WOLF_T v = a[i]; if (v < mn) mn = v; if (v > mx) mx = v; }
    if (mn == mx) return;
    unsigned long long range = (unsigned long long)(mx - mn);
    int range_bits = 0; { unsigned long long r = range; while (r) { range_bits++; r >>= 1; } }
    int lg = 0; { long t = n; while (t >>= 1) lg++; }
    int bucket_bits = lg - 6; if (bucket_bits < 8) bucket_bits = 8; if (bucket_bits > 16) bucket_bits = 16;
    if (bucket_bits > range_bits) bucket_bits = range_bits;
    int shift = range_bits - bucket_bits;
    size_t NB = (size_t)1 << bucket_bits;
    size_t *off = (size_t *)calloc(NB + 1, sizeof(size_t));
    WOLF_T *scratch = (WOLF_T *)malloc((size_t)n * sizeof(WOLF_T));
    if (!off || !scratch) { free(off); free(scratch); WOLF_PDQ(a, n); return; }
    for (long i = 0; i < n; i++) off[(size_t)(((unsigned long long)(a[i] - mn)) >> shift)]++;
    size_t maxb = 0; for (size_t b = 0; b < NB; b++) if (off[b] > maxb) maxb = off[b];
    if (maxb > (size_t)(n - (n >> 2))) { free(off); free(scratch); WOLF_PDQ(a, n); return; }
    size_t acc = 0; for (size_t b = 0; b < NB; b++) { size_t c = off[b]; off[b] = acc; acc += c; }
    off[NB] = acc;
    size_t *cur = (size_t *)malloc(NB * sizeof(size_t));
    if (!cur) { free(off); free(scratch); WOLF_PDQ(a, n); return; }
    for (size_t b = 0; b < NB; b++) cur[b] = off[b];
    for (long i = 0; i < n; i++) { WOLF_T v = a[i]; size_t b = (size_t)(((unsigned long long)(v - mn)) >> shift); scratch[cur[b]++] = v; }
    for (size_t b = 0; b < NB; b++) { size_t s = off[b], e = off[b + 1]; if (e - s > 1) WOLF_PDQ(scratch + s, (long)(e - s)); }
    memcpy(a, scratch, (size_t)n * sizeof(WOLF_T));
    free(off); free(cur); free(scratch);
}

#undef WOLF_FN
#undef WOLF_PDQ
