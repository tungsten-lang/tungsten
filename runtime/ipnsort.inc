/* ipnsort.inc — instruction-parallel network sort (a from-scratch port of the
 * algorithm behind Rust's `sort_unstable`, by Lukas Bergdoll), type-specialized.
 *
 * Include with IPN_T (unsigned element type, e.g. uint32_t) and IPN_SUF (name
 * suffix, e.g. u32) defined; generates `void ipn_sort_<SUF>(IPN_T* a, long n)`.
 * Comparison is `<` on IPN_T (instantiate with the unsigned type to match the
 * runtime's typed-array sort semantics).
 *
 * Three ingredients give it its speed over classic pdqsort on random data:
 *   1. A branchless *cyclic* Lomuto partition (a single moving hole → one pair
 *      of unconditional stores per element; only the lt-boundary advance is
 *      conditional), unrolled 2x for element widths <= 8 bytes.
 *   2. A small-sort (n <= 32) built from exact-size branchless Batcher sorting
 *      networks on the two halves + a dual-ended branchless merge.
 *   3. Introsort discipline: median/ninther pivots and a heapsort fallback after
 *      too many unbalanced partitions guarantee O(n log n) worst case.
 */
#ifndef IPN_COMMON
#define IPN_COMMON
#define IPN_CAT2(a, b) a##b
#define IPN_CAT(a, b) IPN_CAT2(a, b)
#define IPN_SMALL 32
#endif

#define IPN_FN(name) IPN_CAT(IPN_CAT(ipn_##name##_, IPN_SUF), )
#define IPN_LESS(a, b) ((a) < (b))
#define IPN_SWAP(x, y) do { IPN_T _it = (x); (x) = (y); (y) = _it; } while (0)

/* branchless compare-exchange (compiles to cmov / min-max) */
static inline void IPN_FN(cx)(IPN_T *a, int i, int j) {
    IPN_T x = a[i], y = a[j];
    a[i] = x < y ? x : y;
    a[j] = x < y ? y : x;
}
static inline void IPN_FN(net2)(IPN_T *a) { IPN_FN(cx)(a,0,1); }
static inline void IPN_FN(net3)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,2); }
static inline void IPN_FN(net4)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,1,2); }
static inline void IPN_FN(net5)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); }
static inline void IPN_FN(net6)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); }
static inline void IPN_FN(net7)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); }
static inline void IPN_FN(net8)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); }
static inline void IPN_FN(net9)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); }
static inline void IPN_FN(net10)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); }
static inline void IPN_FN(net11)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); }
static inline void IPN_FN(net12)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,10,11); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,9,11); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,3,11); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,7,11); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); }
static inline void IPN_FN(net13)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,10,11); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,9,11); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,8,12); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,3,11); IPN_FN(cx)(a,4,12); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,7,11); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); }
static inline void IPN_FN(net14)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,10,11); IPN_FN(cx)(a,12,13); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,9,11); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,8,12); IPN_FN(cx)(a,9,13); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,3,11); IPN_FN(cx)(a,4,12); IPN_FN(cx)(a,5,13); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,7,11); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); }
static inline void IPN_FN(net15)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,10,11); IPN_FN(cx)(a,12,13); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,9,11); IPN_FN(cx)(a,12,14); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,13,14); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,8,12); IPN_FN(cx)(a,9,13); IPN_FN(cx)(a,10,14); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,13,14); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,3,11); IPN_FN(cx)(a,4,12); IPN_FN(cx)(a,5,13); IPN_FN(cx)(a,6,14); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,7,11); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,13,14); }
static inline void IPN_FN(net16)(IPN_T *a) { IPN_FN(cx)(a,0,1); IPN_FN(cx)(a,2,3); IPN_FN(cx)(a,4,5); IPN_FN(cx)(a,6,7); IPN_FN(cx)(a,8,9); IPN_FN(cx)(a,10,11); IPN_FN(cx)(a,12,13); IPN_FN(cx)(a,14,15); IPN_FN(cx)(a,0,2); IPN_FN(cx)(a,1,3); IPN_FN(cx)(a,4,6); IPN_FN(cx)(a,5,7); IPN_FN(cx)(a,8,10); IPN_FN(cx)(a,9,11); IPN_FN(cx)(a,12,14); IPN_FN(cx)(a,13,15); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,13,14); IPN_FN(cx)(a,0,4); IPN_FN(cx)(a,1,5); IPN_FN(cx)(a,2,6); IPN_FN(cx)(a,3,7); IPN_FN(cx)(a,8,12); IPN_FN(cx)(a,9,13); IPN_FN(cx)(a,10,14); IPN_FN(cx)(a,11,15); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,13,14); IPN_FN(cx)(a,0,8); IPN_FN(cx)(a,1,9); IPN_FN(cx)(a,2,10); IPN_FN(cx)(a,3,11); IPN_FN(cx)(a,4,12); IPN_FN(cx)(a,5,13); IPN_FN(cx)(a,6,14); IPN_FN(cx)(a,7,15); IPN_FN(cx)(a,4,8); IPN_FN(cx)(a,5,9); IPN_FN(cx)(a,6,10); IPN_FN(cx)(a,7,11); IPN_FN(cx)(a,2,4); IPN_FN(cx)(a,3,5); IPN_FN(cx)(a,6,8); IPN_FN(cx)(a,7,9); IPN_FN(cx)(a,10,12); IPN_FN(cx)(a,11,13); IPN_FN(cx)(a,1,2); IPN_FN(cx)(a,3,4); IPN_FN(cx)(a,5,6); IPN_FN(cx)(a,7,8); IPN_FN(cx)(a,9,10); IPN_FN(cx)(a,11,12); IPN_FN(cx)(a,13,14); }
static inline void IPN_FN(net_n)(IPN_T *a, long m) {
    switch (m) {
    case 2: IPN_FN(net2)(a); return;
    case 3: IPN_FN(net3)(a); return;
    case 4: IPN_FN(net4)(a); return;
    case 5: IPN_FN(net5)(a); return;
    case 6: IPN_FN(net6)(a); return;
    case 7: IPN_FN(net7)(a); return;
    case 8: IPN_FN(net8)(a); return;
    case 9: IPN_FN(net9)(a); return;
    case 10: IPN_FN(net10)(a); return;
    case 11: IPN_FN(net11)(a); return;
    case 12: IPN_FN(net12)(a); return;
    case 13: IPN_FN(net13)(a); return;
    case 14: IPN_FN(net14)(a); return;
    case 15: IPN_FN(net15)(a); return;
    case 16: IPN_FN(net16)(a); return;
    default: return;
    }
}

