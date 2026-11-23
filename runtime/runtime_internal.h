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

typedef struct {
    uint64_t d[2];
    uint64_t v[2];
    uint64_t bpow[2][9];
    uint8_t bpow_ready[2];
    uint8_t next;
} BnDivPreinvCache;

typedef struct {
    int parallel;
    int square; /* 0 = equal multiply, 1 = square, 2 = generic product */
    int spin_budget;
    int count;
    int capacity;
    int thread_limit;
    int32_t n;
    size_t operand_limbs;
    size_t scratch_need;
    uint64_t *memory;
    uint64_t *sequential_scratch;
    uint64_t *out[11];
    const uint64_t *a[11];
    const uint64_t *b[11];
    /* Shared claim cursor for tail-stealing dispatch: threads take the next
     * unclaimed slot of order[] instead of a fixed range, so a straggling
     * worker delays the join by at most one (the cheapest) job. */
    _Atomic int next_point;
    uint8_t order[11];
} WToomPointSet;

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
W_RT_INTERNAL int64_t w_rt_deadline_ticks_after_ms(int64_t ms);
W_RT_INTERNAL WValue w_rt_socket_read_string(WString *ws, size_t bytes);
void w_goroutine_count_set_enabled(int enabled);

/* Shared allocation profiler & dispatch method-name macros */
#ifndef W_ALLOCPROF_ARR
#define W_ALLOCPROF_ARR      1
#define W_ALLOCPROF_ALIGNED  2
#define W_ALLOCPROF_GROW     3
#define W_ALLOCPROF_HASH     4
#define W_ALLOCPROF_COUNT    5
#endif
#ifndef W_QUANTITY_ROLE_POINT
#define W_QUANTITY_ROLE_POINT 1
#define W_QUANTITY_ROLE_DELTA 2
#endif
#ifndef W_SSO_TAG
#define W_SSO_TAG W_TAG_STRINGSYM
#define W_M0()                    (W_SSO_TAG)
#define W_M1(s)                   (W_SSO_TAG | (1ULL<<1) | ((uint64_t)(uint8_t)(s)[0]<<4))
#define W_M2(s)                   (W_SSO_TAG | (2ULL<<1) | ((uint64_t)(uint8_t)(s)[0]<<4) | ((uint64_t)(uint8_t)(s)[1]<<12))
#define W_M3(s)                   (W_SSO_TAG | (3ULL<<1) | ((uint64_t)(uint8_t)(s)[0]<<4) | ((uint64_t)(uint8_t)(s)[1]<<12) | ((uint64_t)(uint8_t)(s)[2]<<20))
#define W_M4(s)                   (W_SSO_TAG | (4ULL<<1) | ((uint64_t)(uint8_t)(s)[0]<<4) | ((uint64_t)(uint8_t)(s)[1]<<12) | ((uint64_t)(uint8_t)(s)[2]<<20) | ((uint64_t)(uint8_t)(s)[3]<<28))
#define W_M5(s)                   (W_SSO_TAG | (5ULL<<1) | ((uint64_t)(uint8_t)(s)[0]<<4) | ((uint64_t)(uint8_t)(s)[1]<<12) | ((uint64_t)(uint8_t)(s)[2]<<20) | ((uint64_t)(uint8_t)(s)[3]<<28) | ((uint64_t)(uint8_t)(s)[4]<<36))
#define WN_sort    W_M4("sort")
#define WN_idx     W_M2("[]")
#define WN_idxset  W_M3("[]=")
#endif

static inline uint64_t w_hash_splitmix64(uint64_t v) {
    v ^= v >> 30; v *= 0xbf58476d1ce4e5b9ULL;
    v ^= v >> 27; v *= 0x94d049bb133111ebULL;
    v ^= v >> 31; return v;
}

static inline int64_t array_storage_bits(int64_t bits) {
    if (bits == -116) return 16;
    if (bits == -108 || bits == -109) return 8;
    if (bits == -104) return 4;
    if (bits == 108) return 8;
    if (bits == 116) return 16;
    if (bits == 33) return 32;
    if (bits == 66) return 64;
    if (bits < 0) return -bits;
    if (bits == 65) return 64;
    return bits;
}
static inline int array_is_float_bits(int64_t bits) {
    return bits == -32 || bits == -64 || bits == -116 || bits == -16;
}
static inline int array_is_float(const WArray *a) {
    return array_is_float_bits(a->ebits);
}
static inline int array_is_signed_int_bits(int64_t bits) {
    return bits == -4 || bits == 108 || bits == 116 || bits == 33 || bits == 66;
}
static inline int array_is_signed_int(const WArray *a) {
    return array_is_signed_int_bits(a->ebits);
}
static inline int array_is_byte_int_array(const WArray *a) {
    return a->ebits == 108 || a->ebits == 8;
}

