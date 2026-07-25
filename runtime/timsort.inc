/* timsort.inc — adaptive, stable mergesort (Tim Peters), type-specialized.
 *
 * Include with TIM_T (element type) and TIM_SUF (suffix); generates
 * `void tim_sort_<SUF>(TIM_T* a, long n)`. Natural-run detection, minrun
 * binary-insertion, a run stack with the merge invariants, and galloping
 * merges through a temp buffer. O(n) on already-sorted / reversed input,
 * O(n log n) worst case, stable. On random data a pattern-defeating quicksort
 * or radix is faster — timsort's edge is near-sorted data (and stability).
 */
#ifndef TIM_COMMON
#define TIM_COMMON
#define TIM_CAT2(a, b) a##b
#define TIM_CAT(a, b) TIM_CAT2(a, b)
#define TIM_MIN_MERGE 64
#define TIM_MIN_GALLOP 7
#define TIM_MAX_RUNS 128
#endif

#define TIM_FN(name) TIM_CAT(TIM_CAT(tim_##name##_, TIM_SUF), )
#define TIM_LT(a, b) ((a) < (b))
#define TIM_RUN TIM_CAT(tim_run_, TIM_SUF)
#define TIM_MS  TIM_CAT(tim_ms_, TIM_SUF)

typedef struct { TIM_T *base; long len; } TIM_RUN;
typedef struct { TIM_T *tmp; long tmp_cap; long min_gallop; TIM_RUN runs[TIM_MAX_RUNS]; int n_runs; } TIM_MS;

