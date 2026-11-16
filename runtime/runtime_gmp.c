#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define die w_rt_die
#define die_as w_rt_die_as
#define bigint_box w_rt_bigint_box
#define bn_copy_tail w_rt_bn_copy_tail
#define bigint_alloc w_rt_bigint_alloc
#define bigint_alloc_raw w_rt_bigint_alloc_raw
#define bigint_alloc_raw_hot w_rt_bigint_alloc_raw_hot
#define bigint_alloc_raw_hot_exact w_rt_bigint_alloc_raw_hot_exact
#define bigint_release w_rt_bigint_release
#define bigint_release_if_live w_rt_bigint_release_if_live
#define bigint_normalize w_rt_bigint_normalize
#define bigint_finish_mag_sub w_rt_bigint_finish_mag_sub
#define bigint_finish_one_limb w_rt_bigint_finish_one_limb
#define bigint_finish_div1 w_rt_bigint_finish_div1
#define integer_limbs w_rt_integer_limbs
#define integer_low_i64 w_rt_integer_low_i64
#define bigint_compare w_rt_bigint_compare
#define bigint_compare_c w_rt_bigint_compare
#define bigint_compare_mag w_rt_bigint_compare_mag
#define mag_cmp w_rt_mag_cmp
#define bn_add_n w_rt_bn_add_n
#define bn_sub_n w_rt_bn_sub_n
#define bn_mul_1 w_rt_bn_mul_1
#define bn_addmul_1 w_rt_bn_addmul_1
#define bigint_mul_schoolbook_into w_rt_bigint_mul_schoolbook_into
#define bn_modinv_odd w_rt_bn_modinv_odd
#define bn_div_qr_preinv w_rt_bn_div_qr_preinv
#define mag_div_single w_rt_mag_div_single
#define mag_mod_single w_rt_mag_mod_single
#define mag_div_84 w_rt_mag_div_84
#define mag_mod_63 w_rt_mag_mod_63
#define mag_mod_42 w_rt_mag_mod_42
#define mag_divmod w_rt_mag_divmod
#define mag_divexact w_rt_mag_divexact
#define mag_mod_binary w_rt_mag_mod_binary
#define bn_isqrt_u128 w_rt_bn_isqrt_u128
#define w_prime_test_u64 w_rt_prime_test_u64
#define w_int_bit_length w_rt_int_bit_length
static inline WValue bigint_pair_array(WValue first, WValue second) {
    WValue arr = w_array_new_inline(65, 2);
    WArray *a = w_as_array(arr);
    a->size = 2;
    a->slots[0] = w_is_bigint(first) ? w_bigint_mark_shared_value(first) : first;
    a->slots[1] = w_is_bigint(second) ? w_bigint_mark_shared_value(second) : second;
    return arr;
}

static inline WValue bigint_triple_array(WValue first, WValue second, WValue third) {
    WValue arr = w_array_new_inline(65, 3);
    WArray *a = w_as_array(arr);
    a->size = 3;
    a->slots[0] = w_is_bigint(first) ? w_bigint_mark_shared_value(first) : first;
    a->slots[1] = w_is_bigint(second) ? w_bigint_mark_shared_value(second) : second;
    a->slots[2] = w_is_bigint(third) ? w_bigint_mark_shared_value(third) : third;
    return arr;
}

static inline int64_t bigint_arg_i64(WValue v) {
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_bigint(v)) return w_to_i64(v);
    return (int64_t)v;
}

static inline int bigint_val_sign(WValue v) {
    if (w_is_int(v)) {
        int64_t x = w_as_int(v);
        return (x > 0) - (x < 0);
    }
    if (w_is_bigint(v)) {
        int32_t sz = 0;
        (void)w_bigint_view(v, &sz);
        return (sz > 0) - (sz < 0);
    }
    return 0;
}

static inline void bigint_temp_release(WValue v, WValue keep1, WValue keep2) {
    if (!w_is_bigint(v)) return;
    WBigint *vb = w_as_bigint(v);
    if (w_is_bigint(keep1) && vb == w_as_bigint(keep1)) return;
    if (w_is_bigint(keep2) && vb == w_as_bigint(keep2)) return;
    bigint_release_if_live(vb);
}

static void bigint_tdivmod_pair(WValue a, WValue b, WValue *q_out, WValue *r_out) {
    if (w_both_ints(a, b)) {
        int64_t av = w_as_int(a);
        int64_t bv = w_as_int(b);
        if (__builtin_expect(bv == 0, 0)) die_as("ZeroDivisionError", "division by zero");
        *q_out = w_int(av / bv);
        *r_out = w_int(av % bv);
        return;
    }
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    const uint64_t *bp = integer_limbs(b, &sb, &blen);
    int32_t an = alen < 0 ? -alen : alen;
    int32_t bn = blen < 0 ? -blen : blen;
    if (__builtin_expect(bn == 0, 0)) die_as("ZeroDivisionError", "division by zero");
    if (an == 0 || mag_cmp(ap, an, bp, bn) < 0) {
        *q_out = w_box_int(0);
        *r_out = w_is_bigint(a) ? w_bigint_mark_shared_value(a) : a;
        return;
    }
    int q_neg = (alen < 0) != (blen < 0);
    int r_neg = (alen < 0);
    if (bn == 1) {
        uint64_t rem = 0;
        WBigint *q_mag = mag_div_single(ap, an, bp[0], &rem);
        if (q_neg && q_mag->size > 0) q_mag->size = -q_mag->size;
        *q_out = bigint_normalize(q_mag);
        if (rem == 0) {
            *r_out = w_box_int(0);
        } else if (r_neg) {
            *r_out = (rem <= (uint64_t)W_INT48_MAX) ? w_box_int(-(int64_t)rem) : w_neg(w_u64(rem));
        } else {
            *r_out = w_u64(rem);
        }
        return;
    }
    WBigint *q_mag = NULL, *r_mag = NULL;
    mag_divmod(ap, an, bp, bn, &q_mag, &r_mag);
    if (q_neg && q_mag->size > 0) q_mag->size = -q_mag->size;
    if (r_neg && r_mag->size > 0) r_mag->size = -r_mag->size;
    *q_out = bigint_normalize(q_mag);
    *r_out = bigint_normalize(r_mag);
}

#endif

static inline int bigint_divisible_p_c(WValue a, WValue d) {
    if (__builtin_expect(
            (((a ^ W_TAG_BIGINT) | (d ^ W_TAG_BIGINT)) &
             (W_TAG_MASK | W_BIGINT_SIGN_BIT)) == 0,
            1)) {
        WBigint *aa = w_as_bigint(a);
        WBigint *dd = w_as_bigint(d);
        int32_t an = aa->size;
        int32_t dn = dd->size;
        if (__builtin_expect(an > 0 && dn > 0, 1)) {
            if (an < dn) return 0;
            const uint64_t *ap = aa->limbs;
            const uint64_t *dp = dd->limbs;
            if (dn == 1) {
                uint64_t d0 = dp[0];
                int tz = __builtin_ctzll(d0);
                if (tz > 0 && (ap[0] & ((1ULL << tz) - 1ULL)) != 0) return 0;
                uint64_t d_odd = d0 >> tz;
                uint64_t inv = bn_modinv_odd(d_odd);
                if (an == 2) {
                    uint64_t a0 = (tz == 0) ? ap[0] : ((ap[0] >> tz) | (ap[1] << (64 - tz)));
                    uint64_t a1 = ap[1] >> tz;
                    if (a1 >= d_odd) {
                        if ((d_odd >> 63) != 0 || a1 - d_odd < d_odd) a1 -= d_odd;
                        else a1 %= d_odd;
                    }
                    uint64_t q0 = a0 * inv;
                    uint64_t hi = (uint64_t)(((__uint128_t)q0 * d_odd) >> 64);
                    return hi == a1;
                }
                if (an == 1) {
                    uint64_t a0 = ap[0] >> tz;
                    uint64_t q0 = a0 * inv;
                    return ((__uint128_t)q0 * d_odd) == (__uint128_t)a0;
                }
            } else if (an == 8 && dn == 4 && (dp[0] & 1ULL) != 0) {
                /* Fast 8/4 Hensel divisibility check in registers/stack without allocation. */
                uint64_t r[8];
                memcpy(r, ap, 8 * sizeof(uint64_t));
                uint64_t inv = bn_modinv_odd(dp[0]);
                for (int32_t i = 0; i < 4; i++) {
                    uint64_t qi = r[i] * inv;
                    uint64_t bw = bn_submul_1(r + i, dp, 4, qi);
                    for (int32_t k = i + 4; bw && k < 8; k++) {
                        uint64_t old = r[k];
                        r[k] = old - bw;
                        bw = (old < bw);
                    }
                    if (bw) return 0;
                }
                uint64_t q4 = r[4] * inv;
                if ((__uint128_t)q4 * dp[3] > (__uint128_t)r[7]) return 0;
                if (q4 == 0) return (r[4] | r[5] | r[6] | r[7]) == 0;
                uint64_t bw = bn_submul_1(r + 4, dp, 4, q4);
                return bw == 0 && (r[4] | r[5] | r[6] | r[7]) == 0;
            }
        }
    }
    if (w_both_ints(a, d)) {
        int64_t av = w_as_int(a);
        int64_t dv = w_as_int(d);
        if (dv == 0) return av == 0;
        return (av % dv == 0);
    }
    uint64_t sa, sd;
    int32_t alen, dlen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    const uint64_t *dp = integer_limbs(d, &sd, &dlen);
    int32_t an = alen < 0 ? -alen : alen;
    int32_t dn = dlen < 0 ? -dlen : dlen;
    if (an == 0) return 1;
    if (dn == 0) return 0;
    if (an < dn) return 0;
    int32_t zl = 0;
    while (zl < dn && dp[zl] == 0) {
        if (ap[zl] != 0) return 0;
        zl++;
    }
    ap += zl;
    an -= zl;
    dp += zl;
    dn -= zl;
    int tz = __builtin_ctzll(dp[0]);
    if (tz > 0 && ap[0] != 0 && __builtin_ctzll(ap[0]) < tz) {
        return 0;
    }
    if (dn == 1) {
        return mag_mod_single(ap, an, dp[0]) == 0;
    }
    if (an == dn) {
        int cmp = mag_cmp(ap, an, dp, dn);
        if (cmp < 0) return 0;
        if (cmp == 0) return 1;
    }
    if (an <= 64) {
        uint64_t r[64], dstack[64];
        const uint64_t *dsh;
        if (tz == 0) {
            dsh = dp;
            memcpy(r, ap, (size_t)an * sizeof(uint64_t));
        } else {
            for (int32_t i = 0; i < dn; i++) {
                uint64_t hi = (i + 1 < dn) ? dp[i + 1] : 0;
                dstack[i] = (dp[i] >> tz) | (hi << (64 - tz));
            }
            if (dstack[dn - 1] == 0) dn--;
            dsh = dstack;
            for (int32_t i = 0; i < an; i++) {
                uint64_t hi = (i + 1 < an) ? ap[i + 1] : 0;
                r[i] = (ap[i] >> tz) | (hi << (64 - tz));
            }
            if (r[an - 1] == 0 && an > dn) an--;
        }
        if (dn == 1) {
            return mag_mod_single(r, an, dsh[0]) == 0;
        }
        uint64_t inv = bn_modinv_odd(dsh[0]);
        int32_t m = an - dn;
        for (int32_t i = 0; i < m; i++) {
            uint64_t qi = r[i] * inv;
            if (qi != 0) {
                uint64_t bw = bn_submul_1(r + i, dsh, dn, qi);
                for (int32_t k = i + dn; bw && k < an; k++) {
                    uint64_t old = r[k];
                    r[k] = old - bw;
                    bw = (old < bw);
                }
                if (bw) return 0;
            }
        }
        uint64_t qm = r[m] * inv;
        if ((__uint128_t)qm * dsh[dn - 1] > (__uint128_t)r[an - 1]) return 0;
        if (qm != 0) {
            if (bn_submul_1(r + m, dsh, dn, qm) != 0) return 0;
        }
        for (int32_t j = m; j < an; j++) {
            if (r[j] != 0) return 0;
        }
        return 1;
    }
    WBigint *q = NULL, *r = NULL;
    mag_divmod(ap, an, dp, dn, &q, &r);
    int res = (r->size == 0);
    bigint_release(q);
    bigint_release(r);
    return res;
}

WValue w_bigint_divisible_p(WValue a, WValue d) {
    return bigint_divisible_p_c(a, d) ? W_TRUE : W_FALSE;
}

WValue w_bigint_congruent_p(WValue a, WValue c, WValue d) {
    WValue diff = bigint_sub_any(a, c);
    WValue res = w_bigint_divisible_p(diff, d);
    bigint_temp_release(diff, a, c);
    return res;
}

WValue w_bigint_isqrt_rem(WValue a) {
    if (w_is_int(a)) {
        int64_t n = w_as_int(a);
        if (n < 0) die_as("DomainError", "isqrt of negative number");
        uint64_t r0 = (uint64_t)__builtin_sqrt((double)n);
        return bigint_pair_array(w_box_int((int64_t)r0), w_box_int(n - (int64_t)(r0 * r0)));
    }
    if (bigint_val_sign(a) < 0) {
        die_as("DomainError", "isqrt of negative number");
    }
    if (w_is_bigint(a)) {
        WBigint *ba = w_as_bigint(a);
        int32_t alen = ba->size;
        if (alen <= 2) {
            if (alen == 0) return bigint_pair_array(w_box_int(0), w_box_int(0));
            unsigned __int128 v = alen == 2
                ? (((unsigned __int128)ba->limbs[1] << 64) | ba->limbs[0])
                : (unsigned __int128)ba->limbs[0];
            uint64_t root = bn_isqrt_u128(v);
            unsigned __int128 rem = v - (unsigned __int128)root * root;
            return bigint_pair_array(w_u64(root), w_u128(rem));
        }
    }
    WValue s = bigint_isqrt_any(a);
    WValue s2 = bigint_mul_any(s, s);
    WValue r = bigint_sub_any(a, s2);
    bigint_temp_release(s2, a, s);
    return bigint_pair_array(s, r);
}

