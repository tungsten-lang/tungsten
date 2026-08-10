/* Benchmark-only same-binary controls for the complete immutable and consumed
 * BigInt bitwise migration gate. The C lane enters the retained runtime kernel
 * directly; the source lane enters the compiler-emitted strong seam directly.
 * Both timed paths therefore cross one identical noinline C wrapper and return
 * an ordinary WValue through the same result-consumption path.
 *
 * This file deliberately does not route either lane through w_bit_and/or/xor:
 * doing so would let the runtime shape gate benchmark the C implementation in
 * both lanes for every not-yet-migrated shape. */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>

/* Emitted only when all three stable source seams accept the complete integer
 * pair domain.  Its absence keeps an older partial source build runnable while
 * making full acceptance fail closed. The benchmark supplies a zero-valued
 * weak definition because Darwin's final link is configured to reject even a
 * weak-imported unresolved symbol; a compiler-emitted strong definition wins
 * ordinary strong-over-weak resolution. */
__attribute__((weak))
int64_t __w_bigint_bitwise_source_complete(void) {
    return 0;
}

static int bitwise_source_complete(void) {
    return __w_bigint_bitwise_source_complete != NULL &&
           __w_bigint_bitwise_source_complete() == 1;
}

/* These are the stable compiler/runtime seams.  Integer fixtures are already
 * normalized before they enter this benchmark boundary, so the accepted lane
 * can call them directly instead of paying the public routing wrapper's
 * completion-marker branch on every timed iteration. */
WValue __w_bigint_and_src(WValue a, WValue b);
WValue __w_bigint_or_src(WValue a, WValue b);
WValue __w_bigint_xor_src(WValue a, WValue b);

#define BITWISE_GATE_WRAPPERS(NAME, C_ORACLE, SOURCE_ENTRY)                \
    __attribute__((noinline))                                               \
    WValue w_bitwise_gate_##NAME##_c(WValue a, WValue b) {                 \
        return (C_ORACLE)(a, b);                                            \
    }                                                                       \
    __attribute__((noinline))                                               \
    WValue w_bitwise_gate_##NAME##_source(WValue a, WValue b) {            \
        return (SOURCE_ENTRY)(a, b);                                        \
    }                                                                       \
    __attribute__((noinline))                                               \
    WValue w_bitwise_gate_##NAME##_source_baseline(WValue a, WValue b) {   \
        if (bitwise_source_complete() ||                                   \
            (w_is_bigint(a) && w_is_bigint(b)))                             \
            return (SOURCE_ENTRY)(a, b);                                    \
        return (C_ORACLE)(a, b);                                            \
    }

BITWISE_GATE_WRAPPERS(and, w_bigint_and_c, __w_bigint_and_src)
BITWISE_GATE_WRAPPERS(or, w_bigint_or_c, __w_bigint_or_src)
BITWISE_GATE_WRAPPERS(xor, w_bigint_xor_c, __w_bigint_xor_src)

#undef BITWISE_GATE_WRAPPERS

/* Stage0/baseline defaults for the consumed seams. A freshly emitted strong
 * preserve_mostcc definition wins these weak C-oracle bodies. */
__attribute__((weak, preserve_most))
WValue __w_bigint_and_mut_src(WValue a, WValue b) {
    return w_bigint_and_mut(a, b);
}
__attribute__((weak, preserve_most))
WValue __w_bigint_or_mut_src(WValue a, WValue b) {
    return w_bigint_or_mut(a, b);
}
__attribute__((weak, preserve_most))
WValue __w_bigint_xor_mut_src(WValue a, WValue b) {
    return w_bigint_xor_mut(a, b);
}

#define BITWISE_GATE_MUT_WRAPPERS(NAME, C_ORACLE, SOURCE_SEAM)             \
    __attribute__((noinline))                                               \
    WValue w_bitwise_gate_##NAME##_mut_c(WValue a, WValue b) {             \
        return (C_ORACLE)(a, b);                                            \
    }                                                                       \
    __attribute__((noinline))                                               \
    WValue w_bitwise_gate_##NAME##_mut_source(WValue a, WValue b) {        \
        return (SOURCE_SEAM)(a, b);                                         \
    }

BITWISE_GATE_MUT_WRAPPERS(and, w_bigint_and_mut, __w_bigint_and_mut_src)
BITWISE_GATE_MUT_WRAPPERS(or, w_bigint_or_mut, __w_bigint_or_mut_src)
BITWISE_GATE_MUT_WRAPPERS(xor, w_bigint_xor_mut, __w_bigint_xor_mut_src)

#undef BITWISE_GATE_MUT_WRAPPERS

WValue w_bitwise_gate_source_complete(void) {
    return w_bool(bitwise_source_complete());
}

/* 2 = complete source domain, 1 = partial BigInt/BigInt source seam,
 * 0 = explicitly labelled old-build C/C inline control. */
WValue w_bitwise_gate_lane_kind(WValue a, WValue b) {
    if (bitwise_source_complete()) return w_int(2);
    return w_int(w_is_bigint(a) && w_is_bigint(b) ? 1 : 0);
}

WValue w_bitwise_gate_mut_lane_kind(WValue a, WValue b) {
    if (!bitwise_source_complete() || !w_is_bigint(a) || !w_is_bigint(b))
        return w_int(0);
    if ((a & W_BIGINT_SIGN_BIT) != 0 || (b & W_BIGINT_SIGN_BIT) != 0)
        return w_int(0);
    WBigint *receiver = w_as_bigint(a);
    int32_t rhs_size;
    WBigint *rhs = w_bigint_view(b, &rhs_size);
    if (receiver == rhs || receiver->shared != 0 || receiver->size <= 0 ||
        rhs_size != receiver->size)
        return w_int(0);
    return w_int(2);
}

