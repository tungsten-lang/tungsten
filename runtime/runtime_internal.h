#ifndef TUNGSTEN_RUNTIME_INTERNAL_H
#define TUNGSTEN_RUNTIME_INTERNAL_H

#include "runtime.h"
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef W_RUNTIME_UNITY_INCLUDE
#define W_RT_INTERNAL static
#elif defined(__GNUC__) || defined(__clang__)
#define W_RT_INTERNAL __attribute__((visibility("hidden")))
#else
#define W_RT_INTERNAL
#endif

/* Error & string internal helpers */
W_RT_INTERNAL void w_rt_die(const char *msg) __attribute__((noreturn));
W_RT_INTERNAL void w_rt_dief(const char *fmt, ...) __attribute__((noreturn));
W_RT_INTERNAL void w_rt_die_as(const char *class_name, const char *msg) __attribute__((noreturn));
W_RT_INTERNAL const char *w_rt_as_str(WValue v);
W_RT_INTERNAL WValue w_rt_string_n(const char *s, size_t len);
W_RT_INTERNAL WValue w_rt_string_n_known_ascii(const char *s, size_t len, int ascii);
W_RT_INTERNAL uint32_t w_rt_rope_len(WValue v);
W_RT_INTERNAL void w_rt_rope_write(WValue v, char *buf, uint32_t *pos);

/* Shared crypto / hex helpers */
W_RT_INTERNAL void w_secure_random_fill(uint8_t *buf, size_t len);

static inline int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

/* Shared BigInt / GMP internal helpers */
static inline WValue w_rt_bigint_box(WBigint *b) {
#ifndef NDEBUG
    assert(((uintptr_t)b & ~0x00007FFFFFFFFFFFULL) == 0);
#endif
    return W_TAG_BIGINT | (uint64_t)(uintptr_t)b;
}

static inline void w_rt_bn_copy_tail(uint64_t *restrict dst,
                                     const uint64_t *restrict src, int32_t n) {
    if (n > 0) memcpy(dst, src, (size_t)n * sizeof(uint64_t));
}

W_RT_INTERNAL WBigint *w_rt_bigint_alloc(int32_t cap);
W_RT_INTERNAL WBigint *w_rt_bigint_alloc_raw(int32_t cap);
W_RT_INTERNAL WBigint *w_rt_bigint_alloc_raw_hot(int32_t cap);
W_RT_INTERNAL WBigint *w_rt_bigint_alloc_raw_hot_exact(uint32_t exact_cap);
W_RT_INTERNAL void w_rt_bigint_release(WBigint *b);
W_RT_INTERNAL void w_rt_bigint_release_if_live(WBigint *b);
W_RT_INTERNAL WValue w_rt_bigint_normalize(WBigint *b);
W_RT_INTERNAL WValue w_rt_bigint_finish_mag_sub(WBigint *b);
W_RT_INTERNAL WValue w_rt_bigint_finish_one_limb(uint64_t magnitude, int negative);
W_RT_INTERNAL WValue w_rt_bigint_finish_div1(WBigint *b);
W_RT_INTERNAL const uint64_t *w_rt_integer_limbs(WValue v, uint64_t *stack_limb, int32_t *out_len);
W_RT_INTERNAL int64_t w_rt_integer_low_i64(WValue v);
W_RT_INTERNAL int w_rt_bigint_compare(WValue a, WValue b);
W_RT_INTERNAL int w_rt_bigint_compare_mag(const uint64_t *a, const uint64_t *b, int32_t len);
W_RT_INTERNAL int w_rt_mag_cmp(const uint64_t *a, int32_t alen, const uint64_t *b, int32_t blen);
W_RT_INTERNAL uint64_t w_rt_bn_add_n(uint64_t *r, const uint64_t *a, const uint64_t *b, int32_t m);
W_RT_INTERNAL uint64_t w_rt_bn_sub_n(uint64_t *r, const uint64_t *a, const uint64_t *b, int32_t m);
W_RT_INTERNAL uint64_t w_rt_bn_mul_1(uint64_t *rp, const uint64_t *up, int32_t n, uint64_t v);
W_RT_INTERNAL uint64_t w_rt_bn_addmul_1(uint64_t *rp, const uint64_t *up, int32_t n, uint64_t v);
__attribute__((visibility("hidden")))
uint64_t bn_submul_1(uint64_t *rp, const uint64_t *up, int32_t n, uint64_t v);
W_RT_INTERNAL void w_rt_bigint_mul_schoolbook_into(uint64_t *out, const uint64_t *a, int32_t na,
                                                   const uint64_t *b, int32_t nb);