static inline int u64_pow_le_c(uint64_t base, int64_t exp, uint64_t target, uint64_t *pow_out) {
    if (base <= 1) {
        *pow_out = base;
        return 1;
    }
    unsigned __int128 acc = 1;
    for (int64_t i = 0; i < exp; i++) {
        acc *= (unsigned __int128)base;
        if (acc > (unsigned __int128)target) {
            *pow_out = 0;
            return 0;
        }
    }
    *pow_out = (uint64_t)acc;
    return 1;
}

static inline WValue bigint_pow_nm1_c(WValue x, int64_t nm1) {
    if (nm1 == 1) return x;
    if (nm1 == 2) return bigint_mul_any(x, x);
    return w_pow(x, w_int(nm1));
}

/* Compute x^3 into 5 limbs for x < 2^86. */
static inline void u128_cube_5limbs(unsigned __int128 x, uint64_t out[5]) {
    uint64_t xlo = (uint64_t)x, xhi = (uint64_t)(x >> 64);
    unsigned __int128 p00 = (unsigned __int128)xlo * xlo;
    unsigned __int128 mid = (p00 >> 64) + (((unsigned __int128)xlo * xhi) << 1);
    uint64_t sq0 = (uint64_t)p00;
    uint64_t sq1 = (uint64_t)mid;
    uint64_t sq2 = (uint64_t)(mid >> 64) + xhi * xhi;
    unsigned __int128 c0 = (unsigned __int128)sq0 * xlo;
    out[0] = (uint64_t)c0;
    unsigned __int128 a1 = (c0 >> 64) + (unsigned __int128)sq1 * xlo;
    unsigned __int128 b1 = (unsigned __int128)sq0 * xhi;
    uint64_t lo1 = (uint64_t)a1 + (uint64_t)b1;
    out[1] = lo1;
    uint64_t cy1 = (uint64_t)(a1 >> 64) + (uint64_t)(b1 >> 64) + (lo1 < (uint64_t)a1);
    unsigned __int128 a2 = (unsigned __int128)cy1 + (unsigned __int128)sq2 * xlo + (unsigned __int128)sq1 * xhi;
    out[2] = (uint64_t)a2;
    unsigned __int128 c3 = (a2 >> 64) + (unsigned __int128)sq2 * xhi;
    out[3] = (uint64_t)c3;
    out[4] = (uint64_t)(c3 >> 64);
}

static inline int cube5_le_mag(const uint64_t cube[5], const uint64_t *ap, int32_t an) {
    for (int32_t i = 4; i >= an; i--) {
        if (cube[i] != 0) return 0;
    }
    for (int32_t i = an - 1; i >= 0; i--) {
        if (cube[i] != ap[i]) return cube[i] < ap[i];
    }
    return 1;
}

static void bigint_iroot_rem_pair(WValue a, WValue n_val, WValue *root_out, WValue *rem_out) {
    int64_t n = bigint_arg_i64(n_val);
    if (n <= 0) die_as("DomainError", "iroot degree must be positive");
    int sign_a = bigint_val_sign(a);
    if (sign_a < 0 && (n & 1) == 0) {
        die_as("DomainError", "even root of negative number");
    }
    if (sign_a == 0) {
        *root_out = w_box_int(0);
        if (rem_out) *rem_out = w_box_int(0);
        return;
    }
    if (n == 1) {
        *root_out = w_is_bigint(a) ? w_bigint_mark_shared_value(a) : a;
        if (rem_out) *rem_out = w_box_int(0);
        return;
    }
    uint64_t sa;
    int32_t alen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    int32_t an = alen < 0 ? -alen : alen;
    if (an == 1 && ap[0] == 1ULL) {
        *root_out = w_box_int(sign_a < 0 ? -1 : 1);
        if (rem_out) *rem_out = w_box_int(0);
        return;
    }
    if (an == 1 && n >= 3) {
        uint64_t v = ap[0];
        uint64_t r = 1, p = 1;
        if (n < 64) {
            r = (uint64_t)(n == 3 ? cbrt((double)v) : pow((double)v, 1.0 / (double)n));
            if (r == 0) r = 1;
            while (!u64_pow_le_c(r, n, v, &p)) r--;
            uint64_t p_next = 0;
            while (u64_pow_le_c(r + 1, n, v, &p_next)) {
                r++;
                p = p_next;
            }
        }
        *root_out = w_box_int(sign_a < 0 ? -(int64_t)r : (int64_t)r);
        if (rem_out) {
            uint64_t rem_u = v - p;
            *rem_out = bigint_finish_one_limb(rem_u, sign_a < 0);
        }
        return;
    }
    /* Fast path for cube root of 2..4 limb integers: root <= 86 bits fits in __uint128_t,
     * cbrt(double) gives 53 bits of accuracy, and at most 1 Newton step in stack limbs
     * converges to within +-1 of the exact root. */
    if (n == 3 && an <= 4) {
        int fexp;
        double dval = ldexp((double)ap[an - 1], 64) + (double)ap[an - 2];
        if (an >= 3) dval += ldexp((double)ap[an - 3], -64);
        double m = frexp(dval, &fexp);
        int64_t total_exp = (int64_t)(an - 2) * 64 + fexp;
        int64_t q_exp = total_exp / 3;
        int r_exp = (int)(total_exp - q_exp * 3);
        if (r_exp < 0) { r_exp += 3; q_exp--; }
        double root_m = cbrt(ldexp(m, r_exp));
        int rm_exp;
        double rm_frac = frexp(root_m, &rm_exp);
        uint64_t mant53 = (uint64_t)ldexp(rm_frac, 53);
        int64_t shift = q_exp + rm_exp - 53;
        unsigned __int128 x = (shift >= 0)
            ? ((unsigned __int128)mant53 << shift)
            : ((unsigned __int128)mant53 >> (-shift));
        if (x == 0) x = 1;
        if (shift > 0) {
            /* 1 Newton step: x = (2*x + floor(a / x^2)) / 3 */
            uint64_t xlo = (uint64_t)x, xhi = (uint64_t)(x >> 64);
            unsigned __int128 p00 = (unsigned __int128)xlo * xlo;
            unsigned __int128 mid = (p00 >> 64) + (((unsigned __int128)xlo * xhi) << 1);
            uint64_t sq[3] = { (uint64_t)p00, (uint64_t)mid, (uint64_t)(mid >> 64) + xhi * xhi };
            int32_t sqlen = sq[2] ? 3 : (sq[1] ? 2 : 1);
            WBigint *q_bi = NULL;
            mag_divmod(ap, an, sq, sqlen, &q_bi, NULL);
            unsigned __int128 q = 0;
            if (q_bi->size >= 2) q = ((unsigned __int128)q_bi->limbs[1] << 64) | q_bi->limbs[0];
            else if (q_bi->size == 1) q = q_bi->limbs[0];
            bigint_release(q_bi);
            x = (2 * x + q) / 3;
        }
        uint64_t cube[5], next_cube[5];
        u128_cube_5limbs(x, cube);
        while (!cube5_le_mag(cube, ap, an)) {
            x--;
            u128_cube_5limbs(x, cube);
        }
        u128_cube_5limbs(x + 1, next_cube);
        while (cube5_le_mag(next_cube, ap, an)) {
            x++;
            memcpy(cube, next_cube, sizeof(cube));
            u128_cube_5limbs(x + 1, next_cube);
        }
        WValue rx = w_u128(x);
        *root_out = sign_a < 0 ? w_neg(rx) : rx;
        if (rem_out) {
            WBigint *rem_bi = bigint_alloc_raw_hot(an);
            (void)bn_sub_n(rem_bi->limbs, ap, cube, an);
            int32_t rsz = an;
            while (rsz > 0 && rem_bi->limbs[rsz - 1] == 0) rsz--;
            rem_bi->size = (sign_a < 0 && rsz > 0) ? -rsz : rsz;
            *rem_out = bigint_finish_mag_sub(rem_bi);
        }
        return;
    }
    WValue abs_a = sign_a < 0 ? w_neg(a) : a;
    if (n == 2) {
        WValue s = bigint_isqrt_any(abs_a);
        if (rem_out) {
            WValue s2 = bigint_mul_any(s, s);
            *rem_out = bigint_sub_any(abs_a, s2);
            bigint_temp_release(s2, a, s);
        }
        bigint_temp_release(abs_a, a, s);
        *root_out = s;
        return;
    }
    int64_t bits = (int64_t)(an - 1) * 64 + (64 - __builtin_clzll(ap[an - 1]));
    if (n >= bits) {
        /* Since 2^n > |a| >= 2, floor(|a|^(1/n)) == 1. */
        *root_out = w_box_int(sign_a < 0 ? -1 : 1);
        if (rem_out) {
            WValue r = bigint_sub_any(abs_a, w_box_int(1));
            *rem_out = sign_a < 0 ? w_neg(r) : r;
        }
        bigint_temp_release(abs_a, a, W_NIL);
        return;
    }
    /* 53-bit float seed shifted to the root's bit position for any limb count. */
    int fexp;
    double dval = ldexp((double)ap[an - 1], 64) + (double)ap[an - 2];
    if (an >= 3) dval += ldexp((double)ap[an - 3], -64);
    double m = frexp(dval, &fexp);
    int64_t total_exp = (int64_t)(an - 2) * 64 + fexp;
    int64_t q_exp = total_exp / n;
    int r_exp = (int)(total_exp - q_exp * n);
    if (r_exp < 0) { r_exp += (int)n; q_exp--; }
    double root_m = pow(m, 1.0 / (double)n) * exp2((double)r_exp / (double)n);
    int rm_exp;
    double rm_frac = frexp(root_m, &rm_exp);
    uint64_t mant53 = (uint64_t)ldexp(rm_frac, 53) + 2ULL;
    int64_t shift = q_exp + rm_exp - 53;
    WValue x = (shift >= 0)
        ? w_bigint_shl(w_u64(mant53), w_int(shift))
        : w_u64(mant53 >> (-shift) ? (mant53 >> (-shift)) : 1ULL);
    int64_t nm1 = n - 1;
    WValue nm1_val = w_int(nm1);
    WValue n_box = w_int(n);
    /* First step guarantees x >= floor(|a|^(1/n)) by AM-GM even if float seed under-approximated. */
    WValue x_nm1 = bigint_pow_nm1_c(x, nm1);
    WValue q = w_bigint_tdiv(abs_a, x_nm1);
    if (bigint_compare_c(q, x) > 0) {
        WValue nm1_x = (nm1 == 2) ? w_bigint_shl(x, w_box_int(1)) : bigint_mul_any(nm1_val, x);
        WValue sum = bigint_add_any(nm1_x, q);
        WValue x_next = w_bigint_tdiv(sum, n_box);
        bigint_temp_release(nm1_x, a, x_next);
        bigint_temp_release(sum, a, x_next);
        bigint_temp_release(x_nm1, a, x_next);
        bigint_temp_release(q, a, x_next);
        bigint_temp_release(x, a, x_next);
        x = x_next;
        x_nm1 = bigint_pow_nm1_c(x, nm1);
        q = w_bigint_tdiv(abs_a, x_nm1);
    }
    while (bigint_compare_c(q, x) < 0) {
        WValue nm1_x = (nm1 == 2) ? w_bigint_shl(x, w_box_int(1)) : bigint_mul_any(nm1_val, x);
        WValue sum = bigint_add_any(nm1_x, q);
        WValue x_next = w_bigint_tdiv(sum, n_box);
        bigint_temp_release(nm1_x, a, x_next);
        bigint_temp_release(sum, a, x_next);
        if (bigint_compare_c(x_next, x) >= 0) {
            bigint_temp_release(x_next, a, x);
            break;
        }
        bigint_temp_release(x_nm1, a, x_next);
        bigint_temp_release(q, a, x_next);
        bigint_temp_release(x, a, x_next);
        x = x_next;
        x_nm1 = bigint_pow_nm1_c(x, nm1);
        q = w_bigint_tdiv(abs_a, x_nm1);
    }
    bigint_temp_release(q, a, x);
    if (rem_out) {
        WValue xn = bigint_mul_any(x_nm1, x);
        WValue r = bigint_sub_any(abs_a, xn);
        bigint_temp_release(xn, a, r);
        *rem_out = sign_a < 0 ? w_neg(r) : r;
    }
    bigint_temp_release(x_nm1, a, x);
    bigint_temp_release(abs_a, a, x);
    *root_out = sign_a < 0 ? w_neg(x) : x;
}

WValue w_bigint_iroot(WValue a, WValue n) {
    WValue root = W_NIL;
    bigint_iroot_rem_pair(a, n, &root, NULL);
    return root;
}

WValue w_bigint_iroot_rem(WValue a, WValue n) {
    WValue root = W_NIL, rem = W_NIL;
    bigint_iroot_rem_pair(a, n, &root, &rem);
    return bigint_pair_array(root, rem);
}