static int TIM_FN(ensure_tmp)(TIM_MS *ms, long need) {
    if (ms->tmp_cap >= need) return 1;
    free(ms->tmp);
    ms->tmp = (TIM_T *)malloc((size_t)need * sizeof(TIM_T));
    ms->tmp_cap = ms->tmp ? need : 0;
    return ms->tmp != NULL;
}
static long TIM_FN(minrun)(long n) { long r = 0; while (n >= TIM_MIN_MERGE) { r |= (n & 1); n >>= 1; } return n + r; }
static long TIM_FN(count_run)(TIM_T *a, long n, int *desc) {
    long i; *desc = 0;
    if (n == 1) return 1;
    if (TIM_LT(a[1], a[0])) { *desc = 1; for (i = 2; i < n && TIM_LT(a[i], a[i-1]); i++) {} }
    else { for (i = 2; i < n && !TIM_LT(a[i], a[i-1]); i++) {} }
    return i;
}
static void TIM_FN(reverse)(TIM_T *a, long n) { long i = 0, j = n - 1; while (i < j) { TIM_T t = a[i]; a[i] = a[j]; a[j] = t; i++; j--; } }
static void TIM_FN(binsort)(TIM_T *a, long n, long start) {
    if (start == 0) start = 1;
    for (; start < n; start++) {
        TIM_T pivot = a[start];
        long left = 0, right = start;
        while (left < right) { long mid = left + ((right - left) >> 1); if (TIM_LT(pivot, a[mid])) right = mid; else left = mid + 1; }
        memmove(&a[left + 1], &a[left], (size_t)(start - left) * sizeof(TIM_T));
        a[left] = pivot;
    }
}
static long TIM_FN(gallop_left)(TIM_T key, TIM_T *a, long n, long hint) {
    long ofs = 1, lastofs = 0, k; a += hint;
    if (TIM_LT(*a, key)) { const long maxofs = n - hint; while (ofs < maxofs) { if (TIM_LT(a[ofs], key)) { lastofs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = maxofs; } else break; } if (ofs > maxofs) ofs = maxofs; lastofs += hint; ofs += hint; }
    else { const long maxofs = hint + 1; while (ofs < maxofs) { if (TIM_LT(a[-ofs], key)) break; lastofs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = maxofs; } if (ofs > maxofs) ofs = maxofs; k = lastofs; lastofs = hint - ofs; ofs = hint - k; }
    a -= hint; ++lastofs;
    while (lastofs < ofs) { long m = lastofs + ((ofs - lastofs) >> 1); if (TIM_LT(a[m], key)) lastofs = m + 1; else ofs = m; }
    return ofs;
}
static long TIM_FN(gallop_right)(TIM_T key, TIM_T *a, long n, long hint) {
    long ofs = 1, lastofs = 0, k; a += hint;
    if (TIM_LT(key, *a)) { const long maxofs = hint + 1; while (ofs < maxofs) { if (TIM_LT(key, a[-ofs])) { lastofs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = maxofs; } else break; } if (ofs > maxofs) ofs = maxofs; k = lastofs; lastofs = hint - ofs; ofs = hint - k; }
    else { const long maxofs = n - hint; while (ofs < maxofs) { if (TIM_LT(key, a[ofs])) break; lastofs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = maxofs; } if (ofs > maxofs) ofs = maxofs; lastofs += hint; ofs += hint; }
    a -= hint; ++lastofs;
    while (lastofs < ofs) { long m = lastofs + ((ofs - lastofs) >> 1); if (TIM_LT(key, a[m])) ofs = m; else lastofs = m + 1; }
    return ofs;
}
static void TIM_FN(merge_lo)(TIM_MS *ms, TIM_T *pa, long na, TIM_T *pb, long nb) {
    TIM_FN(ensure_tmp)(ms, na); memcpy(ms->tmp, pa, (size_t)na * sizeof(TIM_T));
    long min_gallop = ms->min_gallop; TIM_T *pa2 = ms->tmp, *dest = pa;
    *dest++ = *pb++; --nb; if (nb == 0) goto Succeed; if (na == 1) goto CopyB;
    for (;;) {
        long ac = 0, bc = 0;
        for (;;) {
            if (TIM_LT(*pb, *pa2)) { *dest++ = *pb++; ++bc; ac = 0; --nb; if (nb == 0) goto Succeed; if (bc >= min_gallop) break; }
            else { *dest++ = *pa2++; ++ac; bc = 0; --na; if (na == 1) goto CopyB; if (ac >= min_gallop) break; }
        }
        ++min_gallop;
        do {
            min_gallop -= (min_gallop > 1); ms->min_gallop = min_gallop;
            long k = TIM_FN(gallop_right)(*pb, pa2, na, 0); ac = k;
            if (k) { memcpy(dest, pa2, (size_t)k * sizeof(TIM_T)); dest += k; pa2 += k; na -= k; if (na == 1) goto CopyB; if (na == 0) goto Succeed; }
            *dest++ = *pb++; --nb; if (nb == 0) goto Succeed;
            k = TIM_FN(gallop_left)(*pa2, pb, nb, 0); bc = k;
            if (k) { memmove(dest, pb, (size_t)k * sizeof(TIM_T)); dest += k; pb += k; nb -= k; if (nb == 0) goto Succeed; }
            *dest++ = *pa2++; --na; if (na == 1) goto CopyB;
        } while (ac >= TIM_MIN_GALLOP || bc >= TIM_MIN_GALLOP);
        ++min_gallop; ms->min_gallop = min_gallop;
    }
Succeed: if (na) memcpy(dest, pa2, (size_t)na * sizeof(TIM_T)); return;
CopyB: memmove(dest, pb, (size_t)nb * sizeof(TIM_T)); dest[nb] = *pa2; return;
}
static void TIM_FN(merge_hi)(TIM_MS *ms, TIM_T *pa, long na, TIM_T *pb, long nb) {
    TIM_FN(ensure_tmp)(ms, nb); memcpy(ms->tmp, pb, (size_t)nb * sizeof(TIM_T));
    long min_gallop = ms->min_gallop; TIM_T *baseb = ms->tmp, *pa_c = pa + na - 1, *pb_c = baseb + nb - 1, *dest = pb + nb - 1;
    *dest-- = *pa_c--; --na; if (na == 0) goto Succeed; if (nb == 1) goto CopyA;
    for (;;) {
        long ac = 0, bc = 0;
        for (;;) {
            if (TIM_LT(*pb_c, *pa_c)) { *dest-- = *pa_c--; ++ac; bc = 0; --na; if (na == 0) goto Succeed; if (ac >= min_gallop) break; }
            else { *dest-- = *pb_c--; ++bc; ac = 0; --nb; if (nb == 1) goto CopyA; if (bc >= min_gallop) break; }
        }
        ++min_gallop;
        do {
            min_gallop -= (min_gallop > 1); ms->min_gallop = min_gallop;
            long k = TIM_FN(gallop_right)(*pb_c, pa, na, na - 1); k = na - k; ac = k;
            if (k) { dest -= k; pa_c -= k; memmove(dest + 1, pa_c + 1, (size_t)k * sizeof(TIM_T)); na -= k; if (na == 0) goto Succeed; }
            *dest-- = *pb_c--; --nb; if (nb == 1) goto CopyA;
            k = TIM_FN(gallop_left)(*pa_c, baseb, nb, nb - 1); k = nb - k; bc = k;
            if (k) { dest -= k; pb_c -= k; memmove(dest + 1, pb_c + 1, (size_t)k * sizeof(TIM_T)); nb -= k; if (nb == 1) goto CopyA; if (nb == 0) goto Succeed; }
            *dest-- = *pa_c--; --na; if (na == 0) goto Succeed;
        } while (ac >= TIM_MIN_GALLOP || bc >= TIM_MIN_GALLOP);
        ++min_gallop; ms->min_gallop = min_gallop;
    }
Succeed: if (nb) memcpy(dest - (nb - 1), baseb, (size_t)nb * sizeof(TIM_T)); return;
CopyA: dest -= na; pa_c -= na; memmove(dest + 1, pa_c + 1, (size_t)na * sizeof(TIM_T)); *dest = *pb_c; return;
}
static void TIM_FN(merge_at)(TIM_MS *ms, int i) {
    TIM_T *pa = ms->runs[i].base; long na = ms->runs[i].len;
    TIM_T *pb = ms->runs[i+1].base; long nb = ms->runs[i+1].len;
    ms->runs[i].len = na + nb;
    if (i == ms->n_runs - 3) ms->runs[i+1] = ms->runs[i+2];
    ms->n_runs--;
    long k = TIM_FN(gallop_right)(*pb, pa, na, 0); pa += k; na -= k; if (na == 0) return;
    nb = TIM_FN(gallop_left)(pa[na - 1], pb, nb, nb - 1); if (nb <= 0) return;
    if (na <= nb) TIM_FN(merge_lo)(ms, pa, na, pb, nb); else TIM_FN(merge_hi)(ms, pa, na, pb, nb);
}
static void TIM_FN(collapse)(TIM_MS *ms) {
    TIM_RUN *r = ms->runs;
    while (ms->n_runs > 1) {
        int n = ms->n_runs - 2;
        if ((n > 0 && r[n-1].len <= r[n].len + r[n+1].len) || (n > 1 && r[n-2].len <= r[n-1].len + r[n].len)) {
            if (r[n-1].len < r[n+1].len) n--; TIM_FN(merge_at)(ms, n);
        } else if (r[n].len <= r[n+1].len) { TIM_FN(merge_at)(ms, n); } else break;
    }
}
static void TIM_FN(force_collapse)(TIM_MS *ms) {
    TIM_RUN *r = ms->runs;
    while (ms->n_runs > 1) { int n = ms->n_runs - 2; if (n > 0 && r[n-1].len < r[n+1].len) n--; TIM_FN(merge_at)(ms, n); }
}
void TIM_FN(sort)(TIM_T *a, long n) {
    if (n < 2) return;
    TIM_MS ms; ms.tmp = NULL; ms.tmp_cap = 0; ms.min_gallop = TIM_MIN_GALLOP; ms.n_runs = 0;
    long minrun = TIM_FN(minrun)(n); TIM_T *lo = a; long remaining = n;
    do {
        int desc; long run_len = TIM_FN(count_run)(lo, remaining, &desc);
        if (desc) TIM_FN(reverse)(lo, run_len);
        if (run_len < minrun) { long force = remaining < minrun ? remaining : minrun; TIM_FN(binsort)(lo, force, run_len); run_len = force; }
        ms.runs[ms.n_runs].base = lo; ms.runs[ms.n_runs].len = run_len; ms.n_runs++;
        TIM_FN(collapse)(&ms); lo += run_len; remaining -= run_len;
    } while (remaining > 0);
    TIM_FN(force_collapse)(&ms); free(ms.tmp);
}

#undef TIM_FN
#undef TIM_LT
#undef TIM_RUN
#undef TIM_MS
