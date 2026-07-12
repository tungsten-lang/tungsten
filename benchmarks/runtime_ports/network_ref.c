/*
 * Benchmark-only references for MAC and IPv6 operations migrated from
 * runtime.c to core/{mac,ipv6}.w. These preserve the former C method bodies
 * while public dispatch exercises the source-defined implementations.
 */

#include "runtime.h"

extern WValue w_ipv6(const uint8_t *bytes, int cidr);
extern WValue w_mac(const uint8_t *bytes);

/* ccall lowers raw machine integers directly. Check that representation
 * before generic-heap predicates, whose type-byte read is invalid for zero. */
static int64_t ref_i64(WValue v) {
    if (w_is_int(v)) return w_as_int(v);
    if (w_is_double(v)) return (int64_t)w_as_double(v);
    if (v <= 0x00007FFFFFFFFFFFULL) return (int64_t)v;
    if (w_is_bigint(v)) return w_to_i64(v);
    return w_to_i64(v);
}

static int ref_ipv6_prefix(const WNetAddr *na) {
    return na->prefix == UINT8_MAX ? 128 : na->prefix;
}

static void ref_ipv6_network_bytes(const uint8_t in[16], int prefix,
                                   uint8_t out[16]) {
    for (int i = 0; i < 16; i++) {
        int bits = prefix - i * 8;
        if (bits >= 8) out[i] = in[i];
        else if (bits <= 0) out[i] = 0;
        else out[i] = (uint8_t)(in[i] & (uint8_t)(0xFFu << (8 - bits)));
    }
}

WValue w_ref_ipv6_prefix(WValue ip) {
    if (!w_is_ipv6(ip)) return W_NIL;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    return na->prefix == UINT8_MAX ? W_NIL : w_int(na->prefix);
}