static __attribute__((noinline))
int bigint_perfect_square_p_slow(WValue a) {
    uint64_t sa;
    int32_t alen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    if (alen < 0) return 0;
    if (alen == 0) return 1;
    if (((0x0202021202030213ULL >> (ap[0] & 63)) & 1ULL) == 0) return 0;
    if (alen == 1) {
        uint64_t v = ap[0];
        uint64_t s = (uint64_t)sqrt((double)v);
        if (s * s < v && (s + 1) * (s + 1) <= v) s++;
        else if (s * s > v) s--;
        return (s * s == v) ? 1 : 0;
    }
    if (alen == 2) {
        unsigned __int128 v = ((unsigned __int128)ap[1] << 64) | ap[0];
        uint64_t s = bn_isqrt_u128(v);
        return ((unsigned __int128)s * s == v) ? 1 : 0;
    }
    /* Every nonzero square has an even number of trailing zeros and an odd
     * part congruent to 1 (mod 8). */
    int32_t zl = 0;
    while (zl < alen && ap[zl] == 0) zl++;
    int tz = __builtin_ctzll(ap[zl]);
    if (tz & 1) return 0;
    uint64_t odd_low = (ap[zl] >> tz) |
        ((tz != 0 && zl + 1 < alen) ? (ap[zl + 1] << (64 - tz)) : 0ULL);
    if ((odd_low & 7ULL) != 1ULL) return 0;
    /* Quadratic residue filter mod 45045 = 9 * 5 * 7 * 11 * 13 (where
     * 2^64 == 16 mod 45045); rejects ~92% of survivors before isqrt. */
    uint64_t rem = 0;
    for (int32_t i = alen - 1; i >= 0; i--) {
        rem = ((rem << 4) + (ap[i] % 45045ULL)) % 45045ULL;
    }
    if (((0x93U >> (rem % 9U)) & 1U) == 0) return 0;
    if (((0x13U >> (rem % 5U)) & 1U) == 0) return 0;
    if (((0x17U >> (rem % 7U)) & 1U) == 0) return 0;
    if (((0x23bU >> (rem % 11U)) & 1U) == 0) return 0;
    if (((0x161bU >> (rem % 13U)) & 1U) == 0) return 0;

    WValue s = bigint_isqrt_any(a);
    WValue s2 = bigint_mul_any(s, s);
    int eq = (bigint_compare_c(s2, a) == 0);
    bigint_temp_release(s2, a, W_NIL);
    bigint_temp_release(s, a, W_NIL);
    return eq;
}

int bigint_perfect_square_p_c(WValue a) {
    if (__builtin_expect(((a ^ W_TAG_BIGINT) & (W_TAG_MASK | W_BIGINT_SIGN_BIT)) == 0, 1)) {
        WBigint *ba = w_as_bigint(a);
        const uint64_t *ap = ba->limbs;
        /* Quadratic residue filter mod 64: rejects 53/64 (82.8%) of inputs in O(1). */
        if (__builtin_expect(((0x0202021202030213ULL >> (ap[0] & 63)) & 1ULL) == 0, 1)) return 0;
        int32_t alen = ba->size;
        if (alen == 1) {
            uint64_t v = ap[0];
            uint64_t s = (uint64_t)sqrt((double)v);
            if (s * s < v && (s + 1) * (s + 1) <= v) s++;
            else if (s * s > v) s--;
            return (s * s == v) ? 1 : 0;
        }
    } else if (__builtin_expect(w_is_int(a), 1)) {
        int64_t n = w_as_int(a);
        if (n < 0) return 0;
        uint64_t v = (uint64_t)n;
        if (((0x0202021202030213ULL >> (v & 63)) & 1ULL) == 0) return 0;
        uint64_t s = (uint64_t)__builtin_sqrt((double)v);
        return (s * s == v) ? 1 : 0;
    }
    return bigint_perfect_square_p_slow(a);
}

WValue w_bigint_perfect_square_p(WValue a) {
    return bigint_perfect_square_p_c(a) ? W_TRUE : W_FALSE;
}

WValue w_bigint_perfect_power_p(WValue a) {
    static const int small_primes[] = {
        2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61
    };
    int num_sp = (int)(sizeof(small_primes) / sizeof(small_primes[0]));
    uint64_t sa;
    int32_t alen_signed;
    const uint64_t *ap = integer_limbs(a, &sa, &alen_signed);
    if (alen_signed == 0) return W_TRUE;
    int sign_a = alen_signed < 0 ? -1 : 1;
    int32_t an = alen_signed < 0 ? -alen_signed : alen_signed;
    if (an == 1) {
        uint64_t v = ap[0];
        if (v <= 1ULL) return W_TRUE;
        int tz = __builtin_ctzll(v);
        if (tz == 1) return W_FALSE;
        int bits = 64 - __builtin_clzll(v);
        for (int i = 0; i < num_sp; i++) {
            int p = small_primes[i];
            if (p > bits) return W_FALSE;
            if (sign_a < 0 && p == 2) continue;
            if (tz > 0 && (tz % p) != 0) continue;
            if (p == 2) {
                if (((0x0202021202030213ULL >> (v & 63)) & 1ULL) != 0) {
                    uint64_t s = (uint64_t)sqrt((double)v);
                    if (s * s < v && (s + 1) * (s + 1) <= v) s++;
                    else if (s * s > v) s--;
                    if (s * s == v) return W_TRUE;
                }
            } else {
                uint64_t r = (uint64_t)(p == 3 ? cbrt((double)v) : pow((double)v, 1.0 / (double)p));
                if (r == 0) r = 1;
                uint64_t pw = 1;
                while (!u64_pow_le_c(r, p, v, &pw)) r--;
                uint64_t pw_next = 0;
                while (u64_pow_le_c(r + 1, p, v, &pw_next)) {
                    r++;
                    pw = pw_next;
                }
                if (pw == v) return W_TRUE;
            }
        }
        return W_FALSE;
    }
    WValue abs_a = sign_a < 0 ? w_neg(a) : a;
    int64_t bits = (int64_t)w_int_bit_length(abs_a);
    int64_t tz = w_to_i64(w_bigint_trailing_zeros(abs_a));
    if (tz == 1) {
        bigint_temp_release(abs_a, a, W_NIL);
        return W_FALSE;
    }
    for (int i = 0; i < num_sp; i++) {
        int p = small_primes[i];
        if (p > bits) {
            bigint_temp_release(abs_a, a, W_NIL);
            return W_FALSE;
        }
        if (sign_a < 0 && p == 2) continue;
        if (tz > 0 && (tz % p) != 0) continue;
        if (p == 2) {
            if (w_bigint_perfect_square_p(abs_a) == W_TRUE) {
                bigint_temp_release(abs_a, a, W_NIL);
                return W_TRUE;
            }
        } else {
            WValue root = W_NIL, rem = W_NIL;
            bigint_iroot_rem_pair(abs_a, w_box_int(p), &root, &rem);
            int is_zero = (rem == w_box_int(0));
            bigint_temp_release(root, a, abs_a);
            bigint_temp_release(rem, a, abs_a);
            if (is_zero) {
                bigint_temp_release(abs_a, a, W_NIL);
                return W_TRUE;
            }
        }
    }
    for (int64_t p = 67; p <= bits; p += 2) {
        if (!w_prime_test_u64((uint64_t)p)) continue;
        if (tz > 0 && (tz % p) != 0) continue;
        WValue root = W_NIL, rem = W_NIL;
        bigint_iroot_rem_pair(abs_a, w_box_int(p), &root, &rem);
        int is_zero = (rem == w_box_int(0));
        bigint_temp_release(root, a, abs_a);
        bigint_temp_release(rem, a, abs_a);
        if (is_zero) {
            bigint_temp_release(abs_a, a, W_NIL);
            return W_TRUE;
        }
    }
    bigint_temp_release(abs_a, a, W_NIL);
    return W_FALSE;
}

WValue w_bigint_gcdext(WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    const uint64_t *bp = integer_limbs(b, &sb, &blen);
    int32_t an = alen < 0 ? -alen : alen;
    int32_t bn = blen < 0 ? -blen : blen;
    if (an == 0 && bn == 0) {
        return bigint_triple_array(w_box_int(0), w_box_int(0), w_box_int(0));
    }
    if (bn == 0) {
        WValue g = alen < 0 ? w_neg(a) : a;
        return bigint_triple_array(g, w_box_int(alen < 0 ? -1 : 1), w_box_int(0));
    }
    if (an == 0) {
        WValue g = blen < 0 ? w_neg(b) : b;
        return bigint_triple_array(g, w_box_int(0), w_box_int(blen < 0 ? -1 : 1));
    }
    /* Fast 1-limb extended Euclidean path in registers. */
    if (an == 1 && bn == 1) {
        uint64_t r0 = ap[0], r1 = bp[0];
        __int128 s0 = 1, s1 = 0;
        __int128 t0 = 0, t1 = 1;
        while (r1 != 0) {
            uint64_t q = r0 / r1;
            uint64_t r2 = r0 - q * r1;
            r0 = r1;
            r1 = r2;
            __int128 s2 = s0 - (__int128)q * s1;
            s0 = s1;
            s1 = s2;
            __int128 t2 = t0 - (__int128)q * t1;
            t0 = t1;
            t1 = t2;
        }
        if (alen < 0) s0 = -s0;
        if (blen < 0) t0 = -t0;
        return bigint_triple_array(w_u64(r0), w_i128(s0), w_i128(t0));
    }
    WValue old_r = alen < 0 ? w_neg(a) : a;
    WValue r = blen < 0 ? w_neg(b) : b;
    WValue old_s = w_box_int(1), s = w_box_int(0);
    WValue old_t = w_box_int(0), t = w_box_int(1);
    while (bigint_val_sign(r) != 0) {
        WValue q, rem;
        bigint_tdivmod_pair(old_r, r, &q, &rem);
        WValue qs = bigint_mul_any(q, s);
        WValue next_s = bigint_sub_any(old_s, qs);
        WValue qt = bigint_mul_any(q, t);
        WValue next_t = bigint_sub_any(old_t, qt);
        bigint_temp_release(qs, a, b);
        bigint_temp_release(qt, a, b);
        bigint_temp_release(q, a, b);
        bigint_temp_release(old_r, a, b);
        bigint_temp_release(old_s, a, b);
        bigint_temp_release(old_t, a, b);
        old_r = r;
        r = rem;
        old_s = s;
        s = next_s;
        old_t = t;
        t = next_t;
    }
    bigint_temp_release(r, a, b);
    bigint_temp_release(s, a, b);
    bigint_temp_release(t, a, b);
    if (alen < 0) old_s = w_neg(old_s);
    if (blen < 0) old_t = w_neg(old_t);
    return bigint_triple_array(old_r, old_s, old_t);
}

/* Compute out = a_mul * a + b_mul * b for unsigned limb arrays (length <= cap). */
static inline int32_t mag_pos_linear_comb(uint64_t *out,
                                          const uint64_t *a, int32_t alen, uint64_t a_mul,
                                          const uint64_t *b, int32_t blen, uint64_t b_mul) {
    if (a_mul == 0 || alen == 0) {
        if (b_mul == 0 || blen == 0) return 0;
        if (b_mul == 1) {
            memcpy(out, b, (size_t)blen * sizeof(uint64_t));
            return blen;
        }
        uint64_t cy = bn_mul_1(out, b, blen, b_mul);
        if (cy) { out[blen] = cy; return blen + 1; }
        return blen;
    }
    if (b_mul == 0 || blen == 0) {
        if (a_mul == 1) {
            memcpy(out, a, (size_t)alen * sizeof(uint64_t));
            return alen;
        }
        uint64_t cy = bn_mul_1(out, a, alen, a_mul);
        if (cy) { out[alen] = cy; return alen + 1; }
        return alen;
    }
    /* Both terms non-empty; put the longer array first. */
    if (alen < blen) {
        const uint64_t *tp = a; a = b; b = tp;
        int32_t tl = alen; alen = blen; blen = tl;
        uint64_t tm = a_mul; a_mul = b_mul; b_mul = tm;
    }
    uint64_t top = (a_mul == 1)
        ? (memcpy(out, a, (size_t)alen * sizeof(uint64_t)), 0ULL)
        : bn_mul_1(out, a, alen, a_mul);
    out[alen] = top;
    int32_t len = alen + (top != 0);
    uint64_t cy = (b_mul == 1)
        ? bn_add_n(out, out, b, blen)
        : bn_addmul_1(out, b, blen, b_mul);
    for (int32_t i = blen; cy && i < len; i++) {
        uint64_t old = out[i];
        out[i] = old + cy;
        cy = (out[i] < old);
    }
    if (cy) {
        out[len] = cy;
        len++;
    }
    while (len > 0 && out[len - 1] == 0) len--;
    return len;
}

/* Certified Lehmer simulation for invmod: simulates Euclidean steps on the
 * top limbs of (u, v) and returns positive matrix (m00, m01, m10, m11). */
static inline int invmod_lehmer_simulate(const uint64_t *u, int32_t ulen,
                                         const uint64_t *v, int32_t vlen,
                                         uint64_t *m00_out, uint64_t *m01_out,
                                         uint64_t *m10_out, uint64_t *m11_out) {
    if (vlen == 0 || vlen < ulen - 1) return 0;
    int shift = __builtin_clzll(u[ulen - 1]);
    uint64_t uh = (shift == 0)
        ? u[ulen - 1]
        : ((u[ulen - 1] << shift) | (u[ulen - 2] >> (64 - shift)));
    uint64_t vtop = (vlen == ulen) ? v[ulen - 1] : 0;
    uint64_t vnext = (vlen >= ulen - 1) ? v[ulen - 2] : 0;
    uint64_t vh = (shift == 0)
        ? vtop
        : ((vtop << shift) | (vnext >> (64 - shift)));
    uint64_t m00 = 1, m01 = 0, m10 = 0, m11 = 1;
    int steps = 0;
    for (;;) {
        uint64_t c0 = (steps & 1) ? m00 : m01;
        uint64_t d0 = (steps & 1) ? m01 : m00;
        uint64_t c1 = (steps & 1) ? m11 : m10;
        uint64_t d1 = (steps & 1) ? m10 : m11;
        if (vh <= c1 || uh < vh || (uh - vh) < c0 + d1) break;
        uint64_t q = uh / vh;
        uint64_t r = uh - q * vh;
        uint64_t nm10 = m00 + q * m10;
        uint64_t nm11 = m01 + q * m11;
        if (__builtin_expect(((nm10 | nm11) >> 62) != 0, 0)) break;
        uint64_t next_c0 = (steps & 1) ? nm10 : nm11;
        uint64_t next_d0 = (steps & 1) ? nm11 : nm10;
        if (r < next_c0 || (vh - r) <= c1 + next_d0) break;
        uh = vh;
        vh = r;
        m00 = m10; m01 = m11;
        m10 = nm10; m11 = nm11;
        steps++;
    }
    *m00_out = m00; *m01_out = m01;
    *m10_out = m10; *m11_out = m11;
    return steps;
}

