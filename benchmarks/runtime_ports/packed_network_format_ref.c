/*
 * Support code for the true-public IPv4/IPv6/MAC formatter gate.
 *
 * The benchmark itself calls the installed public methods.  This file only
 * supplies deterministic receiver corpora, a representation fingerprint, and
 * CLOCK_THREAD_CPUTIME_ID.  It deliberately contains no reference formatter:
 * exact expected strings live in the Tungsten correctness fixture, while the
 * timed checksum compares each public result with the canonical w_to_s
 * formatter outside the timed region.
 */

#include "runtime.h"

#include <stddef.h>
#include <stdint.h>
#include <time.h>

extern WValue w_ipv6(const uint8_t *bytes, int cidr);
extern WValue w_mac(const uint8_t *bytes);

_Static_assert(offsetof(WNetAddr, type) == 0,
               "network formatter fixture: type offset");
_Static_assert(offsetof(WNetAddr, len) == 1,
               "network formatter fixture: len offset");
_Static_assert(offsetof(WNetAddr, prefix) == 2,
               "network formatter fixture: prefix offset");
_Static_assert(offsetof(WNetAddr, bytes) == 4,
               "network formatter fixture: bytes offset");
_Static_assert(sizeof(WNetAddr) == 32,
               "network formatter fixture: WNetAddr size");

static int64_t pnf_i64(WValue value) {
    /* Use nil for the benchmark's no-prefix sentinel. A raw negative ccall
     * literal such as -1 has the same bits as a reserved packed WValue and
     * therefore cannot be distinguished safely at this mixed ABI boundary. */
    if (w_is_nil(value)) return -1;
    if (w_is_int(value)) return w_as_int(value);
    if (w_is_double(value)) return (int64_t)w_as_double(value);
    /* ccall may pass an inferred raw machine integer rather than a WValue. */
    if (value <= 0x00007FFFFFFFFFFFULL) return (int64_t)value;
    return w_to_i64(value);
}
static uint32_t pnf_step(uint32_t x) {
    return x * 1664525u + 1013904223u;
}

WValue w_pnf_ipv4_case(WValue seed_v, WValue prefix_v) {
    uint32_t x = pnf_step((uint32_t)pnf_i64(seed_v) ^ 0x9e3779b9u);
    uint32_t address = x;
    switch ((uint32_t)pnf_i64(seed_v) & 7u) {
        case 0: address = 0x00000000u; break;
        case 1: address = 0xffffffffu; break;
        case 2: address = 0x7f000001u; break;
        case 3: address = 0xc0000201u; break;
        case 4: address = 0xcb007109u; break;
        default: break;
    }
    int64_t prefix = pnf_i64(prefix_v);
    return w_box_ipv4(address, prefix < 0 ? 63 : (int)prefix, 0);
}

WValue w_pnf_ipv6_case(WValue seed_v, WValue prefix_v) {
    uint32_t seed = (uint32_t)pnf_i64(seed_v);
    uint32_t x = seed ^ 0xa5a5f00du;
    uint8_t bytes[16];
    for (int i = 0; i < 16; i++) {
        x = pnf_step(x);
        bytes[i] = (uint8_t)(x >> 24);
    }
    switch (seed & 7u) {
        case 0:
            for (int i = 0; i < 16; i++) bytes[i] = 0;
            break;
        case 1:
            for (int i = 0; i < 16; i++) bytes[i] = 0;
            bytes[15] = 1;
            break;
        case 2:
            for (int i = 0; i < 16; i++) bytes[i] = 0xff;
            break;
        case 3:
            bytes[0] = 0x20; bytes[1] = 0x01;
            bytes[2] = 0x0d; bytes[3] = 0xb8;
            for (int i = 4; i < 15; i++) bytes[i] = 0;
            bytes[15] = 1;
            break;
        default:
            break;
    }
    return w_ipv6(bytes, (int)pnf_i64(prefix_v));
}

WValue w_pnf_mac_case(WValue seed_v) {
    uint32_t seed = (uint32_t)pnf_i64(seed_v);
    uint32_t x = seed ^ 0x6d2b79f5u;
    uint8_t bytes[6];
    for (int i = 0; i < 6; i++) {
        x = pnf_step(x);
        bytes[i] = (uint8_t)(x >> 24);
    }
    if ((seed & 7u) == 0)
        for (int i = 0; i < 6; i++) bytes[i] = 0;
    else if ((seed & 7u) == 1)
        for (int i = 0; i < 6; i++) bytes[i] = 0xff;
    return w_mac(bytes);
}

static uint64_t pnf_mix(uint64_t h, uint8_t byte) {
    h ^= byte;
    h *= 1099511628211ULL;
    return h;
}

WValue w_pnf_network_fingerprint(WValue value) {
    if (w_is_ipv4(value))
        return w_u64(((uint64_t)value ^ 0x4950763400000000ULL) *
                     0x9e3779b97f4a7c15ULL);
    if (!w_is_ipv6(value) && !w_is_mac(value)) return W_NIL;

    const WNetAddr *addr = (const WNetAddr *)w_as_ptr(value);
    uint64_t h = 1469598103934665603ULL;
    h = pnf_mix(h, addr->type);
    h = pnf_mix(h, addr->len);
    h = pnf_mix(h, addr->prefix);
    for (uint8_t i = 0; i < addr->len; i++) h = pnf_mix(h, addr->bytes[i]);
    return w_u64(h);
}

/* O(1), representation-independent consumption for the timed result.  The
 * full exact strings are checked before timing; this signature prevents the
 * optimizer from discarding formatter calls without requiring pointer
 * identity (a frozen slab legitimately returns fresh heap strings). */
WValue w_pnf_string_signature(WValue value) {
    char inline_buf[6];
    const char *bytes;
    size_t len;
    w_str_data(value, inline_buf, &bytes, &len);
    uint64_t first = len ? (uint8_t)bytes[0] : 0;
    uint64_t quarter = len ? (uint8_t)bytes[len / 4] : 0;
    uint64_t middle = len ? (uint8_t)bytes[len / 2] : 0;
    uint64_t last = len ? (uint8_t)bytes[len - 1] : 0;
    return w_int((int64_t)((len << 32) | (first << 24) |
                           (quarter << 16) | (middle << 8) | last));
}

WValue w_pnf_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) return W_NIL;
    return w_u64((uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec);
}
