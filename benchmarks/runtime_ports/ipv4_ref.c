/*
 * Benchmark-only references for IPv4 operations migrated from runtime.c to
 * core/ipv4.w. Keep these bodies deliberately identical to the removed C
 * implementations: the native benchmark compares them with the public
 * Tungsten methods in one executable.
 */

#include "runtime.h"

/* Match runtime.c's old ccall integer coercion for octet indexes. */
static int64_t ref_ccall_arg_i64(WValue v) {
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_bigint(v)) return w_to_i64(v);
    if (w_is_double(v)) return (int64_t)w_as_double(v);
    /* ccall can lower raw machine integers as plain i64. */
    if (v <= 0x00007FFFFFFFFFFFULL) return (int64_t)v;
    return w_to_i64(v);
}

WValue w_ref_ipv4_to_i(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    return w_int((int64_t)w_unbox_ipv4_addr(ip));
}

WValue w_ref_ipv4_prefix(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    int prefix = w_unbox_ipv4_cidr(ip);
    return prefix <= 32 ? w_int(prefix) : W_NIL;
}

WValue w_ref_ipv4_cidr_p(WValue ip) {
    return (w_is_ipv4(ip) && w_unbox_ipv4_cidr(ip) <= 32) ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_octet(WValue ip, WValue index_v) {
    if (!w_is_ipv4(ip)) return W_NIL;
    int64_t index = ref_ccall_arg_i64(index_v);
    if (index < 0 || index > 3) return W_NIL;
    uint32_t addr = w_unbox_ipv4_addr(ip);
    return w_int((addr >> (8 * (3 - index))) & 0xFF);
}

WValue w_ref_ipv4_private_p(WValue ip) {
    if (!w_is_ipv4(ip)) return W_FALSE;
    uint32_t a = w_unbox_ipv4_addr(ip);
    int yes = ((a & 0xFF000000u) == 0x0A000000u) ||
              ((a & 0xFFF00000u) == 0xAC100000u) ||
              ((a & 0xFFFF0000u) == 0xC0A80000u);
    return yes ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_loopback_p(WValue ip) {
    return (w_is_ipv4(ip) &&
            ((w_unbox_ipv4_addr(ip) & 0xFF000000u) == 0x7F000000u))
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_link_local_p(WValue ip) {
    return (w_is_ipv4(ip) &&
            ((w_unbox_ipv4_addr(ip) & 0xFFFF0000u) == 0xA9FE0000u))
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_multicast_p(WValue ip) {
    return (w_is_ipv4(ip) &&
            ((w_unbox_ipv4_addr(ip) & 0xF0000000u) == 0xE0000000u))
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_unspecified_p(WValue ip) {
    return (w_is_ipv4(ip) && w_unbox_ipv4_addr(ip) == 0)
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_broadcast_p(WValue ip) {
    return (w_is_ipv4(ip) && w_unbox_ipv4_addr(ip) == 0xFFFFFFFFu)
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_reserved_p(WValue ip) {
    return (w_is_ipv4(ip) &&
            ((w_unbox_ipv4_addr(ip) & 0xF0000000u) == 0xF0000000u))
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv4_global_p(WValue ip) {
    if (!w_is_ipv4(ip)) return W_FALSE;
    if (w_ref_ipv4_private_p(ip) == W_TRUE ||
        w_ref_ipv4_loopback_p(ip) == W_TRUE ||
        w_ref_ipv4_link_local_p(ip) == W_TRUE ||
        w_ref_ipv4_multicast_p(ip) == W_TRUE ||
        w_ref_ipv4_unspecified_p(ip) == W_TRUE ||
        w_ref_ipv4_broadcast_p(ip) == W_TRUE ||
        w_ref_ipv4_reserved_p(ip) == W_TRUE)
        return W_FALSE;
    return W_TRUE;
}