static inline int invmod_lehmer_u128_step(unsigned __int128 *uu_io, unsigned __int128 *vv_io,
                                          uint64_t *m00_out, uint64_t *m01_out,
                                          uint64_t *m10_out, uint64_t *m11_out) {
    unsigned __int128 uu = *uu_io, vv = *vv_io;
    uint64_t u1 = (uint64_t)(uu >> 64);
    if (u1 == 0 || vv == 0) return 0;
    uint64_t v1 = (uint64_t)(vv >> 64);
    int shift = __builtin_clzll(u1);
    uint64_t uh = (shift == 0) ? u1 : ((u1 << shift) | ((uint64_t)uu >> (64 - shift)));
    uint64_t vh = (shift == 0) ? v1 : ((v1 << shift) | ((uint64_t)vv >> (64 - shift)));
    uint64_t m00 = 1, m01 = 0, m10 = 0, m11 = 1;
    int steps = 0;
    for (;;) {
        uint64_t c0 = (steps & 1) ? m00 : m01;
        uint64_t d0 = (steps & 1) ? m01 : m00;
        uint64_t c1 = (steps & 1) ? m11 : m10;
        uint64_t d1 = (steps & 1) ? m10 : m11;
        if (vh <= c1 || uh < vh || (uh - vh) < c0 + d1) break;
        uint64_t q = uh / vh;
        uint64_t r = uh - q * vh;
        uint64_t nm10 = m00 + q * m10;
        uint64_t nm11 = m01 + q * m11;
        if (__builtin_expect(((nm10 | nm11) >> 62) != 0, 0)) break;
        uint64_t next_c0 = (steps & 1) ? nm10 : nm11;
        uint64_t next_d0 = (steps & 1) ? nm11 : nm10;
        if (r < next_c0 || (vh - r) <= c1 + next_d0) break;
        uh = vh;
        vh = r;
        m00 = m10; m01 = m11;
        m10 = nm10; m11 = nm11;
        steps++;
    }
    if (steps > 0) {
        unsigned __int128 nu, nv;
        if (!(steps & 1)) {
            nu = (unsigned __int128)m00 * uu - (unsigned __int128)m01 * vv;
            nv = (unsigned __int128)m11 * vv - (unsigned __int128)m10 * uu;
        } else {
            nu = (unsigned __int128)m01 * vv - (unsigned __int128)m00 * uu;
            nv = (unsigned __int128)m10 * uu - (unsigned __int128)m11 * vv;
        }
        *uu_io = nu;
        *vv_io = nv;
    }
    *m00_out = m00; *m01_out = m01;
    *m10_out = m10; *m11_out = m11;
    return steps;
}

static inline int invmod_linear_comb_uv(uint64_t *nu, uint64_t *nv,
                                        const uint64_t *u, int32_t ulen,
                                        const uint64_t *v, int32_t vlen,
                                        uint64_t m00, uint64_t m01,
                                        uint64_t m10, uint64_t m11,
                                        int odd_steps,
                                        int32_t *nul_out, int32_t *nvl_out) {
    int64_t cu = 0, cv = 0;
    if (!odd_steps) {
        for (int32_t i = 0; i < vlen; i++) {
            uint64_t ui = u[i], vi = v[i];
            __int128 pu = (__int128)((unsigned __int128)ui * m00)
                        - (__int128)((unsigned __int128)vi * m01)
                        + (__int128)cu;
            __int128 pv = (__int128)((unsigned __int128)vi * m11)
                        - (__int128)((unsigned __int128)ui * m10)
                        + (__int128)cv;
            nu[i] = (uint64_t)pu;
            cu = (int64_t)(pu >> 64);
            nv[i] = (uint64_t)pv;
            cv = (int64_t)(pv >> 64);
        }
        for (int32_t i = vlen; i < ulen; i++) {
            uint64_t ui = u[i];
            __int128 pu = (__int128)((unsigned __int128)ui * m00) + (__int128)cu;
            __int128 pv = -(__int128)((unsigned __int128)ui * m10) + (__int128)cv;
            nu[i] = (uint64_t)pu;
            cu = (int64_t)(pu >> 64);
            nv[i] = (uint64_t)pv;
            cv = (int64_t)(pv >> 64);
        }
    } else {
        for (int32_t i = 0; i < vlen; i++) {
            uint64_t ui = u[i], vi = v[i];
            __int128 pu = (__int128)((unsigned __int128)vi * m01)
                        - (__int128)((unsigned __int128)ui * m00)
                        + (__int128)cu;
            __int128 pv = (__int128)((unsigned __int128)ui * m10)
                        - (__int128)((unsigned __int128)vi * m11)
                        + (__int128)cv;
            nu[i] = (uint64_t)pu;
            cu = (int64_t)(pu >> 64);
            nv[i] = (uint64_t)pv;
            cv = (int64_t)(pv >> 64);
        }
        for (int32_t i = vlen; i < ulen; i++) {
            uint64_t ui = u[i];
            __int128 pu = -(__int128)((unsigned __int128)ui * m00) + (__int128)cu;
            __int128 pv = (__int128)((unsigned __int128)ui * m10) + (__int128)cv;
            nu[i] = (uint64_t)pu;
            cu = (int64_t)(pu >> 64);
            nv[i] = (uint64_t)pv;
            cv = (int64_t)(pv >> 64);
        }
    }
    if (__builtin_expect(cu != 0 || cv != 0, 0)) return 0;
    int32_t nul = ulen;
    while (nul > 0 && nu[nul - 1] == 0) nul--;
    int32_t nvl = ulen;
    while (nvl > 0 && nv[nvl - 1] == 0) nvl--;
    *nul_out = nul;
    *nvl_out = nvl;
    return 1;
}

static inline void invmod_pos_linear_comb_pair(uint64_t *ns0, uint64_t *ns1,
                                               const uint64_t *s0, int32_t s0len,
                                               const uint64_t *s1, int32_t s1len,
                                               uint64_t m00, uint64_t m01,
                                               uint64_t m10, uint64_t m11,
                                               int need_s1,
                                               int32_t *ns0len_out, int32_t *ns1len_out) {
    if (s0len == 0 && s1len == 1 && s1[0] == 1ULL) {
        ns0[0] = m01;
        *ns0len_out = (m01 != 0);
        if (need_s1) {
            ns1[0] = m11;
            *ns1len_out = (m11 != 0);
        } else {
            *ns1len_out = 0;
        }
        return;
    }
    int32_t min_len = s0len < s1len ? s0len : s1len;
    uint64_t c0 = 0;
    if (need_s1) {
        uint64_t c1 = 0;
        for (int32_t i = 0; i < min_len; i++) {
            uint64_t a = s0[i], b = s1[i];
            unsigned __int128 p0 = (unsigned __int128)a * m00 + (unsigned __int128)b * m01 + c0;
            unsigned __int128 p1 = (unsigned __int128)a * m10 + (unsigned __int128)b * m11 + c1;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
            ns1[i] = (uint64_t)p1;
            c1 = (uint64_t)(p1 >> 64);
        }
        for (int32_t i = min_len; i < s1len; i++) {
            uint64_t b = s1[i];
            unsigned __int128 p0 = (unsigned __int128)b * m01 + c0;
            unsigned __int128 p1 = (unsigned __int128)b * m11 + c1;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
            ns1[i] = (uint64_t)p1;
            c1 = (uint64_t)(p1 >> 64);
        }
        for (int32_t i = min_len; i < s0len; i++) {
            uint64_t a = s0[i];
            unsigned __int128 p0 = (unsigned __int128)a * m00 + c0;
            unsigned __int128 p1 = (unsigned __int128)a * m10 + c1;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
            ns1[i] = (uint64_t)p1;
            c1 = (uint64_t)(p1 >> 64);
        }
        int32_t n = s0len > s1len ? s0len : s1len;
        int32_t l0 = n;
        if (c0) ns0[l0++] = c0;
        while (l0 > 0 && ns0[l0 - 1] == 0) l0--;
        int32_t l1 = n;
        if (c1) ns1[l1++] = c1;
        while (l1 > 0 && ns1[l1 - 1] == 0) l1--;
        *ns0len_out = l0;
        *ns1len_out = l1;
    } else {
        for (int32_t i = 0; i < min_len; i++) {
            uint64_t a = s0[i], b = s1[i];
            unsigned __int128 p0 = (unsigned __int128)a * m00 + (unsigned __int128)b * m01 + c0;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
        }
        for (int32_t i = min_len; i < s1len; i++) {
            uint64_t b = s1[i];
            unsigned __int128 p0 = (unsigned __int128)b * m01 + c0;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
        }
        for (int32_t i = min_len; i < s0len; i++) {
            uint64_t a = s0[i];
            unsigned __int128 p0 = (unsigned __int128)a * m00 + c0;
            ns0[i] = (uint64_t)p0;
            c0 = (uint64_t)(p0 >> 64);
        }
        int32_t l0 = s0len > s1len ? s0len : s1len;
        if (c0) ns0[l0++] = c0;
        while (l0 > 0 && ns0[l0 - 1] == 0) l0--;
        *ns0len_out = l0;
        *ns1len_out = 0;
    }
}

