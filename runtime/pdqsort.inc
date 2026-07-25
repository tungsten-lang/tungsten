/* pdqsort.inc — pattern-defeating quicksort (Orson Peters), type-specialized.
 *
 * Include with PDQ_T (element type, e.g. uint32_t) and PDQ_SUF (name suffix,
 * e.g. u32) defined; generates `void pdq_sort_<SUF>(PDQ_T* a, long n)` and its
 * static helpers. Comparison is `<` on PDQ_T (so integer arrays sort by the
 * type's own ordering — instantiate with the unsigned type to match the
 * runtime's existing typed-array sort semantics).
 *
 * Beats libc qsort ~4x on random data: inlined comparisons (no callback) plus
 * branchless block partitioning. Internally size-adaptive: insertion sort for
 * runs < 24, branchless quicksort above, heapsort fallback (introsort) to
 * guarantee O(n log n) on adversarial input, and already-sorted detection.
 */
#ifndef PDQ_COMMON
#define PDQ_COMMON
#define PDQ_CAT2(a, b) a##b
#define PDQ_CAT(a, b) PDQ_CAT2(a, b)
#define PDQ_INSERTION_THRESHOLD 24
#define PDQ_NINTHER_THRESHOLD 128
#define PDQ_PARTIAL_LIMIT 8
#define PDQ_BLOCK 64
#endif

#define PDQ_FN(name) PDQ_CAT(PDQ_CAT(pdq_##name##_, PDQ_SUF), )
#define PDQ_LESS(a, b) ((a) < (b))
#define PDQ_SWAP(x, y) do { PDQ_T _pt = (x); (x) = (y); (y) = _pt; } while (0)

