/* Focused SSA tail oracle: real multiplication, not only an FFT round trip.
 * Reuse the established boxed helpers and GMP oracle. Build under the same
 * release profile as bench_big_math, with both normalization knob values. */
#define main retained_big_math_main
#include "../../bench_big_math.c"
#undef main
#ifndef HAVE_GMP
#error "The SSA normalization check requires GMP"
#endif

static uint64_t check_state = UINT64_C(0x71ef6309d24a5b88);
static unsigned check_count;
static const uint64_t canary = UINT64_C(0x61c9d37efb2045a8);

static void fill_case(uint64_t *a, int32_t n, int pattern) {
    for (int32_t i = 0; i < n; i++) {
        switch (pattern) {
        case 0: a[i] = 0; break;
        case 1: a[i] = i == 0 ? 1 : 0; break;
        case 2: a[i] = UINT64_MAX; break;
        case 3: a[i] = i & 1 ? UINT64_C(0xaaaaaaaaaaaaaaaa)
                               : UINT64_C(0x5555555555555555); break;
        case 4: a[i] = i == 0 || i == n - 1 ? UINT64_MAX : 0; break;
        default: a[i] = bench_rng(&check_state); break;
        }
    }
}

static void check_case(int32_t na, int32_t nb, int pattern,
                       int square, int alias_output) {
    if (square) nb = na;
    size_t an = (size_t)na, bn = (size_t)nb, rn = an + bn;
    uint64_t *a = malloc(an * 8), *b = malloc(bn * 8);
    uint64_t *asave = malloc(an * 8), *bsave = malloc(bn * 8);
    uint64_t *want = calloc(rn, 8), *storage = malloc((rn + 2) * 8);
    if (!a || !b || !asave || !bsave || !want || !storage)
        die("SSA check allocation failure");
    fill_case(a, na, pattern);
    fill_case(b, nb, (pattern + 1) % 6);
    memcpy(asave, a, an * 8); memcpy(bsave, b, bn * 8);
    if (square) mpn_mul_n((mp_ptr)want, (mp_srcptr)a, (mp_srcptr)a, na);
    else if (na >= nb) mpn_mul((mp_ptr)want, (mp_srcptr)a, na, (mp_srcptr)b, nb);
    else mpn_mul((mp_ptr)want, (mp_srcptr)b, nb, (mp_srcptr)a, na);
    storage[0] = storage[rn + 1] = canary;
    for (size_t i = 0; i < rn; i++) storage[i + 1] = UINT64_MAX;
    uint64_t *out = storage + 1;
    const uint64_t *input_a = a;
    if (alias_output) { memcpy(out, a, an * 8); input_a = out; }
    bn_ssa_mul(out, input_a, na, square ? NULL : b, nb);
    if (memcmp(out, want, rn * 8) || storage[0] != canary ||
        storage[rn + 1] != canary || memcmp(a, asave, an * 8) ||
        memcmp(b, bsave, bn * 8)) {
        fprintf(stderr, "SSA mismatch/canary/input clobber na=%d nb=%d pattern=%d square=%d alias=%d\n",
                na, nb, pattern, square, alias_output);
        exit(1);
    }
    check_count++;
    free(a); free(b); free(asave); free(bsave); free(want); free(storage);
}

int main(void) {
    static const int32_t sizes[] = {
        1,2,3,7,8,9,15,16,17,31,32,33,127,128,129,511,512,513,
        2047,2048,2049,4095,4096,4097,8191,8192,8193,
        16383,16384,16385,24575,24576,24577,32767,32768,32769,
        65535,65536,65537,131071,131072,131073
    };
    for (size_t z = 0; z < sizeof sizes / sizeof sizes[0]; z++) {
        int32_t n = sizes[z];
        for (int pattern = 0; pattern < 6; pattern++) {
            check_case(n, n, pattern, 0, 0);
            check_case(n, n, pattern, 1, 0);
        }
        if (n >= 8192) {
            printf("DISPATCH limbs=%d mul=%d sqr=%d (0=Toom,1=SSA,2=NTT)\n",
                   n, bn_top_choice(n,n,0), bn_top_choice(n,n,1));
            fflush(stdout);
        }
    }
    static const int32_t big[] = {16385,32769,65537,131073};
    for (size_t j = 0; j < sizeof big / sizeof big[0]; j++) {
        int32_t n = big[j];
        int32_t ragged[] = {1, n/3+1, n/2+1, n-17};
        for (size_t k = 0; k < sizeof ragged / sizeof ragged[0]; k++) {
            check_case(n, ragged[k], 2, 0, 0);
            check_case(n, ragged[k], 5, 0, 0);
            check_case(n, ragged[k], 5, 0, 1);
        }
        check_case(n,n,2,1,1);
    }
    printf("PASS_SSA_TAIL_GMP cases=%u fused=%d canaries_and_inputs=PASS\n",
           check_count, BN_SSA_NORMALIZE_RECOMPOSE_FUSED);
    fflush(stdout);
    fuzz_boxed_mul_sqr_against_gmp(96,65537);
    printf("PASS_SSA_NORMALIZE_RECOMPOSE focused=%u boxed=96 fused=%d\n",
           check_count, BN_SSA_NORMALIZE_RECOMPOSE_FUSED);
    return 0;
}