static inline WValue invmod_run_lehmer_workspace(const uint64_t *ap0, int32_t alen0, int32_t an0,
                                                 const uint64_t *mp0, int32_t mn0,
                                                 uint64_t *u, uint64_t *v,
                                                 uint64_t *nu, uint64_t *nv,
                                                 uint64_t *s0, uint64_t *s1,
                                                 uint64_t *ns0, uint64_t *ns1) {
    memcpy(u, mp0, (size_t)mn0 * sizeof(uint64_t));
    int32_t ulen = mn0;
    int32_t vlen = 0;
    if (an0 < mn0 || (an0 == mn0 && mag_cmp(ap0, an0, mp0, mn0) < 0)) {
        if (alen0 > 0) {
            memcpy(v, ap0, (size_t)an0 * sizeof(uint64_t));
            vlen = an0;
        } else {
            uint64_t bw = bn_sub_n(v, mp0, ap0, an0);
            for (int32_t i = an0; i < mn0; i++) {
                uint64_t mi = mp0[i];
                v[i] = mi - bw;
                bw = (mi < bw);
            }
            vlen = mn0;
            while (vlen > 0 && v[vlen - 1] == 0) vlen--;
        }
    } else if (an0 == mn0 && alen0 > 0 && (ap0[mn0 - 1] >> 1) < mp0[mn0 - 1]) {
        /* Equal-length with a < 2*m: remainder is simply a - m. */
        (void)bn_sub_n(v, ap0, mp0, mn0);
        vlen = mn0;
        while (vlen > 0 && v[vlen - 1] == 0) vlen--;
    } else {
        WBigint *rem_bi = NULL;
        mag_divmod(ap0, an0, mp0, mn0, NULL, &rem_bi);
        if (rem_bi->size > 0) {
            if (alen0 > 0) {
                vlen = rem_bi->size;
                memcpy(v, rem_bi->limbs, (size_t)vlen * sizeof(uint64_t));
            } else {
                int32_t rn = rem_bi->size;
                uint64_t bw = bn_sub_n(v, mp0, rem_bi->limbs, rn);
                for (int32_t i = rn; i < mn0; i++) {
                    uint64_t mi = mp0[i];
                    v[i] = mi - bw;
                    bw = (mi < bw);
                }
                vlen = mn0;
                while (vlen > 0 && v[vlen - 1] == 0) vlen--;
            }
        }
        bigint_release(rem_bi);
    }
    if (vlen == 0) die("Integer#invmod: not invertible");
    int32_t s0len = 0;
    s1[0] = 1ULL;
    int32_t s1len = 1;
    int odd = 0;
    while (vlen > 0) {
        if (ulen == 2) {
            unsigned __int128 uu = ((unsigned __int128)u[1] << 64) | u[0];
            unsigned __int128 vv = (vlen == 2)
                ? (((unsigned __int128)v[1] << 64) | v[0])
                : (unsigned __int128)v[0];
            uint64_t m00, m01, m10, m11;
            int steps1 = invmod_lehmer_u128_step(&uu, &vv, &m00, &m01, &m10, &m11);
            if (steps1 > 0) {
                uint64_t a00, a01, a10, a11;
                int steps2 = 0;
                if ((uu >> 64) != 0 && vv != 0) {
                    steps2 = invmod_lehmer_u128_step(&uu, &vv, &a00, &a01, &a10, &a11);
                }
                if (steps2 > 0) {
                    unsigned __int128 c00 = (unsigned __int128)a00 * m00 + (unsigned __int128)a01 * m10;
                    unsigned __int128 c01 = (unsigned __int128)a00 * m01 + (unsigned __int128)a01 * m11;
                    unsigned __int128 c10 = (unsigned __int128)a10 * m00 + (unsigned __int128)a11 * m10;
                    unsigned __int128 c11 = (unsigned __int128)a10 * m01 + (unsigned __int128)a11 * m11;
                    if (((c00 | c01 | c10 | c11) >> 64) == 0) {
                        m00 = (uint64_t)c00; m01 = (uint64_t)c01;
                        m10 = (uint64_t)c10; m11 = (uint64_t)c11;
                        steps1 += steps2;
                        steps2 = 0;
                    }
                }
                u[0] = (uint64_t)uu;
                u[1] = (uint64_t)(uu >> 64);
                ulen = (u[1] != 0) ? 2 : (u[0] != 0);
                v[0] = (uint64_t)vv;
                v[1] = (uint64_t)(vv >> 64);
                vlen = (v[1] != 0) ? 2 : (v[0] != 0);
                int32_t ns0len, ns1len;
                invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                            m00, m01, m10, m11, vlen > 0 || steps2 > 0,
                                            &ns0len, &ns1len);
                uint64_t *tp;
                tp = s0; s0 = ns0; ns0 = tp; s0len = ns0len;
                tp = s1; s1 = ns1; ns1 = tp; s1len = ns1len;
                odd ^= (steps1 & 1);
                if (steps2 > 0) {
                    invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                                a00, a01, a10, a11, vlen > 0,
                                                &ns0len, &ns1len);
                    tp = s0; s0 = ns0; ns0 = tp; s0len = ns0len;
                    tp = s1; s1 = ns1; ns1 = tp; s1len = ns1len;
                    odd ^= (steps2 & 1);
                }
                if (vlen == 0) break;
                if (ulen > 1) continue;
            }
        }
        if (ulen == 1) {
            uint64_t uh = u[0], vh = v[0];
            uint64_t m00 = 1, m01 = 0, m10 = 0, m11 = 1;
            int steps = 0;
            while (vh != 0) {
                uint64_t q = uh / vh;
                uint64_t r = uh - q * vh;
                uh = vh;
                vh = r;
                uint64_t nm10 = m00 + q * m10;
                uint64_t nm11 = m01 + q * m11;
                m00 = m10; m01 = m11;
                m10 = nm10; m11 = nm11;
                steps++;
            }
            if (uh != 1ULL) die("Integer#invmod: not invertible");
            int32_t dummy_l1;
            invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                        m00, m01, 0, 0, 0, &s0len, &dummy_l1);
            s0 = ns0;
            odd ^= (steps & 1);
            ulen = 1;
            u[0] = 1ULL;
            break;
        }
        uint64_t m00, m01, m10, m11;
        int steps = invmod_lehmer_simulate(u, ulen, v, vlen, &m00, &m01, &m10, &m11);
        if (steps > 0) {
            int32_t nul, nvl;
            if (invmod_linear_comb_uv(nu, nv, u, ulen, v, vlen,
                                      m00, m01, m10, m11, steps & 1, &nul, &nvl)) {
                uint64_t *tp;
                tp = u; u = nu; nu = tp; ulen = nul;
                tp = v; v = nv; nv = tp; vlen = nvl;
                uint64_t a00, a01, a10, a11;
                int steps2 = 0;
                if (ulen >= 2 && vlen > 0) {
                    int s2 = invmod_lehmer_simulate(u, ulen, v, vlen, &a00, &a01, &a10, &a11);
                    if (s2 > 0 && invmod_linear_comb_uv(nu, nv, u, ulen, v, vlen,
                                                        a00, a01, a10, a11, s2 & 1, &nul, &nvl)) {
                        tp = u; u = nu; nu = tp; ulen = nul;
                        tp = v; v = nv; nv = tp; vlen = nvl;
                        steps2 = s2;
                        unsigned __int128 c00 = (unsigned __int128)a00 * m00 + (unsigned __int128)a01 * m10;
                        unsigned __int128 c01 = (unsigned __int128)a00 * m01 + (unsigned __int128)a01 * m11;
                        unsigned __int128 c10 = (unsigned __int128)a10 * m00 + (unsigned __int128)a11 * m10;
                        unsigned __int128 c11 = (unsigned __int128)a10 * m01 + (unsigned __int128)a11 * m11;
                        if (((c00 | c01 | c10 | c11) >> 64) == 0) {
                            m00 = (uint64_t)c00; m01 = (uint64_t)c01;
                            m10 = (uint64_t)c10; m11 = (uint64_t)c11;
                            steps += steps2;
                            steps2 = 0;
                        }
                    }
                }
                int32_t ns0len, ns1len;
                invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                            m00, m01, m10, m11, vlen > 0 || steps2 > 0,
                                            &ns0len, &ns1len);
                tp = s0; s0 = ns0; ns0 = tp; s0len = ns0len;
                tp = s1; s1 = ns1; ns1 = tp; s1len = ns1len;
                odd ^= (steps & 1);
                if (steps2 > 0) {
                    invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                                a00, a01, a10, a11, vlen > 0,
                                                &ns0len, &ns1len);
                    tp = s0; s0 = ns0; ns0 = tp; s0len = ns0len;
                    tp = s1; s1 = ns1; ns1 = tp; s1len = ns1len;
                    odd ^= (steps2 & 1);
                }
                continue;
            }
        }
        /* Fallback single Euclidean step (when top limbs are too close for Lehmer). */
        if (ulen == vlen && (u[ulen - 1] >> 1) < v[vlen - 1]) {
            /* Quotient is 1: u -= v, s0 += s1, swap. */
            (void)bn_sub_n(u, u, v, vlen);
            while (ulen > 0 && u[ulen - 1] == 0) ulen--;
            int32_t ns0len, dummy_l1;
            invmod_pos_linear_comb_pair(ns0, ns1, s0, s0len, s1, s1len,
                                        1ULL, 1ULL, 0, 0, 0, &ns0len, &dummy_l1);
            uint64_t *tp;
            tp = u; u = v; v = tp;
            int32_t tl = ulen; ulen = vlen; vlen = tl;
            tp = s0; s0 = s1; s1 = ns0; ns0 = tp;
            s0len = s1len; s1len = ns0len;
            odd ^= 1;
            continue;
        }
        /* Allocation-free 1-limb quotient step when ulen <= vlen + 1 and u / v < 2^64. */
        if (ulen == vlen || (ulen == vlen + 1 && u[ulen - 1] < v[vlen - 1])) {
            uint64_t q;
            if (vlen == 1) {
                unsigned __int128 uu = (ulen == 2)
                    ? (((unsigned __int128)u[1] << 64) | u[0])
                    : (unsigned __int128)u[0];
                q = (uint64_t)(uu / v[0]);
                u[0] = (uint64_t)(uu - (unsigned __int128)q * v[0]);
                ulen = (u[0] != 0);
            } else {
                int sh = __builtin_clzll(v[vlen - 1]);
                uint64_t v1 = (sh == 0)
                    ? v[vlen - 1]
                    : ((v[vlen - 1] << sh) | (v[vlen - 2] >> (64 - sh)));
                uint64_t u2 = (ulen > vlen) ? u[vlen] : 0ULL;
                uint64_t u1 = u[vlen - 1];
                uint64_t u0 = u[vlen - 2];
                unsigned __int128 uu = (sh == 0)
                    ? (((unsigned __int128)u2 << 64) | u1)
                    : (((unsigned __int128)((u2 << sh) | (u1 >> (64 - sh))) << 64) |
                       ((u1 << sh) | (u0 >> (64 - sh))));
                q = (v1 == UINT64_MAX) ? (uint64_t)(uu >> 64) : (uint64_t)(uu / (v1 + 1ULL));
                if (q > 0) {
                    uint64_t cy = bn_submul_1(u, v, vlen, q);
                    if (ulen > vlen) u[vlen] -= cy;
                    while (ulen > 0 && u[ulen - 1] == 0) ulen--;
                }
                while (ulen > vlen || (ulen == vlen && mag_cmp(u, ulen, v, vlen) >= 0)) {
                    uint64_t bw = bn_sub_n(u, u, v, vlen);
                    if (ulen > vlen) u[vlen] -= bw;
                    while (ulen > 0 && u[ulen - 1] == 0) ulen--;
                    q++;
                }
            }
            int32_t ns0len = mag_pos_linear_comb(ns0, s0, s0len, 1ULL, s1, s1len, q);
            uint64_t *tp;
            tp = u; u = v; v = tp;
            int32_t tl = ulen; ulen = vlen; vlen = tl;
            tp = s0; s0 = s1; s1 = ns0; ns0 = tp;
            s0len = s1len; s1len = ns0len;
            odd ^= 1;
            continue;
        }
        WBigint *q_bi = NULL, *r_bi = NULL;
        mag_divmod(u, ulen, v, vlen, &q_bi, &r_bi);
        int32_t qn = q_bi->size;
        /* ns0 = s0 + q * s1 */
        int32_t ns0len = 0;
        if (s1len == 0 || qn == 0) {
            if (s0len > 0) memcpy(ns0, s0, (size_t)s0len * sizeof(uint64_t));
            ns0len = s0len;
        } else if (qn == 1) {
            ns0len = mag_pos_linear_comb(ns0, s0, s0len, 1ULL, s1, s1len, q_bi->limbs[0]);
        } else {
            int32_t plen = qn + s1len;
            memset(ns0, 0, (size_t)(plen + 1) * sizeof(uint64_t));
            bigint_mul_schoolbook_into(ns0, q_bi->limbs, qn, s1, s1len);
            while (plen > 0 && ns0[plen - 1] == 0) plen--;
            if (s0len > 0) {
                int32_t add_n = s0len < plen ? s0len : plen;
                uint64_t cy = bn_add_n(ns0, ns0, s0, add_n);
                for (int32_t i = add_n; i < s0len; i++) {
                    uint64_t v_i = s0[i] + cy;
                    cy = (v_i < cy);
                    ns0[i] = v_i;
                }
                int32_t top_len = plen > s0len ? plen : s0len;
                for (int32_t i = s0len; cy && i < top_len; i++) {
                    uint64_t old = ns0[i];
                    ns0[i] = old + cy;
                    cy = (ns0[i] < old);
                }
                if (cy) ns0[top_len++] = cy;
                plen = top_len;
            }
            ns0len = plen;
        }
        memcpy(u, v, (size_t)vlen * sizeof(uint64_t));
        ulen = vlen;
        vlen = r_bi->size;
        if (vlen > 0) memcpy(v, r_bi->limbs, (size_t)vlen * sizeof(uint64_t));
        bigint_release(q_bi);
        bigint_release(r_bi);
        uint64_t *tp = s0; s0 = s1; s1 = ns0; ns0 = tp;
        s0len = s1len; s1len = ns0len;
        odd ^= 1;
    }
    if (ulen != 1 || u[0] != 1ULL) die("Integer#invmod: not invertible");
    if (s0len == 0) return w_box_int(0);
    WBigint *res = bigint_alloc_raw_hot(mn0);
    if (odd) {
        memcpy(res->limbs, s0, (size_t)s0len * sizeof(uint64_t));
        res->size = s0len;
    } else {
        uint64_t bw = bn_sub_n(res->limbs, mp0, s0, s0len);
        for (int32_t i = s0len; i < mn0; i++) {
            uint64_t mi = mp0[i];
            res->limbs[i] = mi - bw;
            bw = (mi < bw);
        }
        int32_t rsz = mn0;
        while (rsz > 0 && res->limbs[rsz - 1] == 0) rsz--;
        res->size = rsz;
    }
    return bigint_finish_mag_sub(res);
}

static __attribute__((noinline))
WValue w_bigint_invmod_medium(const uint64_t *ap0, int32_t alen0, int32_t an0,
                              const uint64_t *mp0, int32_t mn0) {
    uint64_t buf_u[66], buf_v[66], buf_nu[66], buf_nv[66];
    uint64_t buf_s0[68], buf_s1[68], buf_ns0[68], buf_ns1[68];
    return invmod_run_lehmer_workspace(ap0, alen0, an0, mp0, mn0,
                                       buf_u, buf_v, buf_nu, buf_nv,
                                       buf_s0, buf_s1, buf_ns0, buf_ns1);
}

WValue w_bigint_invmod(WValue a, WValue m_val) {
    uint64_t sa0, sm0;
    int32_t alen0, mlen0;
    const uint64_t *ap0, *mp0;
    if (__builtin_expect(
            (((a ^ W_TAG_BIGINT) | (m_val ^ W_TAG_BIGINT)) & (W_TAG_MASK | W_BIGINT_SIGN_BIT)) == 0,
            1)) {
        WBigint *ba = w_as_bigint_pos(a);
        WBigint *bm = w_as_bigint_pos(m_val);
        alen0 = ba->size;
        mlen0 = bm->size;
        ap0 = ba->limbs;
        mp0 = bm->limbs;
    } else {
        ap0 = integer_limbs(a, &sa0, &alen0);
        mp0 = integer_limbs(m_val, &sm0, &mlen0);
    }
    int32_t mn0 = mlen0 < 0 ? -mlen0 : mlen0;
    if (mn0 == 0) die("Integer#invmod: modulus must be nonzero");
    if (mn0 == 1 && mp0[0] == 1ULL) return w_box_int(0);
    /* Fast 1-limb path without any temporary BigInt allocation. */
    if (mn0 == 1) {
        int32_t an0 = alen0 < 0 ? -alen0 : alen0;
        if (an0 == 0) die("Integer#invmod: not invertible");
        uint64_t m0 = mp0[0];
        uint64_t r1 = (an0 == 1) ? (ap0[0] % m0) : mag_mod_single(ap0, an0, m0);
        if (alen0 < 0 && r1 != 0) r1 = m0 - r1;
        if (r1 == 0) die("Integer#invmod: not invertible");
        uint64_t r0 = m0;
        uint64_t t0 = 0, t1 = 1;
        int odd = 0;
        while (r1 != 0) {
            uint64_t q = r0 / r1;
            uint64_t r2 = r0 - q * r1;
            r0 = r1;
            r1 = r2;
            uint64_t t2 = t0 + q * t1;
            t0 = t1;
            t1 = t2;
            odd ^= 1;
        }
        if (r0 != 1) die("Integer#invmod: not invertible");
        uint64_t ans = odd ? t0 : (m0 - t0);
        return w_u64(ans);
    }
    int32_t an0 = alen0 < 0 ? -alen0 : alen0;
    if (an0 == 0) die("Integer#invmod: not invertible");
    if (mn0 <= 4) {
        uint64_t buf_u[6], buf_v[6], buf_nu[6], buf_nv[6];
        uint64_t buf_s0[6], buf_s1[6], buf_ns0[6], buf_ns1[6];
        return invmod_run_lehmer_workspace(ap0, alen0, an0, mp0, mn0,
                                           buf_u, buf_v, buf_nu, buf_nv,
                                           buf_s0, buf_s1, buf_ns0, buf_ns1);
    }
    if (mn0 <= 64) {
        return w_bigint_invmod_medium(ap0, alen0, an0, mp0, mn0);
    }
    WValue m = mlen0 < 0 ? w_neg(m_val) : m_val;
    WValue a_mod = w_bigint_fmod(a, m);
    if (bigint_val_sign(a_mod) == 0) {
        bigint_temp_release(a_mod, a, m_val);
        bigint_temp_release(m, a, m_val);
        die("Integer#invmod: not invertible");
    }
    WValue old_r = a_mod, r = m;
    WValue old_s = w_box_int(1), s = w_box_int(0);
    while (bigint_val_sign(r) != 0) {
        WValue q, rem;
        bigint_tdivmod_pair(old_r, r, &q, &rem);
        WValue qs = bigint_mul_any(q, s);
        WValue next_s = bigint_sub_any(old_s, qs);
        bigint_temp_release(qs, a, m_val);
        bigint_temp_release(q, a, m_val);
        if (old_r != m) bigint_temp_release(old_r, a, m_val);
        bigint_temp_release(old_s, a, m_val);
        old_r = r;
        r = rem;
        old_s = s;
        s = next_s;
    }
    bigint_temp_release(r, a, m_val);
    bigint_temp_release(s, a, m_val);
    if (old_r != w_box_int(1)) {
        if (old_r != m) bigint_temp_release(old_r, a, m_val);
        bigint_temp_release(old_s, a, m_val);
        bigint_temp_release(m, a, m_val);
        die("Integer#invmod: not invertible");
    }
    if (bigint_val_sign(old_s) < 0) {
        WValue fixed_s = bigint_add_any(old_s, m);
        bigint_temp_release(old_s, a, m_val);
        old_s = fixed_s;
    }
    bigint_temp_release(m, a, m_val);
    return old_s;
}

