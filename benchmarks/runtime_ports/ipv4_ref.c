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

static int ref_ipv4_normalize_prefix(int64_t prefix) {
    if (prefix < 0) return 63;
    if (prefix <= 32 || prefix == 63) return (int)prefix;
    w_raise(w_string("IPv4 prefix must be between 0 and 32"));
    return 63;
}

static uint32_t ref_ipv4_mask_for_prefix(int prefix) {
    if (prefix <= 0) return 0;
    if (prefix >= 32) return 0xFFFFFFFFu;
    return 0xFFFFFFFFu << (32 - prefix);
}

static int ref_ipv4_effective_prefix(WValue ip) {
    int prefix = w_unbox_ipv4_cidr(ip);
    return prefix <= 32 ? prefix : 32;
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

WValue w_ref_ipv4_with_prefix(WValue ip, WValue prefix_v) {
    if (!w_is_ipv4(ip)) {
        w_raise(w_string("IPv4#with_prefix requires an IPv4 address"));
        return W_NIL;
    }
    int64_t raw = w_is_nil(prefix_v) ? -1 : ref_ccall_arg_i64(prefix_v);
    int prefix = ref_ipv4_normalize_prefix(raw);
    return w_box_ipv4(w_unbox_ipv4_addr(ip), prefix, 0);
}

WValue w_ref_ipv4_octet(WValue ip, WValue index_v) {
    if (!w_is_ipv4(ip)) return W_NIL;
    int64_t index = ref_ccall_arg_i64(index_v);
    if (index < 0 || index > 3) return W_NIL;
    uint32_t addr = w_unbox_ipv4_addr(ip);
    return w_int((addr >> (8 * (3 - index))) & 0xFF);
}

WValue w_ref_ipv4_network(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    int prefix = ref_ipv4_effective_prefix(ip);
    uint32_t mask = ref_ipv4_mask_for_prefix(prefix);
    return w_box_ipv4(w_unbox_ipv4_addr(ip) & mask,
                      w_unbox_ipv4_cidr(ip), 0);
}

WValue w_ref_ipv4_broadcast(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    int prefix = ref_ipv4_effective_prefix(ip);
    uint32_t mask = ref_ipv4_mask_for_prefix(prefix);
    return w_box_ipv4(w_unbox_ipv4_addr(ip) | ~mask,
                      w_unbox_ipv4_cidr(ip), 0);
}

WValue w_ref_ipv4_netmask(WValue ip) {
    if (!w_is_ipv4(ip)) return W_NIL;
    uint32_t mask = ref_ipv4_mask_for_prefix(ref_ipv4_effective_prefix(ip));
    return w_box_ipv4(mask, 63, 0);
}

WValue w_ref_ipv4_in_cidr(WValue ip, WValue cidr) {
    if (!w_is_ipv4(ip) || !w_is_ipv4(cidr)) return W_FALSE;
    uint32_t mask = ref_ipv4_mask_for_prefix(ref_ipv4_effective_prefix(cidr));
    return ((w_unbox_ipv4_addr(ip) & mask) ==
            (w_unbox_ipv4_addr(cidr) & mask)) ? W_TRUE : W_FALSE;
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