static void PDQ_FN(insertion)(PDQ_T *begin, PDQ_T *end) {
    if (begin == end) return;
    for (PDQ_T *cur = begin + 1; cur != end; ++cur) {
        PDQ_T *sift = cur, *sift1 = cur - 1;
        if (PDQ_LESS(*sift, *sift1)) {
            PDQ_T tmp = *sift;
            do { *sift-- = *sift1; } while (sift != begin && PDQ_LESS(tmp, *--sift1));
            *sift = tmp;
        }
    }
}
static void PDQ_FN(uinsertion)(PDQ_T *begin, PDQ_T *end) {
    if (begin == end) return;
    for (PDQ_T *cur = begin + 1; cur != end; ++cur) {
        PDQ_T *sift = cur, *sift1 = cur - 1;
        if (PDQ_LESS(*sift, *sift1)) {
            PDQ_T tmp = *sift;
            do { *sift-- = *sift1; } while (PDQ_LESS(tmp, *--sift1));
            *sift = tmp;
        }
    }
}
static int PDQ_FN(partial)(PDQ_T *begin, PDQ_T *end) {
    if (begin == end) return 1;
    long limit = 0;
    for (PDQ_T *cur = begin + 1; cur != end; ++cur) {
        PDQ_T *sift = cur, *sift1 = cur - 1;
        if (PDQ_LESS(*sift, *sift1)) {
            PDQ_T tmp = *sift;
            do { *sift-- = *sift1; } while (sift != begin && PDQ_LESS(tmp, *--sift1));
            *sift = tmp;
            limit += (long)(cur - sift);
        }
        if (limit > PDQ_PARTIAL_LIMIT) return 0;
    }
    return 1;
}
static void PDQ_FN(sort2)(PDQ_T *a, PDQ_T *b) { if (PDQ_LESS(*b, *a)) PDQ_SWAP(*a, *b); }
static void PDQ_FN(sort3)(PDQ_T *a, PDQ_T *b, PDQ_T *c) {
    PDQ_FN(sort2)(a, b); PDQ_FN(sort2)(b, c); PDQ_FN(sort2)(a, b);
}
static void PDQ_FN(swapoff)(PDQ_T *obl, PDQ_T *obr, unsigned char *ol, unsigned char *orr, size_t num, int use_swaps) {
    if (use_swaps) {
        for (size_t i = 0; i < num; i++) PDQ_SWAP(*(obl + ol[i]), *(obr - orr[i]));
    } else if (num > 0) {
        PDQ_T *l = obl + ol[0], *r = obr - orr[0];
        PDQ_T tmp = *l; *l = *r;
        for (size_t i = 1; i < num; i++) { l = obl + ol[i]; *r = *l; r = obr - orr[i]; *l = *r; }
        *r = tmp;
    }
}
static PDQ_T *PDQ_FN(part_right)(PDQ_T *begin, PDQ_T *end, int *already_part) {
    PDQ_T pivot = *begin;
    PDQ_T *first = begin, *last = end;
    while (PDQ_LESS(*++first, pivot));
    if (first - 1 == begin) while (first < last && !PDQ_LESS(*--last, pivot));
    else                    while (               !PDQ_LESS(*--last, pivot));
    int already = (first >= last);
    *already_part = already;
    if (!already) {
        PDQ_SWAP(*first, *last);
        ++first;
        unsigned char ol[PDQ_BLOCK], orr[PDQ_BLOCK];
        PDQ_T *obl = first, *obr = last;
        size_t num_l = 0, num_r = 0, start_l = 0, start_r = 0;
        while (first < last) {
            size_t num_unknown = (size_t)(last - first);
            size_t left_split  = (num_l == 0) ? ((num_r == 0) ? num_unknown / 2 : num_unknown) : 0;
            size_t right_split = (num_r == 0) ? (num_unknown - left_split) : 0;
            if (left_split >= PDQ_BLOCK) {
                for (size_t i = 0; i < PDQ_BLOCK;) {
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                    ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first;
                }
            } else {
                for (size_t i = 0; i < left_split;) { ol[num_l] = (unsigned char)i++; num_l += !PDQ_LESS(*first, pivot); ++first; }
            }
            if (right_split >= PDQ_BLOCK) {
                for (size_t i = 0; i < PDQ_BLOCK;) {
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                    orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot);
                }
            } else {
                for (size_t i = 0; i < right_split;) { orr[num_r] = (unsigned char)++i; num_r += PDQ_LESS(*--last, pivot); }
            }
            size_t num = num_l < num_r ? num_l : num_r;
            PDQ_FN(swapoff)(obl, obr, ol + start_l, orr + start_r, num, num_l == num_r);
            num_l -= num; num_r -= num; start_l += num; start_r += num;
            if (num_l == 0) { start_l = 0; obl = first; }
            if (num_r == 0) { start_r = 0; obr = last; }
        }
        if (num_l) {
            unsigned char *olp = ol + start_l;
            while (num_l--) { --last; PDQ_SWAP(*(obl + olp[num_l]), *last); }
            first = last;
        }
        if (num_r) {
            unsigned char *orp = orr + start_r;
            while (num_r--) { PDQ_SWAP(*(obr - orp[num_r]), *first); ++first; }
            last = first;
        }
    }
    PDQ_T *pivot_pos = first - 1;
    *begin = *pivot_pos;
    *pivot_pos = pivot;
    return pivot_pos;
}
static PDQ_T *PDQ_FN(part_left)(PDQ_T *begin, PDQ_T *end) {
    PDQ_T pivot = *begin;
    PDQ_T *first = begin, *last = end;
    while (PDQ_LESS(pivot, *--last));
    if (last + 1 == end) while (first < last && !PDQ_LESS(pivot, *++first));
    else                 while (                !PDQ_LESS(pivot, *++first));
    while (first < last) {
        PDQ_SWAP(*first, *last);
        while (PDQ_LESS(pivot, *--last));
        while (!PDQ_LESS(pivot, *++first));
    }
    PDQ_T *pivot_pos = last;
    *begin = *pivot_pos;
    *pivot_pos = pivot;
    return pivot_pos;
}
static void PDQ_FN(siftdown)(PDQ_T *a, long lo, long n) {
    long r = lo;
    for (;;) {
        long l = 2 * r + 1, rr = 2 * r + 2, m = r;
        if (l < n && PDQ_LESS(a[m], a[l])) m = l;
        if (rr < n && PDQ_LESS(a[m], a[rr])) m = rr;
        if (m == r) return;
        PDQ_SWAP(a[r], a[m]); r = m;
    }
}
static void PDQ_FN(heap)(PDQ_T *begin, long n) {
    for (long i = n / 2 - 1; i >= 0; i--) PDQ_FN(siftdown)(begin, i, n);
    for (long e = n - 1; e > 0; e--) { PDQ_SWAP(begin[0], begin[e]); PDQ_FN(siftdown)(begin, 0, e); }
}
static void PDQ_FN(loop)(PDQ_T *begin, PDQ_T *end, int bad_allowed, int leftmost) {
    for (;;) {
        long size = end - begin;
        if (size < PDQ_INSERTION_THRESHOLD) {
            if (leftmost) PDQ_FN(insertion)(begin, end);
            else PDQ_FN(uinsertion)(begin, end);
            return;
        }
        long s2 = size / 2;
        if (size > PDQ_NINTHER_THRESHOLD) {
            PDQ_FN(sort3)(begin, begin + s2, end - 1);
            PDQ_FN(sort3)(begin + 1, begin + (s2 - 1), end - 2);
            PDQ_FN(sort3)(begin + 2, begin + (s2 + 1), end - 3);
            PDQ_FN(sort3)(begin + (s2 - 1), begin + s2, begin + (s2 + 1));
            PDQ_SWAP(*begin, *(begin + s2));
        } else {
            PDQ_FN(sort3)(begin + s2, begin, end - 1);
        }
        if (!leftmost && !PDQ_LESS(*(begin - 1), *begin)) {
            begin = PDQ_FN(part_left)(begin, end) + 1;
            continue;
        }
        int already_part;
        PDQ_T *pivot_pos = PDQ_FN(part_right)(begin, end, &already_part);
        long l_size = pivot_pos - begin;
        long r_size = end - (pivot_pos + 1);
        int highly_unbalanced = (l_size < size / 8) || (r_size < size / 8);
        if (highly_unbalanced) {
            if (--bad_allowed == 0) { PDQ_FN(heap)(begin, size); return; }
            if (l_size >= PDQ_INSERTION_THRESHOLD) {
                PDQ_SWAP(*begin, *(begin + l_size / 4));
                PDQ_SWAP(*(pivot_pos - 1), *(pivot_pos - l_size / 4));
                if (l_size > PDQ_NINTHER_THRESHOLD) {
                    PDQ_SWAP(*(begin + 1), *(begin + (l_size / 4 + 1)));
                    PDQ_SWAP(*(begin + 2), *(begin + (l_size / 4 + 2)));
                    PDQ_SWAP(*(pivot_pos - 2), *(pivot_pos - (l_size / 4 + 1)));
                    PDQ_SWAP(*(pivot_pos - 3), *(pivot_pos - (l_size / 4 + 2)));
                }
            }
            if (r_size >= PDQ_INSERTION_THRESHOLD) {
                PDQ_SWAP(*(pivot_pos + 1), *(pivot_pos + (1 + r_size / 4)));
                PDQ_SWAP(*(end - 1), *(end - r_size / 4));
                if (r_size > PDQ_NINTHER_THRESHOLD) {
                    PDQ_SWAP(*(pivot_pos + 2), *(pivot_pos + (2 + r_size / 4)));
                    PDQ_SWAP(*(pivot_pos + 3), *(pivot_pos + (3 + r_size / 4)));
                    PDQ_SWAP(*(end - 2), *(end - (1 + r_size / 4)));
                    PDQ_SWAP(*(end - 3), *(end - (2 + r_size / 4)));
                }
            }
        } else {
            if (already_part && PDQ_FN(partial)(begin, pivot_pos) && PDQ_FN(partial)(pivot_pos + 1, end)) return;
        }
        PDQ_FN(loop)(begin, pivot_pos, bad_allowed, leftmost);
        begin = pivot_pos + 1;
        leftmost = 0;
    }
}
void PDQ_FN(sort)(PDQ_T *a, long n) {
    if (n < 2) return;
    int bad = 0; long t = n; while (t >>= 1) bad++;
    PDQ_FN(loop)(a, a + n, bad, 1);
}

#undef PDQ_FN
#undef PDQ_LESS
#undef PDQ_SWAP