static inline __attribute__((always_inline))
int jacobi_u64_odd_with_sign(uint64_t u, uint64_t v, uint64_t sign_bit) {
    if (v == 1ULL) return 1 - (int)((sign_bit & 1ULL) << 1);
    u %= v;
    while (u != 0ULL) {
        int tz = __builtin_ctzll(u);
        u >>= tz;
        sign_bit ^= (uint64_t)tz & ((v >> 1) ^ (v >> 2));
        if (u == 1ULL) return 1 - (int)((sign_bit & 1ULL) << 1);
        sign_bit ^= (u & v) >> 1;
        uint64_t tmp = u;
        u = v % u;
        v = tmp;
    }
    return (v == 1ULL) ? (1 - (int)((sign_bit & 1ULL) << 1)) : 0;
}

static inline __attribute__((always_inline))
int jacobi_u64_odd_c(uint64_t u, uint64_t v) {
    return jacobi_u64_odd_with_sign(u, v, 0);
}

static inline int jacobi_u128_odd_c(unsigned __int128 u, unsigned __int128 v, uint64_t sign_bit) {
    if (u == 0) return (v == 1) ? (1 - (int)((sign_bit & 1ULL) << 1)) : 0;
    if (__builtin_expect((uint64_t)u == 0, 0)) u >>= 64;
    {
        int tz = __builtin_ctzll((uint64_t)u);
        if (tz > 0) {
            uint64_t u0 = (uint64_t)u;
            uint64_t u1 = (uint64_t)(u >> 64);
            u0 = (u0 >> tz) | (u1 << (64 - tz));
            u1 >>= tz;
            u = ((unsigned __int128)u1 << 64) | u0;
            uint64_t v0 = (uint64_t)v;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        }
    }
    while ((u >> 64) != 0 && (v >> 64) != 0) {
        unsigned __int128 diff = u - v;
        uint64_t d0 = (uint64_t)diff;
        uint64_t lt = (u < v);
        sign_bit ^= lt & (((uint64_t)u & (uint64_t)v) >> 1);
        v = lt ? u : v;
        u = lt ? -diff : diff;
        if (__builtin_expect(d0 != 0, 1)) {
            int tz = __builtin_ctzll(d0);
            uint64_t u0 = (uint64_t)u;
            uint64_t u1 = (uint64_t)(u >> 64);
            u0 = (u0 >> tz) | (u1 << (64 - tz));
            u1 >>= tz;
            u = ((unsigned __int128)u1 << 64) | u0;
            uint64_t v0 = (uint64_t)v;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        } else {
            if (diff == 0) return 0;
            uint64_t u1 = (uint64_t)(u >> 64);
            int tz = __builtin_ctzll(u1);
            u = (unsigned __int128)(u1 >> tz);
            uint64_t v0 = (uint64_t)v;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        }
    }
    if ((u >> 64) != 0) {
        /* v fits in 64 bits and is odd; swap u and v. */
        uint64_t v64 = (uint64_t)v;
        if (v64 == 1ULL) return 1 - (int)((sign_bit & 1ULL) << 1);
        uint64_t vp[2] = { (uint64_t)u, (uint64_t)(u >> 64) };
        uint64_t rem = mag_mod_single(vp, 2, v64);
        return jacobi_u64_odd_with_sign(rem, v64, sign_bit);
    }
    uint64_t u64 = (uint64_t)u;
    if (u64 == 1ULL) return 1 - (int)((sign_bit & 1ULL) << 1);
    sign_bit ^= (u64 & (uint64_t)v) >> 1;
    uint64_t rem;
    if ((v >> 64) == 0) {
        rem = (uint64_t)v % u64;
    } else {
        uint64_t vp[2] = { (uint64_t)v, (uint64_t)(v >> 64) };
        rem = mag_mod_single(vp, 2, u64);
    }
    return jacobi_u64_odd_with_sign(rem, u64, sign_bit);
}

static inline int jacobi_u256_odd_c(unsigned __int128 u_lo, unsigned __int128 u_hi,
                                    unsigned __int128 v_lo, unsigned __int128 v_hi,
                                    uint64_t sign_bit) {
    if ((u_lo | u_hi) == 0) {
        return (v_hi == 0 && v_lo == 1) ? (1 - (int)((sign_bit & 1ULL) << 1)) : 0;
    }
    while (__builtin_expect((uint64_t)u_lo == 0, 0)) {
        u_lo = (u_lo >> 64) | (u_hi << 64);
        u_hi >>= 64;
    }
    {
        int tz = __builtin_ctzll((uint64_t)u_lo);
        if (tz > 0) {
            int inv_tz = 64 - tz;
            uint64_t u0 = (uint64_t)u_lo, u1 = (uint64_t)(u_lo >> 64);
            uint64_t u2 = (uint64_t)u_hi, u3 = (uint64_t)(u_hi >> 64);
            u0 = (u0 >> tz) | (u1 << inv_tz);
            u1 = (u1 >> tz) | (u2 << inv_tz);
            u2 = (u2 >> tz) | (u3 << inv_tz);
            u3 >>= tz;
            u_lo = ((unsigned __int128)u1 << 64) | u0;
            u_hi = ((unsigned __int128)u3 << 64) | u2;
            uint64_t v0 = (uint64_t)v_lo;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        }
    }
    /* Stage 1: 4-limb reduction while either top limb (u3 or v3) is nonzero. */
    while (((u_hi | v_hi) >> 64) != 0) {
        unsigned __int128 bw = (u_lo < v_lo);
        unsigned __int128 d_lo = u_lo - v_lo;
        unsigned __int128 d_hi = u_hi - v_hi - bw;
        uint64_t d0 = (uint64_t)d_lo;
        uint64_t lt = (u_hi < v_hi) | ((u_hi == v_hi) & (uint64_t)bw);
        sign_bit ^= lt & (((uint64_t)u_lo & (uint64_t)v_lo) >> 1);
        v_lo = lt ? u_lo : v_lo;
        v_hi = lt ? u_hi : v_hi;
        if (__builtin_expect(d0 != 0, 1)) {
            int tz = __builtin_ctzll(d0);
            int inv_tz = 64 - tz;
            u_lo = lt ? -d_lo : d_lo;
            u_hi = lt ? ~d_hi : d_hi;
            uint64_t u0 = (uint64_t)u_lo, u1 = (uint64_t)(u_lo >> 64);
            uint64_t u2 = (uint64_t)u_hi, u3 = (uint64_t)(u_hi >> 64);
            u0 = (u0 >> tz) | (u1 << inv_tz);
            u1 = (u1 >> tz) | (u2 << inv_tz);
            u2 = (u2 >> tz) | (u3 << inv_tz);
            u3 >>= tz;
            u_lo = ((unsigned __int128)u1 << 64) | u0;
            u_hi = ((unsigned __int128)u3 << 64) | u2;
            uint64_t v0 = (uint64_t)v_lo;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        } else {
            if ((d_lo | d_hi) == 0) return 0;
            unsigned __int128 nd_lo = -d_lo;
            unsigned __int128 nd_hi = ~d_hi + (nd_lo == 0);
            u_lo = lt ? nd_lo : d_lo;
            u_hi = lt ? nd_hi : d_hi;
            do {
                u_lo = (u_lo >> 64) | (u_hi << 64);
                u_hi >>= 64;
            } while ((uint64_t)u_lo == 0);
            int tz = __builtin_ctzll((uint64_t)u_lo);
            if (tz > 0) {
                int inv_tz = 64 - tz;
                uint64_t u0 = (uint64_t)u_lo, u1 = (uint64_t)(u_lo >> 64);
                uint64_t u2 = (uint64_t)u_hi, u3 = (uint64_t)(u_hi >> 64);
                u0 = (u0 >> tz) | (u1 << inv_tz);
                u1 = (u1 >> tz) | (u2 << inv_tz);
                u2 = (u2 >> tz) | (u3 << inv_tz);
                u3 >>= tz;
                u_lo = ((unsigned __int128)u1 << 64) | u0;
                u_hi = ((unsigned __int128)u3 << 64) | u2;
                uint64_t v0 = (uint64_t)v_lo;
                sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
            }
        }
    }
    /* Stage 2: 3-limb (192-bit) reduction while u2 or v2 is nonzero. */
    uint64_t u2 = (uint64_t)u_hi;
    uint64_t v2 = (uint64_t)v_hi;
    while ((u2 | v2) != 0) {
        uint64_t bw = (u_lo < v_lo);
        unsigned __int128 d_lo = u_lo - v_lo;
        uint64_t d2 = u2 - v2 - bw;
        uint64_t d0 = (uint64_t)d_lo;
        uint64_t lt = (u2 < v2) | ((u2 == v2) & bw);
        sign_bit ^= lt & (((uint64_t)u_lo & (uint64_t)v_lo) >> 1);
        v_lo = lt ? u_lo : v_lo;
        v2 = lt ? u2 : v2;
        if (__builtin_expect(d0 != 0, 1)) {
            int tz = __builtin_ctzll(d0);
            int inv_tz = 64 - tz;
            u_lo = lt ? -d_lo : d_lo;
            u2 = lt ? ~d2 : d2;
            uint64_t u0 = (uint64_t)u_lo, u1 = (uint64_t)(u_lo >> 64);
            u0 = (u0 >> tz) | (u1 << inv_tz);
            u1 = (u1 >> tz) | (u2 << inv_tz);
            u2 >>= tz;
            u_lo = ((unsigned __int128)u1 << 64) | u0;
            uint64_t v0 = (uint64_t)v_lo;
            sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
        } else {
            if ((d_lo | d2) == 0) return 0;
            unsigned __int128 nd_lo = -d_lo;
            uint64_t nd2 = ~d2 + (nd_lo == 0);
            u_lo = lt ? nd_lo : d_lo;
            u2 = lt ? nd2 : d2;
            do {
                u_lo = (u_lo >> 64) | ((unsigned __int128)u2 << 64);
                u2 = 0;
            } while ((uint64_t)u_lo == 0);
            int tz = __builtin_ctzll((uint64_t)u_lo);
            if (tz > 0) {
                int inv_tz = 64 - tz;
                uint64_t u0 = (uint64_t)u_lo, u1 = (uint64_t)(u_lo >> 64);
                u0 = (u0 >> tz) | (u1 << inv_tz);
                u1 = (u1 >> tz) | (u2 << inv_tz);
                u2 >>= tz;
                u_lo = ((unsigned __int128)u1 << 64) | u0;
                uint64_t v0 = (uint64_t)v_lo;
                sign_bit ^= (uint64_t)tz & ((v0 >> 1) ^ (v0 >> 2));
            }
        }
    }
    return jacobi_u128_odd_c(u_lo, v_lo, sign_bit);
}