W_RT_INTERNAL uint64_t w_rt_bn_modinv_odd(uint64_t c);
W_RT_INTERNAL uint64_t w_rt_bn_div_preinv_thread(uint64_t d);
W_RT_INTERNAL uint64_t w_rt_bn_div_qr_preinv(uint64_t nh, uint64_t nl, uint64_t d, uint64_t dinv, uint64_t *rem);
W_RT_INTERNAL WBigint *w_rt_mag_div_single(const uint64_t *a, int32_t alen, uint64_t d, uint64_t *rem);
W_RT_INTERNAL uint64_t w_rt_mag_mod_single(const uint64_t *a, int32_t alen, uint64_t d);
W_RT_INTERNAL WBigint *w_rt_mag_div_84(const uint64_t *u, const uint64_t *v, WBigint **r_out);
W_RT_INTERNAL WBigint *w_rt_mag_mod_63(const uint64_t *u, const uint64_t *v);
W_RT_INTERNAL WBigint *w_rt_mag_mod_42(const uint64_t *u, const uint64_t *v);
W_RT_INTERNAL void w_rt_mag_divmod(const uint64_t *u, int32_t ulen, const uint64_t *v, int32_t vlen,
                                   WBigint **q_out, WBigint **r_out);
W_RT_INTERNAL WBigint *w_rt_mag_divexact(const uint64_t *np, int32_t nn, const uint64_t *dp, int32_t dn);
W_RT_INTERNAL int32_t w_rt_mag_mod_binary(uint64_t *u, int32_t ulen, const uint64_t *v, int32_t vlen);
W_RT_INTERNAL uint64_t w_rt_bn_isqrt_u128(unsigned __int128 a);
WValue bigint_isqrt_any(WValue a);
WValue bigint_gcd_any(WValue a, WValue b);
WValue w_bigint_mark_shared_value(WValue v);
W_RT_INTERNAL WValue bigint_add_any(WValue a, WValue b);
W_RT_INTERNAL WValue bigint_sub_any(WValue a, WValue b);
W_RT_INTERNAL WValue bigint_mul_any(WValue a, WValue b);
W_RT_INTERNAL WValue bigint_div_any(WValue a, WValue b);
W_RT_INTERNAL WValue bigint_mod_any(WValue a, WValue b);
W_RT_INTERNAL int w_rt_prime_test_u64(uint64_t n);
W_RT_INTERNAL int w_rt_int_bit_length(WValue v);

/* Shared HTTP / socket / scheduler internal helpers */
W_RT_INTERNAL WValue w_rt_call_closure_1(WClosure *cl, WValue arg);
W_RT_INTERNAL WEventLoop *w_rt_get_coop_event_loop(void);
W_RT_INTERNAL void w_rt_set_coop_event_loop(WEventLoop *el);
W_RT_INTERNAL void w_rt_set_scheduler_persistent(int val);
W_RT_INTERNAL void w_rt_socket_park_uring(void);
W_RT_INTERNAL int w_rt_fd_set_nonblocking(int fd);
void w_goroutine_count_set_enabled(int enabled);

#endif /* TUNGSTEN_RUNTIME_INTERNAL_H */