/* Shared Quantity / Units internal helpers */
W_RT_INTERNAL void w_rt_decimal_normalize(int64_t *sig, int *scale);
W_RT_INTERNAL int w_rt_decimal_quotient_i128(__int128 n, __int128 d, int round, int64_t *sig, int *scale);
W_RT_INTERNAL void w_rt_decimal_narrow_i128(__int128 *sig, int *scale);
W_RT_INTERNAL void w_rt_decimal_align(__int128 *a_sig, int *a_scale, __int128 *b_sig, int *b_scale);
W_RT_INTERNAL WValue w_rt_domain_heap_alloc(uint8_t type, int64_t sig, int32_t scale, int32_t extra, int64_t extra2);
W_RT_INTERNAL void w_rt_decimal_extract(WValue v, int64_t *sig, int *scale);
W_RT_INTERNAL void w_rt_quantity_extract(WValue v, int *unit, int64_t *sig, int *scale);
W_RT_INTERNAL int w_rt_is_decimal_any(WValue v);
W_RT_INTERNAL int w_rt_is_quantity_any(WValue v);
W_RT_INTERNAL int w_rt_quantity_explicit_role(WValue v);
W_RT_INTERNAL WValue w_rt_quantity_origin_value(WValue v);
W_RT_INTERNAL WValue w_rt_quantity_with_role(WValue v, int role, WValue origin);
W_RT_INTERNAL const char *w_rt_unit_name(int unit);
W_RT_INTERNAL int w_rt_unit_lookup_id(const char *name);
W_RT_INTERNAL int w_rt_parse_sig_scale_cstr(const char *s, int64_t *sig_out, int *scale_out);
W_RT_INTERNAL int w_rt_quantity_convert(int64_t *sig, int *scale, int from_unit, int to_unit);
W_RT_INTERNAL int w_rt_quantity_pi_parts(WValue v, int64_t *sig, int *scale);
W_RT_INTERNAL double w_rt_quantity_pi_double(int64_t sig, int scale);
W_RT_INTERNAL int w_rt_double_to_sig_scale(double d, int64_t *sig, int *scale);
W_RT_INTERNAL WValue w_rt_date_shift_quantity(WValue d, WValue q, int sign);
WValue w_decimal_big(WValue sig_boxed, int64_t scale);
WValue w_bit_and(WValue a, WValue b);
WValue w_bit_or(WValue a, WValue b);
WValue w_bit_xor(WValue a, WValue b);
WValue __w_type(WValue v);

/* Shared Typed Array / Array internal helpers */
W_RT_INTERNAL void w_rt_raise_error_named(const char *class_name, const char *msg) __attribute__((noreturn));
W_RT_INTERNAL int w_rt_string_ascii_p(WValue v);
W_RT_INTERNAL int w_rt_string_compare(WValue a, WValue b);
W_RT_INTERNAL size_t w_rt_utf8_index_width(const char *s, size_t remaining);
W_RT_INTERNAL void w_rt_allocprof(int kind, long long bytes);
W_RT_INTERNAL WArray **w_rt_arr_park_ptr(void);
W_RT_INTERNAL double w_rt_as_numeric_double(WValue v);
W_RT_INTERNAL double w_rt_cmp_numeric_double(WValue v);
W_RT_INTERNAL double w_rt_math_to_double(WValue v);
W_RT_INTERNAL void w_rt_bn_pool_run_tasks(void (*fn)(void *), void **args, int count, int spin_budget);
W_RT_INTERNAL int w_rt_hash_key_eq(WValue a, WValue b);
W_RT_INTERNAL uint64_t w_rt_hash_value_fast(WValue key);
W_RT_INTERNAL WValue w_rt_ic_string_size(WValue r, WValue *a, int c);
W_RT_INTERNAL WValue w_rt_method_dispatch(WValue recv, WValue name, WArray *args, WValue args_arr);
W_RT_INTERNAL int w_rt_value_compare(const void *ap, const void *bp);
W_RT_INTERNAL WValue w_rt_array_slot_load_decoded(WArray *a, int64_t i);
W_RT_INTERNAL void w_rt_array_release_slots(WValue *slots, int64_t bits, int64_t cap, uint8_t flags);
W_RT_INTERNAL int w_rt_array_has_views(WValue arr);