static __attribute__((noinline))
int bigint_jacobi_odd_limbs_large(const uint64_t *ap, int32_t alen,
                                  const uint64_t *np, int32_t nlen) {
    int32_t an = alen < 0 ? -alen : alen;
    if (an == 0) return 0;
    uint64_t u_stack[64], v_stack[64];
    int heap_work = nlen > 64;
    uint64_t *u_alloc = heap_work ? (uint64_t *)malloc((size_t)nlen * 2 * sizeof(uint64_t)) : NULL;
    uint64_t *u = heap_work ? u_alloc : u_stack;
    uint64_t *v = heap_work ? (u_alloc + nlen) : v_stack;
    memcpy(v, np, (size_t)nlen * sizeof(uint64_t));
    int32_t vlen = nlen;
    int32_t ulen = 0;
    if (an < nlen || (an == nlen && mag_cmp(ap, an, np, nlen) < 0)) {
        if (alen > 0) {
            memcpy(u, ap, (size_t)an * sizeof(uint64_t));
            ulen = an;
        } else {
            uint64_t bw = bn_sub_n(u, np, ap, an);
            for (int32_t i = an; i < nlen; i++) {
                uint64_t ni = np[i];
                u[i] = ni - bw;
                bw = (ni < bw);
            }
            ulen = nlen;
            while (ulen > 0 && u[ulen - 1] == 0) ulen--;
        }
    } else if (an == nlen && alen > 0 && (ap[nlen - 1] >> 1) < np[nlen - 1]) {
        (void)bn_sub_n(u, ap, np, nlen);
        ulen = nlen;
        while (ulen > 0 && u[ulen - 1] == 0) ulen--;
    } else {
        WBigint *rem_bi = NULL;
        mag_divmod(ap, an, np, nlen, NULL, &rem_bi);
        if (rem_bi->size > 0) {
            if (alen > 0) {
                ulen = rem_bi->size;
                memcpy(u, rem_bi->limbs, (size_t)ulen * sizeof(uint64_t));
            } else {
                int32_t rn = rem_bi->size;
                uint64_t bw = bn_sub_n(u, np, rem_bi->limbs, rn);
                for (int32_t i = rn; i < nlen; i++) {
                    uint64_t ni = np[i];
                    u[i] = ni - bw;
                    bw = (ni < bw);
                }
                ulen = nlen;
                while (ulen > 0 && u[ulen - 1] == 0) ulen--;
            }
        }
        bigint_release(rem_bi);
    }
    uint64_t sign_bit = 0;
    while (ulen > 0) {
        if (ulen <= 4 && vlen <= 4) {
            unsigned __int128 u_lo = (unsigned __int128)u[0] |
                                     (ulen >= 2 ? ((unsigned __int128)u[1] << 64) : 0);
            unsigned __int128 u_hi = (ulen >= 3 ? (unsigned __int128)u[2] : 0) |
                                     (ulen == 4 ? ((unsigned __int128)u[3] << 64) : 0);
            unsigned __int128 v_lo = (unsigned __int128)v[0] |
                                     (vlen >= 2 ? ((unsigned __int128)v[1] << 64) : 0);
            unsigned __int128 v_hi = (vlen >= 3 ? (unsigned __int128)v[2] : 0) |
                                     (vlen == 4 ? ((unsigned __int128)v[3] << 64) : 0);
            int res = jacobi_u256_odd_c(u_lo, u_hi, v_lo, v_hi, sign_bit);
            if (heap_work) free(u_alloc);
            return res;
        }
        /* Strip whole zero limbs (64 bits = even shift, so Jacobi sign is unchanged). */
        if (__builtin_expect(u[0] == 0, 0)) {
            int32_t zl = 1;
            while (zl < ulen && u[zl] == 0) zl++;
            ulen -= zl;
            memmove(u, u + zl, (size_t)ulen * sizeof(uint64_t));
        }
        int tz = __builtin_ctzll(u[0]);
        if (tz > 0) {
            for (int32_t i = 0; i < ulen - 1; i++)
                u[i] = (u[i] >> tz) | (u[i + 1] << (64 - tz));
            u[ulen - 1] >>= tz;
            if (u[ulen - 1] == 0) ulen--;
            sign_bit ^= (uint64_t)tz & ((v[0] >> 1) ^ (v[0] >> 2));
        }
        if (ulen == 1) {
            uint64_t u0 = u[0];
            int result = 1 - (int)((sign_bit & 1ULL) << 1);
            if (u0 == 1ULL) {
                if (heap_work) free(u_alloc);
                return result;
            }
            if ((u0 & v[0] & 2ULL) != 0) result = -result;
            uint64_t rem = (vlen == 1) ? (v[0] % u0) : mag_mod_single(v, vlen, u0);
            int tail = jacobi_u64_odd_c(rem, u0);
            if (heap_work) free(u_alloc);
            return result * tail;
        }
        if (vlen == 1) {
            uint64_t v0 = v[0];
            int result = 1 - (int)((sign_bit & 1ULL) << 1);
            if (v0 == 1ULL) {
                if (heap_work) free(u_alloc);
                return result;
            }
            uint64_t rem = mag_mod_single(u, ulen, v0);
            int tail = jacobi_u64_odd_c(rem, v0);
            if (heap_work) free(u_alloc);
            return result * tail;
        }
        /* Both u and v are odd and >= 2 limbs. Ensure u >= v. */
        int cmp = (ulen != vlen) ? (ulen > vlen ? 1 : -1) : mag_cmp(u, ulen, v, vlen);
        if (cmp == 0) {
            if (heap_work) free(u_alloc);
            return 0;
        }
        if (cmp < 0) {
            sign_bit ^= (u[0] & v[0]) >> 1;
            uint64_t *tp = u; u = v; v = tp;
            int32_t tl = ulen; ulen = vlen; vlen = tl;
        }
        if (ulen > vlen + 1) {
            ulen = mag_mod_binary(u, ulen, v, vlen);
        } else {
            uint64_t bw = bn_sub_n(u, u, v, vlen);
            if (ulen > vlen) u[vlen] -= bw;
            while (ulen > 0 && u[ulen - 1] == 0) ulen--;
        }
    }
    int is_one = (vlen == 1 && v[0] == 1ULL);
    if (heap_work) free(u_alloc);
    return is_one ? (1 - (int)((sign_bit & 1ULL) << 1)) : 0;
}

static inline int bigint_jacobi_odd_limbs(const uint64_t *ap, int32_t alen,
                                          const uint64_t *np, int32_t nlen) {
    if (nlen == 1) {
        uint64_t n0 = np[0];
        if (n0 == 1ULL) return 1;
        int32_t an = alen < 0 ? -alen : alen;
        if (an == 0) return 0;
        uint64_t rem = (an == 1) ? (ap[0] % n0) : mag_mod_single(ap, an, n0);
        if (alen < 0 && rem != 0) rem = n0 - rem;
        return jacobi_u64_odd_c(rem, n0);
    }
    int32_t an = alen < 0 ? -alen : alen;
    if (an == 0) return 0;
    if (__builtin_expect(nlen <= 4 && an <= 4, 1)) {
        unsigned __int128 v_lo = (unsigned __int128)np[0] | ((unsigned __int128)np[1] << 64);
        unsigned __int128 v_hi = (nlen >= 3 ? (unsigned __int128)np[2] : 0) |
                                 (nlen == 4 ? ((unsigned __int128)np[3] << 64) : 0);
        unsigned __int128 u_lo = (unsigned __int128)ap[0] |
                                 (an >= 2 ? ((unsigned __int128)ap[1] << 64) : 0);
        unsigned __int128 u_hi = (an >= 3 ? (unsigned __int128)ap[2] : 0) |
                                 (an == 4 ? ((unsigned __int128)ap[3] << 64) : 0);
        if (u_hi > v_hi || (u_hi == v_hi && u_lo >= v_lo)) {
            unsigned __int128 bw = (u_lo < v_lo);
            u_lo -= v_lo;
            u_hi = u_hi - v_hi - bw;
            if (__builtin_expect(u_hi > v_hi || (u_hi == v_hi && u_lo >= v_lo), 0)) {
                return bigint_jacobi_odd_limbs_large(ap, alen, np, nlen);
            }
        }
        if (alen < 0 && (u_lo | u_hi) != 0) {
            unsigned __int128 bw = (v_lo < u_lo);
            u_lo = v_lo - u_lo;
            u_hi = v_hi - u_hi - bw;
        }
        return jacobi_u256_odd_c(u_lo, u_hi, v_lo, v_hi, 0);
    }
    return bigint_jacobi_odd_limbs_large(ap, alen, np, nlen);
}

static __attribute__((noinline))
int bigint_jacobi_cold(WValue a, WValue n) {
    uint64_t sn, sa;
    int32_t nlen, alen;
    const uint64_t *np = integer_limbs(n, &sn, &nlen);
    if (__builtin_expect(nlen <= 0 || (np[0] & 1ULL) == 0, 0)) {
        die_as("DomainError", "jacobi requires positive odd modulus");
    }
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    return bigint_jacobi_odd_limbs(ap, alen, np, nlen);
}

int bigint_jacobi_c(WValue a, WValue n) {
    if (__builtin_expect(
            (((a ^ W_TAG_BIGINT) | (n ^ W_TAG_BIGINT)) & (W_TAG_MASK | W_BIGINT_SIGN_BIT)) == 0,
            1)) {
        WBigint *ba = w_as_bigint_pos(a);
        WBigint *bn = w_as_bigint_pos(n);
        int32_t nlen = bn->size;
        int32_t alen = ba->size;
        if (__builtin_expect(nlen > 0 && (bn->limbs[0] & 1ULL) != 0, 1)) {
            if (nlen == 1 && alen == 1) {
                return jacobi_u64_odd_c(ba->limbs[0], bn->limbs[0]);
            }
            return bigint_jacobi_odd_limbs(ba->limbs, alen, bn->limbs, nlen);
        }
    }
    return bigint_jacobi_cold(a, n);
}

WValue w_bigint_jacobi(WValue a, WValue n) {
    return w_box_int(bigint_jacobi_c(a, n));
}

static __attribute__((noinline))
int bigint_kronecker_cold(WValue a, WValue b) {
    uint64_t sa, sb;
    int32_t alen, blen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    const uint64_t *bp = integer_limbs(b, &sb, &blen);
    int32_t an = alen < 0 ? -alen : alen;
    int32_t bn = blen < 0 ? -blen : blen;
    if (bn == 0) {
        return (an == 1 && ap[0] == 1ULL) ? 1 : 0;
    }
    int result = (blen < 0 && alen < 0) ? -1 : 1;
    if ((bp[0] & 1ULL) != 0) {
        return result * bigint_jacobi_odd_limbs(ap, alen, bp, bn);
    }
    if (an == 0 || (ap[0] & 1ULL) == 0) return 0;
    int32_t zl = 0;
    while (zl < bn && bp[zl] == 0) zl++;
    bp += zl;
    bn -= zl;
    int tz = __builtin_ctzll(bp[0]);
    if (tz & 1) {
        uint64_t a8 = ap[0] & 7ULL;
        if (a8 == 3ULL || a8 == 5ULL) result = -result;
    }
    if (tz == 0) {
        return result * bigint_jacobi_odd_limbs(ap, alen, bp, bn);
    }
    if (bn == 1) {
        uint64_t b0 = bp[0] >> tz;
        return result * bigint_jacobi_odd_limbs(ap, alen, &b0, 1);
    }
    uint64_t b_stack[64];
    uint64_t *b_odd = bn <= 64 ? b_stack : (uint64_t *)malloc((size_t)bn * sizeof(uint64_t));
    for (int32_t i = 0; i < bn - 1; i++)
        b_odd[i] = (bp[i] >> tz) | (bp[i + 1] << (64 - tz));
    b_odd[bn - 1] = bp[bn - 1] >> tz;
    if (b_odd[bn - 1] == 0) bn--;
    int jac = bigint_jacobi_odd_limbs(ap, alen, b_odd, bn);
    if (b_odd != b_stack) free(b_odd);
    return result * jac;
}

int bigint_kronecker_c(WValue a, WValue b) {
    if (__builtin_expect(
            (((a ^ W_TAG_BIGINT) | (b ^ W_TAG_BIGINT)) & (W_TAG_MASK | W_BIGINT_SIGN_BIT)) == 0,
            1)) {
        WBigint *ba = w_as_bigint_pos(a);
        WBigint *bb = w_as_bigint_pos(b);
        int32_t alen = ba->size;
        int32_t blen = bb->size;
        if (__builtin_expect(blen > 0 && (bb->limbs[0] & 1ULL) != 0, 1)) {
            if (blen == 1 && alen == 1) {
                return jacobi_u64_odd_c(ba->limbs[0], bb->limbs[0]);
            }
            return bigint_jacobi_odd_limbs(ba->limbs, alen, bb->limbs, blen);
        }
    }
    return bigint_kronecker_cold(a, b);
}

WValue w_bigint_kronecker(WValue a, WValue b) {
    return w_box_int(bigint_kronecker_c(a, b));
}

WValue w_bigint_nextprime(WValue a) {
    if (bigint_compare_c(a, w_box_int(2)) < 0) return w_box_int(2);
    uint64_t sa;
    int32_t alen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    if (alen == 1 && ap[0] == 2) return w_box_int(3);
    if (alen == 1 && ap[0] < UINT64_MAX - 4096) {
        uint64_t cand = (ap[0] + 1ULL) | 1ULL;
        while (!w_prime_test_u64(cand)) cand += 2ULL;
        return w_u64(cand);
    }
    WValue cand = bigint_add_any(a, w_box_int(1));
    if ((integer_low_i64(cand) & 1) == 0) {
        cand = bigint_add_any(cand, w_box_int(1));
    }
    while (w_bigint_prime_q(cand) != W_TRUE) {
        cand = bigint_add_any(cand, w_box_int(2));
    }
    return cand;
}

WValue w_bigint_prevprime(WValue a) {
    if (bigint_compare_c(a, w_box_int(2)) <= 0) {
        die_as("DomainError", "prevprime requires argument > 2");
    }
    uint64_t sa;
    int32_t alen;
    const uint64_t *ap = integer_limbs(a, &sa, &alen);
    if (alen == 1) {
        if (ap[0] == 3) return w_box_int(2);
        uint64_t cand = (ap[0] - 1ULL) | 1ULL;
        if (cand >= ap[0]) cand -= 2ULL;
        while (cand >= 3 && !w_prime_test_u64(cand)) cand -= 2ULL;
        return w_u64(cand);
    }
    WValue cand = bigint_sub_any(a, w_box_int(1));
    if ((integer_low_i64(cand) & 1) == 0) {
        cand = bigint_sub_any(cand, w_box_int(1));
    }
    while (w_bigint_prime_q(cand) != W_TRUE) {
        cand = bigint_sub_any(cand, w_box_int(2));
    }
    return cand;
}

