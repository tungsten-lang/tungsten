/* skasort.inc — Malte Skarupke's in-place MSD byte-radix (american-flag sort),
 * type-specialized. Include with SKA_T (unsigned type) + SKA_SUF. 256 buckets
 * per pass, in-place cycle permutation, recursion into buckets on the next
 * byte, insertion sort for small partitions. In-place (no scratch), but its
 * recursive random scatter is less cache-friendly than LSD radix at scale. */
#ifndef SKA_COMMON
#define SKA_COMMON
#define SKA_CAT2(a, b) a##b
#define SKA_CAT(a, b) SKA_CAT2(a, b)
#define SKA_INSERTION_THRESHOLD 32
#endif
#define SKA_FN(name) SKA_CAT(SKA_CAT(ska_##name##_, SKA_SUF), )

static void SKA_FN(ins)(SKA_T *a, long n) {
    for (long i = 1; i < n; i++) { SKA_T v = a[i]; long j = i; while (j > 0 && a[j-1] > v) { a[j] = a[j-1]; j--; } a[j] = v; }
}
static void SKA_FN(radix)(SKA_T *a, long n, int shift) {
    if (n <= SKA_INSERTION_THRESHOLD) { SKA_FN(ins)(a, n); return; }
    size_t count[256]; for (int b = 0; b < 256; b++) count[b] = 0;
    for (long i = 0; i < n; i++) count[(size_t)((a[i] >> shift) & 0xFFu)]++;
    size_t bstart[257], next[256], sum = 0; int nonempty = 0;
    for (int b = 0; b < 256; b++) { bstart[b] = sum; next[b] = sum; sum += count[b]; if (count[b]) nonempty++; }
    bstart[256] = sum;
    if (nonempty > 1) {
        for (int b = 0; b < 256; b++) {
            while (next[b] < bstart[b + 1]) {
                SKA_T v = a[next[b]];
                int t = (int)((v >> shift) & 0xFFu);
                while (t != b) { SKA_T tmp = a[next[t]]; a[next[t]] = v; v = tmp; next[t]++; t = (int)((v >> shift) & 0xFFu); }
                a[next[b]] = v; next[b]++;
            }
        }
    }
    if (shift > 0) for (int b = 0; b < 256; b++) if (count[b] > 1) SKA_FN(radix)(a + bstart[b], (long)count[b], shift - 8);
}
void SKA_FN(sort)(SKA_T *a, long n) { if (n < 2) return; SKA_FN(radix)(a, n, 8 * ((int)sizeof(SKA_T) - 1)); }

#undef SKA_FN