WValue w_ref_ipv6_cidr_p(WValue ip) {
    return w_is_ipv6(ip) && ((WNetAddr *)w_as_ptr(ip))->prefix != UINT8_MAX
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_with_prefix(WValue ip, WValue prefix_v) {
    if (!w_is_ipv6(ip)) return W_NIL;
    int prefix = w_is_nil(prefix_v) ? -1 : (int)ref_i64(prefix_v);
    return w_ipv6(((WNetAddr *)w_as_ptr(ip))->bytes, prefix);
}

WValue w_ref_ipv6_byte(WValue ip, WValue index_v) {
    if (!w_is_ipv6(ip)) return W_NIL;
    int64_t index = ref_i64(index_v);
    if (index < 0 || index > 15) return W_NIL;
    return w_int(((WNetAddr *)w_as_ptr(ip))->bytes[index]);
}

WValue w_ref_ipv6_bytes(WValue ip) {
    if (!w_is_ipv6(ip)) return W_NIL;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    WValue out = w_array_new_empty();
    for (int i = 0; i < 16; i++) w_array_push(out, w_int(na->bytes[i]));
    return out;
}

WValue w_ref_ipv6_network(WValue ip) {
    if (!w_is_ipv6(ip)) return W_NIL;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    uint8_t bytes[16];
    ref_ipv6_network_bytes(na->bytes, ref_ipv6_prefix(na), bytes);
    return w_ipv6(bytes, na->prefix == UINT8_MAX ? -1 : na->prefix);
}

WValue w_ref_ipv6_include(WValue cidr, WValue ip) {
    if (!w_is_ipv6(ip) || !w_is_ipv6(cidr)) return W_FALSE;
    WNetAddr *ipa = (WNetAddr *)w_as_ptr(ip);
    WNetAddr *net = (WNetAddr *)w_as_ptr(cidr);
    int prefix = ref_ipv6_prefix(net);
    uint8_t ip_net[16], cidr_net[16];
    ref_ipv6_network_bytes(ipa->bytes, prefix, ip_net);
    ref_ipv6_network_bytes(net->bytes, prefix, cidr_net);
    return memcmp(ip_net, cidr_net, 16) == 0 ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_unspecified_p(WValue ip) {
    if (!w_is_ipv6(ip)) return W_FALSE;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    for (int i = 0; i < 16; i++) if (na->bytes[i] != 0) return W_FALSE;
    return W_TRUE;
}

WValue w_ref_ipv6_loopback_p(WValue ip) {
    if (!w_is_ipv6(ip)) return W_FALSE;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    for (int i = 0; i < 15; i++) if (na->bytes[i] != 0) return W_FALSE;
    return na->bytes[15] == 1 ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_multicast_p(WValue ip) {
    return w_is_ipv6(ip) && ((WNetAddr *)w_as_ptr(ip))->bytes[0] == 0xFF
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_link_local_p(WValue ip) {
    if (!w_is_ipv6(ip)) return W_FALSE;
    WNetAddr *na = (WNetAddr *)w_as_ptr(ip);
    return na->bytes[0] == 0xFE && (na->bytes[1] & 0xC0) == 0x80
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_unique_local_p(WValue ip) {
    return w_is_ipv6(ip) &&
                   ((((WNetAddr *)w_as_ptr(ip))->bytes[0] & 0xFE) == 0xFC)
               ? W_TRUE : W_FALSE;
}

WValue w_ref_ipv6_global_p(WValue ip) {
    if (!w_is_ipv6(ip)) return W_FALSE;
    if (w_ref_ipv6_unspecified_p(ip) == W_TRUE ||
        w_ref_ipv6_loopback_p(ip) == W_TRUE ||
        w_ref_ipv6_multicast_p(ip) == W_TRUE ||
        w_ref_ipv6_link_local_p(ip) == W_TRUE ||
        w_ref_ipv6_unique_local_p(ip) == W_TRUE)
        return W_FALSE;
    return W_TRUE;
}

WValue w_ref_mac_byte(WValue mac, WValue index_v) {
    if (!w_is_mac(mac)) return W_NIL;
    int64_t index = ref_i64(index_v);
    if (index < 0 || index > 5) return W_NIL;
    return w_int(((WNetAddr *)w_as_ptr(mac))->bytes[index]);
}

WValue w_ref_mac_bytes(WValue mac) {
    if (!w_is_mac(mac)) return W_NIL;
    WNetAddr *na = (WNetAddr *)w_as_ptr(mac);
    WValue out = w_array_new_empty();
    for (int i = 0; i < 6; i++) w_array_push(out, w_int(na->bytes[i]));
    return out;
}

WValue w_ref_mac_multicast_p(WValue mac) {
    return w_is_mac(mac) && (((WNetAddr *)w_as_ptr(mac))->bytes[0] & 1)
               ? W_TRUE : W_FALSE;
}

WValue w_ref_mac_unicast_p(WValue mac) {
    return w_ref_mac_multicast_p(mac) == W_TRUE ? W_FALSE
                                                 : (w_is_mac(mac) ? W_TRUE : W_FALSE);
}

WValue w_ref_mac_local_p(WValue mac) {
    return w_is_mac(mac) && (((WNetAddr *)w_as_ptr(mac))->bytes[0] & 2)
               ? W_TRUE : W_FALSE;
}

WValue w_ref_mac_universal_p(WValue mac) {
    return w_ref_mac_local_p(mac) == W_TRUE ? W_FALSE
                                             : (w_is_mac(mac) ? W_TRUE : W_FALSE);
}

WValue w_ref_mac_broadcast_p(WValue mac) {
    if (!w_is_mac(mac)) return W_FALSE;
    WNetAddr *na = (WNetAddr *)w_as_ptr(mac);
    for (int i = 0; i < 6; i++) if (na->bytes[i] != 0xFF) return W_FALSE;
    return W_TRUE;
}

/* Deterministic corpus constructors; corpus creation is outside timings. */
WValue w_ref_ipv6_seed(WValue seed_v, WValue prefix_v) {
    uint32_t seed = (uint32_t)ref_i64(seed_v);
    uint8_t b[16];
    for (int i = 0; i < 16; i++) {
        seed = seed * 1664525u + 1013904223u;
        b[i] = (uint8_t)(seed >> 24);
    }
    switch ((uint32_t)ref_i64(seed_v) & 15u) {
        case 0: memset(b, 0, 16); break;
        case 1: memset(b, 0, 16); b[15] = 1; break;
        case 2: b[0] = 0xFF; break;
        case 3: b[0] = 0xFE; b[1] = 0x80; break;
        case 4: b[0] = 0xFE; b[1] = 0xBF; break;
        case 5: b[0] = 0xFE; b[1] = 0xC0; break;
        case 6: b[0] = 0xFC; break;
        case 7: b[0] = 0xFD; break;
        case 8: b[0] = 0x20; b[1] = 0x01; break;
    }
    int prefix = w_is_nil(prefix_v) ? -1 : (int)ref_i64(prefix_v);
    return w_ipv6(b, prefix);
}

WValue w_ref_mac_seed(WValue first_v, WValue seed_v) {
    uint8_t b[6];
    uint32_t seed = (uint32_t)ref_i64(seed_v);
    b[0] = (uint8_t)ref_i64(first_v);
    for (int i = 1; i < 6; i++) {
        seed = seed * 1664525u + 1013904223u;
        b[i] = (uint8_t)(seed >> 24);
    }
    return w_mac(b);
}

WValue w_ref_mac_broadcast(void) {
    uint8_t b[6]; memset(b, 0xFF, sizeof(b)); return w_mac(b);
}

WValue w_ref_array_ebits(WValue value) {
    return w_is_array(value) ? w_int(((WArray *)w_as_ptr(value))->ebits) : W_NIL;
}

WValue w_ref_array_size(WValue value) {
    return w_is_array(value) ? w_int(((WArray *)w_as_ptr(value))->size) : W_NIL;
}

WValue w_ref_array_item(WValue value, WValue index_v) {
    if (!w_is_array(value)) return W_NIL;
    return w_array_get(value, w_int(ref_i64(index_v)));
}