/* merge two adjacent sorted runs v[0..h) and v[h..n) (n <= IPN_SMALL): one
 * branchless stream from the front, one from the back, meeting in the middle. */
static void IPN_FN(merge)(IPN_T *v, long h, long n) {
    IPN_T buf[IPN_SMALL];
    long up = n - n / 2, dn = n / 2;
    long i = 0, j = h, k = 0;
    for (long c = 0; c < up; c++) { int tl = (i < h) && (j >= n || v[i] <= v[j]); buf[k++] = tl ? v[i] : v[j]; i += tl; j += !tl; }
    long p = h - 1, q = n - 1, r = n - 1;
    for (long c = 0; c < dn; c++) { int tl = (p >= i) && (q < h || v[p] > v[q]); buf[r--] = tl ? v[p] : v[q]; p -= tl; q -= !tl; }
    memcpy(v, buf, (size_t)n * sizeof(IPN_T));
}
static void IPN_FN(small)(IPN_T *v, long n) {
    if (n < 2) return;
    if (n <= 16) { IPN_FN(net_n)(v, n); return; }
    long h = n / 2;
    IPN_FN(net_n)(v, h);
    IPN_FN(net_n)(v + h, n - h);
    IPN_FN(merge)(v, h, n);
}

/* cyclic branchless Lomuto: partition v[0..n) around `piv`; returns count < piv
 * (those land in v[0..cnt)). A single hole rotates through the array so each
 * element costs two unconditional stores; only the boundary advance branches. */
static size_t IPN_FN(part)(IPN_T *v, size_t n, IPN_T piv) {
    if (n == 0) return 0;
    size_t num_lt = 0, gap = 0, right = 1;
    IPN_T gap_value = v[0];
#define IPN_BODY() do { \
        int is_lt = IPN_LESS(v[right], piv); \
        size_t left = num_lt; \
        v[gap] = v[left]; \
        v[left] = v[right]; \
        gap = right; \
        num_lt += (size_t)is_lt; \
        right++; \
    } while (0)