/* Shared LexChar / Unicode helpers */
static inline uint64_t w_lexchar_cached_t(uint32_t cp, const uint64_t (*blocks)[256], const uint16_t *index) {
    if (cp >= 0x110000) return 0xFFFC40000000EF80ULL;
    return blocks[index[cp >> 8]][cp & 0xFF];
}
int w_lexchar_tables(const uint64_t (**blocks)[256], const uint16_t **index);
int64_t w_byte_scan_count(const uint8_t *data, int64_t size, uint8_t needle);
int64_t w_byte_scan_eq(const uint8_t *data, int64_t size, uint8_t needle);
int64_t w_byte_scan_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t w_byte_scan_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                         int64_t e, int64_t f, int64_t g, int64_t h);
int64_t w_byte_scan_count_any4(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t w_byte_scan_count_any8(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                               int64_t e, int64_t f, int64_t g, int64_t h);
int64_t w_byte_scan_eq_rev(const uint8_t *data, int64_t size, uint8_t needle);
int64_t w_byte_replace(uint8_t *data, int64_t size, uint8_t old_b, uint8_t new_b);
int64_t w_u16_scan_eq(const uint16_t *data, int64_t size, uint16_t needle);
int64_t w_u16_scan_count(const uint16_t *data, int64_t size, uint16_t needle);
int64_t w_u32_scan_eq(const uint32_t *data, int64_t size, uint32_t needle);
int64_t w_u32_scan_count(const uint32_t *data, int64_t size, uint32_t needle);
int64_t w_u16_scan_eq_rev(const uint16_t *data, int64_t size, uint16_t needle);
int64_t w_u32_scan_eq_rev(const uint32_t *data, int64_t size, uint32_t needle);
int64_t w_u1_count_set(const uint8_t *data, int64_t bit_size);
int64_t w_u1_index_set(const uint8_t *data, int64_t bit_size);
int64_t w_u1_index_unset(const uint8_t *data, int64_t bit_size);
int64_t w_u64_scan_eq(const uint64_t *data, int64_t size, uint64_t needle);
int64_t w_u64_scan_count(const uint64_t *data, int64_t size, uint64_t needle);
int64_t w_u64_scan_eq_rev(const uint64_t *data, int64_t size, uint64_t needle);
int64_t w_byte_scan_count_threaded(const uint8_t *data, int64_t size, uint8_t needle);
int64_t w_byte_scan_eq_threaded(const uint8_t *data, int64_t size, uint8_t needle);
int64_t w_byte_scan_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t w_byte_scan_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                  int64_t e, int64_t f, int64_t g, int64_t h);
int64_t w_byte_scan_count_any4_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d);
int64_t w_byte_scan_count_any8_threaded(const uint8_t *data, int64_t size, int64_t a, int64_t b, int64_t c, int64_t d,
                                        int64_t e, int64_t f, int64_t g, int64_t h);
int64_t w_u16_scan_count_threaded(const uint16_t *data, int64_t size, uint16_t needle);
int64_t w_u16_scan_eq_threaded(const uint16_t *data, int64_t size, uint16_t needle);
int64_t w_u32_scan_count_threaded(const uint32_t *data, int64_t size, uint32_t needle);
int64_t w_u32_scan_eq_threaded(const uint32_t *data, int64_t size, uint32_t needle);
W_RT_INTERNAL int w_rt_bytes_ascii_p(const uint8_t *data, size_t len);
W_RT_INTERNAL const uint8_t *w_rt_load_lang_flags(const char *lang, int bits);
W_RT_INTERNAL WValue w_rt_string_to_lexchars_lang(const char *str, size_t str_len, const uint8_t *lang_flags);
W_RT_INTERNAL WValue w_rt_string_to_lex32_lang(const char *str, size_t str_len, const uint8_t *lex32_flags);
W_RT_INTERNAL WValue w_rt_string_to_lex16_lang(const char *str, size_t str_len, const uint8_t *lex16_flags, const uint8_t *lex64_flags);
W_RT_INTERNAL int w_rt_bytes_valid_utf8_p(const uint8_t *data, size_t len);
W_RT_INTERNAL uint32_t w_rt_un_decode_at(const char *s, size_t len, size_t i, size_t *width);