WValue w_bigint_remove(WValue a, WValue f) {
    uint64_t sf;
    int32_t flen;
    const uint64_t *fp = integer_limbs(f, &sf, &flen);
    int32_t fn = flen < 0 ? -flen : flen;
    if (fn == 0 || (fn == 1 && fp[0] <= 1)) {
        die_as("DomainError", "remove_factor requires |factor| > 1");
    }
    if (bigint_val_sign(a) == 0) {
        return bigint_pair_array(w_box_int(0), w_box_int(0));
    }
    if (flen == 1 && fp[0] == 2) {
        int64_t tz = w_to_i64(w_bigint_trailing_zeros(a));
        if (tz == 0) return bigint_pair_array(a, w_box_int(0));
        int sign_a = bigint_val_sign(a);
        WValue abs_a = sign_a < 0 ? w_neg(a) : a;
        WValue shifted = w_bigint_shr(abs_a, w_int(tz));
        if (sign_a < 0) shifted = w_neg(shifted);
        return bigint_pair_array(shifted, w_int(tz));
    }
    WValue cur = a;
    int64_t mult = 0;
    while (w_bigint_divisible_p(cur, f) == W_TRUE) {
        cur = w_bigint_divexact(cur, f);
        mult++;
    }
    return bigint_pair_array(cur, w_int(mult));
}

static WValue bigint_prod_u64_slice(const uint64_t *vals, int64_t lo, int64_t hi) {
    int64_t count = hi - lo;
    if (count <= 0) return w_box_int(1);
    if (count <= 16) {
        unsigned __int128 acc = 1;
        WValue prod = W_NIL;
        for (int64_t i = lo; i < hi; i++) {
            uint64_t v = vals[i];
            if (acc <= (~(unsigned __int128)0) / v) {
                acc *= v;
            } else {
                WValue chunk = w_u128(acc);
                prod = (prod == W_NIL) ? chunk : bigint_mul_any(prod, chunk);
                acc = v;
            }
        }
        WValue tail = w_u128(acc);
        return (prod == W_NIL) ? tail : bigint_mul_any(prod, tail);
    }
    int64_t mid = lo + (count >> 1);
    WValue left = bigint_prod_u64_slice(vals, lo, mid);
    WValue right = bigint_prod_u64_slice(vals, mid, hi);
    return bigint_mul_any(left, right);
}

static WValue bigint_prod_step_rec(uint64_t start, uint64_t step, int64_t count) {
    if (count <= 0) return w_box_int(1);
    if (count <= 16) {
        unsigned __int128 acc = 1;
        WValue prod = W_NIL;
        uint64_t cur = start;
        for (int64_t i = 0; i < count; i++, cur += step) {
            if (acc <= (~(unsigned __int128)0) / cur) {
                acc *= cur;
            } else {
                WValue chunk = w_u128(acc);
                prod = (prod == W_NIL) ? chunk : bigint_mul_any(prod, chunk);
                acc = cur;
            }
        }
        WValue tail = w_u128(acc);
        return (prod == W_NIL) ? tail : bigint_mul_any(prod, tail);
    }
    int64_t half = count >> 1;
    WValue left = bigint_prod_step_rec(start, step, half);
    WValue right = bigint_prod_step_rec(start + (uint64_t)half * step, step, count - half);
    return bigint_mul_any(left, right);
}

WValue w_bigint_fac_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "factorial of negative number");
    if (n <= 1) return w_box_int(1);
    if (n <= 20) {
        uint64_t acc = 1;
        for (int64_t i = 2; i <= n; i++) acc *= (uint64_t)i;
        return w_u64(acc);
    }
    return bigint_prod_step_rec(2, 1, n - 1);
}

WValue w_bigint_2fac_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < -1) die_as("DomainError", "double_factorial of negative number < -1");
    if (n <= 1) return w_box_int(1);
    if ((n & 1) == 0) {
        int64_t k = n >> 1;
        return w_bigint_shl(w_bigint_fac_ui(w_int(k)), w_int(k));
    }
    int64_t count = (n - 1) >> 1;
    return bigint_prod_step_rec(3, 2, count);
}

WValue w_bigint_mfac_uiui(WValue n_val, WValue m_val) {
    int64_t n = bigint_arg_i64(n_val);
    int64_t m = bigint_arg_i64(m_val);
    if (n < 0) die_as("DomainError", "multifactorial of negative number");
    if (m <= 0) die_as("DomainError", "multifactorial step must be positive");
    if (n <= 1) return w_box_int(1);
    if (m == 1) return w_bigint_fac_ui(w_int(n));
    if (m == 2) return w_bigint_2fac_ui(w_int(n));
    int64_t rem = n % m;
    uint64_t first = (rem == 0) ? (uint64_t)m : (uint64_t)rem;
    if (first == 1) first += (uint64_t)m;
    if (first > (uint64_t)n) return w_box_int(1);
    int64_t count = (int64_t)(((uint64_t)n - first) / (uint64_t)m) + 1;
    return bigint_prod_step_rec(first, (uint64_t)m, count);
}

WValue w_bigint_primorial_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "primorial of negative number");
    if (n < 2) return w_box_int(1);
    if (n == 2) return w_box_int(2);
    int64_t odd_cnt = (n - 1) >> 1;
    uint8_t *sieve = (uint8_t *)calloc((size_t)odd_cnt, 1);
    if (!sieve) die("primorial: out of memory");
    for (int64_t i = 0; (2 * i + 3) * (2 * i + 3) <= n; i++) {
        if (!sieve[i]) {
            int64_t p = 2 * i + 3;
            for (int64_t j = (p * p - 3) >> 1; j < odd_cnt; j += p) {
                sieve[j] = 1;
            }
        }
    }
    uint64_t *primes = (uint64_t *)malloc((size_t)(odd_cnt + 1) * sizeof(uint64_t));
    if (!primes) {
        free(sieve);
        die("primorial: out of memory");
    }
    int64_t np = 0;
    primes[np++] = 2;
    for (int64_t i = 0; i < odd_cnt; i++) {
        if (!sieve[i]) primes[np++] = (uint64_t)(2 * i + 3);
    }
    free(sieve);
    WValue res = bigint_prod_u64_slice(primes, 0, np);
    free(primes);
    return res;
}

WValue w_bigint_bin_ui(WValue n_val, WValue k_val) {
    int64_t k = bigint_arg_i64(k_val);
    if (!w_is_integer_any(n_val)) n_val = w_int((int64_t)n_val);
    if (!w_is_integer_any(k_val)) k_val = w_int(k);
    if (k < 0) return w_box_int(0);
    if (k == 0) return w_box_int(1);
    if (k == 1) return n_val;
    if (w_is_int(n_val)) {
        int64_t n = w_as_int(n_val);
        if (n >= 0) {
            if (k > n) return w_box_int(0);
            if (k > n - k) k = n - k;
            if (k == 0) return w_box_int(1);
            if (k == 1) return w_int(n);
            WValue num = bigint_prod_step_rec((uint64_t)(n - k + 1), 1, k);
            WValue den = w_bigint_fac_ui(w_int(k));
            return w_bigint_divexact(num, den);
        }
    }
    /* General n (negative or BigInt): prod_{i=0}^{k-1} (n - i) / k! */
    if (bigint_val_sign(n_val) >= 0 && bigint_compare_c(k_val, n_val) > 0) {
        return w_box_int(0);
    }
    WValue num = w_box_int(1);
    for (int64_t i = 0; i < k; i++) {
        num = bigint_mul_any(num, bigint_sub_any(n_val, w_int(i)));
    }
    WValue den = w_bigint_fac_ui(w_int(k));
    return w_bigint_divexact(num, den);
}

static const uint64_t W_FIB_TAB[94] = {
    0ULL, 1ULL, 1ULL, 2ULL, 3ULL, 5ULL, 8ULL, 13ULL, 21ULL, 34ULL,
    55ULL, 89ULL, 144ULL, 233ULL, 377ULL, 610ULL, 987ULL, 1597ULL, 2584ULL, 4181ULL,
    6765ULL, 10946ULL, 17711ULL, 28657ULL, 46368ULL, 75025ULL, 121393ULL, 196418ULL, 317811ULL, 514229ULL,
    832040ULL, 1346269ULL, 2178309ULL, 3524578ULL, 5702887ULL, 9227465ULL, 14930352ULL, 24157817ULL, 39088169ULL, 63245986ULL,
    102334155ULL, 165580141ULL, 267914296ULL, 433494437ULL, 701408733ULL, 1134903170ULL, 1836311903ULL, 2971215073ULL, 4807526976ULL, 7778742049ULL,
    12586269025ULL, 20365011074ULL, 32951280099ULL, 53316291173ULL, 86267571272ULL, 139583862445ULL, 225851433717ULL, 365435296162ULL, 591286729879ULL, 956722026041ULL,
    1548008755920ULL, 2504730781961ULL, 4052739537881ULL, 6557470319842ULL, 10610209857723ULL, 17167680177565ULL, 27777890035288ULL, 44945570212853ULL, 72723460248141ULL, 117669030460994ULL,
    190392490709135ULL, 308061521170129ULL, 498454011879264ULL, 806515533049393ULL, 1304969544928657ULL, 2111485077978050ULL, 3416454622906707ULL, 5527939700884757ULL, 8944394323791464ULL, 14472334024676221ULL,
    23416728348467685ULL, 37889062373143906ULL, 61305790721611591ULL, 99194853094755497ULL, 160500643816367088ULL, 259695496911122585ULL, 420196140727489673ULL, 679891637638612258ULL, 1100087778366101931ULL, 1779979416004714189ULL,
    2880067194370816120ULL, 4660046610375530309ULL, 7540113804746346429ULL, 12200160415121876738ULL
};

static void bigint_fib_pair_ui(int64_t n, WValue *fn_out, WValue *fnp1_out) {
    if (n <= 92) {
        *fn_out = w_u64(W_FIB_TAB[n]);
        *fnp1_out = w_u64(W_FIB_TAB[n + 1]);
        return;
    }
    int s = 0;
    while ((n >> s) > 92) s++;
    int64_t top_n = n >> s;
    WValue a = w_u64(W_FIB_TAB[top_n]);
    WValue b = w_u64(W_FIB_TAB[top_n + 1]);
    for (int i = s - 1; i >= 0; i--) {
        WValue two_b = w_bigint_shl(b, w_box_int(1));
        WValue c = bigint_mul_any(a, bigint_sub_any(two_b, a));
        WValue d = bigint_add_any(bigint_mul_any(a, a), bigint_mul_any(b, b));
        if ((n >> i) & 1) {
            a = d;
            b = bigint_add_any(c, d);
        } else {
            a = c;
            b = d;
        }
    }
    *fn_out = a;
    *fnp1_out = b;
}

WValue w_bigint_fib_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "fib of negative index");
    if (n <= 93) return w_u64(W_FIB_TAB[n]);
    WValue fn, fnp1;
    bigint_fib_pair_ui(n, &fn, &fnp1);
    return fn;
}

WValue w_bigint_fib2_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "fib2 of negative index");
    if (n == 0) return bigint_pair_array(w_box_int(0), w_box_int(1));
    if (n <= 93) return bigint_pair_array(w_u64(W_FIB_TAB[n]), w_u64(W_FIB_TAB[n - 1]));
    WValue fn, fnp1;
    bigint_fib_pair_ui(n, &fn, &fnp1);
    WValue fnm1 = bigint_sub_any(fnp1, fn);
    return bigint_pair_array(fn, fnm1);
}

WValue w_bigint_lucnum_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "lucas of negative index");
    if (n == 0) return w_box_int(2);
    if (n <= 92) return w_u64(W_FIB_TAB[n + 1] + W_FIB_TAB[n - 1]);
    WValue fn, fnp1;
    bigint_fib_pair_ui(n, &fn, &fnp1);
    /* L_n = 2*F_{n+1} - F_n */
    return bigint_sub_any(w_bigint_shl(fnp1, w_box_int(1)), fn);
}

WValue w_bigint_lucnum2_ui(WValue n_val) {
    int64_t n = bigint_arg_i64(n_val);
    if (n < 0) die_as("DomainError", "lucas2 of negative index");
    if (n == 0) return bigint_pair_array(w_box_int(2), w_box_int(-1));
    if (n == 1) return bigint_pair_array(w_box_int(1), w_box_int(2));
    if (n <= 92) {
        return bigint_pair_array(
            w_u64(W_FIB_TAB[n + 1] + W_FIB_TAB[n - 1]),
            w_u64(W_FIB_TAB[n] + W_FIB_TAB[n - 2]));
    }
    WValue fn, fnp1;
    bigint_fib_pair_ui(n, &fn, &fnp1);
    WValue two_fnp1 = w_bigint_shl(fnp1, w_box_int(1));
    WValue ln = bigint_sub_any(two_fnp1, fn);
    /* L_{n-1} = 2*F_n - F_{n-1} = 3*F_n - F_{n+1} */
    WValue three_fn = bigint_add_any(w_bigint_shl(fn, w_box_int(1)), fn);
    WValue lnm1 = bigint_sub_any(three_fn, fnp1);
    return bigint_pair_array(ln, lnm1);
}


#ifndef W_RUNTIME_UNITY_INCLUDE
#undef die
#undef die_as
#undef bigint_box
#undef bn_copy_tail
#undef bigint_alloc
#undef bigint_alloc_raw
#undef bigint_alloc_raw_hot
#undef bigint_alloc_raw_hot_exact
#undef bigint_release
#undef bigint_release_if_live
#undef bigint_normalize
#undef bigint_finish_mag_sub
#undef bigint_finish_one_limb
#undef bigint_finish_div1
#undef integer_limbs
#undef integer_low_i64
#undef bigint_compare
#undef bigint_compare_c
#undef bigint_compare_mag
#undef mag_cmp
#undef bn_add_n
#undef bn_sub_n
#undef bn_mul_1
#undef bn_addmul_1
#undef bigint_mul_schoolbook_into
#undef bn_modinv_odd
#undef bn_div_qr_preinv
#undef mag_div_single
#undef mag_mod_single
#undef mag_div_84
#undef mag_mod_63
#undef mag_mod_42
#undef mag_divmod
#undef mag_divexact
#undef mag_mod_binary
#undef bn_isqrt_u128
#undef w_prime_test_u64
#undef w_int_bit_length
#endif