/* Correctness-only ownership probe. The caller hands over a fresh, unshared
 * positive receiver and a distinct equal-width positive rhs. A successful
 * consumed source call must publish through the same receiver storage and
 * leave that storage eligible for another consumed operation. */
WValue w_bitwise_gate_source_and_reused_receiver(WValue a, WValue b) {
    if (!bitwise_source_complete() || !w_is_bigint(a) || !w_is_bigint(b))
        return w_bool(0);
    if ((a & W_BIGINT_SIGN_BIT) != 0 || (b & W_BIGINT_SIGN_BIT) != 0)
        return w_bool(0);
    WBigint *before = w_as_bigint(a);
    int32_t b_size;
    WBigint *rhs = w_bigint_view(b, &b_size);
    if (before == rhs || before->shared != 0 || before->size <= 0 ||
        b_size != before->size)
        return w_bool(0);
    WValue result = __w_bigint_and_mut_src(a, b);
    return w_bool(w_is_bigint(result) &&
                  w_as_bigint(result) == before && before->shared == 0);
}


/* Numeric equality is evaluated by the retained C comparator, independently
 * of the source comparison seam being migrated elsewhere. */
WValue w_bitwise_gate_exact_integer(WValue got, WValue expected) {
    if (!w_is_integer_any(got) || !w_is_integer_any(expected))
        return w_bool(0);
    return w_bool(w_as_int(w_bigint_compare_c(got, expected)) == 0);
}

/* Verify the public integer representation contract as well as its value.
 * A heap BigInt must be nonzero, normalized, within its allocation, and too
 * large for the signed i48 immediate representation. */
WValue w_bitwise_gate_canonical_integer(WValue value) {
    if (w_is_int(value)) return w_bool(1);
    if (!w_is_bigint(value)) return w_bool(0);

    int32_t signed_size;
    WBigint *big = w_bigint_view(value, &signed_size);
    int64_t wide_size = signed_size;
    uint32_t limbs = (uint32_t)(wide_size < 0 ? -wide_size : wide_size);
    if (big->type != W_TYPE_BIGINT || limbs == 0 || limbs > big->cap)
        return w_bool(0);
    if (big->limbs[limbs - 1] == 0)
        return w_bool(0);
    if (limbs == 1) {
        uint64_t magnitude = big->limbs[0];
        uint64_t inline_limit = signed_size < 0
            ? (uint64_t)W_INT48_MAX + UINT64_C(1)
            : (uint64_t)W_INT48_MAX;
        if (magnitude <= inline_limit) return w_bool(0);
    }
    return w_bool(1);
}

WValue w_bitwise_gate_inline_integer(WValue value) {
    return w_bool(w_is_int(value));
}

WValue w_bitwise_gate_distinct_storage(WValue a, WValue b) {
    if (!w_is_bigint(a) || !w_is_bigint(b)) return w_bool(a != b);
    return w_bool(w_as_bigint(a) != w_as_bigint(b));
}

/* Construct a true header-negative fixture without retaining a positive alias.
 * The caller passes a freshly allocated, unshared positive BigInt and discards
 * that positive interpretation immediately.  This is correctness-corpus setup,
 * never part of a timed lane. */
WValue w_bitwise_gate_header_negative(WValue value) {
    if (!w_is_bigint(value)) abort();
    if ((value & W_BIGINT_SIGN_BIT) != 0) abort();
    WBigint *big = w_as_bigint(value);
    if (big->type != W_TYPE_BIGINT || big->shared != 0 || big->size <= 0)
        abort();
    big->size = -big->size;
    return value;
}

/* Construct the alternate negative representation explicitly.  Unary `0 - x`
 * is free to choose a header-negative result, so it is not a reliable way to
 * exercise the tag-sign overlay path.  w_neg marks the backing BigInt shared
 * before handing out the sign-flipped alias. */
WValue w_bitwise_gate_overlay_negative(WValue value) {
    if (!w_is_bigint(value)) abort();
    if ((value & W_BIGINT_SIGN_BIT) != 0) abort();
    WBigint *big = w_as_bigint(value);
    if (big->type != W_TYPE_BIGINT || big->size <= 0)
        abort();
    WValue result = w_neg(value);
    int32_t signed_size;
    WBigint *view = w_bigint_view(result, &signed_size);
    if (signed_size >= 0 || view->size <= 0) abort();
    return result;
}

/* Expose the two negative encodings to the deterministic fixture audit:
 * 0 = nonnegative/non-BigInt, 1 = negative header, 2 = tag-sign overlay. */
WValue w_bitwise_gate_negative_form(WValue value) {
    if (!w_is_bigint(value)) return w_int(0);
    int32_t signed_size;
    WBigint *big = w_bigint_view(value, &signed_size);
    if (signed_size >= 0) return w_int(0);
    return w_int(big->size < 0 ? 1 : 2);
}

WValue w_bitwise_gate_low_byte_no_release(WValue value) {
    if (w_is_int(value)) {
        int64_t signed_value = w_as_int(value);
        uint64_t magnitude = signed_value < 0
            ? UINT64_C(0) - (uint64_t)signed_value
            : (uint64_t)signed_value;
        return w_int((int64_t)(magnitude & UINT64_C(0xFF)));
    }
    if (!w_is_bigint(value)) abort();
    WBigint *big = w_as_bigint(value);
    return w_int((int64_t)(big->limbs[0] & UINT64_C(0xFF)));
}