/* Shared Number-Theory / BigInt REDC helpers */
W_RT_INTERNAL void w_rt_bigint_backing_free(WBigint *b);
W_RT_INTERNAL WValue w_rt_bigint_from_u64(uint64_t v);
W_RT_INTERNAL uint64_t w_rt_bn_addmul_2(uint64_t *rp, const uint64_t *up, int32_t n, uint64_t v0, uint64_t v1);
W_RT_INTERNAL uint64_t w_rt_bn_mul_2(uint64_t *rp, const uint64_t *up, int32_t n, uint64_t v0, uint64_t v1);
W_RT_INTERNAL void w_rt_bn_addto(uint64_t *out, int32_t room, const uint64_t *b, int32_t n);
W_RT_INTERNAL void w_rt_bigint_mul_dispatch(uint64_t *out, const uint64_t *a, int32_t na, const uint64_t *b, int32_t nb);
W_RT_INTERNAL void w_rt_bigint_sqr_dispatch(uint64_t *out, const uint64_t *a, int32_t na);
W_RT_INTERNAL void w_rt_mulmod_bnm1(uint64_t *out, const uint64_t *a, const uint64_t *b, int32_t n, uint64_t *scratch);
W_RT_INTERNAL void w_rt_mersenne_ws_release_thread(void);
W_RT_INTERNAL int w_rt_bn_cmp_n(const uint64_t *a, const uint64_t *b, int32_t m);
W_RT_INTERNAL void w_rt_bn_mul_eq4_inline(uint64_t *out, const uint64_t *a, const uint64_t *b);
W_RT_INTERNAL void w_rt_bn_mul_eq6_inline(uint64_t *out, const uint64_t *a, const uint64_t *b);
W_RT_INTERNAL void w_rt_bn_mul_eq8_inline(uint64_t *out, const uint64_t *a, const uint64_t *b);
W_RT_INTERNAL void w_rt_bn_sqr4_inline(uint64_t *out, const uint64_t *a);
W_RT_INTERNAL void w_rt_bn_sqr6_inline(uint64_t *out, const uint64_t *a);
W_RT_INTERNAL void w_rt_bn_sqr8_inline(uint64_t *out, const uint64_t *a);
W_RT_INTERNAL void w_rt_bn_sqr16_split(uint64_t *out, const uint64_t *a);
#ifdef __aarch64__
W_RT_INTERNAL uint64_t bn_addmul_1_blocks(uint64_t *rp, const uint64_t *up, int32_t blocks, uint64_t v);
W_RT_INTERNAL uint64_t bn_addmul_1_f16(uint64_t *rp, const uint64_t *up, uint64_t v);
W_RT_INTERNAL uint64_t bn_addmul_2_f16(uint64_t *rp, const uint64_t *up, uint64_t v0, uint64_t v1);
W_RT_INTERNAL uint64_t w_rt_bn_add16_fixed(uint64_t *r, const uint64_t *a, const uint64_t *b);
W_RT_INTERNAL uint64_t w_rt_bn_sub16_fixed(uint64_t *r, const uint64_t *a, const uint64_t *b);
#endif


/* Shared BigInt division / OS internal helpers */
W_RT_INTERNAL int32_t w_rt_mag_div_single_to(uint64_t *q, const uint64_t *a, int32_t alen, uint64_t d, uint64_t *rem_out, BnDivPreinvCache *cache);
W_RT_INTERNAL void w_rt_bigint_div_release_recip_thread(void);
W_RT_INTERNAL void w_rt_bigint_div_release_thread(void);
W_RT_INTERNAL BnDivPreinvCache *w_rt_bn_div_preinv_thread_cache(void);
W_RT_INTERNAL uint32_t w_rt_bigint_alloc_capacity(uint32_t requested);
W_RT_INTERNAL uint64_t w_rt_bn_submul_from_1(uint64_t *rp, const uint64_t *mp, const uint64_t *up, int32_t n, uint64_t v);
W_RT_INTERNAL int w_rt_bn_page_hazard(const uint64_t *dst, const uint64_t *src);
W_RT_INTERNAL int *w_rt_bn_toom_no_spin_ptr(void);
W_RT_INTERNAL int *w_rt_bn_toom_parallel_depth_ptr(void);
W_RT_INTERNAL int *w_rt_bn_div_recip_diff28_depth_ptr(void);
W_RT_INTERNAL void w_rt_bn_toom_product_set_init(WToomPointSet *set, int capacity, int thread_limit);
W_RT_INTERNAL void w_rt_bn_toom_product_set_add(WToomPointSet *set, uint64_t *out, const uint64_t *a, int32_t na, const uint64_t *b, int32_t nb);
W_RT_INTERNAL void w_rt_bn_toom_point_set_run(WToomPointSet *set);
W_RT_INTERNAL WValue w_rt_bigint_abs_alias(WValue v);
W_RT_INTERNAL uint64_t *w_rt_bn_ws_get(size_t limbs);
W_RT_INTERNAL uint64_t w_rt_bn_gcd_u64_nonzero(uint64_t a, uint64_t b);
W_RT_INTERNAL WMmap *w_rt_as_mmap(WValue v);
W_RT_INTERNAL int w_rt_sandbox_on(void);
W_RT_INTERNAL int w_rt_child_own_group(void);
void w_sandbox_gate(const char *op, const char *detail);
int w_sandbox_stub(const char *op, const char *detail);
int64_t __w_clock_ns_raw(void);
int64_t __w_clock_ticks_raw(void);
int64_t __w_deadline_ticks_after_ms(int64_t ms);

#endif /* TUNGSTEN_RUNTIME_INTERNAL_H */