#if defined(IPN_UNROLL2)
    { size_t quad = 1 + ((n - 1) & ~(size_t)1);
      while (right < quad) { IPN_BODY(); IPN_BODY(); } }
#endif
    while (right < n) { IPN_BODY(); }
#undef IPN_BODY
    { int is_lt = IPN_LESS(gap_value, piv);
      size_t left = num_lt;
      v[gap] = v[left];
      v[left] = gap_value;
      num_lt += (size_t)is_lt; }
    return num_lt;
}
static void IPN_FN(sort3)(IPN_T *a, IPN_T *b, IPN_T *c) {
    if (IPN_LESS(*b, *a)) IPN_SWAP(*a, *b);
    if (IPN_LESS(*c, *b)) IPN_SWAP(*b, *c);
    if (IPN_LESS(*b, *a)) IPN_SWAP(*a, *b);
}
static void IPN_FN(pivot)(IPN_T *v, long n) {
    long s2 = n / 2;
    if (n > 128) {
        IPN_FN(sort3)(&v[0], &v[s2], &v[n - 1]);
        IPN_FN(sort3)(&v[1], &v[s2 - 1], &v[n - 2]);
        IPN_FN(sort3)(&v[2], &v[s2 + 1], &v[n - 3]);
        IPN_FN(sort3)(&v[s2 - 1], &v[s2], &v[s2 + 1]);
    } else {
        IPN_FN(sort3)(&v[0], &v[s2], &v[n - 1]);
    }
    IPN_SWAP(v[0], v[s2]);
}
static void IPN_FN(siftdown)(IPN_T *a, long lo, long n) {
    long r = lo;
    for (;;) {
        long l = 2 * r + 1, rr = 2 * r + 2, m = r;
        if (l < n && IPN_LESS(a[m], a[l])) m = l;
        if (rr < n && IPN_LESS(a[m], a[rr])) m = rr;
        if (m == r) return;
        IPN_SWAP(a[r], a[m]); r = m;
    }
}
static void IPN_FN(heap)(IPN_T *b, long n) {
    for (long i = n / 2 - 1; i >= 0; i--) IPN_FN(siftdown)(b, i, n);
    for (long e = n - 1; e > 0; e--) { IPN_SWAP(b[0], b[e]); IPN_FN(siftdown)(b, 0, e); }
}
static void IPN_FN(qs)(IPN_T *v, long n, int limit) {
    for (;;) {
        if (n <= IPN_SMALL) { IPN_FN(small)(v, n); return; }
        if (limit == 0) { IPN_FN(heap)(v, n); return; }
        IPN_FN(pivot)(v, n);
        IPN_T piv = v[0];
        size_t cnt = IPN_FN(part)(v + 1, (size_t)(n - 1), piv);
        long pp = (long)cnt;
        IPN_SWAP(v[0], v[pp]);
        long l = pp, r = n - pp - 1;
        limit -= (l < n / 8) || (r < n / 8);
        if (l == 0) { /* pivot is the min: skip its equal block to guarantee progress */
            long k = 1; while (k < n && !IPN_LESS(piv, v[k])) k++;
            v += k; n -= k; continue;
        }
        if (l < r) { IPN_FN(qs)(v, l, limit); v += pp + 1; n = r; }
        else       { IPN_FN(qs)(v + pp + 1, r, limit); n = l; }
    }
}
void IPN_FN(sort)(IPN_T *a, long n) {
    if (n < 2) return;
    /* Whole-array run pre-scans, mirroring upstream ipnsort's run
     * detection: already-sorted input is a no-op, reversed input one
     * in-place reverse. ~2 wasted comparisons on random data. */
    long s = 1;
    while (s < n && !IPN_LESS(a[s], a[s - 1])) s++;
    if (s == n) return;
    s = 1;
    while (s < n && !IPN_LESS(a[s - 1], a[s])) s++;
    if (s == n) {
        for (long i = 0, j = n - 1; i < j; i++, j--) IPN_SWAP(a[i], a[j]);
        return;
    }
    int lim = 0; long t = n; while (t >>= 1) lim++;
    IPN_FN(qs)(a, n, 2 * lim);
}

#undef IPN_FN
#undef IPN_LESS
#undef IPN_SWAP
