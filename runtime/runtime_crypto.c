#ifndef W_RUNTIME_UNITY_INCLUDE
#ifdef __linux__
#define _GNU_SOURCE
#endif
#include "runtime_internal.h"
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <net/if_dl.h>
#include <sys/sysctl.h>
#endif
#ifdef __linux__
#include <netpacket/packet.h>
#include <sys/random.h>
#endif
#define die w_rt_die
#define dief w_rt_dief
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#endif

/* ---- Crypto: secure randomness, digests, and UUIDs ---- */

W_RT_INTERNAL void w_secure_random_fill(uint8_t *buf, size_t len) {
    if (len == 0) return;

#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    arc4random_buf(buf, len);
    return;
#elif defined(__linux__)
    size_t loff = 0;
    while (loff < len) {
        size_t want = len - loff;
        if (want > (1u << 20)) want = (1u << 20);
        ssize_t n = getrandom(buf + loff, want, 0);
        if (n > 0) {
            loff += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == ENOSYS || errno == EAGAIN)) break;
        dief("secure random failed: %s", strerror(errno));
    }
    if (loff == len) return;
#endif

    int flags = O_RDONLY;
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    int fd = open("/dev/urandom", flags);
    if (fd < 0) dief("secure random failed: %s", strerror(errno));
    size_t off = 0;
    while (off < len) {
        ssize_t n = read(fd, buf + off, len - off);
        if (n > 0) {
            off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        int saved = errno;
        close(fd);
        dief("secure random failed: %s", strerror(saved));
    }
    close(fd);
}

WValue w_crypto_random_bytes(WValue length_v) {
    int64_t length = w_to_i64(length_v);
    if (length < 0 || length > INT32_MAX) {
        w_raise(w_string("Crypto.random_bytes: length out of range"));
        return W_NIL;
    }
    WValue out = w_bytes_new(length);
    if (length > 0) {
        WArray *a = w_as_array(out);
        w_secure_random_fill((uint8_t *)a->slots, (size_t)length);
    }
    return out;
}

static void w_crypto_input_data(WValue data, const uint8_t **out, size_t *len, char inline_buf[6]) {
    if (w_is_bytes(data)) {
        WArray *a = w_as_array(data);
        *out = ((const uint8_t *)a->slots) + a->start;
        *len = (size_t)a->size;
        return;
    }
    if (w_is_rope(data) || w_is_stringy(data)) {
        const char *s;
        w_str_data(data, inline_buf, &s, len);
        *out = (const uint8_t *)s;
        return;
    }
    w_raise(w_string("Crypto digest: expected String or ByteArray"));
    *out = NULL;
    *len = 0;
}

static WValue w_hex_from_bytes(const uint8_t *bytes, size_t len) {
    static const char hex[] = "0123456789abcdef";
    size_t hlen = len * 2;
    if (hlen <= W_SLAB_SSO2_MAX) {
        char stack_out[W_SLAB_SSO2_MAX + 1];
        for (size_t i = 0; i < len; i++) {
            stack_out[i * 2] = hex[bytes[i] >> 4];
            stack_out[i * 2 + 1] = hex[bytes[i] & 0x0F];
        }
        stack_out[hlen] = '\0';
        return w_string_n_known_ascii(stack_out, hlen, 1);
    }
    if (__builtin_expect(!g_string_slab.base, 0)) w_slab_init();
    WString *ws = (WString *)malloc(sizeof(WString) + hlen + 1);
    w_heap_string_set_meta(ws, (uint32_t)hlen, 1);
    char *out = ws->data;
    for (size_t i = 0; i < len; i++) {
        out[i * 2] = hex[bytes[i] >> 4];
        out[i * 2 + 1] = hex[bytes[i] & 0x0F];
    }
    out[hlen] = '\0';
    return w_box_heap_str(ws);
}

static uint32_t w_rotl32(uint32_t x, uint32_t n) {
    return (x << n) | (x >> (32 - n));
}

static uint32_t w_rotr32(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

static uint64_t w_rotr64(uint64_t x, uint64_t n) {
    return (x >> n) | (x << (64 - n));
}

static uint32_t w_load_le32(const uint8_t *p) {
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint32_t w_load_be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | ((uint32_t)p[3]);
}

static uint64_t w_load_be64(const uint8_t *p) {
    return ((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) | ((uint64_t)p[2] << 40) | ((uint64_t)p[3] << 32) |
           ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) | ((uint64_t)p[6] << 8) | ((uint64_t)p[7]);
}

static void w_store_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static void w_store_be64(uint8_t *p, uint64_t v) {
    p[0] = (uint8_t)(v >> 56);
    p[1] = (uint8_t)(v >> 48);
    p[2] = (uint8_t)(v >> 40);
    p[3] = (uint8_t)(v >> 32);
    p[4] = (uint8_t)(v >> 24);
    p[5] = (uint8_t)(v >> 16);
    p[6] = (uint8_t)(v >> 8);
    p[7] = (uint8_t)v;
}

static size_t w_digest_padded_len(size_t len) {
    if (len > SIZE_MAX - 72) die("digest input too large");
    size_t padded = len + 1;
    while ((padded % 64) != 56) padded++;
    return padded + 8;
}

static size_t w_digest_padded_len_128(size_t len) {
    if (len > SIZE_MAX - 144) die("digest input too large");
    size_t padded = len + 1;
    while ((padded % 128) != 112) padded++;
    return padded + 16;
}

/* ================= hardware-accelerated crypto kernels ==================
 * Ported from bits/tungsten-crypto/runtime/sha256_hw.c (SHA-256 + Bitcoin
 * miner) and extended with SHA-1/SHA-512 compress, SHA-3/SHAKE, CRC-32/32C,
 * and AES-GCM. Feature-gated on the architecture with per-function target
 * attributes and cached runtime probes, so -march=native (which resets the
 * crypto feature on Apple Silicon) does not silently drop the fast path.
 * Differentially validated against Python hashlib / Go crypto vectors and a
 * GF(2^128) GHASH oracle. See spec/core/crypto_accel_spec.w. */

/* The hardware path is gated on the ARCHITECTURE, not on whether the
 * toolchain happened to enable the crypto feature for the whole
 * translation unit. Each function that issues SHA-256 instructions carries
 * its own `target("crypto")` attribute, so the code is emitted even when
 * the surrounding build disables the feature globally.
 *
 * This matters concretely: Tungsten compiles C with `-march=native`, and
 * on Apple Silicon `-march=native` RESETS the feature set to a baseline
 * that EXCLUDES crypto — Apple clang enables it by default, and passing
 * -march=native turns it off. Keying the hardware path off
 * __ARM_FEATURE_CRYPTO therefore silently compiled it out under the exact
 * build the miner uses, falling back to scalar at ~1/10 the speed with no
 * diagnostic. The attribute makes the fast path independent of that.
 *
 * Emitting the instructions is not the same as being allowed to run them,
 * so hw_probe() still checks the CPU at runtime before dispatching.
 */
#if defined(__aarch64__)
#  define W_SHA256_HW 1
#  define W_SHA256_HW_TARGET __attribute__((target("sha2")))
#  include <arm_neon.h>
#  if defined(__APPLE__)
#    include <sys/sysctl.h>
#  elif defined(__linux__)
#    include <sys/auxv.h>
#    include <asm/hwcap.h>
#  endif
#else
#  define W_SHA256_HW 0
#  define W_SHA256_HW_TARGET
#endif

/* ---- public interface ---------------------------------------------------
 *
 * The `hw` trio is the API the bit calls; it dispatches to whichever back end
 * is usable. The `sw` pair is the portable implementation, exported under its
 * own name so a single test binary can run both against each other. */

int64_t w_sha256_hw_available(void);
void w_sha256_hw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_hw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash,
                         uint32_t *out_best, uint32_t *out_best_hash);

void w_sha256_sw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_sw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash,
                         uint32_t *out_best, uint32_t *out_best_hash);

/* ---- constants ---------------------------------------------------------- */

/* First 32 bits of the fractional parts of the cube roots of the first 64
 * primes. 16-byte aligned because the hardware path loads it four words at a
 * time with vld1q_u32. */
static const uint32_t K256[64] __attribute__((aligned(16))) = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

/* First 32 bits of the fractional parts of the square roots of the first 8
 * primes: the IV every SHA-256 starts from. */
static const uint32_t IV256[8] __attribute__((aligned(16))) = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

/* Bitcoin's second SHA block hashes a 32-byte message: 0x80 terminator in
 * word 8 and a 256-bit length in word 15. The first hash's second block
 * covers an 80-byte header, i.e. 640 bits, with the terminator in word 4. */
#define PAD_TERMINATOR 0x80000000u
#define HEADER_BITLEN  640u
#define DIGEST_BITLEN  256u

/* ---- shared helpers ----------------------------------------------------- */

static inline uint32_t bswap32(uint32_t x) { return __builtin_bswap32(x); }

/* Shift form rather than memcpy+bswap32 so the result depends on the message
 * bytes and not on the host's byte order; clang still folds it to `ldr`+`rev`. */
static inline uint32_t load_be32(const uint8_t *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) |
         (uint32_t)p[3];
}

/* Bitcoin's magnitude test: is the digest, read as a little-endian 256-bit
 * integer, <= target? target_be[0] is the most significant word, and the most
 * significant word of the digest's value is bswap32(H7) — hence the 7-i. */
static inline int meets_target(const uint32_t digest[8], const uint32_t target_be[8]) {
  for (int i = 0; i < 8; i++) {
    uint32_t v = bswap32(digest[7 - i]);
    if (v < target_be[i]) return 1;
    if (v > target_be[i]) return 0;
  }
  return 1; /* exactly equal still meets the target */
}

/* Block 2 of the first hash, with the nonce slot left at zero. Both back ends
 * build the same 16 words, so this lives in one place.
 *
 * w[0..2] are the merkle-root tail, time and bits (header bytes 64..75);
 * w[3] is the nonce; w[4..15] are pure SHA-256 padding for a 640-bit message.
 * The header stores the nonce little-endian, so the big-endian schedule word
 * the compression consumes is its byteswap — filled in per candidate. */
static inline void build_block2(uint32_t w[16], const uint8_t tail[12]) {
  w[0] = load_be32(tail + 0);
  w[1] = load_be32(tail + 4);
  w[2] = load_be32(tail + 8);
  w[3] = 0;
  w[4] = PAD_TERMINATOR;
  for (int i = 5; i < 15; i++) w[i] = 0;
  w[15] = HEADER_BITLEN;
}

/* Padding half of the second hash's block. The message is the 32-byte first
 * digest, so words 0..7 are refilled per candidate and 8..15 never change —
 * they are written once, outside the search loop. */
static inline void build_second_pad(uint32_t w[16]) {
  w[8] = PAD_TERMINATOR;
  for (int i = 9; i < 15; i++) w[i] = 0;
  w[15] = DIGEST_BITLEN;
}

/* ==== portable software path ============================================= */

static inline uint32_t rotr32(uint32_t x, int n) {
  return (x >> n) | (x << (32 - n));
}

static inline uint32_t ssig0(uint32_t x) { return rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3); }
static inline uint32_t ssig1(uint32_t x) { return rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10); }
static inline uint32_t bsig0(uint32_t x) { return rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22); }
static inline uint32_t bsig1(uint32_t x) { return rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25); }

/* Expand w[from-16 .. from-1] forward to w[63]. `from` is a parameter because
 * the miner precomputes w[16] and w[17] once per job (neither depends on the
 * nonce in w[3]) and resumes expansion at 18. */
static void sw_expand(uint32_t w[64], int from) {
  for (int i = from; i < 64; i++)
    w[i] = w[i - 16] + ssig0(w[i - 15]) + w[i - 7] + ssig1(w[i - 2]);
}

/* Rounds [from, to) of the compression function, operating on the eight
 * working variables in place. No feed-forward add — callers decide whether
 * and where to apply it, which is what makes partial-block reuse possible. */
static void sw_rounds(uint32_t v[8], const uint32_t w[64], int from, int to) {
  uint32_t a = v[0], b = v[1], c = v[2], d = v[3];
  uint32_t e = v[4], f = v[5], g = v[6], h = v[7];
  for (int i = from; i < to; i++) {
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t t1 = h + bsig1(e) + ch + K256[i] + w[i];
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = bsig0(a) + maj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  v[0] = a; v[1] = b; v[2] = c; v[3] = d;
  v[4] = e; v[5] = f; v[6] = g; v[7] = h;
}

/* One full block: expand, run all 64 rounds, feed forward into `state`. */
static void sw_block(uint32_t state[8], uint32_t w[64]) {
  uint32_t v[8];
  sw_expand(w, 16);
  memcpy(v, state, sizeof v);
  sw_rounds(v, w, 0, 64);
  for (int i = 0; i < 8; i++) state[i] += v[i];
}

void w_sha256_sw_compress(uint32_t *state, const uint8_t *data, size_t nblocks) {
  uint32_t w[64];
  for (size_t b = 0; b < nblocks; b++) {
    for (int j = 0; j < 16; j++) w[j] = load_be32(data + b * 64 + j * 4);
    sw_block(state, w);
  }
}

int64_t w_sha256_sw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash,
                         uint32_t *out_best, uint32_t *out_best_hash) {
  uint32_t w1[64], w2[64];
  uint32_t resume[8]; /* working variables after rounds 0..2 of block 2 */

  build_block2(w1, tail);

  /* Per-job reuse, exactly as miner.w derives it:
   *
   *   w[16] = w[0] + ssig0(w[1]) + w[9]  + ssig1(w[14])
   *   w[17] = w[1] + ssig0(w[2]) + w[10] + ssig1(w[15])
   *
   * Neither reads w[3], so both are nonce-independent. Written in the general
   * form rather than folded against the zero padding words so the derivation
   * stays checkable against the FIPS recurrence. */
  w1[16] = w1[0] + ssig0(w1[1]) + w1[9] + ssig1(w1[14]);
  w1[17] = w1[1] + ssig0(w1[2]) + w1[10] + ssig1(w1[15]);

  /* Rounds 0..2 consume w[0..2] only, so their output is fixed for the whole
   * search and the per-nonce compression resumes at round 3. */
  memcpy(resume, midstate, 8 * sizeof(uint32_t));
  sw_rounds(resume, w1, 0, 3);

  build_second_pad(w2);

  uint32_t best = 0xFFFFFFFFu;

  for (int64_t i = 0; i < count; i++) {
    uint32_t nonce = (uint32_t)(start + i);
    uint32_t v[8], st1[8], st2[8], h7;

    /* --- first hash, block 2 only: block 1 is the caller's midstate ---
     * Expansion resumes at 18 because w1[16] and w1[17] are nonce-independent
     * and were written above; w1[3] is the only input word that moves. */
    w1[3] = bswap32(nonce);
    sw_expand(w1, 18);
    memcpy(v, resume, sizeof v);
    sw_rounds(v, w1, 3, 64);
    for (int j = 0; j < 8; j++) st1[j] = midstate[j] + v[j];

    /* --- second hash of the 32-byte digest --- */
    for (int j = 0; j < 8; j++) w2[j] = st1[j];
    sw_expand(w2, 16);

    /* Reject on H7 alone. The round variables rotate, so the `h` feeding H7
     * after round 63 is the `e` standing after round 60: rounds 61..63 cannot
     * influence it and are skipped. bswap32(H7) is the top of the compared
     * value, so this one word rejects all but a vanishing fraction. */
    memcpy(v, IV256, sizeof v);
    sw_rounds(v, w2, 0, 61);
    h7 = IV256[7] + v[4];
    {
      /* Maintain the running best here too. Without this the portable path
       * silently returned nothing through out_best/out_best_hash, and since
       * w_sha256_hw_mine forwards to this function on every non-ARM target,
       * those outputs did nothing at all off Apple Silicon. */
      uint32_t bv = bswap32(h7);
      if (bv < best) {
        best = bv;
        if (out_best_hash) {
          uint32_t full[8];
          memcpy(full, v, sizeof full);
          sw_rounds(full, w2, 61, 64);
          for (int j = 0; j < 8; j++) full[j] = full[j] + IV256[j];
          memcpy(out_best_hash, full, sizeof full);
        }
      }
    }
    if (bswap32(h7) > target_be[0]) continue;

    /* Rare: finish the block properly and do the full 256-bit compare. */
    memcpy(v, IV256, sizeof v);
    sw_rounds(v, w2, 0, 64);
    for (int j = 0; j < 8; j++) st2[j] = IV256[j] + v[j];
    if (meets_target(st2, target_be)) {
      if (out_hash) memcpy(out_hash, st2, sizeof st2);
      return (int64_t)nonce;
    }
  }
  if (out_best) *out_best = best;
  return -1;
}

/* ==== ARMv8 SHA-256 extension path ======================================= */

#if W_SHA256_HW

/* SHA256H/SHA256H2 consume four rounds per pair and SHA256SU0/SHA256SU1
 * produce four schedule words per pair, so the whole block is sixteen groups
 * of four rounds. Each group needs its round constants pre-added to the
 * message words, and that add is issued one group ahead so it overlaps with
 * the (long-latency, serially dependent) hash instructions of the current
 * group. `wk` therefore ping-pongs between two registers.
 *
 * Group i runs rounds 4i..4i+3 against msg[i % 4] and, for i < 12, rewrites
 * msg[i % 4] in place with schedule words 16+4i..19+4i. SHA256SU0 folds in
 * sigma0 of the next quad; SHA256SU1 adds sigma1 of the quad two ahead plus
 * the wrapped-around w[i-7] term. */
#define HW_GROUP(ma, mb, mc, md, wk_cur, wk_next, kidx) \
  do {                                                  \
    (ma) = vsha256su0q_u32((ma), (mb));                 \
    tmp = s0;                                           \
    (wk_next) = vaddq_u32((mb), vld1q_u32(&K256[kidx]));\
    s0 = vsha256hq_u32(s0, s1, (wk_cur));               \
    s1 = vsha256h2q_u32(s1, tmp, (wk_cur));             \
    (ma) = vsha256su1q_u32((ma), (mc), (md));           \
  } while (0)

/* Groups 12..15 run rounds 48..63, for which the schedule is already complete
 * — same round pair, no SU work. */
#define HW_GROUP_NOSU(mnext, wk_cur, wk_next, kidx)      \
  do {                                                   \
    tmp = s0;                                            \
    (wk_next) = vaddq_u32((mnext), vld1q_u32(&K256[kidx]));\
    s0 = vsha256hq_u32(s0, s1, (wk_cur));                \
    s1 = vsha256h2q_u32(s1, tmp, (wk_cur));              \
  } while (0)

/* All 64 rounds, WITHOUT the feed-forward add. Leaving the add to the caller
 * is what lets the miner read a single output word (H7) off lane 3 of `efgh`
 * and bail before committing the other seven. */
__attribute__((always_inline)) W_SHA256_HW_TARGET static inline void
hw_rounds(uint32x4_t *abcd, uint32x4_t *efgh, uint32x4_t m0, uint32x4_t m1,
          uint32x4_t m2, uint32x4_t m3) {
  uint32x4_t s0 = *abcd, s1 = *efgh, tmp;
  uint32x4_t wk0 = vaddq_u32(m0, vld1q_u32(&K256[0]));
  uint32x4_t wk1;

  HW_GROUP(m0, m1, m2, m3, wk0, wk1, 4);   /* rounds  0.. 3 -> w[16..19] */
  HW_GROUP(m1, m2, m3, m0, wk1, wk0, 8);   /* rounds  4.. 7 -> w[20..23] */
  HW_GROUP(m2, m3, m0, m1, wk0, wk1, 12);  /* rounds  8..11 -> w[24..27] */
  HW_GROUP(m3, m0, m1, m2, wk1, wk0, 16);  /* rounds 12..15 -> w[28..31] */
  HW_GROUP(m0, m1, m2, m3, wk0, wk1, 20);  /* rounds 16..19 -> w[32..35] */
  HW_GROUP(m1, m2, m3, m0, wk1, wk0, 24);  /* rounds 20..23 -> w[36..39] */
  HW_GROUP(m2, m3, m0, m1, wk0, wk1, 28);  /* rounds 24..27 -> w[40..43] */
  HW_GROUP(m3, m0, m1, m2, wk1, wk0, 32);  /* rounds 28..31 -> w[44..47] */
  HW_GROUP(m0, m1, m2, m3, wk0, wk1, 36);  /* rounds 32..35 -> w[48..51] */
  HW_GROUP(m1, m2, m3, m0, wk1, wk0, 40);  /* rounds 36..39 -> w[52..55] */
  HW_GROUP(m2, m3, m0, m1, wk0, wk1, 44);  /* rounds 40..43 -> w[56..59] */
  HW_GROUP(m3, m0, m1, m2, wk1, wk0, 48);  /* rounds 44..47 -> w[60..63] */
  HW_GROUP_NOSU(m1, wk0, wk1, 52);         /* rounds 48..51 */
  HW_GROUP_NOSU(m2, wk1, wk0, 56);         /* rounds 52..55 */
  HW_GROUP_NOSU(m3, wk0, wk1, 60);         /* rounds 56..59 */
  tmp = s0;                                /* rounds 60..63: nothing left to
                                              stage, so no next wk */
  s0 = vsha256hq_u32(s0, s1, wk1);
  s1 = vsha256h2q_u32(s1, tmp, wk1);

  *abcd = s0;
  *efgh = s1;
}

#undef HW_GROUP
#undef HW_GROUP_NOSU

/* ---- what actually limits this kernel -----------------------------------
 *
 * Measured on the target core with independent streams of each opcode:
 *
 *   SHA256H + SHA256H2, 1 dependent chain     1.76 G instr/s
 *   SHA256H + SHA256H2, >= 2 chains           2.19 G instr/s   <- saturated
 *   SHA256SU0 / SHA256SU1                     5.9  G instr/s
 *   the miner's 2-hash + 2-SU group mix       2.21 G hash + 2.21 G SU
 *
 * Two facts follow, and they set the whole shape of the code below.
 *
 * 1. The schedule instructions are free. SU0/SU1 run at ~2.7x the hash rate
 *    and, in the mixed sequence, do not slow the hash pair down at all — they
 *    are not competing for the same issue slot. So folding nonce-independent
 *    parts of the message schedule buys nothing; the ONLY thing that moves
 *    the throughput needle is emitting fewer SHA256H/SHA256H2 instructions.
 *
 * 2. Throughput, not latency, is the wall — but only just. A single chain
 *    reaches 1.76 of the 2.19 G instr/s ceiling on its own, because the
 *    out-of-order window already overlaps the tail of one candidate's second
 *    hash with the head of the next candidate's first hash. Interleaving
 *    recovers the remaining ~20%, not the 2x the latency model predicts.
 *
 * At 32 hash instructions per block and two blocks per candidate, 64 hash
 * instructions per nonce puts a hard 2.19G/64 = 34.2 MH/s ceiling on this
 * core. Both optimizations below exist to get under that number:
 * HW_ROUNDS1_NW skips the first hash pair of the first block and
 * HW_ROUNDS2_NW the last hash pair of the second, for 60 per nonce.
 *
 * ---- N-way interleaved round engine --------------------------------------
 *
 * NW independent nonces advance through the same groups in lockstep, so each
 * group issues 2*NW mutually independent hash instructions instead of 2.
 * Structurally this is hw_rounds with every statement replaced by a
 * lane-indexed loop over a literal bound, so it unrolls to the same
 * instruction mix, just NW-wide. It is a macro rather than a function so the
 * lane arrays are unconditionally scalar-replaced into registers; NW=1
 * reproduces hw_rounds and is what the range tail runs.
 *
 * One deliberate difference from hw_rounds: the K-add is issued in the group
 * that consumes it instead of one group ahead. The ping-pong that staged it
 * early existed to hide the add behind the hash chain of a single stream;
 * with NW streams the other lanes already cover it.
 *
 * The lane loop is a single pass rather than one pass per opcode, which looks
 * like it would give up interleaving and does not: cross-lane there are no
 * dependencies at all, and the reorder window is far wider than the ~24
 * instructions a group emits. What it buys is register pressure. `wk` and
 * `tmp` die two instructions after they are born, so ONE of each covers all
 * NW lanes instead of NW of each; only A, E and the four message quads stay
 * live per lane. Six registers a lane against the machine's 32 is the
 * difference between NW=4 running out of registers and not.
 *
 * Group I runs rounds 4I..4I+3 against m[I%4]. SU=1 rewrites that quad in
 * place with schedule words 16+4I..19+4I; groups 12..15 need no schedule. */
#define HW_NW_GROUP(NW, A, E, M, I, SU)                                        \
  do {                                                                         \
    const uint32x4_t kv_ = vld1q_u32(&K256[4 * (I)]);                          \
    for (int l_ = 0; l_ < (NW); l_++) {                                        \
      /* The K-add must read the quad before SU0 overwrites it. */             \
      uint32x4_t wk_ = vaddq_u32((M)[l_][(I) & 3], kv_);                       \
      uint32x4_t tm_;                                                          \
      if (SU)                                                                  \
        (M)[l_][(I) & 3] =                                                     \
            vsha256su0q_u32((M)[l_][(I) & 3], (M)[l_][((I) + 1) & 3]);         \
      tm_ = (A)[l_];                                                           \
      (A)[l_] = vsha256hq_u32((A)[l_], (E)[l_], wk_);                          \
      (E)[l_] = vsha256h2q_u32((E)[l_], tm_, wk_);                             \
      if (SU)                                                                  \
        (M)[l_][(I) & 3] = vsha256su1q_u32(                                    \
            (M)[l_][(I) & 3], (M)[l_][((I) + 2) & 3], (M)[l_][((I) + 3) & 3]); \
    }                                                                          \
  } while (0)

/* Group I's schedule half alone: turns m[I%4] into w[16+4I..19+4I] without
 * touching the chaining state or emitting a single hash instruction. Used for
 * group 0 of the header's second block — see HW_ROUNDS1_NW. */
#define HW_NW_GROUP_SU(NW, M, I)                                               \
  do {                                                                         \
    for (int l_ = 0; l_ < (NW); l_++) {                                        \
      (M)[l_][(I) & 3] =                                                       \
          vsha256su0q_u32((M)[l_][(I) & 3], (M)[l_][((I) + 1) & 3]);           \
      (M)[l_][(I) & 3] = vsha256su1q_u32(                                      \
          (M)[l_][(I) & 3], (M)[l_][((I) + 2) & 3], (M)[l_][((I) + 3) & 3]);   \
    }                                                                          \
  } while (0)

/* The header's second block, rounds 4..63, for NW candidates.
 *
 * Group 0 is present for its schedule side effect only. Rounds 0..2 read
 * w[0..2] and never the nonce, so the state they leave is fixed for the whole
 * job; round 3 is the first to read w[3], and it reads it LINEARLY — t1 is a
 * constant plus w[3], t2 is a constant, and every other working variable just
 * shifts down. The post-round-3 state is therefore two job constants plus the
 * nonce word, which hw_mine_impl computes with two scalar adds. That retires
 * the first SHA256H pair of every candidate for free. The schedule half of
 * group 0 still has to run: it is what turns m[0] into w[16..19]. */
#define HW_ROUNDS1_NW(NW, A, E, M)                    \
  do {                                                \
    HW_NW_GROUP_SU(NW, M, 0);                       \
    HW_NW_GROUP(NW, A, E, M, 1, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 2, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 3, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 4, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 5, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 6, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 7, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 8, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 9, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 10, 1);                \
    HW_NW_GROUP(NW, A, E, M, 11, 1);                \
    HW_NW_GROUP(NW, A, E, M, 12, 0);                \
    HW_NW_GROUP(NW, A, E, M, 13, 0);                \
    HW_NW_GROUP(NW, A, E, M, 14, 0);                \
    HW_NW_GROUP(NW, A, E, M, 15, 0);                \
  } while (0)

/* The second hash, rounds 0..59, for NW candidates.
 *
 * Group 15 (rounds 60..63) is missing on purpose. The reject test reads H7
 * only, and H7 = IV[7] + h-after-63; the round variables rotate, so h after
 * round 63 is g after 62 is f after 61 is e after 60. Rounds 61..63 cannot
 * reach it. hw_h7_from_g14 finishes round 60 in scalar off the saturated
 * crypto pipe, which is the hardware analogue of the software path's
 * sw_rounds(v, w2, 0, 61). The candidates that survive the test are rare
 * enough to re-hash from scratch. */
#define HW_ROUNDS2_NW(NW, A, E, M)                    \
  do {                                                \
    HW_NW_GROUP(NW, A, E, M, 0, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 1, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 2, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 3, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 4, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 5, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 6, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 7, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 8, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 9, 1);                 \
    HW_NW_GROUP(NW, A, E, M, 10, 1);                \
    HW_NW_GROUP(NW, A, E, M, 11, 1);                \
    HW_NW_GROUP(NW, A, E, M, 12, 0);                \
    HW_NW_GROUP(NW, A, E, M, 13, 0);                \
    HW_NW_GROUP(NW, A, E, M, 14, 0);                \
  } while (0)

/* Round 60 of the second hash, in scalar, from the state standing after
 * group 14 — see HW_ROUNDS2_NW. `abcd`/`efgh` are raw working variables (no
 * feed-forward yet), and w[60] is lane 0 of the quad group 11 produced. */
W_SHA256_HW_TARGET static inline uint32_t
hw_h7_from_g14(uint32x4_t abcd, uint32x4_t efgh, uint32x4_t w60_63) {
  uint32_t d = vgetq_lane_u32(abcd, 3);
  uint32_t e = vgetq_lane_u32(efgh, 0), f = vgetq_lane_u32(efgh, 1);
  uint32_t g = vgetq_lane_u32(efgh, 2), h = vgetq_lane_u32(efgh, 3);
  uint32_t t1 = h + bsig1(e) + ((e & f) ^ (~e & g)) + K256[60] +
                vgetq_lane_u32(w60_63, 0);
  return IV256[7] + d + t1;
}

W_SHA256_HW_TARGET static void hw_compress_impl(uint32_t *state, const uint8_t *data, size_t nblocks) {
  uint32x4_t abcd = vld1q_u32(state);
  uint32x4_t efgh = vld1q_u32(state + 4);

  for (size_t b = 0; b < nblocks; b++, data += 64) {
    uint32x4_t sa = abcd, se = efgh;
    /* Message bytes are big-endian; NEON loads them little-endian. One
     * vrev32q_u8 per quad converts a 16-byte load into four schedule words. */
    uint32x4_t m0 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 0)));
    uint32x4_t m1 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 16)));
    uint32x4_t m2 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 32)));
    uint32x4_t m3 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 48)));

    hw_rounds(&abcd, &efgh, m0, m1, m2, m3);
    abcd = vaddq_u32(abcd, sa);
    efgh = vaddq_u32(efgh, se);
  }

  vst1q_u32(state, abcd);
  vst1q_u32(state + 4, efgh);
}

/* The full 256-bit digest of one candidate, by the book: both blocks, all 64
 * rounds each, both feed-forwards. This is the cold path. The search loop
 * carries only enough state to produce H7, so anything that needs the whole
 * digest — a candidate that passes the reject test, or a new best-so-far —
 * re-hashes the nonce here. Both happen a handful of times per 2^32 scan, so
 * doubling their cost is invisible; what it buys is a hot loop that never
 * carries the other seven words. */
W_SHA256_HW_TARGET static void hw_digest_one(const uint32_t *midstate,
                                             const uint32_t w1[16],
                                             uint32_t nonce, uint32_t out[8]) {
  uint32_t w[16] __attribute__((aligned(16)));
  const uint32x4_t mid_abcd = vld1q_u32(midstate);
  const uint32x4_t mid_efgh = vld1q_u32(midstate + 4);
  const uint32x4_t iv_abcd = vld1q_u32(&IV256[0]);
  const uint32x4_t iv_efgh = vld1q_u32(&IV256[4]);
  uint32x4_t a = mid_abcd, e = mid_efgh;

  memcpy(w, w1, 16 * sizeof(uint32_t));
  w[3] = bswap32(nonce);
  hw_rounds(&a, &e, vld1q_u32(w), vld1q_u32(w + 4), vld1q_u32(w + 8),
            vld1q_u32(w + 12));
  vst1q_u32(w + 0, vaddq_u32(a, mid_abcd));
  vst1q_u32(w + 4, vaddq_u32(e, mid_efgh));
  build_second_pad(w);

  a = iv_abcd;
  e = iv_efgh;
  hw_rounds(&a, &e, vld1q_u32(w), vld1q_u32(w + 4), vld1q_u32(w + 8),
            vld1q_u32(w + 12));
  vst1q_u32(out + 0, vaddq_u32(a, iv_abcd));
  vst1q_u32(out + 4, vaddq_u32(e, iv_efgh));
}

/* How many nonces the search advances in lockstep. Tuned by measurement on
 * the target core; override at build time to re-tune elsewhere. NW=1
 * degenerates to a single-chain loop, which is what the range tail runs. */
#ifndef W_SHA256_HW_WAYS
#  define W_SHA256_HW_WAYS 4
#endif

/* One lockstep step over NW nonces starting at index BASE.
 *
 * Everything the two hashes need is lane-local, so the only cross-lane logic
 * is the result scan at the bottom — and that walks lanes in ascending nonce
 * order and returns from the FIRST hit, which is what makes an interleaved
 * search report the same winner as a serial one. Lanes past the winner have
 * already been hashed by then, but they are never inspected: `best` and
 * out_best_hash advance only up to the returning lane, matching the serial
 * loop's early return exactly. (out_best is written on the -1 path only, as
 * before, so the extra lanes cannot leak into it either.) */
#define HW_MINE_STEP(NW, BASE)                                                \
  do {                                                                        \
    uint32x4_t a_[NW], e_[NW], m_[NW][4];                                     \
    uint32_t v_[NW];                                                          \
                                                                              \
    /* First hash, block 2 only: block 1 is the caller's midstate, and the    \
     * nonce is the single moving word (header byte order, hence bswap).      \
     * `a3`/`e3` carry the post-round-3 state described at HW_ROUNDS1_NW —    \
     * lane 0 of each is the one word that moves with the nonce. */           \
    for (int l_ = 0; l_ < (NW); l_++) {                                       \
      uint32_t n_ = bswap32((uint32_t)(start + (BASE) + l_));                 \
      m_[l_][0] = vsetq_lane_u32(n_, hdr0, 3);                                \
      m_[l_][1] = hdr1;                                                       \
      m_[l_][2] = hdr2;                                                       \
      m_[l_][3] = hdr3;                                                       \
      a_[l_] = vsetq_lane_u32(r3_a + n_, r3_abcd, 0);                         \
      e_[l_] = vsetq_lane_u32(r3_e + n_, r3_efgh, 0);                         \
    }                                                                         \
    HW_ROUNDS1_NW(NW, a_, e_, m_);                                            \
                                                                              \
    /* Feed forward into the first digest, which is verbatim the message of   \
     * the second hash: words 0..7, then the fixed 256-bit-length padding. */ \
    for (int l_ = 0; l_ < (NW); l_++) {                                       \
      m_[l_][0] = vaddq_u32(a_[l_], mid_abcd);                                \
      m_[l_][1] = vaddq_u32(e_[l_], mid_efgh);                                \
      m_[l_][2] = pad2;                                                       \
      m_[l_][3] = pad3;                                                       \
      a_[l_] = iv_abcd;                                                       \
      e_[l_] = iv_efgh;                                                       \
    }                                                                         \
    HW_ROUNDS2_NW(NW, a_, e_, m_);                                            \
                                                                              \
    /* bswap32(H7) is the top 32 bits of the value Bitcoin compares, so this  \
     * one word turns away all but a vanishing fraction of candidates. */     \
    for (int l_ = 0; l_ < (NW); l_++)                                         \
      v_[l_] = bswap32(hw_h7_from_g14(a_[l_], e_[l_], m_[l_][3]));            \
                                                                              \
    for (int l_ = 0; l_ < (NW); l_++) {                                       \
      if (v_[l_] < best) {                                                    \
        best = v_[l_];                                                        \
        /* An improvement lands a few dozen times per 2^32 scan, so the       \
         * re-hash below never reaches steady state. */                       \
        if (out_best_hash)                                                    \
          hw_digest_one(midstate, w1,                                         \
                        (uint32_t)(start + (BASE) + l_), out_best_hash);      \
      }                                                                       \
      if (v_[l_] > top) continue;                                             \
      {                                                                       \
        uint32_t st2_[8];                                                     \
        hw_digest_one(midstate, w1, (uint32_t)(start + (BASE) + l_), st2_);   \
        if (meets_target(st2_, target_be)) {                                  \
          if (out_hash) memcpy(out_hash, st2_, sizeof st2_);                  \
          return (int64_t)(uint32_t)(start + (BASE) + l_);                    \
        }                                                                     \
      }                                                                       \
    }                                                                         \
  } while (0)

W_SHA256_HW_TARGET static int64_t hw_mine_impl(const uint32_t *midstate, const uint8_t *tail,
                            const uint32_t *target_be, uint32_t start,
                            int64_t count, uint32_t *out_hash,
                         uint32_t *out_best, uint32_t *out_best_hash) {
  enum { NW = W_SHA256_HW_WAYS };
  uint32_t w1[16] __attribute__((aligned(16)));
  uint32_t w2[16] __attribute__((aligned(16)));
  const uint32x4_t mid_abcd = vld1q_u32(midstate);
  const uint32x4_t mid_efgh = vld1q_u32(midstate + 4);
  const uint32x4_t iv_abcd = vld1q_u32(&IV256[0]);
  const uint32x4_t iv_efgh = vld1q_u32(&IV256[4]);
  const uint32_t top = target_be[0];
  uint32x4_t r3_abcd, r3_efgh;
  uint32_t r3_a, r3_e;

  build_block2(w1, tail);
  build_second_pad(w2);

  /* Job constants, hoisted into registers once: the three fixed quads of the
   * header's second block (lane 3 of hdr0 is the nonce slot, overwritten per
   * candidate) and the two fixed padding quads of the second hash. */
  const uint32x4_t hdr0 = vld1q_u32(w1 + 0);
  const uint32x4_t hdr1 = vld1q_u32(w1 + 4);
  const uint32x4_t hdr2 = vld1q_u32(w1 + 8);
  const uint32x4_t hdr3 = vld1q_u32(w1 + 12);
  const uint32x4_t pad2 = vld1q_u32(w2 + 8);
  const uint32x4_t pad3 = vld1q_u32(w2 + 12);

  /* The post-round-3 state of the header's second block, which HW_ROUNDS1_NW
   * starts from. Rounds 0..2 read w[0..2] only, so sw_rounds can run them
   * once here against the (still zero) nonce slot; round 3 is then written
   * out longhand because w[3] enters t1 additively and nowhere else:
   *
   *   a' = (t1const + t2const) + w[3]      b' = a   c' = b   d' = c
   *   e' = (d + t1const)       + w[3]      f' = e   g' = f   h' = g
   *
   * so lane 0 of each half is a scalar add per candidate and the other three
   * lanes are loop-invariant. */
  {
    uint32_t r[8], q[4] __attribute__((aligned(16)));
    uint32_t a, b, c, d, e, f, g, h, t1c, t2;
    memcpy(r, midstate, sizeof r);
    sw_rounds(r, w1, 0, 3);
    a = r[0]; b = r[1]; c = r[2]; d = r[3];
    e = r[4]; f = r[5]; g = r[6]; h = r[7];
    t1c = h + bsig1(e) + (((e & f) ^ (~e & g))) + K256[3];
    t2 = bsig0(a) + ((a & b) ^ (a & c) ^ (b & c));
    r3_a = t1c + t2;
    r3_e = d + t1c;
    q[0] = 0; q[1] = a; q[2] = b; q[3] = c;
    r3_abcd = vld1q_u32(q);
    q[0] = 0; q[1] = e; q[2] = f; q[3] = g;
    r3_efgh = vld1q_u32(q);
  }

  uint32_t best = 0xFFFFFFFFu;
  int64_t i = 0;

  /* The interleaved body only runs while a full group of NW nonces is still
   * inside the range, so no nonce past start+count-1 is ever hashed. */
  for (; i + NW <= count; i += NW) HW_MINE_STEP(NW, i);
  for (; i < count; i++) HW_MINE_STEP(1, i);

  if (out_best) *out_best = best;
  return -1;
}

/* The compile-time guard says the toolchain emitted the instructions; this
 * says the CPU executing them has FEAT_SHA256. They can differ when an object
 * built with -march=armv8-a+crypto is shipped to a plain armv8-a core, and a
 * mismatch is SIGILL rather than a wrong answer, so it is worth one probe. */
static int hw_probe(void) {
#if defined(__APPLE__)
  int val = 0;
  size_t len = sizeof val;
  if (sysctlbyname("hw.optional.arm.FEAT_SHA256", &val, &len, NULL, 0) == 0)
    return val != 0;
  /* Key absent on older kernels; every arm64 Mac ships the extension. */
  return 1;
#elif defined(__linux__)
  return (getauxval(AT_HWCAP) & HWCAP_SHA2) != 0;
#else
  return 1;
#endif
}

#endif /* W_SHA256_HW */

/* ==== public entry points ================================================ */

int64_t w_sha256_hw_available(void) {
#if W_SHA256_HW
  /* Benign race: hw_probe is pure and every writer stores the same value. */
  static int cached = -1;
  int v = cached;
  if (v < 0) cached = v = hw_probe();
  return v;
#else
  return 0;
#endif
}

void w_sha256_hw_compress(uint32_t *state, const uint8_t *data, size_t nblocks) {
#if W_SHA256_HW
  if (w_sha256_hw_available()) {
    hw_compress_impl(state, data, nblocks);
    return;
  }
#endif
  w_sha256_sw_compress(state, data, nblocks);
}

int64_t w_sha256_hw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash,
                         uint32_t *out_best, uint32_t *out_best_hash) {
#if W_SHA256_HW
  if (w_sha256_hw_available())
    return hw_mine_impl(midstate, tail, target_be, start, count, out_hash, out_best, out_best_hash);
#endif
  return w_sha256_sw_mine(midstate, tail, target_be, start, count, out_hash, out_best, out_best_hash);
}

/* ---- SHA-1 / SHA-512 hw compress, SHA-3, CRC-32, AES-GCM ---------------- */
#if defined(__aarch64__)
#  define W_CRYPTO_HW 1
#  define W_TARGET_SHA2 __attribute__((target("sha2")))
#  define W_TARGET_SHA3 __attribute__((target("sha3")))
#  define W_TARGET_CRC  __attribute__((target("crc")))
#  define W_TARGET_AES  __attribute__((target("aes")))
#  include <arm_neon.h>
#  if defined(__APPLE__)
#    include <sys/sysctl.h>
#  elif defined(__linux__)
#    include <sys/auxv.h>
#    include <asm/hwcap.h>
#  endif
#else
#  define W_CRYPTO_HW 0
#  define W_TARGET_SHA2
#  define W_TARGET_SHA3
#  define W_TARGET_CRC
#  define W_TARGET_AES
#endif

/* One cached-probe helper per feature family. Benign race: the probe is pure
 * and every writer stores the same value. */
#if W_CRYPTO_HW
#if defined(__APPLE__)
static int w_hw_sysctl_probe(const char *name) {
    int val = 0;
    size_t len = sizeof val;
    if (sysctlbyname(name, &val, &len, NULL, 0) == 0) return val != 0;
    /* Key absent on older kernels; every arm64 Mac ships these extensions. */
    return 1;
}
#endif
#endif

static int w_hw_sha1_available(void) {
#if W_CRYPTO_HW
    static int cached = -1;
    int v = cached;
    if (v < 0) {
#if defined(__APPLE__)
        cached = v = w_hw_sysctl_probe("hw.optional.arm.FEAT_SHA1");
#elif defined(__linux__)
        cached = v = (getauxval(AT_HWCAP) & HWCAP_SHA1) != 0;
#else
        cached = v = 1;
#endif
    }
    return v;
#else
    return 0;
#endif
}

static int w_hw_sha512_available(void) {
#if W_CRYPTO_HW
    static int cached = -1;
    int v = cached;
    if (v < 0) {
#if defined(__APPLE__)
        cached = v = w_hw_sysctl_probe("hw.optional.arm.FEAT_SHA512");
#elif defined(__linux__)
#ifdef HWCAP_SHA512
        cached = v = (getauxval(AT_HWCAP) & HWCAP_SHA512) != 0;
#else
        cached = v = 0;
#endif
#else
        cached = v = 1;
#endif
    }
    return v;
#else
    return 0;
#endif
}

static int w_hw_crc32_available(void) {
#if W_CRYPTO_HW
    static int cached = -1;
    int v = cached;
    if (v < 0) {
#if defined(__APPLE__)
        cached = v = w_hw_sysctl_probe("hw.optional.armv8_crc32");
#elif defined(__linux__)
        cached = v = (getauxval(AT_HWCAP) & HWCAP_CRC32) != 0;
#else
        cached = v = 1;
#endif
    }
    return v;
#else
    return 0;
#endif
}

static int w_hw_aes_available(void) {
#if W_CRYPTO_HW
    static int cached = -1;
    int v = cached;
    if (v < 0) {
#if defined(__APPLE__)
        cached = v = w_hw_sysctl_probe("hw.optional.arm.FEAT_AES") &&
                     w_hw_sysctl_probe("hw.optional.arm.FEAT_PMULL");
#elif defined(__linux__)
        cached = v = (getauxval(AT_HWCAP) & HWCAP_AES) != 0 &&
                     (getauxval(AT_HWCAP) & HWCAP_PMULL) != 0;
#else
        cached = v = 1;
#endif
    }
    return v;
#else
    return 0;
#endif
}

/* ==== SHA-1: ARMv8 crypto-extension compress ============================= */

#if W_CRYPTO_HW
/* Dataflow from Go's crypto/sha1 sha1block_arm64.s (itself the canonical ARM
 * sequence): 20 groups of 4 rounds; the message quads rotate m0..m3; the round
 * constant switches every 5 groups; groups 16..19 need no schedule update.
 * The new e for a group is SHA1H of the a standing BEFORE the group's update. */
#define W_SHA1_G(OPQ, KC, MA, MB, MC, MD, SU)              \
    do {                                                   \
        wk = vaddq_u32(MA, vdupq_n_u32(KC));               \
        ep = vsha1h_u32(vgetq_lane_u32(abcd, 0));          \
        if (SU) MA = vsha1su0q_u32(MA, MB, MC);            \
        abcd = OPQ(abcd, e, wk);                           \
        if (SU) MA = vsha1su1q_u32(MA, MD);                \
        e = ep;                                            \
    } while (0)

W_TARGET_SHA2 static void w_sha1_hw_compress(uint32_t state[5], const uint8_t *data, size_t nblocks) {
    uint32x4_t abcd = vld1q_u32(state);
    uint32_t e = state[4];
    for (size_t b = 0; b < nblocks; b++, data += 64) {
        uint32x4_t abcd0 = abcd;
        uint32_t e0 = e, ep;
        uint32x4_t wk;
        uint32x4_t m0 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 0)));
        uint32x4_t m1 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 16)));
        uint32x4_t m2 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 32)));
        uint32x4_t m3 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(data + 48)));

        W_SHA1_G(vsha1cq_u32, 0x5A827999u, m0, m1, m2, m3, 1);
        W_SHA1_G(vsha1cq_u32, 0x5A827999u, m1, m2, m3, m0, 1);
        W_SHA1_G(vsha1cq_u32, 0x5A827999u, m2, m3, m0, m1, 1);
        W_SHA1_G(vsha1cq_u32, 0x5A827999u, m3, m0, m1, m2, 1);
        W_SHA1_G(vsha1cq_u32, 0x5A827999u, m0, m1, m2, m3, 1);
        W_SHA1_G(vsha1pq_u32, 0x6ED9EBA1u, m1, m2, m3, m0, 1);
        W_SHA1_G(vsha1pq_u32, 0x6ED9EBA1u, m2, m3, m0, m1, 1);
        W_SHA1_G(vsha1pq_u32, 0x6ED9EBA1u, m3, m0, m1, m2, 1);
        W_SHA1_G(vsha1pq_u32, 0x6ED9EBA1u, m0, m1, m2, m3, 1);
        W_SHA1_G(vsha1pq_u32, 0x6ED9EBA1u, m1, m2, m3, m0, 1);
        W_SHA1_G(vsha1mq_u32, 0x8F1BBCDCu, m2, m3, m0, m1, 1);
        W_SHA1_G(vsha1mq_u32, 0x8F1BBCDCu, m3, m0, m1, m2, 1);
        W_SHA1_G(vsha1mq_u32, 0x8F1BBCDCu, m0, m1, m2, m3, 1);
        W_SHA1_G(vsha1mq_u32, 0x8F1BBCDCu, m1, m2, m3, m0, 1);
        W_SHA1_G(vsha1mq_u32, 0x8F1BBCDCu, m2, m3, m0, m1, 1);
        W_SHA1_G(vsha1pq_u32, 0xCA62C1D6u, m3, m0, m1, m2, 1);
        W_SHA1_G(vsha1pq_u32, 0xCA62C1D6u, m0, m1, m2, m3, 0);
        W_SHA1_G(vsha1pq_u32, 0xCA62C1D6u, m1, m2, m3, m0, 0);
        W_SHA1_G(vsha1pq_u32, 0xCA62C1D6u, m2, m3, m0, m1, 0);
        W_SHA1_G(vsha1pq_u32, 0xCA62C1D6u, m3, m0, m1, m2, 0);

        abcd = vaddq_u32(abcd, abcd0);
        e += e0;
    }
    vst1q_u32(state, abcd);
    state[4] = e;
}
#undef W_SHA1_G
#endif /* W_CRYPTO_HW */

/* ==== SHA-512: ARMv8.2 sha512 extension compress ========================= */

static const uint64_t W_K512[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

#if W_CRYPTO_HW
/* Dataflow from Go's crypto/internal/fips140/sha512 sha512block_arm64.s,
 * itself derived from the Linux kernel implementation by Ard Biesheuvel.
 * Each W_SHA512_R advances two rounds; the five state vectors rotate roles
 * across invocations exactly as the assembly's V0..V4 do. */
#define W_SHA512_R(i0, i1, i2, i3, i4, in0, in1, in2, in3, in4)  \
    do {                                                         \
        uint64x2_t t5 = vaddq_u64(in0, vld1q_u64(&W_K512[kk]));  \
        uint64x2_t t6 = vextq_u64(i2, i3, 1);                    \
        uint64x2_t t7 = vextq_u64(i1, i2, 1);                    \
        uint64x2_t t8 = vextq_u64(in3, in4, 1);                  \
        kk += 2;                                                 \
        t5 = vextq_u64(t5, t5, 1);                               \
        i3 = vaddq_u64(i3, t5);                                  \
        in0 = vsha512su0q_u64(in0, in1);                         \
        i3 = vsha512hq_u64(i3, t6, t7);                          \
        in0 = vsha512su1q_u64(in0, in2, t8);                     \
        i4 = vaddq_u64(i1, i3);                                  \
        i3 = vsha512h2q_u64(i3, i1, i0);                         \
    } while (0)

#define W_SHA512_RN(i0, i1, i2, i3, i4, in0)                     \
    do {                                                         \
        uint64x2_t t5 = vaddq_u64(in0, vld1q_u64(&W_K512[kk]));  \
        uint64x2_t t6 = vextq_u64(i2, i3, 1);                    \
        uint64x2_t t7 = vextq_u64(i1, i2, 1);                    \
        kk += 2;                                                 \
        t5 = vextq_u64(t5, t5, 1);                               \
        i3 = vaddq_u64(i3, t5);                                  \
        i3 = vsha512hq_u64(i3, t6, t7);                          \
        i4 = vaddq_u64(i1, i3);                                  \
        i3 = vsha512h2q_u64(i3, i1, i0);                         \
    } while (0)

W_TARGET_SHA3 static void w_sha512_hw_compress(uint64_t state[8], const uint8_t *data, size_t nblocks) {
    uint64x2_t s0 = vld1q_u64(state + 0);
    uint64x2_t s1 = vld1q_u64(state + 2);
    uint64x2_t s2 = vld1q_u64(state + 4);
    uint64x2_t s3 = vld1q_u64(state + 6);
    for (size_t b = 0; b < nblocks; b++, data += 128) {
        uint64x2_t a0 = s0, a1 = s1, a2 = s2, a3 = s3, a4;
        uint64x2_t m0 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 0)));
        uint64x2_t m1 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 16)));
        uint64x2_t m2 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 32)));
        uint64x2_t m3 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 48)));
        uint64x2_t m4 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 64)));
        uint64x2_t m5 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 80)));
        uint64x2_t m6 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 96)));
        uint64x2_t m7 = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(data + 112)));
        int kk = 0;

        W_SHA512_R(a0, a1, a2, a3, a4, m0, m1, m7, m4, m5);
        W_SHA512_R(a3, a0, a4, a2, a1, m1, m2, m0, m5, m6);
        W_SHA512_R(a2, a3, a1, a4, a0, m2, m3, m1, m6, m7);
        W_SHA512_R(a4, a2, a0, a1, a3, m3, m4, m2, m7, m0);
        W_SHA512_R(a1, a4, a3, a0, a2, m4, m5, m3, m0, m1);
        W_SHA512_R(a0, a1, a2, a3, a4, m5, m6, m4, m1, m2);
        W_SHA512_R(a3, a0, a4, a2, a1, m6, m7, m5, m2, m3);
        W_SHA512_R(a2, a3, a1, a4, a0, m7, m0, m6, m3, m4);
        W_SHA512_R(a4, a2, a0, a1, a3, m0, m1, m7, m4, m5);
        W_SHA512_R(a1, a4, a3, a0, a2, m1, m2, m0, m5, m6);
        W_SHA512_R(a0, a1, a2, a3, a4, m2, m3, m1, m6, m7);
        W_SHA512_R(a3, a0, a4, a2, a1, m3, m4, m2, m7, m0);
        W_SHA512_R(a2, a3, a1, a4, a0, m4, m5, m3, m0, m1);
        W_SHA512_R(a4, a2, a0, a1, a3, m5, m6, m4, m1, m2);
        W_SHA512_R(a1, a4, a3, a0, a2, m6, m7, m5, m2, m3);
        W_SHA512_R(a0, a1, a2, a3, a4, m7, m0, m6, m3, m4);
        W_SHA512_R(a3, a0, a4, a2, a1, m0, m1, m7, m4, m5);
        W_SHA512_R(a2, a3, a1, a4, a0, m1, m2, m0, m5, m6);
        W_SHA512_R(a4, a2, a0, a1, a3, m2, m3, m1, m6, m7);
        W_SHA512_R(a1, a4, a3, a0, a2, m3, m4, m2, m7, m0);
        W_SHA512_R(a0, a1, a2, a3, a4, m4, m5, m3, m0, m1);
        W_SHA512_R(a3, a0, a4, a2, a1, m5, m6, m4, m1, m2);
        W_SHA512_R(a2, a3, a1, a4, a0, m6, m7, m5, m2, m3);
        W_SHA512_R(a4, a2, a0, a1, a3, m7, m0, m6, m3, m4);
        W_SHA512_R(a1, a4, a3, a0, a2, m0, m1, m7, m4, m5);
        W_SHA512_R(a0, a1, a2, a3, a4, m1, m2, m0, m5, m6);
        W_SHA512_R(a3, a0, a4, a2, a1, m2, m3, m1, m6, m7);
        W_SHA512_R(a2, a3, a1, a4, a0, m3, m4, m2, m7, m0);
        W_SHA512_R(a4, a2, a0, a1, a3, m4, m5, m3, m0, m1);
        W_SHA512_R(a1, a4, a3, a0, a2, m5, m6, m4, m1, m2);
        W_SHA512_R(a0, a1, a2, a3, a4, m6, m7, m5, m2, m3);
        W_SHA512_R(a3, a0, a4, a2, a1, m7, m0, m6, m3, m4);
        W_SHA512_RN(a2, a3, a1, a4, a0, m0);
        W_SHA512_RN(a4, a2, a0, a1, a3, m1);
        W_SHA512_RN(a1, a4, a3, a0, a2, m2);
        W_SHA512_RN(a0, a1, a2, a3, a4, m3);
        W_SHA512_RN(a3, a0, a4, a2, a1, m4);
        W_SHA512_RN(a2, a3, a1, a4, a0, m5);
        W_SHA512_RN(a4, a2, a0, a1, a3, m6);
        W_SHA512_RN(a1, a4, a3, a0, a2, m7);

        s0 = vaddq_u64(s0, a0);
        s1 = vaddq_u64(s1, a1);
        s2 = vaddq_u64(s2, a2);
        s3 = vaddq_u64(s3, a3);
    }
    vst1q_u64(state + 0, s0);
    vst1q_u64(state + 2, s1);
    vst1q_u64(state + 4, s2);
    vst1q_u64(state + 6, s3);
}
#undef W_SHA512_R
#undef W_SHA512_RN
#endif /* W_CRYPTO_HW */

/* ==== SHA-3 / SHAKE: Keccak-f[1600] sponge =============================== */
/* Scalar permutation (compact Saarinen-style form). The EOR3/RAX1/XAR
 * accelerated permutation is deliberately not attempted here: scalar Keccak
 * already runs at multiple GB/s per core on this target and an accelerated
 * variant would need its own differential harness to trust. */

static int w_hw_sha3_available(void) {
#if W_CRYPTO_HW
    static int cached = -1;
    int v = cached;
    if (v < 0) {
#if defined(__APPLE__)
        cached = v = w_hw_sysctl_probe("hw.optional.arm.FEAT_SHA3") ||
                     w_hw_sysctl_probe("hw.optional.armv8_2_sha3");
#elif defined(__linux__)
#ifdef HWCAP_SHA3
        cached = v = (getauxval(AT_HWCAP) & HWCAP_SHA3) != 0;
#else
        cached = v = 0;
#endif
#else
        cached = v = 1;
#endif
    }
    return v;
#else
    return 0;
#endif
}

static inline uint64_t w_keccak_rotl64(uint64_t x, int n) { return (x << n) | (x >> (64 - n)); }

#if W_CRYPTO_HW
W_TARGET_SHA3 static void w_keccak_absorb_hw(uint64_t st[25], const uint8_t *data, size_t blocks, size_t rate_words) {
    static const uint64_t rc[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL, 0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL, 0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };
    uint64x2_t s00 = vld1q_dup_u64(&st[0]),  s01 = vld1q_dup_u64(&st[1]),  s02 = vld1q_dup_u64(&st[2]),  s03 = vld1q_dup_u64(&st[3]),  s04 = vld1q_dup_u64(&st[4]);
    uint64x2_t s05 = vld1q_dup_u64(&st[5]),  s06 = vld1q_dup_u64(&st[6]),  s07 = vld1q_dup_u64(&st[7]),  s08 = vld1q_dup_u64(&st[8]),  s09 = vld1q_dup_u64(&st[9]);
    uint64x2_t s10 = vld1q_dup_u64(&st[10]), s11 = vld1q_dup_u64(&st[11]), s12 = vld1q_dup_u64(&st[12]), s13 = vld1q_dup_u64(&st[13]), s14 = vld1q_dup_u64(&st[14]);
    uint64x2_t s15 = vld1q_dup_u64(&st[15]), s16 = vld1q_dup_u64(&st[16]), s17 = vld1q_dup_u64(&st[17]), s18 = vld1q_dup_u64(&st[18]), s19 = vld1q_dup_u64(&st[19]);
    uint64x2_t s20 = vld1q_dup_u64(&st[20]), s21 = vld1q_dup_u64(&st[21]), s22 = vld1q_dup_u64(&st[22]), s23 = vld1q_dup_u64(&st[23]), s24 = vld1q_dup_u64(&st[24]);

    size_t rate_bytes = rate_words * 8;
    for (size_t blk = 0; blk < blocks; blk++, data += rate_bytes) {
        if (rate_words >= 9) {
            const uint64_t *w = (const uint64_t *)data;
            s00 = veorq_u64(s00, vld1q_dup_u64(&w[0]));
            s01 = veorq_u64(s01, vld1q_dup_u64(&w[1]));
            s02 = veorq_u64(s02, vld1q_dup_u64(&w[2]));
            s03 = veorq_u64(s03, vld1q_dup_u64(&w[3]));
            s04 = veorq_u64(s04, vld1q_dup_u64(&w[4]));
            s05 = veorq_u64(s05, vld1q_dup_u64(&w[5]));
            s06 = veorq_u64(s06, vld1q_dup_u64(&w[6]));
            s07 = veorq_u64(s07, vld1q_dup_u64(&w[7]));
            s08 = veorq_u64(s08, vld1q_dup_u64(&w[8]));
            if (rate_words >= 13) {
                s09 = veorq_u64(s09, vld1q_dup_u64(&w[9]));
                s10 = veorq_u64(s10, vld1q_dup_u64(&w[10]));
                s11 = veorq_u64(s11, vld1q_dup_u64(&w[11]));
                s12 = veorq_u64(s12, vld1q_dup_u64(&w[12]));
                if (rate_words >= 17) {
                    s13 = veorq_u64(s13, vld1q_dup_u64(&w[13]));
                    s14 = veorq_u64(s14, vld1q_dup_u64(&w[14]));
                    s15 = veorq_u64(s15, vld1q_dup_u64(&w[15]));
                    s16 = veorq_u64(s16, vld1q_dup_u64(&w[16]));
                    if (rate_words >= 18) {
                        s17 = veorq_u64(s17, vld1q_dup_u64(&w[17]));
                        if (rate_words >= 21) {
                            s18 = veorq_u64(s18, vld1q_dup_u64(&w[18]));
                            s19 = veorq_u64(s19, vld1q_dup_u64(&w[19]));
                            s20 = veorq_u64(s20, vld1q_dup_u64(&w[20]));
                        }
                    }
                }
            }
        }

#pragma clang loop unroll(full)
        for (int round = 0; round < 24; round++) {
            uint64x2_t c0 = veor3q_u64(veor3q_u64(s00, s05, s10), s15, s20);
            uint64x2_t c1 = veor3q_u64(veor3q_u64(s01, s06, s11), s16, s21);
            uint64x2_t c2 = veor3q_u64(veor3q_u64(s02, s07, s12), s17, s22);
            uint64x2_t c3 = veor3q_u64(veor3q_u64(s03, s08, s13), s18, s23);
            uint64x2_t c4 = veor3q_u64(veor3q_u64(s04, s09, s14), s19, s24);

            uint64x2_t d0 = vrax1q_u64(c4, c1);
            uint64x2_t d1 = vrax1q_u64(c0, c2);
            uint64x2_t d2 = vrax1q_u64(c1, c3);
            uint64x2_t d3 = vrax1q_u64(c2, c4);
            uint64x2_t d4 = vrax1q_u64(c3, c0);

            s00 = veorq_u64(s00, d0);
            uint64x2_t t = s01;
            s01 = vxarq_u64(s06, d1, 64 - 44);
            s06 = vxarq_u64(s09, d4, 64 - 20);
            s09 = vxarq_u64(s22, d2, 64 - 61);
            s22 = vxarq_u64(s14, d4, 64 - 39);
            s14 = vxarq_u64(s20, d0, 64 - 18);
            s20 = vxarq_u64(s02, d2, 64 - 62);
            s02 = vxarq_u64(s12, d2, 64 - 43);
            s12 = vxarq_u64(s13, d3, 64 - 25);
            s13 = vxarq_u64(s19, d4, 64 - 8);
            s19 = vxarq_u64(s23, d3, 64 - 56);
            s23 = vxarq_u64(s15, d0, 64 - 41);
            s15 = vxarq_u64(s04, d4, 64 - 27);
            s04 = vxarq_u64(s24, d4, 64 - 14);
            s24 = vxarq_u64(s21, d1, 64 - 2);
            s21 = vxarq_u64(s08, d3, 64 - 55);
            s08 = vxarq_u64(s16, d1, 64 - 45);
            s16 = vxarq_u64(s05, d0, 64 - 36);
            s05 = vxarq_u64(s03, d3, 64 - 28);
            s03 = vxarq_u64(s18, d3, 64 - 21);
            s18 = vxarq_u64(s17, d2, 64 - 15);
            s17 = vxarq_u64(s11, d1, 64 - 10);
            s11 = vxarq_u64(s07, d2, 64 - 6);
            s07 = vxarq_u64(s10, d0, 64 - 3);
            s10 = vxarq_u64(t,   d1, 64 - 1);

            c0 = vbcaxq_u64(s00, s02, s01); c1 = vbcaxq_u64(s01, s03, s02);
            s02 = vbcaxq_u64(s02, s04, s03); s03 = vbcaxq_u64(s03, s00, s04); s04 = vbcaxq_u64(s04, s01, s00);
            s00 = veorq_u64(c0, vld1q_dup_u64(&rc[round])); s01 = c1;

            c0 = vbcaxq_u64(s05, s07, s06); c1 = vbcaxq_u64(s06, s08, s07);
            s07 = vbcaxq_u64(s07, s09, s08); s08 = vbcaxq_u64(s08, s05, s09); s09 = vbcaxq_u64(s09, s06, s05);
            s05 = c0; s06 = c1;

            c0 = vbcaxq_u64(s10, s12, s11); c1 = vbcaxq_u64(s11, s13, s12);
            s12 = vbcaxq_u64(s12, s14, s13); s13 = vbcaxq_u64(s13, s10, s14); s14 = vbcaxq_u64(s14, s11, s10);
            s10 = c0; s11 = c1;

            c0 = vbcaxq_u64(s15, s17, s16); c1 = vbcaxq_u64(s16, s18, s17);
            s17 = vbcaxq_u64(s17, s19, s18); s18 = vbcaxq_u64(s18, s15, s19); s19 = vbcaxq_u64(s19, s16, s15);
            s15 = c0; s16 = c1;

            c0 = vbcaxq_u64(s20, s22, s21); c1 = vbcaxq_u64(s21, s23, s22);
            s22 = vbcaxq_u64(s22, s24, s23); s23 = vbcaxq_u64(s23, s20, s24); s24 = vbcaxq_u64(s24, s21, s20);
            s20 = c0; s21 = c1;
        }
    }

    vst1q_lane_u64(&st[0],  s00, 0); vst1q_lane_u64(&st[1],  s01, 0); vst1q_lane_u64(&st[2],  s02, 0); vst1q_lane_u64(&st[3],  s03, 0); vst1q_lane_u64(&st[4],  s04, 0);
    vst1q_lane_u64(&st[5],  s05, 0); vst1q_lane_u64(&st[6],  s06, 0); vst1q_lane_u64(&st[7],  s07, 0); vst1q_lane_u64(&st[8],  s08, 0); vst1q_lane_u64(&st[9],  s09, 0);
    vst1q_lane_u64(&st[10], s10, 0); vst1q_lane_u64(&st[11], s11, 0); vst1q_lane_u64(&st[12], s12, 0); vst1q_lane_u64(&st[13], s13, 0); vst1q_lane_u64(&st[14], s14, 0);
    vst1q_lane_u64(&st[15], s15, 0); vst1q_lane_u64(&st[16], s16, 0); vst1q_lane_u64(&st[17], s17, 0); vst1q_lane_u64(&st[18], s18, 0); vst1q_lane_u64(&st[19], s19, 0);
    vst1q_lane_u64(&st[20], s20, 0); vst1q_lane_u64(&st[21], s21, 0); vst1q_lane_u64(&st[22], s22, 0); vst1q_lane_u64(&st[23], s23, 0); vst1q_lane_u64(&st[24], s24, 0);
}
#endif

static void w_keccakf1600(uint64_t st[25]) {
#if W_CRYPTO_HW
    if (__builtin_expect(w_hw_sha3_available(), 1)) {
        w_keccak_absorb_hw(st, NULL, 1, 0);
        return;
    }
#endif
    static const uint64_t rc[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL, 0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL, 0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };
    uint64_t s00 = st[0],  s01 = st[1],  s02 = st[2],  s03 = st[3],  s04 = st[4];
    uint64_t s05 = st[5],  s06 = st[6],  s07 = st[7],  s08 = st[8],  s09 = st[9];
    uint64_t s10 = st[10], s11 = st[11], s12 = st[12], s13 = st[13], s14 = st[14];
    uint64_t s15 = st[15], s16 = st[16], s17 = st[17], s18 = st[18], s19 = st[19];
    uint64_t s20 = st[20], s21 = st[21], s22 = st[22], s23 = st[23], s24 = st[24];

    for (int round = 0; round < 24; round++) {
        uint64_t c0 = s00 ^ s05 ^ s10 ^ s15 ^ s20;
        uint64_t c1 = s01 ^ s06 ^ s11 ^ s16 ^ s21;
        uint64_t c2 = s02 ^ s07 ^ s12 ^ s17 ^ s22;
        uint64_t c3 = s03 ^ s08 ^ s13 ^ s18 ^ s23;
        uint64_t c4 = s04 ^ s09 ^ s14 ^ s19 ^ s24;

        uint64_t d0 = c4 ^ w_keccak_rotl64(c1, 1);
        uint64_t d1 = c0 ^ w_keccak_rotl64(c2, 1);
        uint64_t d2 = c1 ^ w_keccak_rotl64(c3, 1);
        uint64_t d3 = c2 ^ w_keccak_rotl64(c4, 1);
        uint64_t d4 = c3 ^ w_keccak_rotl64(c0, 1);

        s00 ^= d0; s05 ^= d0; s10 ^= d0; s15 ^= d0; s20 ^= d0;
        s01 ^= d1; s06 ^= d1; s11 ^= d1; s16 ^= d1; s21 ^= d1;
        s02 ^= d2; s07 ^= d2; s12 ^= d2; s17 ^= d2; s22 ^= d2;
        s03 ^= d3; s08 ^= d3; s13 ^= d3; s18 ^= d3; s23 ^= d3;
        s04 ^= d4; s09 ^= d4; s14 ^= d4; s19 ^= d4; s24 ^= d4;

        uint64_t t = s01;
        s01 = w_keccak_rotl64(s06, 44);
        s06 = w_keccak_rotl64(s09, 20);
        s09 = w_keccak_rotl64(s22, 61);
        s22 = w_keccak_rotl64(s14, 39);
        s14 = w_keccak_rotl64(s20, 18);
        s20 = w_keccak_rotl64(s02, 62);
        s02 = w_keccak_rotl64(s12, 43);
        s12 = w_keccak_rotl64(s13, 25);
        s13 = w_keccak_rotl64(s19, 8);
        s19 = w_keccak_rotl64(s23, 56);
        s23 = w_keccak_rotl64(s15, 41);
        s15 = w_keccak_rotl64(s04, 27);
        s04 = w_keccak_rotl64(s24, 14);
        s24 = w_keccak_rotl64(s21, 2);
        s21 = w_keccak_rotl64(s08, 55);
        s08 = w_keccak_rotl64(s16, 45);
        s16 = w_keccak_rotl64(s05, 36);
        s05 = w_keccak_rotl64(s03, 28);
        s03 = w_keccak_rotl64(s18, 21);
        s18 = w_keccak_rotl64(s17, 15);
        s17 = w_keccak_rotl64(s11, 10);
        s11 = w_keccak_rotl64(s07, 6);
        s07 = w_keccak_rotl64(s10, 3);
        s10 = w_keccak_rotl64(t, 1);

        c0 = s00 ^ ((~s01) & s02); c1 = s01 ^ ((~s02) & s03);
        s02 ^= (~s03) & s04; s03 ^= (~s04) & s00; s04 ^= (~s00) & s01;
        s00 = c0 ^ rc[round]; s01 = c1;

        c0 = s05 ^ ((~s06) & s07); c1 = s06 ^ ((~s07) & s08);
        s07 ^= (~s08) & s09; s08 ^= (~s09) & s05; s09 ^= (~s05) & s06;
        s05 = c0; s06 = c1;

        c0 = s10 ^ ((~s11) & s12); c1 = s11 ^ ((~s12) & s13);
        s12 ^= (~s13) & s14; s13 ^= (~s14) & s10; s14 ^= (~s10) & s11;
        s10 = c0; s11 = c1;

        c0 = s15 ^ ((~s16) & s17); c1 = s16 ^ ((~s17) & s18);
        s17 ^= (~s18) & s19; s18 ^= (~s19) & s15; s19 ^= (~s15) & s16;
        s15 = c0; s16 = c1;

        c0 = s20 ^ ((~s21) & s22); c1 = s21 ^ ((~s22) & s23);
        s22 ^= (~s23) & s24; s23 ^= (~s24) & s20; s24 ^= (~s20) & s21;
        s20 = c0; s21 = c1;
    }

    st[0]  = s00; st[1]  = s01; st[2]  = s02; st[3]  = s03; st[4]  = s04;
    st[5]  = s05; st[6]  = s06; st[7]  = s07; st[8]  = s08; st[9]  = s09;
    st[10] = s10; st[11] = s11; st[12] = s12; st[13] = s13; st[14] = s14;
    st[15] = s15; st[16] = s16; st[17] = s17; st[18] = s18; st[19] = s19;
    st[20] = s20; st[21] = s21; st[22] = s22; st[23] = s23; st[24] = s24;
}

/* Sponge over a little-endian host (every Tungsten target). pad is the domain
 * byte: 0x06 for SHA-3, 0x1f for SHAKE. */
static void w_keccak_sponge(const uint8_t *data, size_t len, size_t rate, uint8_t pad,
                            uint8_t *out, size_t outlen) {
    uint64_t st[25];
    uint8_t *sb = (uint8_t *)st;
    memset(st, 0, sizeof st);
    size_t rate_words = rate >> 3;
#if W_CRYPTO_HW
    if (len >= rate && __builtin_expect(w_hw_sha3_available(), 1)) {
        size_t full_blocks = len / rate;
        w_keccak_absorb_hw(st, data, full_blocks, rate_words);
        data += full_blocks * rate;
        len -= full_blocks * rate;
    }
#endif
    while (len >= rate) {
        for (size_t i = 0; i < rate_words; i++) {
            uint64_t v;
            memcpy(&v, data + i * 8, 8);
            st[i] ^= v;
        }
        w_keccakf1600(st);
        data += rate;
        len -= rate;
    }
    size_t rem_words = len >> 3;
    for (size_t i = 0; i < rem_words; i++) {
        uint64_t v;
        memcpy(&v, data + i * 8, 8);
        st[i] ^= v;
    }
    for (size_t i = rem_words * 8; i < len; i++) sb[i] ^= data[i];
    sb[len] ^= pad;
    sb[rate - 1] ^= 0x80;
    w_keccakf1600(st);
    while (outlen > rate) {
        memcpy(out, sb, rate);
        out += rate;
        outlen -= rate;
        w_keccakf1600(st);
    }
    memcpy(out, sb, outlen);
}

static void w_sha3_digest(const uint8_t *data, size_t len, size_t mdlen, uint8_t *out) {
    w_keccak_sponge(data, len, 200 - 2 * mdlen, 0x06, out, mdlen);
}

static void w_shake_digest(const uint8_t *data, size_t len, int bits256, uint8_t *out, size_t outlen) {
    w_keccak_sponge(data, len, bits256 ? 136 : 168, 0x1f, out, outlen);
}

/* ==== CRC-32 (IEEE) and CRC-32C (Castagnoli) ============================= */
/* Checksums, not cryptography: fine for framing/dedup/integrity against
 * accident, useless against an adversary. */

static uint32_t w_crc32_tables[2][256];
static int w_crc32_tables_ready = 0;

static void w_crc32_tables_build(void) {
    static const uint32_t polys[2] = {0xEDB88320u, 0x82F63B78u};
    for (int t = 0; t < 2; t++) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int b = 0; b < 8; b++) c = (c & 1) ? (c >> 1) ^ polys[t] : (c >> 1);
            w_crc32_tables[t][i] = c;
        }
    }
    w_crc32_tables_ready = 1;
}

static uint32_t w_crc32_sw(uint32_t crc, const uint8_t *p, size_t n, int castagnoli) {
    if (!w_crc32_tables_ready) w_crc32_tables_build();
    const uint32_t *tab = w_crc32_tables[castagnoli ? 1 : 0];
    while (n--) crc = tab[(crc ^ *p++) & 0xFF] ^ (crc >> 8);
    return crc;
}

#if W_CRYPTO_HW
__attribute__((target("crc,aes"))) static uint32_t w_crc32_hw_ieee(uint32_t crc, const uint8_t *p, size_t n) {
    if (n >= 1024 && w_hw_aes_available()) {
        static uint32_t k1 = 0, k2 = 0, k3 = 0;
        if (__builtin_expect(k1 == 0, 0)) {
            uint32_t c = 1;
            for (int i = 0; i < 31; i++) c = __builtin_arm_crc32d(c, 0);
            k1 = c;
            for (int i = 31; i < 63; i++) c = __builtin_arm_crc32d(c, 0);
            k2 = c;
            for (int i = 63; i < 95; i++) c = __builtin_arm_crc32d(c, 0);
            k3 = c;
        }
        const poly64_t pk1 = (poly64_t)k1, pk2 = (poly64_t)k2, pk3 = (poly64_t)k3;
        while (n >= 1024) {
            uint32_t c0 = crc, c1 = 0, c2 = 0, c3 = 0;
            const uint8_t *p0 = p, *p1 = p + 256, *p2 = p + 512, *p3 = p + 768;
            for (int i = 0; i < 32; i++) {
                uint64_t v0, v1, v2, v3;
                memcpy(&v0, p0 + i * 8, 8);
                memcpy(&v1, p1 + i * 8, 8);
                memcpy(&v2, p2 + i * 8, 8);
                memcpy(&v3, p3 + i * 8, 8);
                c0 = __builtin_arm_crc32d(c0, v0);
                c1 = __builtin_arm_crc32d(c1, v1);
                c2 = __builtin_arm_crc32d(c2, v2);
                c3 = __builtin_arm_crc32d(c3, v3);
            }
            uint64_t cl0 = (uint64_t)vmull_p64((poly64_t)c0, pk3);
            uint64_t cl1 = (uint64_t)vmull_p64((poly64_t)c1, pk2);
            uint64_t cl2 = (uint64_t)vmull_p64((poly64_t)c2, pk1);
            crc = c3 ^ __builtin_arm_crc32d(0, cl0 ^ cl1 ^ cl2);
            p += 1024;
            n -= 1024;
        }
    }
    while (n >= 8) {
        uint64_t v;
        memcpy(&v, p, 8);
        crc = __builtin_arm_crc32d(crc, v);
        p += 8;
        n -= 8;
    }
    while (n--) crc = __builtin_arm_crc32b(crc, *p++);
    return crc;
}

__attribute__((target("crc,aes"))) static uint32_t w_crc32_hw_castagnoli(uint32_t crc, const uint8_t *p, size_t n) {
    if (n >= 1024 && w_hw_aes_available()) {
        static uint32_t k1 = 0, k2 = 0, k3 = 0;
        if (__builtin_expect(k1 == 0, 0)) {
            uint32_t c = 1;
            for (int i = 0; i < 31; i++) c = __builtin_arm_crc32cd(c, 0);
            k1 = c;
            for (int i = 31; i < 63; i++) c = __builtin_arm_crc32cd(c, 0);
            k2 = c;
            for (int i = 63; i < 95; i++) c = __builtin_arm_crc32cd(c, 0);
            k3 = c;
        }
        const poly64_t pk1 = (poly64_t)k1, pk2 = (poly64_t)k2, pk3 = (poly64_t)k3;
        while (n >= 1024) {
            uint32_t c0 = crc, c1 = 0, c2 = 0, c3 = 0;
            const uint8_t *p0 = p, *p1 = p + 256, *p2 = p + 512, *p3 = p + 768;
            for (int i = 0; i < 32; i++) {
                uint64_t v0, v1, v2, v3;
                memcpy(&v0, p0 + i * 8, 8);
                memcpy(&v1, p1 + i * 8, 8);
                memcpy(&v2, p2 + i * 8, 8);
                memcpy(&v3, p3 + i * 8, 8);
                c0 = __builtin_arm_crc32cd(c0, v0);
                c1 = __builtin_arm_crc32cd(c1, v1);
                c2 = __builtin_arm_crc32cd(c2, v2);
                c3 = __builtin_arm_crc32cd(c3, v3);
            }
            uint64_t cl0 = (uint64_t)vmull_p64((poly64_t)c0, pk3);
            uint64_t cl1 = (uint64_t)vmull_p64((poly64_t)c1, pk2);
            uint64_t cl2 = (uint64_t)vmull_p64((poly64_t)c2, pk1);
            crc = c3 ^ __builtin_arm_crc32cd(0, cl0 ^ cl1 ^ cl2);
            p += 1024;
            n -= 1024;
        }
    }
    while (n >= 8) {
        uint64_t v;
        memcpy(&v, p, 8);
        crc = __builtin_arm_crc32cd(crc, v);
        p += 8;
        n -= 8;
    }
    while (n--) crc = __builtin_arm_crc32cb(crc, *p++);
    return crc;
}
#endif

static uint32_t w_crc32_run(const uint8_t *p, size_t n, int castagnoli) {
    uint32_t crc = 0xFFFFFFFFu;
#if W_CRYPTO_HW
    if (w_hw_crc32_available()) {
        crc = castagnoli ? w_crc32_hw_castagnoli(crc, p, n) : w_crc32_hw_ieee(crc, p, n);
        return crc ^ 0xFFFFFFFFu;
    }
#endif
    return w_crc32_sw(crc, p, n, castagnoli) ^ 0xFFFFFFFFu;
}

/* ==== AES-GCM ============================================================ */

static const uint8_t w_aes_sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

/* Round keys as raw bytes: what vld1q_u8 wants and what the software rounds
 * index directly. 15 slots covers AES-256's Nr+1 = 15. */
typedef struct {
    uint8_t rk[15][16];
    int nrounds;
} WAesKey;

static void w_aes_key_expand(const uint8_t *key, size_t keylen, WAesKey *ks) {
    static const uint8_t rcon[15] = {0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
                                     0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d, 0x9a};
    int nk = (int)(keylen / 4);            /* 4 or 8 words */
    int nr = nk + 6;                       /* 10 or 14 rounds */
    uint8_t w[60][4];
    memcpy(w, key, keylen);
    for (int i = nk; i < 4 * (nr + 1); i++) {
        uint8_t t[4];
        memcpy(t, w[i - 1], 4);
        if (i % nk == 0) {
            uint8_t hi = t[0];
            t[0] = w_aes_sbox[t[1]] ^ rcon[i / nk - 1];
            t[1] = w_aes_sbox[t[2]];
            t[2] = w_aes_sbox[t[3]];
            t[3] = w_aes_sbox[hi];
        } else if (nk > 6 && i % nk == 4) {
            for (int j = 0; j < 4; j++) t[j] = w_aes_sbox[t[j]];
        }
        for (int j = 0; j < 4; j++) w[i][j] = w[i - nk][j] ^ t[j];
    }
    memcpy(ks->rk, w, 16 * (size_t)(nr + 1));
    ks->nrounds = nr;
}

static uint8_t w_aes_xtime(uint8_t x) { return (uint8_t)((x << 1) ^ ((x >> 7) * 0x1B)); }

/* Portable fallback block encrypt. Table lookups are input-dependent, so this
 * path is not cache-timing hardened; every deployment target with the AES
 * extension takes the constant-time hardware path instead. */
static void w_aes_encrypt_block_sw(const WAesKey *ks, const uint8_t in[16], uint8_t out[16]) {
    uint8_t s[16];
    for (int i = 0; i < 16; i++) s[i] = in[i] ^ ks->rk[0][i];
    for (int round = 1; round <= ks->nrounds; round++) {
        uint8_t t[16];
        /* SubBytes + ShiftRows: byte at row r, col c comes from col (c+r)%4. */
        for (int c = 0; c < 4; c++) {
            for (int r = 0; r < 4; r++) t[4 * c + r] = w_aes_sbox[s[4 * ((c + r) % 4) + r]];
        }
        if (round < ks->nrounds) {
            for (int c = 0; c < 4; c++) {
                uint8_t a0 = t[4 * c], a1 = t[4 * c + 1], a2 = t[4 * c + 2], a3 = t[4 * c + 3];
                s[4 * c + 0] = (uint8_t)(w_aes_xtime(a0) ^ w_aes_xtime(a1) ^ a1 ^ a2 ^ a3);
                s[4 * c + 1] = (uint8_t)(a0 ^ w_aes_xtime(a1) ^ w_aes_xtime(a2) ^ a2 ^ a3);
                s[4 * c + 2] = (uint8_t)(a0 ^ a1 ^ w_aes_xtime(a2) ^ w_aes_xtime(a3) ^ a3);
                s[4 * c + 3] = (uint8_t)(w_aes_xtime(a0) ^ a0 ^ a1 ^ a2 ^ w_aes_xtime(a3));
            }
        } else {
            memcpy(s, t, 16);
        }
        for (int i = 0; i < 16; i++) s[i] ^= ks->rk[round][i];
    }
    memcpy(out, s, 16);
}

#if W_CRYPTO_HW
W_TARGET_AES static void w_aes_encrypt_block_hw(const WAesKey *ks, const uint8_t in[16], uint8_t out[16]) {
    uint8x16_t b = vld1q_u8(in);
    for (int i = 0; i < ks->nrounds - 1; i++)
        b = vaesmcq_u8(vaeseq_u8(b, vld1q_u8(ks->rk[i])));
    b = vaeseq_u8(b, vld1q_u8(ks->rk[ks->nrounds - 1]));
    b = veorq_u8(b, vld1q_u8(ks->rk[ks->nrounds]));
    vst1q_u8(out, b);
}
#endif

static void w_aes_encrypt_block(const WAesKey *ks, const uint8_t in[16], uint8_t out[16]) {
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        w_aes_encrypt_block_hw(ks, in, out);
        return;
    }
#endif
    w_aes_encrypt_block_sw(ks, in, out);
}

/* GHASH multiply, software reference: NIST SP 800-38D right-shift algorithm.
 * X <- X * H in the GHASH field (bit 0 = MSB of byte 0). */
static void w_ghash_mul_sw(uint8_t X[16], const uint8_t H[16]) {
    uint8_t Z[16], V[16];
    memset(Z, 0, 16);
    memcpy(V, H, 16);
    for (int i = 0; i < 128; i++) {
        if (X[i / 8] & (uint8_t)(0x80u >> (i % 8))) {
            for (int j = 0; j < 16; j++) Z[j] ^= V[j];
        }
        int lsb = V[15] & 1;
        for (int j = 15; j > 0; j--) V[j] = (uint8_t)((V[j] >> 1) | (V[j - 1] << 7));
        V[0] >>= 1;
        if (lsb) V[0] ^= 0xE1;
    }
    memcpy(X, Z, 16);
}

#if W_CRYPTO_HW
/* PMULL GHASH multiply. GHASH's bit order is reflected WITHIN each byte
 * (coefficient x^(8b+k) is bit 7-k of byte b), so vrbit — bit-reverse per
 * byte, byte positions unchanged — maps blocks to plain little-endian
 * polynomials: byte b bit j becomes x^(8b+j), low 64-bit lane = x^0..x^63.
 * In that domain the product is a standard 128x128 carryless multiply
 * reduced mod x^128+x^7+x^2+x+1 (0x87 folds). This is the mbedTLS-style
 * formulation; OpenSSL's ghashv8 works byte-swapped instead and therefore
 * needs the reflected 0xc2 constant — the earlier failed attempt mixed the
 * two domains (0x87 fold without the vrbit transform). Pinned to
 * w_ghash_mul_sw by the differential harness (100k random + 128 edges). */
W_TARGET_AES static inline uint8x16_t w_ghash_reduce_hw(uint64x2_t lo, uint64x2_t hi, uint64x2_t m) {
    uint64x2_t z = vdupq_n_u64(0);
    poly64_t c87 = (poly64_t)0x87ULL;
    lo = veorq_u64(lo, vextq_u64(z, m, 1));
    hi = veorq_u64(hi, vextq_u64(m, z, 1));
    poly64x2_t hp = vreinterpretq_p64_u64(hi);
    uint64x2_t p0 = vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(hp), 0), c87));
    uint64x2_t p1 = vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_high_p64(hp), 0), c87));
    poly64x2_t p1p = vreinterpretq_p64_u64(p1);
    uint64x2_t f2 = vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_high_p64(p1p), 0), c87));
    uint64x2_t r = veorq_u64(lo, p0);
    r = veorq_u64(r, vcombine_u64(vget_low_u64(f2), vget_low_u64(p1)));
    return vreinterpretq_u8_u64(r);
}

W_TARGET_AES static inline uint8x16_t w_ghash_mul_poly_hw(uint8x16_t a_u8, uint8x16_t b_u8) {
    poly64x2_t a = vreinterpretq_p64_u8(a_u8);
    poly64x2_t b = vreinterpretq_p64_u8(b_u8);
    uint64x2_t au = vreinterpretq_u64_u8(a_u8);
    uint64x2_t bu = vreinterpretq_u64_u8(b_u8);
    poly64x1_t ax = vreinterpret_p64_u64(veor_u64(vget_low_u64(au), vget_high_u64(au)));
    poly64x1_t bx = vreinterpret_p64_u64(veor_u64(vget_low_u64(bu), vget_high_u64(bu)));
    uint64x2_t lo = vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(a), 0), vget_lane_p64(vget_low_p64(b), 0)));
    uint64x2_t hi = vreinterpretq_u64_p128(vmull_high_p64(a, b));
    uint64x2_t m  = veorq_u64(vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(ax, 0), vget_lane_p64(bx, 0))),
                              veorq_u64(lo, hi));
    return w_ghash_reduce_hw(lo, hi, m);
}

W_TARGET_AES static void w_ghash_mul_hw(uint8_t X[16], const uint8_t H[16]) {
    uint8x16_t a = vrbitq_u8(vld1q_u8(X));
    uint8x16_t b = vrbitq_u8(vld1q_u8(H));
    vst1q_u8(X, vrbitq_u8(w_ghash_mul_poly_hw(a, b)));
}

W_TARGET_AES static void w_ghash_absorb_hw(uint8_t Y[16], const uint8_t H[16], const uint8_t *data, size_t len) {
    uint8x16_t y = vrbitq_u8(vld1q_u8(Y));
    uint8x16_t h1 = vrbitq_u8(vld1q_u8(H));
    if (len >= 64) {
        uint8x16_t h2 = w_ghash_mul_poly_hw(h1, h1);
        uint8x16_t h3 = w_ghash_mul_poly_hw(h2, h1);
        uint8x16_t h4 = w_ghash_mul_poly_hw(h2, h2);
        poly64x2_t h1p = vreinterpretq_p64_u8(h1), h2p = vreinterpretq_p64_u8(h2);
        poly64x2_t h3p = vreinterpretq_p64_u8(h3), h4p = vreinterpretq_p64_u8(h4);
        poly64x1_t h1x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(h1)), vget_high_u64(vreinterpretq_u64_u8(h1))));
        poly64x1_t h2x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(h2)), vget_high_u64(vreinterpretq_u64_u8(h2))));
        poly64x1_t h3x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(h3)), vget_high_u64(vreinterpretq_u64_u8(h3))));
        poly64x1_t h4x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(h4)), vget_high_u64(vreinterpretq_u64_u8(h4))));
        while (len >= 64) {
            uint8x16_t x0 = veorq_u8(y, vrbitq_u8(vld1q_u8(data + 0)));
            uint8x16_t x1 = vrbitq_u8(vld1q_u8(data + 16));
            uint8x16_t x2 = vrbitq_u8(vld1q_u8(data + 32));
            uint8x16_t x3 = vrbitq_u8(vld1q_u8(data + 48));
            poly64x2_t a0 = vreinterpretq_p64_u8(x0), a1 = vreinterpretq_p64_u8(x1);
            poly64x2_t a2 = vreinterpretq_p64_u8(x2), a3 = vreinterpretq_p64_u8(x3);
            poly64x1_t a0x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(x0)), vget_high_u64(vreinterpretq_u64_u8(x0))));
            poly64x1_t a1x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(x1)), vget_high_u64(vreinterpretq_u64_u8(x1))));
            poly64x1_t a2x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(x2)), vget_high_u64(vreinterpretq_u64_u8(x2))));
            poly64x1_t a3x = vreinterpret_p64_u64(veor_u64(vget_low_u64(vreinterpretq_u64_u8(x3)), vget_high_u64(vreinterpretq_u64_u8(x3))));
            uint64x2_t lo = veorq_u64(
                veorq_u64(vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(a0), 0), vget_lane_p64(vget_low_p64(h4p), 0))),
                          vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(a1), 0), vget_lane_p64(vget_low_p64(h3p), 0)))),
                veorq_u64(vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(a2), 0), vget_lane_p64(vget_low_p64(h2p), 0))),
                          vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(a3), 0), vget_lane_p64(vget_low_p64(h1p), 0)))));
            uint64x2_t hi = veorq_u64(
                veorq_u64(vreinterpretq_u64_p128(vmull_high_p64(a0, h4p)),
                          vreinterpretq_u64_p128(vmull_high_p64(a1, h3p))),
                veorq_u64(vreinterpretq_u64_p128(vmull_high_p64(a2, h2p)),
                          vreinterpretq_u64_p128(vmull_high_p64(a3, h1p))));
            uint64x2_t m = veorq_u64(
                veorq_u64(vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(a0x, 0), vget_lane_p64(h4x, 0))),
                          vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(a1x, 0), vget_lane_p64(h3x, 0)))),
                veorq_u64(vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(a2x, 0), vget_lane_p64(h2x, 0))),
                          vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(a3x, 0), vget_lane_p64(h1x, 0)))));
            m = veorq_u64(m, veorq_u64(lo, hi));
            y = w_ghash_reduce_hw(lo, hi, m);
            data += 64;
            len -= 64;
        }
    }
    while (len >= 16) {
        y = veorq_u8(y, vrbitq_u8(vld1q_u8(data)));
        y = w_ghash_mul_poly_hw(y, h1);
        data += 16;
        len -= 16;
    }
    if (len > 0) {
        uint8_t tail[16] = {0};
        for (size_t i = 0; i < len; i++) tail[i] = data[i];
        y = veorq_u8(y, vrbitq_u8(vld1q_u8(tail)));
        y = w_ghash_mul_poly_hw(y, h1);
    }
    vst1q_u8(Y, vrbitq_u8(y));
}
#endif

/* GHASH multiply: PMULL kernel when the CPU has it (FEAT_PMULL rides the
 * same probe as AES), NIST SP 800-38D software reference otherwise. */
static void w_ghash_mul(uint8_t X[16], const uint8_t H[16]) {
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        w_ghash_mul_hw(X, H);
        return;
    }
#endif
    w_ghash_mul_sw(X, H);
}

static void w_ghash_absorb(uint8_t Y[16], const uint8_t H[16], const uint8_t *data, size_t len) {
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        w_ghash_absorb_hw(Y, H, data, len);
        return;
    }
#endif
    while (len >= 16) {
        for (int i = 0; i < 16; i++) Y[i] ^= data[i];
        w_ghash_mul_sw(Y, H);
        data += 16;
        len -= 16;
    }
    if (len > 0) {
        for (size_t i = 0; i < len; i++) Y[i] ^= data[i];
        w_ghash_mul_sw(Y, H);
    }
}

#if W_CRYPTO_HW
typedef struct {
    int valid;
    size_t keylen;
    uint8_t key[32];
    uint8_t H[16];
    WAesKey ks;
    poly64x2_t hp[8];
    poly64x1_t hx[8];
} WGcmKeyCache;

static _Thread_local WGcmKeyCache g_w_gcm_cache;

W_TARGET_AES static const WGcmKeyCache *w_gcm_get_cached_key(const uint8_t *key, size_t keylen) {
    WGcmKeyCache *c = &g_w_gcm_cache;
    if (c->valid && c->keylen == keylen) {
        unsigned diff = 0;
        for (size_t i = 0; i < keylen; i++) diff |= (unsigned)(c->key[i] ^ key[i]);
        if (diff == 0) return c;
    }
    static const uint8_t zero[16] = {0};
    memcpy(c->key, key, keylen);
    c->keylen = keylen;
    w_aes_key_expand(key, keylen, &c->ks);
    w_aes_encrypt_block_hw(&c->ks, zero, c->H);
    uint8x16_t h1 = vrbitq_u8(vld1q_u8(c->H));
    uint8x16_t cur = h1;
    for (int i = 0; i < 8; i++) {
        if (i > 0) cur = w_ghash_mul_poly_hw(cur, h1);
        c->hp[i] = vreinterpretq_p64_u8(cur);
        uint64x2_t u = vreinterpretq_u64_u8(cur);
        c->hx[i] = vreinterpret_p64_u64(veor_u64(vget_low_u64(u), vget_high_u64(u)));
    }
    c->valid = 1;
    return c;
}

W_TARGET_AES static void w_aes_gcm_ctr_hw(const WAesKey *ks, const uint8_t nonce[12],
                                          const uint8_t *in, size_t len, uint8_t *out) {
    uint8_t ctr_base[16];
    memcpy(ctr_base, nonce, 12);
    uint32_t c = 2;
    size_t off = 0;
    int nr = ks->nrounds;
    uint8x16_t rk0  = vld1q_u8(ks->rk[0]);
    uint8x16_t rk1  = vld1q_u8(ks->rk[1]);
    uint8x16_t rk2  = vld1q_u8(ks->rk[2]);
    uint8x16_t rk3  = vld1q_u8(ks->rk[3]);
    uint8x16_t rk4  = vld1q_u8(ks->rk[4]);
    uint8x16_t rk5  = vld1q_u8(ks->rk[5]);
    uint8x16_t rk6  = vld1q_u8(ks->rk[6]);
    uint8x16_t rk7  = vld1q_u8(ks->rk[7]);
    uint8x16_t rk8  = vld1q_u8(ks->rk[8]);
    uint8x16_t rk9  = vld1q_u8(ks->rk[9]);
    uint8x16_t rk10 = vld1q_u8(ks->rk[10]);
    uint8x16_t rkl  = vld1q_u8(ks->rk[nr - 1]);
    uint8x16_t rkf  = vld1q_u8(ks->rk[nr]);
    w_store_be32(ctr_base + 12, 0);
    uint32x4_t nonce_vec = vreinterpretq_u32_u8(vld1q_u8(ctr_base));
    while (off + 128 <= len) {
        uint8x16_t b0 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 0), nonce_vec, 3));
        uint8x16_t b1 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 1), nonce_vec, 3));
        uint8x16_t b2 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 2), nonce_vec, 3));
        uint8x16_t b3 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 3), nonce_vec, 3));
        uint8x16_t b4 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 4), nonce_vec, 3));
        uint8x16_t b5 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 5), nonce_vec, 3));
        uint8x16_t b6 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 6), nonce_vec, 3));
        uint8x16_t b7 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 7), nonce_vec, 3));
        c += 8;
        #define W_AES_ROUND8(rk) do { \
            b0 = vaesmcq_u8(vaeseq_u8(b0, rk)); b1 = vaesmcq_u8(vaeseq_u8(b1, rk)); \
            b2 = vaesmcq_u8(vaeseq_u8(b2, rk)); b3 = vaesmcq_u8(vaeseq_u8(b3, rk)); \
            b4 = vaesmcq_u8(vaeseq_u8(b4, rk)); b5 = vaesmcq_u8(vaeseq_u8(b5, rk)); \
            b6 = vaesmcq_u8(vaeseq_u8(b6, rk)); b7 = vaesmcq_u8(vaeseq_u8(b7, rk)); \
        } while (0)
        W_AES_ROUND8(rk0); W_AES_ROUND8(rk1); W_AES_ROUND8(rk2);
        W_AES_ROUND8(rk3); W_AES_ROUND8(rk4); W_AES_ROUND8(rk5);
        W_AES_ROUND8(rk6); W_AES_ROUND8(rk7); W_AES_ROUND8(rk8);
        if (__builtin_expect(nr > 10, 0)) {
            uint8x16_t rk11 = vld1q_u8(ks->rk[11]);
            uint8x16_t rk12 = vld1q_u8(ks->rk[12]);
            W_AES_ROUND8(rk9); W_AES_ROUND8(rk10);
            W_AES_ROUND8(rk11); W_AES_ROUND8(rk12);
        }
        #undef W_AES_ROUND8
        b0 = veorq_u8(vaeseq_u8(b0, rkl), rkf);
        b1 = veorq_u8(vaeseq_u8(b1, rkl), rkf);
        b2 = veorq_u8(vaeseq_u8(b2, rkl), rkf);
        b3 = veorq_u8(vaeseq_u8(b3, rkl), rkf);
        b4 = veorq_u8(vaeseq_u8(b4, rkl), rkf);
        b5 = veorq_u8(vaeseq_u8(b5, rkl), rkf);
        b6 = veorq_u8(vaeseq_u8(b6, rkl), rkf);
        b7 = veorq_u8(vaeseq_u8(b7, rkl), rkf);
        vst1q_u8(out + off +   0, veorq_u8(vld1q_u8(in + off +   0), b0));
        vst1q_u8(out + off +  16, veorq_u8(vld1q_u8(in + off +  16), b1));
        vst1q_u8(out + off +  32, veorq_u8(vld1q_u8(in + off +  32), b2));
        vst1q_u8(out + off +  48, veorq_u8(vld1q_u8(in + off +  48), b3));
        vst1q_u8(out + off +  64, veorq_u8(vld1q_u8(in + off +  64), b4));
        vst1q_u8(out + off +  80, veorq_u8(vld1q_u8(in + off +  80), b5));
        vst1q_u8(out + off +  96, veorq_u8(vld1q_u8(in + off +  96), b6));
        vst1q_u8(out + off + 112, veorq_u8(vld1q_u8(in + off + 112), b7));
        off += 128;
    }
    uint8_t ks_block[16];
    for (; off < len; off += 16) {
        w_store_be32(ctr_base + 12, c++);
        w_aes_encrypt_block_hw(ks, ctr_base, ks_block);
        size_t n = len - off < 16 ? len - off : 16;
        for (size_t i = 0; i < n; i++) out[off + i] = in[off + i] ^ ks_block[i];
    }
}

W_TARGET_AES static void w_aes_gcm_crypt_fused_hw(const WGcmKeyCache *kc,
                                                   const uint8_t nonce[12],
                                                   const uint8_t *in, size_t len,
                                                   const uint8_t *aad, size_t alen,
                                                   uint8_t *out, uint8_t tag_out[16],
                                                   int decrypt) {
    const WAesKey *ks = &kc->ks;
    uint8_t Y[16] = {0}, J0[16], EJ0[16], lenblk[16], ctr_base[16];
    if (alen > 0) w_ghash_absorb_hw(Y, kc->H, aad, alen);
    uint8x16_t y = vrbitq_u8(vld1q_u8(Y));
    const poly64x2_t *hp = kc->hp;
    const poly64x1_t *hx = kc->hx;
    memcpy(ctr_base, nonce, 12);
    w_store_be32(ctr_base + 12, 0);
    uint32x4_t nonce_vec = vreinterpretq_u32_u8(vld1q_u8(ctr_base));
    uint32_t c = 2;
    size_t off = 0;
    int nr = ks->nrounds;
    uint8x16_t rk0 = vld1q_u8(ks->rk[0]), rk1 = vld1q_u8(ks->rk[1]), rk2 = vld1q_u8(ks->rk[2]);
    uint8x16_t rk3 = vld1q_u8(ks->rk[3]), rk4 = vld1q_u8(ks->rk[4]), rk5 = vld1q_u8(ks->rk[5]);
    uint8x16_t rk6 = vld1q_u8(ks->rk[6]), rk7 = vld1q_u8(ks->rk[7]), rk8 = vld1q_u8(ks->rk[8]);
    uint8x16_t rkl = vld1q_u8(ks->rk[nr - 1]);
    uint8x16_t rkf = vld1q_u8(ks->rk[nr]);

    #define W_AES_ROUND8(rk) do { \
        b0 = vaesmcq_u8(vaeseq_u8(b0, rk)); b1 = vaesmcq_u8(vaeseq_u8(b1, rk)); \
        b2 = vaesmcq_u8(vaeseq_u8(b2, rk)); b3 = vaesmcq_u8(vaeseq_u8(b3, rk)); \
        b4 = vaesmcq_u8(vaeseq_u8(b4, rk)); b5 = vaesmcq_u8(vaeseq_u8(b5, rk)); \
        b6 = vaesmcq_u8(vaeseq_u8(b6, rk)); b7 = vaesmcq_u8(vaeseq_u8(b7, rk)); \
    } while (0)

    #define W_GHASH_STEP(acc_lo, acc_hi, acc_m, q_blk, idx) do { \
        uint8x16_t _qb = (q_blk); \
        poly64x2_t _a = vreinterpretq_p64_u8(_qb); \
        uint64x2_t _au = vreinterpretq_u64_u8(_qb); \
        poly64x1_t _ax = vreinterpret_p64_u64(veor_u64(vget_low_u64(_au), vget_high_u64(_au))); \
        (acc_lo) = veorq_u64((acc_lo), vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(vget_low_p64(_a), 0), vget_lane_p64(vget_low_p64(hp[idx]), 0)))); \
        (acc_hi) = veorq_u64((acc_hi), vreinterpretq_u64_p128(vmull_high_p64(_a, hp[idx]))); \
        (acc_m)  = veorq_u64((acc_m),  vreinterpretq_u64_p128(vmull_p64(vget_lane_p64(_ax, 0), vget_lane_p64(hx[idx], 0)))); \
    } while (0)

    if (decrypt) {
        while (off + 128 <= len) {
            uint8x16_t b0 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 0), nonce_vec, 3));
            uint8x16_t b1 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 1), nonce_vec, 3));
            uint8x16_t b2 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 2), nonce_vec, 3));
            uint8x16_t b3 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 3), nonce_vec, 3));
            uint8x16_t b4 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 4), nonce_vec, 3));
            uint8x16_t b5 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 5), nonce_vec, 3));
            uint8x16_t b6 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 6), nonce_vec, 3));
            uint8x16_t b7 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 7), nonce_vec, 3));
            c += 8;
            uint64x2_t glo = vdupq_n_u64(0), ghi = glo, gm = glo;
            W_AES_ROUND8(rk0); W_GHASH_STEP(glo, ghi, gm, veorq_u8(y, vrbitq_u8(vld1q_u8(in + off +   0))), 7);
            W_AES_ROUND8(rk1); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  16)), 6);
            W_AES_ROUND8(rk2); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  32)), 5);
            W_AES_ROUND8(rk3); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  48)), 4);
            W_AES_ROUND8(rk4); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  64)), 3);
            W_AES_ROUND8(rk5); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  80)), 2);
            W_AES_ROUND8(rk6); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off +  96)), 1);
            W_AES_ROUND8(rk7); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(in + off + 112)), 0);
            W_AES_ROUND8(rk8);
            if (__builtin_expect(nr > 10, 0)) {
                W_AES_ROUND8(vld1q_u8(ks->rk[9]));  W_AES_ROUND8(vld1q_u8(ks->rk[10]));
                W_AES_ROUND8(vld1q_u8(ks->rk[11])); W_AES_ROUND8(vld1q_u8(ks->rk[12]));
            }
            gm = veorq_u64(gm, veorq_u64(glo, ghi));
            y = w_ghash_reduce_hw(glo, ghi, gm);
            vst1q_u8(out + off +   0, veorq_u8(vld1q_u8(in + off +   0), veorq_u8(vaeseq_u8(b0, rkl), rkf)));
            vst1q_u8(out + off +  16, veorq_u8(vld1q_u8(in + off +  16), veorq_u8(vaeseq_u8(b1, rkl), rkf)));
            vst1q_u8(out + off +  32, veorq_u8(vld1q_u8(in + off +  32), veorq_u8(vaeseq_u8(b2, rkl), rkf)));
            vst1q_u8(out + off +  48, veorq_u8(vld1q_u8(in + off +  48), veorq_u8(vaeseq_u8(b3, rkl), rkf)));
            vst1q_u8(out + off +  64, veorq_u8(vld1q_u8(in + off +  64), veorq_u8(vaeseq_u8(b4, rkl), rkf)));
            vst1q_u8(out + off +  80, veorq_u8(vld1q_u8(in + off +  80), veorq_u8(vaeseq_u8(b5, rkl), rkf)));
            vst1q_u8(out + off +  96, veorq_u8(vld1q_u8(in + off +  96), veorq_u8(vaeseq_u8(b6, rkl), rkf)));
            vst1q_u8(out + off + 112, veorq_u8(vld1q_u8(in + off + 112), veorq_u8(vaeseq_u8(b7, rkl), rkf)));
            off += 128;
        }
    } else if (off + 128 <= len) {
        {
            uint8x16_t b0 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 0), nonce_vec, 3));
            uint8x16_t b1 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 1), nonce_vec, 3));
            uint8x16_t b2 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 2), nonce_vec, 3));
            uint8x16_t b3 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 3), nonce_vec, 3));
            uint8x16_t b4 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 4), nonce_vec, 3));
            uint8x16_t b5 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 5), nonce_vec, 3));
            uint8x16_t b6 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 6), nonce_vec, 3));
            uint8x16_t b7 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 7), nonce_vec, 3));
            c += 8;
            W_AES_ROUND8(rk0); W_AES_ROUND8(rk1);
            W_AES_ROUND8(rk2); W_AES_ROUND8(rk3);
            W_AES_ROUND8(rk4); W_AES_ROUND8(rk5);
            W_AES_ROUND8(rk6); W_AES_ROUND8(rk7);
            W_AES_ROUND8(rk8);
            if (__builtin_expect(nr > 10, 0)) {
                W_AES_ROUND8(vld1q_u8(ks->rk[9]));  W_AES_ROUND8(vld1q_u8(ks->rk[10]));
                W_AES_ROUND8(vld1q_u8(ks->rk[11])); W_AES_ROUND8(vld1q_u8(ks->rk[12]));
            }
            vst1q_u8(out + off +   0, veorq_u8(vld1q_u8(in + off +   0), veorq_u8(vaeseq_u8(b0, rkl), rkf)));
            vst1q_u8(out + off +  16, veorq_u8(vld1q_u8(in + off +  16), veorq_u8(vaeseq_u8(b1, rkl), rkf)));
            vst1q_u8(out + off +  32, veorq_u8(vld1q_u8(in + off +  32), veorq_u8(vaeseq_u8(b2, rkl), rkf)));
            vst1q_u8(out + off +  48, veorq_u8(vld1q_u8(in + off +  48), veorq_u8(vaeseq_u8(b3, rkl), rkf)));
            vst1q_u8(out + off +  64, veorq_u8(vld1q_u8(in + off +  64), veorq_u8(vaeseq_u8(b4, rkl), rkf)));
            vst1q_u8(out + off +  80, veorq_u8(vld1q_u8(in + off +  80), veorq_u8(vaeseq_u8(b5, rkl), rkf)));
            vst1q_u8(out + off +  96, veorq_u8(vld1q_u8(in + off +  96), veorq_u8(vaeseq_u8(b6, rkl), rkf)));
            vst1q_u8(out + off + 112, veorq_u8(vld1q_u8(in + off + 112), veorq_u8(vaeseq_u8(b7, rkl), rkf)));
            off += 128;
        }
        while (off + 128 <= len) {
            uint8x16_t b0 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 0), nonce_vec, 3));
            uint8x16_t b1 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 1), nonce_vec, 3));
            uint8x16_t b2 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 2), nonce_vec, 3));
            uint8x16_t b3 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 3), nonce_vec, 3));
            uint8x16_t b4 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 4), nonce_vec, 3));
            uint8x16_t b5 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 5), nonce_vec, 3));
            uint8x16_t b6 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 6), nonce_vec, 3));
            uint8x16_t b7 = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + 7), nonce_vec, 3));
            c += 8;
            const uint8_t *prev = out + off - 128;
            uint64x2_t glo = vdupq_n_u64(0), ghi = glo, gm = glo;
            W_AES_ROUND8(rk0); W_GHASH_STEP(glo, ghi, gm, veorq_u8(y, vrbitq_u8(vld1q_u8(prev +   0))), 7);
            W_AES_ROUND8(rk1); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  16)), 6);
            W_AES_ROUND8(rk2); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  32)), 5);
            W_AES_ROUND8(rk3); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  48)), 4);
            W_AES_ROUND8(rk4); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  64)), 3);
            W_AES_ROUND8(rk5); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  80)), 2);
            W_AES_ROUND8(rk6); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  96)), 1);
            W_AES_ROUND8(rk7); W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev + 112)), 0);
            W_AES_ROUND8(rk8);
            if (__builtin_expect(nr > 10, 0)) {
                W_AES_ROUND8(vld1q_u8(ks->rk[9]));  W_AES_ROUND8(vld1q_u8(ks->rk[10]));
                W_AES_ROUND8(vld1q_u8(ks->rk[11])); W_AES_ROUND8(vld1q_u8(ks->rk[12]));
            }
            gm = veorq_u64(gm, veorq_u64(glo, ghi));
            y = w_ghash_reduce_hw(glo, ghi, gm);
            vst1q_u8(out + off +   0, veorq_u8(vld1q_u8(in + off +   0), veorq_u8(vaeseq_u8(b0, rkl), rkf)));
            vst1q_u8(out + off +  16, veorq_u8(vld1q_u8(in + off +  16), veorq_u8(vaeseq_u8(b1, rkl), rkf)));
            vst1q_u8(out + off +  32, veorq_u8(vld1q_u8(in + off +  32), veorq_u8(vaeseq_u8(b2, rkl), rkf)));
            vst1q_u8(out + off +  48, veorq_u8(vld1q_u8(in + off +  48), veorq_u8(vaeseq_u8(b3, rkl), rkf)));
            vst1q_u8(out + off +  64, veorq_u8(vld1q_u8(in + off +  64), veorq_u8(vaeseq_u8(b4, rkl), rkf)));
            vst1q_u8(out + off +  80, veorq_u8(vld1q_u8(in + off +  80), veorq_u8(vaeseq_u8(b5, rkl), rkf)));
            vst1q_u8(out + off +  96, veorq_u8(vld1q_u8(in + off +  96), veorq_u8(vaeseq_u8(b6, rkl), rkf)));
            vst1q_u8(out + off + 112, veorq_u8(vld1q_u8(in + off + 112), veorq_u8(vaeseq_u8(b7, rkl), rkf)));
            off += 128;
        }
        const uint8_t *prev = out + off - 128;
        uint64x2_t glo = vdupq_n_u64(0), ghi = glo, gm = glo;
        W_GHASH_STEP(glo, ghi, gm, veorq_u8(y, vrbitq_u8(vld1q_u8(prev +   0))), 7);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  16)), 6);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  32)), 5);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  48)), 4);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  64)), 3);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  80)), 2);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev +  96)), 1);
        W_GHASH_STEP(glo, ghi, gm, vrbitq_u8(vld1q_u8(prev + 112)), 0);
        gm = veorq_u64(gm, veorq_u64(glo, ghi));
        y = w_ghash_reduce_hw(glo, ghi, gm);
    }
    #undef W_GHASH_STEP
    #undef W_AES_ROUND8

    vst1q_u8(Y, vrbitq_u8(y));
    if (off < len) {
        size_t tail_start = off;
        uint8_t ks_block[16];
        for (; off < len; off += 16) {
            w_store_be32(ctr_base + 12, c++);
            w_aes_encrypt_block_hw(ks, ctr_base, ks_block);
            size_t n = len - off < 16 ? len - off : 16;
            for (size_t i = 0; i < n; i++) out[off + i] = in[off + i] ^ ks_block[i];
        }
        w_ghash_absorb_hw(Y, kc->H, decrypt ? (in + tail_start) : (out + tail_start), len - tail_start);
    }
    w_store_be64(lenblk, (uint64_t)alen * 8U);
    w_store_be64(lenblk + 8, (uint64_t)len * 8U);
    for (int i = 0; i < 16; i++) Y[i] ^= lenblk[i];
    w_ghash_mul_hw(Y, kc->H);
    memcpy(J0, nonce, 12);
    memset(J0 + 12, 0, 4);
    J0[15] = 1;
    w_aes_encrypt_block_hw(ks, J0, EJ0);
    for (int i = 0; i < 16; i++) tag_out[i] = Y[i] ^ EJ0[i];
}
#endif

/* AES-GCM seal/open core (12-byte nonce, 16-byte tag). Returns 1 on success;
 * open returns 0 on tag mismatch (constant-time compare) and leaves out
 * unspecified. out must hold ptlen+16 (seal) / ctlen-16 (open) bytes. */
static void w_aes_gcm_ctr(const WAesKey *ks, const uint8_t nonce[12], const uint8_t *in,
                          size_t len, uint8_t *out) {
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        w_aes_gcm_ctr_hw(ks, nonce, in, len, out);
        return;
    }
#endif
    uint8_t ctr[16], ks_block[16];
    memcpy(ctr, nonce, 12);
    uint32_t c = 2;
    for (size_t off = 0; off < len; off += 16) {
        w_store_be32(ctr + 12, c++);
        w_aes_encrypt_block_sw(ks, ctr, ks_block);
        size_t n = len - off < 16 ? len - off : 16;
        for (size_t i = 0; i < n; i++) out[off + i] = in[off + i] ^ ks_block[i];
    }
}

static void w_aes_gcm_tag(const WAesKey *ks, const uint8_t H[16], const uint8_t nonce[12],
                          const uint8_t *aad, size_t alen, const uint8_t *ct, size_t clen,
                          uint8_t tag[16]) {
    uint8_t Y[16], J0[16], EJ0[16], lenblk[16];
    memset(Y, 0, 16);
    w_ghash_absorb(Y, H, aad, alen);
    w_ghash_absorb(Y, H, ct, clen);
    w_store_be64(lenblk, (uint64_t)alen * 8U);
    w_store_be64(lenblk + 8, (uint64_t)clen * 8U);
    for (int i = 0; i < 16; i++) Y[i] ^= lenblk[i];
    w_ghash_mul(Y, H);
    memcpy(J0, nonce, 12);
    memset(J0 + 12, 0, 4);
    J0[15] = 1;
    w_aes_encrypt_block(ks, J0, EJ0);
    for (int i = 0; i < 16; i++) tag[i] = Y[i] ^ EJ0[i];
}

static int w_aes_gcm_seal_core(const uint8_t *key, size_t keylen, const uint8_t nonce[12],
                               const uint8_t *pt, size_t ptlen, const uint8_t *aad, size_t alen,
                               uint8_t *out /* ptlen + 16 */) {
    if (keylen != 16 && keylen != 32) return 0;
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        const WGcmKeyCache *kc = w_gcm_get_cached_key(key, keylen);
        w_aes_gcm_crypt_fused_hw(kc, nonce, pt, ptlen, aad, alen, out, out + ptlen, 0);
        return 1;
    }
#endif
    WAesKey ks;
    uint8_t H[16];
    static const uint8_t zero[16] = {0};
    w_aes_key_expand(key, keylen, &ks);
    w_aes_encrypt_block(&ks, zero, H);
    w_aes_gcm_ctr(&ks, nonce, pt, ptlen, out);
    w_aes_gcm_tag(&ks, H, nonce, aad, alen, out, ptlen, out + ptlen);
    return 1;
}

static int w_aes_gcm_open_core(const uint8_t *key, size_t keylen, const uint8_t nonce[12],
                               const uint8_t *sealed, size_t slen, const uint8_t *aad, size_t alen,
                               uint8_t *out /* slen - 16 */) {
    uint8_t expect[16];
    if (keylen != 16 && keylen != 32) return 0;
    if (slen < 16) return 0;
    size_t clen = slen - 16;
#if W_CRYPTO_HW
    if (w_hw_aes_available()) {
        const WGcmKeyCache *kc = w_gcm_get_cached_key(key, keylen);
        w_aes_gcm_crypt_fused_hw(kc, nonce, sealed, clen, aad, alen, out, expect, 1);
        uint8_t diff = 0;
        for (int i = 0; i < 16; i++) diff |= (uint8_t)(expect[i] ^ sealed[clen + i]);
        if (diff != 0) {
            memset(out, 0, clen);
            return 0;
        }
        return 1;
    }
#endif
    WAesKey ks;
    uint8_t H[16];
    static const uint8_t zero[16] = {0};
    w_aes_key_expand(key, keylen, &ks);
    w_aes_encrypt_block(&ks, zero, H);
    w_aes_gcm_tag(&ks, H, nonce, aad, alen, sealed, clen, expect);
    uint8_t diff = 0;
    for (int i = 0; i < 16; i++) diff |= (uint8_t)(expect[i] ^ sealed[clen + i]);
    if (diff != 0) return 0;
    w_aes_gcm_ctr(&ks, nonce, sealed, clen, out);
    return 1;
}

#define W_MD5_F1(x, y, z) ((z) ^ ((x) & ((y) ^ (z))))
#define W_MD5_F2(x, y, z) W_MD5_F1((z), (x), (y))
#define W_MD5_F3(x, y, z) ((x) ^ (y) ^ (z))
#define W_MD5_F4(x, y, z) ((y) ^ ((x) | ~(z)))
#define W_MD5_STEP(f, a, b, c, d, x, t, s) \
    (a) += f((b), (c), (d)) + (x) + (t); \
    (a) = w_rotl32((a), (s)); \
    (a) += (b);

static void w_md5_compress(uint32_t st[4], const uint8_t *data, size_t blocks) {
    uint32_t h0 = st[0], h1 = st[1], h2 = st[2], h3 = st[3];
    for (size_t blk = 0; blk < blocks; blk++, data += 64) {
        uint32_t w0  = w_load_le32(data +  0), w1  = w_load_le32(data +  4);
        uint32_t w2  = w_load_le32(data +  8), w3  = w_load_le32(data + 12);
        uint32_t w4  = w_load_le32(data + 16), w5  = w_load_le32(data + 20);
        uint32_t w6  = w_load_le32(data + 24), w7  = w_load_le32(data + 28);
        uint32_t w8  = w_load_le32(data + 32), w9  = w_load_le32(data + 36);
        uint32_t w10 = w_load_le32(data + 40), w11 = w_load_le32(data + 44);
        uint32_t w12 = w_load_le32(data + 48), w13 = w_load_le32(data + 52);
        uint32_t w14 = w_load_le32(data + 56), w15 = w_load_le32(data + 60);

        uint32_t a = h0, b = h1, c = h2, d = h3;

        W_MD5_STEP(W_MD5_F1, a, b, c, d, w0,  0xd76aa478U,  7)
        W_MD5_STEP(W_MD5_F1, d, a, b, c, w1,  0xe8c7b756U, 12)
        W_MD5_STEP(W_MD5_F1, c, d, a, b, w2,  0x242070dbU, 17)
        W_MD5_STEP(W_MD5_F1, b, c, d, a, w3,  0xc1bdceeeU, 22)
        W_MD5_STEP(W_MD5_F1, a, b, c, d, w4,  0xf57c0fafU,  7)
        W_MD5_STEP(W_MD5_F1, d, a, b, c, w5,  0x4787c62aU, 12)
        W_MD5_STEP(W_MD5_F1, c, d, a, b, w6,  0xa8304613U, 17)
        W_MD5_STEP(W_MD5_F1, b, c, d, a, w7,  0xfd469501U, 22)
        W_MD5_STEP(W_MD5_F1, a, b, c, d, w8,  0x698098d8U,  7)
        W_MD5_STEP(W_MD5_F1, d, a, b, c, w9,  0x8b44f7afU, 12)
        W_MD5_STEP(W_MD5_F1, c, d, a, b, w10, 0xffff5bb1U, 17)
        W_MD5_STEP(W_MD5_F1, b, c, d, a, w11, 0x895cd7beU, 22)
        W_MD5_STEP(W_MD5_F1, a, b, c, d, w12, 0x6b901122U,  7)
        W_MD5_STEP(W_MD5_F1, d, a, b, c, w13, 0xfd987193U, 12)
        W_MD5_STEP(W_MD5_F1, c, d, a, b, w14, 0xa679438eU, 17)
        W_MD5_STEP(W_MD5_F1, b, c, d, a, w15, 0x49b40821U, 22)

        W_MD5_STEP(W_MD5_F2, a, b, c, d, w1,  0xf61e2562U,  5)
        W_MD5_STEP(W_MD5_F2, d, a, b, c, w6,  0xc040b340U,  9)
        W_MD5_STEP(W_MD5_F2, c, d, a, b, w11, 0x265e5a51U, 14)
        W_MD5_STEP(W_MD5_F2, b, c, d, a, w0,  0xe9b6c7aaU, 20)
        W_MD5_STEP(W_MD5_F2, a, b, c, d, w5,  0xd62f105dU,  5)
        W_MD5_STEP(W_MD5_F2, d, a, b, c, w10, 0x02441453U,  9)
        W_MD5_STEP(W_MD5_F2, c, d, a, b, w15, 0xd8a1e681U, 14)
        W_MD5_STEP(W_MD5_F2, b, c, d, a, w4,  0xe7d3fbc8U, 20)
        W_MD5_STEP(W_MD5_F2, a, b, c, d, w9,  0x21e1cde6U,  5)
        W_MD5_STEP(W_MD5_F2, d, a, b, c, w14, 0xc33707d6U,  9)
        W_MD5_STEP(W_MD5_F2, c, d, a, b, w3,  0xf4d50d87U, 14)
        W_MD5_STEP(W_MD5_F2, b, c, d, a, w8,  0x455a14edU, 20)
        W_MD5_STEP(W_MD5_F2, a, b, c, d, w13, 0xa9e3e905U,  5)
        W_MD5_STEP(W_MD5_F2, d, a, b, c, w2,  0xfcefa3f8U,  9)
        W_MD5_STEP(W_MD5_F2, c, d, a, b, w7,  0x676f02d9U, 14)
        W_MD5_STEP(W_MD5_F2, b, c, d, a, w12, 0x8d2a4c8aU, 20)

        W_MD5_STEP(W_MD5_F3, a, b, c, d, w5,  0xfffa3942U,  4)
        W_MD5_STEP(W_MD5_F3, d, a, b, c, w8,  0x8771f681U, 11)
        W_MD5_STEP(W_MD5_F3, c, d, a, b, w11, 0x6d9d6122U, 16)
        W_MD5_STEP(W_MD5_F3, b, c, d, a, w14, 0xfde5380cU, 23)
        W_MD5_STEP(W_MD5_F3, a, b, c, d, w1,  0xa4beea44U,  4)
        W_MD5_STEP(W_MD5_F3, d, a, b, c, w4,  0x4bdecfa9U, 11)
        W_MD5_STEP(W_MD5_F3, c, d, a, b, w7,  0xf6bb4b60U, 16)
        W_MD5_STEP(W_MD5_F3, b, c, d, a, w10, 0xbebfbc70U, 23)
        W_MD5_STEP(W_MD5_F3, a, b, c, d, w13, 0x289b7ec6U,  4)
        W_MD5_STEP(W_MD5_F3, d, a, b, c, w0,  0xeaa127faU, 11)
        W_MD5_STEP(W_MD5_F3, c, d, a, b, w3,  0xd4ef3085U, 16)
        W_MD5_STEP(W_MD5_F3, b, c, d, a, w6,  0x04881d05U, 23)
        W_MD5_STEP(W_MD5_F3, a, b, c, d, w9,  0xd9d4d039U,  4)
        W_MD5_STEP(W_MD5_F3, d, a, b, c, w12, 0xe6db99e5U, 11)
        W_MD5_STEP(W_MD5_F3, c, d, a, b, w15, 0x1fa27cf8U, 16)
        W_MD5_STEP(W_MD5_F3, b, c, d, a, w2,  0xc4ac5665U, 23)

        W_MD5_STEP(W_MD5_F4, a, b, c, d, w0,  0xf4292244U,  6)
        W_MD5_STEP(W_MD5_F4, d, a, b, c, w7,  0x432aff97U, 10)
        W_MD5_STEP(W_MD5_F4, c, d, a, b, w14, 0xab9423a7U, 15)
        W_MD5_STEP(W_MD5_F4, b, c, d, a, w5,  0xfc93a039U, 21)
        W_MD5_STEP(W_MD5_F4, a, b, c, d, w12, 0x655b59c3U,  6)
        W_MD5_STEP(W_MD5_F4, d, a, b, c, w3,  0x8f0ccc92U, 10)
        W_MD5_STEP(W_MD5_F4, c, d, a, b, w10, 0xffeff47dU, 15)
        W_MD5_STEP(W_MD5_F4, b, c, d, a, w1,  0x85845dd1U, 21)
        W_MD5_STEP(W_MD5_F4, a, b, c, d, w8,  0x6fa87e4fU,  6)
        W_MD5_STEP(W_MD5_F4, d, a, b, c, w15, 0xfe2ce6e0U, 10)
        W_MD5_STEP(W_MD5_F4, c, d, a, b, w6,  0xa3014314U, 15)
        W_MD5_STEP(W_MD5_F4, b, c, d, a, w13, 0x4e0811a1U, 21)
        W_MD5_STEP(W_MD5_F4, a, b, c, d, w4,  0xf7537e82U,  6)
        W_MD5_STEP(W_MD5_F4, d, a, b, c, w11, 0xbd3af235U, 10)
        W_MD5_STEP(W_MD5_F4, c, d, a, b, w2,  0x2ad7d2bbU, 15)
        W_MD5_STEP(W_MD5_F4, b, c, d, a, w9,  0xeb86d391U, 21)

        h0 += a;
        h1 += b;
        h2 += c;
        h3 += d;
    }
    st[0] = h0; st[1] = h1; st[2] = h2; st[3] = h3;
}
#undef W_MD5_F1
#undef W_MD5_F2
#undef W_MD5_F3
#undef W_MD5_F4
#undef W_MD5_STEP

static void w_md5_digest(const uint8_t *data, size_t len, uint8_t out[16]) {
    uint32_t st[4] = {0x67452301U, 0xefcdab89U, 0x98badcfeU, 0x10325476U};
    size_t full_blocks = len / 64;
    if (full_blocks > 0) {
        w_md5_compress(st, data, full_blocks);
    }
    size_t rem = len - full_blocks * 64;
    size_t tail_len = (rem < 56) ? 64 : 128;
    uint8_t tail[128];
    memset(tail, 0, tail_len);
    if (rem > 0) memcpy(tail, data + full_blocks * 64, rem);
    tail[rem] = 0x80;
    uint64_t bit_len = (uint64_t)len * 8U;
    for (int i = 0; i < 8; i++) tail[tail_len - 8 + i] = (uint8_t)(bit_len >> (8 * i));
    w_md5_compress(st, tail, tail_len / 64);

    for (int i = 0; i < 4; i++) {
        out[i * 4]     = (uint8_t)st[i];
        out[i * 4 + 1] = (uint8_t)(st[i] >> 8);
        out[i * 4 + 2] = (uint8_t)(st[i] >> 16);
        out[i * 4 + 3] = (uint8_t)(st[i] >> 24);
    }
}

static void w_sha1_digest(const uint8_t *data, size_t len, uint8_t out[20]) {
    uint32_t h0 = 0x67452301U;
    uint32_t h1 = 0xefcdab89U;
    uint32_t h2 = 0x98badcfeU;
    uint32_t h3 = 0x10325476U;
    uint32_t h4 = 0xc3d2e1f0U;

#if W_CRYPTO_HW
    if (w_hw_sha1_available()) {
        uint32_t st[5] = {h0, h1, h2, h3, h4};
        size_t full_blocks = len / 64;
        if (full_blocks > 0) {
            w_sha1_hw_compress(st, data, full_blocks);
        }
        size_t rem = len - full_blocks * 64;
        size_t tail_len = (rem < 56) ? 64 : 128;
        uint8_t tail[128];
        memset(tail, 0, tail_len);
        if (rem > 0) memcpy(tail, data + full_blocks * 64, rem);
        tail[rem] = 0x80;
        uint64_t bit_len = (uint64_t)len * 8U;
        for (int i = 0; i < 8; i++) tail[tail_len - 1 - i] = (uint8_t)(bit_len >> (8 * i));
        w_sha1_hw_compress(st, tail, tail_len / 64);
        for (int i = 0; i < 5; i++) w_store_be32(out + i * 4, st[i]);
        return;
    }
#endif

    size_t total = w_digest_padded_len(len);
    uint8_t *msg = calloc(1, total);
    if (len > 0) memcpy(msg, data, len);
    msg[len] = 0x80;
    uint64_t bit_len = (uint64_t)len * 8U;
    for (int i = 0; i < 8; i++) msg[total - 1 - i] = (uint8_t)(bit_len >> (8 * i));

    for (size_t offset = 0; offset < total; offset += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) w[i] = w_load_be32(msg + offset + i * 4);
        for (int i = 16; i < 80; i++) w[i] = w_rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

        uint32_t a = h0, b = h1, c = h2, d = h3, e = h4;
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 0x5a827999U;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1U;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdcU;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6U;
            }
            uint32_t temp = w_rotl32(a, 5) + f + e + k + w[i];
            e = d;
            d = c;
            c = w_rotl32(b, 30);
            b = a;
            a = temp;
        }
        h0 += a;
        h1 += b;
        h2 += c;
        h3 += d;
        h4 += e;
    }
    free(msg);

    uint32_t h[5] = {h0, h1, h2, h3, h4};
    for (int i = 0; i < 5; i++) w_store_be32(out + i * 4, h[i]);
}

static void w_sha256_family_digest(const uint8_t *data, size_t len, const uint32_t initial[8],
                                   uint8_t *out, size_t out_len) {
    static const uint32_t k[64] = {
        0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
        0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
        0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
        0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
        0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
        0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
        0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
        0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
        0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
        0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
        0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
        0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
        0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
        0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
        0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
        0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
    };

    uint32_t h[8];
    memcpy(h, initial, sizeof(h));

#if W_SHA256_HW
    if (w_sha256_hw_available()) {
        size_t full_blocks = len / 64;
        if (full_blocks > 0) {
            w_sha256_hw_compress(h, data, full_blocks);
        }
        size_t rem = len - full_blocks * 64;
        size_t tail_len = (rem < 56) ? 64 : 128;
        uint8_t tail[128];
        memset(tail, 0, tail_len);
        if (rem > 0) memcpy(tail, data + full_blocks * 64, rem);
        tail[rem] = 0x80;
        uint64_t bit_len = (uint64_t)len * 8U;
        for (int i = 0; i < 8; i++) tail[tail_len - 1 - i] = (uint8_t)(bit_len >> (8 * i));
        w_sha256_hw_compress(h, tail, tail_len / 64);
        uint8_t full[32];
        for (int i = 0; i < 8; i++) w_store_be32(full + i * 4, h[i]);
        memcpy(out, full, out_len);
        return;
    }
#endif

    size_t total = w_digest_padded_len(len);
    uint8_t *msg = calloc(1, total);
    if (len > 0) memcpy(msg, data, len);
    msg[len] = 0x80;
    uint64_t bit_len = (uint64_t)len * 8U;
    for (int i = 0; i < 8; i++) msg[total - 1 - i] = (uint8_t)(bit_len >> (8 * i));

    for (size_t offset = 0; offset < total; offset += 64) {
        uint32_t w[64];
        for (int i = 0; i < 16; i++) w[i] = w_load_be32(msg + offset + i * 4);
        for (int i = 16; i < 64; i++) {
            uint32_t s0 = w_rotr32(w[i - 15], 7) ^ w_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = w_rotr32(w[i - 2], 17) ^ w_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; i++) {
            uint32_t s1 = w_rotr32(e, 6) ^ w_rotr32(e, 11) ^ w_rotr32(e, 25);
            uint32_t ch = (e & f) ^ ((~e) & g);
            uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
            uint32_t s0 = w_rotr32(a, 2) ^ w_rotr32(a, 13) ^ w_rotr32(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t temp2 = s0 + maj;
            hh = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
        h[5] += f;
        h[6] += g;
        h[7] += hh;
    }
    free(msg);

    uint8_t full[32];
    for (int i = 0; i < 8; i++) w_store_be32(full + i * 4, h[i]);
    memcpy(out, full, out_len);
}

static void w_sha224_digest(const uint8_t *data, size_t len, uint8_t out[28]) {
    static const uint32_t iv[8] = {
        0xc1059ed8U, 0x367cd507U, 0x3070dd17U, 0xf70e5939U,
        0xffc00b31U, 0x68581511U, 0x64f98fa7U, 0xbefa4fa4U
    };
    w_sha256_family_digest(data, len, iv, out, 28);
}

static void w_sha256_digest(const uint8_t *data, size_t len, uint8_t out[32]) {
    static const uint32_t iv[8] = {
        0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
        0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U
    };
    w_sha256_family_digest(data, len, iv, out, 32);
}

static void w_sha512_family_digest(const uint8_t *data, size_t len, const uint64_t initial[8],
                                   uint8_t *out, size_t out_len) {
    static const uint64_t k[80] = {
        0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
        0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
        0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
        0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
        0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
        0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
        0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
        0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
        0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
        0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
        0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
        0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
        0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
        0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
        0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
        0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
        0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
        0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
        0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
        0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
    };

    uint64_t h[8];
    memcpy(h, initial, sizeof(h));

#if W_CRYPTO_HW
    if (w_hw_sha512_available()) {
        size_t full_blocks = len / 128;
        if (full_blocks > 0) {
            w_sha512_hw_compress(h, data, full_blocks);
        }
        size_t rem = len - full_blocks * 128;
        size_t tail_len = (rem < 112) ? 128 : 256;
        uint8_t tail[256];
        memset(tail, 0, tail_len);
        if (rem > 0) memcpy(tail, data + full_blocks * 128, rem);
        tail[rem] = 0x80;
        uint64_t bit_len = (uint64_t)len * 8U;
        for (int i = 0; i < 8; i++) tail[tail_len - 1 - i] = (uint8_t)(bit_len >> (8 * i));
        w_sha512_hw_compress(h, tail, tail_len / 128);
        uint8_t full[64];
        for (int i = 0; i < 8; i++) w_store_be64(full + i * 8, h[i]);
        memcpy(out, full, out_len);
        return;
    }
#endif

    size_t total = w_digest_padded_len_128(len);
    uint8_t *msg = calloc(1, total);
    if (len > 0) memcpy(msg, data, len);
    msg[len] = 0x80;
    uint64_t bit_len = (uint64_t)len * 8U;
    for (int i = 0; i < 8; i++) msg[total - 1 - i] = (uint8_t)(bit_len >> (8 * i));

    for (size_t offset = 0; offset < total; offset += 128) {
        uint64_t w[80];
        for (int i = 0; i < 16; i++) w[i] = w_load_be64(msg + offset + i * 8);
        for (int i = 16; i < 80; i++) {
            uint64_t s0 = w_rotr64(w[i - 15], 1) ^ w_rotr64(w[i - 15], 8) ^ (w[i - 15] >> 7);
            uint64_t s1 = w_rotr64(w[i - 2], 19) ^ w_rotr64(w[i - 2], 61) ^ (w[i - 2] >> 6);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint64_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 80; i++) {
            uint64_t s1 = w_rotr64(e, 14) ^ w_rotr64(e, 18) ^ w_rotr64(e, 41);
            uint64_t ch = (e & f) ^ ((~e) & g);
            uint64_t temp1 = hh + s1 + ch + k[i] + w[i];
            uint64_t s0 = w_rotr64(a, 28) ^ w_rotr64(a, 34) ^ w_rotr64(a, 39);
            uint64_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint64_t temp2 = s0 + maj;
            hh = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
        h[5] += f;
        h[6] += g;
        h[7] += hh;
    }
    free(msg);

    uint8_t full[64];
    for (int i = 0; i < 8; i++) w_store_be64(full + i * 8, h[i]);
    memcpy(out, full, out_len);
}

static void w_sha384_digest(const uint8_t *data, size_t len, uint8_t out[48]) {
    static const uint64_t iv[8] = {
        0xcbbb9d5dc1059ed8ULL, 0x629a292a367cd507ULL, 0x9159015a3070dd17ULL, 0x152fecd8f70e5939ULL,
        0x67332667ffc00b31ULL, 0x8eb44a8768581511ULL, 0xdb0c2e0d64f98fa7ULL, 0x47b5481dbefa4fa4ULL
    };
    w_sha512_family_digest(data, len, iv, out, 48);
}

static void w_sha512_digest(const uint8_t *data, size_t len, uint8_t out[64]) {
    static const uint64_t iv[8] = {
        0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
        0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL
    };
    w_sha512_family_digest(data, len, iv, out, 64);
}

static void w_sha512_224_digest(const uint8_t *data, size_t len, uint8_t out[28]) {
    static const uint64_t iv[8] = {
        0x8c3d37c819544da2ULL, 0x73e1996689dcd4d6ULL, 0x1dfab7ae32ff9c82ULL, 0x679dd514582f9fcfULL,
        0x0f6d2b697bd44da8ULL, 0x77e36f7304c48942ULL, 0x3f9d85a86a1d36c8ULL, 0x1112e6ad91d692a1ULL
    };
    w_sha512_family_digest(data, len, iv, out, 28);
}

static void w_sha512_256_digest(const uint8_t *data, size_t len, uint8_t out[32]) {
    static const uint64_t iv[8] = {
        0x22312194fc2bf72cULL, 0x9f555fa3c84c64c2ULL, 0x2393b86b6f53b151ULL, 0x963877195940eabdULL,
        0x96283ee2a88effe3ULL, 0xbe5e1e2553863992ULL, 0x2b0199fc2c85b8aaULL, 0x0eb72ddc81c52ca2ULL
    };
    w_sha512_family_digest(data, len, iv, out, 32);
}

WValue w_crypto_md5_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[16];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_md5_digest(input, len, digest);
    return w_bytes_from_data(digest, 16);
}

WValue w_crypto_md5_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[16];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_md5_digest(input, len, digest);
    return w_hex_from_bytes(digest, 16);
}

WValue w_crypto_sha1_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[20];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha1_digest(input, len, digest);
    return w_bytes_from_data(digest, 20);
}

WValue w_crypto_sha1_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[20];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha1_digest(input, len, digest);
    return w_hex_from_bytes(digest, 20);
}

WValue w_crypto_sha224_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[28];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha224_digest(input, len, digest);
    return w_bytes_from_data(digest, 28);
}

WValue w_crypto_sha224_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[28];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha224_digest(input, len, digest);
    return w_hex_from_bytes(digest, 28);
}

WValue w_crypto_sha256_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[32];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha256_digest(input, len, digest);
    return w_bytes_from_data(digest, 32);
}

WValue w_crypto_sha256_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[32];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha256_digest(input, len, digest);
    return w_hex_from_bytes(digest, 32);
}

WValue w_crypto_sha384_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[48];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha384_digest(input, len, digest);
    return w_bytes_from_data(digest, 48);
}

WValue w_crypto_sha384_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[48];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha384_digest(input, len, digest);
    return w_hex_from_bytes(digest, 48);
}

WValue w_crypto_sha512_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[64];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_digest(input, len, digest);
    return w_bytes_from_data(digest, 64);
}

WValue w_crypto_sha512_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[64];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_digest(input, len, digest);
    return w_hex_from_bytes(digest, 64);
}

WValue w_crypto_sha512_224_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[28];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_224_digest(input, len, digest);
    return w_bytes_from_data(digest, 28);
}

WValue w_crypto_sha512_224_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[28];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_224_digest(input, len, digest);
    return w_hex_from_bytes(digest, 28);
}

WValue w_crypto_sha512_256_bytes(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[32];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_256_digest(input, len, digest);
    return w_bytes_from_data(digest, 32);
}

WValue w_crypto_sha512_256_hex(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[32];
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha512_256_digest(input, len, digest);
    return w_hex_from_bytes(digest, 32);
}

/* ---- SHA-3 / SHAKE / CRC-32 / AES-GCM public entry points --------------- */

static size_t w_sha3_mdlen(WValue bits_v) {
    int64_t bits = w_to_i64(bits_v);
    switch (bits) {
        case 224: return 28;
        case 256: return 32;
        case 384: return 48;
        case 512: return 64;
        default:
            w_raise(w_string("Crypto:SHA3: bits must be 224, 256, 384, or 512"));
            return 0;
    }
}

WValue w_crypto_sha3_bytes(WValue data, WValue bits_v) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[64];
    size_t mdlen = w_sha3_mdlen(bits_v);
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha3_digest(input, len, mdlen, digest);
    return w_bytes_from_data(digest, (int64_t)mdlen);
}

WValue w_crypto_sha3_hex(WValue data, WValue bits_v) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    uint8_t digest[64];
    size_t mdlen = w_sha3_mdlen(bits_v);
    w_crypto_input_data(data, &input, &len, inline_buf);
    w_sha3_digest(input, len, mdlen, digest);
    return w_hex_from_bytes(digest, mdlen);
}

/* SHAKE extendable-output: bits selects the security level (128 or 256),
 * outlen the number of output bytes. */
WValue w_crypto_shake_bytes(WValue data, WValue bits_v, WValue outlen_v) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    int64_t bits = w_to_i64(bits_v);
    int64_t outlen = w_to_i64(outlen_v);
    if (bits != 128 && bits != 256) w_raise(w_string("Crypto:SHAKE: bits must be 128 or 256"));
    if (outlen < 0 || outlen > INT32_MAX) w_raise(w_string("Crypto:SHAKE: outlen out of range"));
    w_crypto_input_data(data, &input, &len, inline_buf);
    WValue out = w_bytes_new(outlen);
    if (outlen > 0) {
        WArray *a = w_as_array(out);
        w_shake_digest(input, len, bits == 256 ? 1 : 0, (uint8_t *)a->slots, (size_t)outlen);
    }
    return out;
}

WValue w_crypto_shake_hex(WValue data, WValue bits_v, WValue outlen_v) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    int64_t bits = w_to_i64(bits_v);
    int64_t outlen = w_to_i64(outlen_v);
    if (bits != 128 && bits != 256) w_raise(w_string("Crypto:SHAKE: bits must be 128 or 256"));
    if (outlen < 0 || outlen > INT32_MAX / 2) w_raise(w_string("Crypto:SHAKE: outlen out of range"));
    w_crypto_input_data(data, &input, &len, inline_buf);
    uint8_t *buf = malloc((size_t)outlen ? (size_t)outlen : 1);
    w_shake_digest(input, len, bits == 256 ? 1 : 0, buf, (size_t)outlen);
    WValue r = w_hex_from_bytes(buf, (size_t)outlen);
    free(buf);
    return r;
}

WValue w_crypto_crc32(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    w_crypto_input_data(data, &input, &len, inline_buf);
    return w_int((int64_t)w_crc32_run(input, len, 0));
}

WValue w_crypto_crc32c(WValue data) {
    const uint8_t *input;
    size_t len;
    char inline_buf[6];
    w_crypto_input_data(data, &input, &len, inline_buf);
    return w_int((int64_t)w_crc32_run(input, len, 1));
}

WValue w_crypto_aes_gcm_seal(WValue key_v, WValue nonce_v, WValue pt_v, WValue aad_v) {
    const uint8_t *key, *nonce, *pt, *aad;
    size_t keylen, noncelen, ptlen, aadlen;
    char kb[6], nb[6], pb[6], ab[6];
    w_crypto_input_data(key_v, &key, &keylen, kb);
    w_crypto_input_data(nonce_v, &nonce, &noncelen, nb);
    w_crypto_input_data(pt_v, &pt, &ptlen, pb);
    w_crypto_input_data(aad_v, &aad, &aadlen, ab);
    if (keylen != 16 && keylen != 32) w_raise(w_string("Crypto:AES.gcm: key must be 16 or 32 bytes"));
    if (noncelen != 12) w_raise(w_string("Crypto:AES.gcm: nonce must be 12 bytes"));
    WValue out = w_array_new_uninit_sized(8, (int64_t)(ptlen + 16));
    WArray *a = w_as_array(out);
    if (!w_aes_gcm_seal_core(key, keylen, nonce, pt, ptlen, aad, aadlen, (uint8_t *)a->slots))
        w_raise(w_string("Crypto:AES.gcm: seal failed"));
    return out;
}

WValue w_crypto_aes_gcm_open(WValue key_v, WValue nonce_v, WValue sealed_v, WValue aad_v) {
    const uint8_t *key, *nonce, *sealed, *aad;
    size_t keylen, noncelen, slen, aadlen;
    char kb[6], nb[6], sb[6], ab[6];
    w_crypto_input_data(key_v, &key, &keylen, kb);
    w_crypto_input_data(nonce_v, &nonce, &noncelen, nb);
    w_crypto_input_data(sealed_v, &sealed, &slen, sb);
    w_crypto_input_data(aad_v, &aad, &aadlen, ab);
    if (keylen != 16 && keylen != 32) w_raise(w_string("Crypto:AES.gcm: key must be 16 or 32 bytes"));
    if (noncelen != 12) w_raise(w_string("Crypto:AES.gcm: nonce must be 12 bytes"));
    if (slen < 16) w_raise(w_string("Crypto:AES.gcm: ciphertext too short for tag"));
    size_t out_len = slen - 16;
    WValue out = w_array_new_uninit_sized(8, (int64_t)(out_len > 0 ? out_len : 1));
    WArray *a = w_as_array(out);
    a->size = (int32_t)out_len;
    if (!w_aes_gcm_open_core(key, keylen, nonce, sealed, slen, aad, aadlen, (uint8_t *)a->slots))
        w_raise(w_string("Crypto:AES.gcm: authentication failed"));
    return out;
}


static int w_uuid_parse_bytes(const char *text, size_t len, uint8_t out[16]) {
    if (len >= 9 && strncasecmp(text, "urn:uuid:", 9) == 0) {
        text += 9;
        len -= 9;
    }

    if (len == 36) {
        if (text[8] != '-' || text[13] != '-' || text[18] != '-' || text[23] != '-') return 0;
        int bi = 0;
        for (size_t i = 0; i < len;) {
            if (text[i] == '-') {
                i++;
                continue;
            }
            if (i + 1 >= len) return 0;
            int hi = hex_nibble(text[i]);
            int lo = hex_nibble(text[i + 1]);
            if (hi < 0 || lo < 0 || bi >= 16) return 0;
            out[bi++] = (uint8_t)((hi << 4) | lo);
            i += 2;
        }
        return bi == 16;
    }

    if (len == 32) {
        for (int bi = 0; bi < 16; bi++) {
            int hi = hex_nibble(text[bi * 2]);
            int lo = hex_nibble(text[bi * 2 + 1]);
            if (hi < 0 || lo < 0) return 0;
            out[bi] = (uint8_t)((hi << 4) | lo);
        }
        return 1;
    }

    return 0;
}

static WValue w_uuid_from_bytes(const uint8_t bytes[16]) {
    uint8_t *copy = malloc(16);
    memcpy(copy, bytes, 16);
    return w_box_ptr(copy, W_SUBTAG_UUID);
}

static uint8_t *w_uuid_ptr(WValue uuid) {
    if (!w_is_obj(uuid) || w_subtag(uuid) != W_SUBTAG_UUID) {
        w_raise(w_string("expected UUID"));
        return NULL;
    }
    return (uint8_t *)w_as_ptr(uuid);
}

static void w_uuid_arg_bytes(WValue uuid, uint8_t out[16]) {
    if (w_is_obj(uuid) && w_subtag(uuid) == W_SUBTAG_UUID) {
        memcpy(out, w_as_ptr(uuid), 16);
        return;
    }
    if (w_is_rope(uuid) || w_is_stringy(uuid)) {
        char inline_buf[6];
        const char *s;
        size_t len;
        w_str_data(uuid, inline_buf, &s, &len);
        if (w_uuid_parse_bytes(s, len, out)) return;
    }
    w_raise(w_string("UUID namespace must be a UUID or UUID string"));
}

static WValue w_uuid_namespace(const uint8_t bytes[16]) {
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_from_hex(const char *hex) {
    uint8_t bytes[16];
    if (!w_uuid_parse_bytes(hex, strlen(hex), bytes)) {
        w_raise(w_string("invalid UUID"));
        return W_NIL;
    }
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_parse(WValue text) {
    if (w_is_obj(text) && w_subtag(text) == W_SUBTAG_UUID) return text;
    char inline_buf[6];
    const char *s;
    size_t len;
    w_str_data(text, inline_buf, &s, &len);
    uint8_t bytes[16];
    if (!w_uuid_parse_bytes(s, len, bytes)) {
        w_raise(w_string("invalid UUID"));
        return W_NIL;
    }
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_byte(WValue uuid, WValue index) {
    uint8_t *bytes = w_uuid_ptr(uuid);
    int64_t i = w_to_i64(index);
    if (i < 0 || i >= 16) return W_NIL;
    return w_int(bytes[i]);
}

WValue w_uuid_to_s(WValue uuid) {
    uint8_t *bytes = w_uuid_ptr(uuid);
    char buf[37];
    static const char hex[] = "0123456789abcdef";
    int bi = 0;
    for (int i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) buf[bi++] = '-';
        buf[bi++] = hex[bytes[i] >> 4];
        buf[bi++] = hex[bytes[i] & 0xF];
    }
    buf[36] = '\0';
    return w_string_n(buf, 36);
}

WValue w_uuid_namespace_nil(void) {
    static const uint8_t ns[16] = {0};
    return w_uuid_namespace(ns);
}

WValue w_uuid_namespace_dns(void) {
    static const uint8_t ns[16] = {
        0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
    };
    return w_uuid_namespace(ns);
}

WValue w_uuid_namespace_url(void) {
    static const uint8_t ns[16] = {
        0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
    };
    return w_uuid_namespace(ns);
}

WValue w_uuid_namespace_oid(void) {
    static const uint8_t ns[16] = {
        0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
    };
    return w_uuid_namespace(ns);
}

WValue w_uuid_namespace_x500(void) {
    static const uint8_t ns[16] = {
        0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
        0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
    };
    return w_uuid_namespace(ns);
}

static void w_uuid_set_version_variant(uint8_t bytes[16], uint8_t version) {
    bytes[6] = (uint8_t)((bytes[6] & 0x0F) | (version << 4));
    bytes[8] = (uint8_t)((bytes[8] & 0x3F) | 0x80);
}

static uint64_t w_uuid_100ns_now(void) {
    static const uint64_t uuid_epoch_offset = 0x01B21DD213814000ULL;
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
        return uuid_epoch_offset + (uint64_t)ts.tv_sec * 10000000ULL + (uint64_t)(ts.tv_nsec / 100);
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return uuid_epoch_offset + (uint64_t)tv.tv_sec * 10000000ULL + (uint64_t)tv.tv_usec * 10ULL;
}

static pthread_mutex_t g_uuid_time_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_uuid_time_inited = 0;
static int g_uuid_node_inited = 0;
static uint64_t g_uuid_last_timestamp = 0;
static uint16_t g_uuid_clock_seq = 0;
static uint8_t g_uuid_node[6];

static int w_uuid_node_usable(const uint8_t node[6]) {
    int all_zero = 1;
    for (int i = 0; i < 6; i++) {
        if (node[i] != 0) {
            all_zero = 0;
            break;
        }
    }
    return !all_zero && ((node[0] & 0x01) == 0);
}

static int w_uuid_read_local_mac(uint8_t node[6]) {
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) != 0) return 0;

    int found = 0;
    for (struct ifaddrs *ifa = ifaddr; ifa != NULL && !found; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
#ifdef __linux__
        if (ifa->ifa_addr->sa_family == AF_PACKET) {
            struct sockaddr_ll *sll = (struct sockaddr_ll *)ifa->ifa_addr;
            if (sll->sll_halen == 6 && w_uuid_node_usable(sll->sll_addr)) {
                memcpy(node, sll->sll_addr, 6);
                found = 1;
            }
        }
#endif
#ifdef __APPLE__
        if (ifa->ifa_addr->sa_family == AF_LINK) {
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            if (sdl->sdl_alen == 6) {
                const uint8_t *addr = (const uint8_t *)LLADDR(sdl);
                if (w_uuid_node_usable(addr)) {
                    memcpy(node, addr, 6);
                    found = 1;
                }
            }
        }
#endif
    }

    freeifaddrs(ifaddr);
    return found;
}

static void w_uuid_default_node(uint8_t node[6]) {
    if (!g_uuid_node_inited) {
        if (!w_uuid_read_local_mac(g_uuid_node)) {
            w_secure_random_fill(g_uuid_node, 6);
            g_uuid_node[0] |= 0x01;  /* RFC-compatible random multicast node, not a MAC address. */
        }
        g_uuid_node_inited = 1;
    }
    memcpy(node, g_uuid_node, 6);
}

static void w_uuid_ensure_clock_seq(void) {
    if (!g_uuid_time_inited) {
        uint8_t seed[2];
        w_secure_random_fill(seed, sizeof(seed));
        g_uuid_clock_seq = (uint16_t)((((uint16_t)seed[0]) << 8 | seed[1]) & 0x3FFF);
        g_uuid_time_inited = 1;
    }
}

static uint64_t w_uuid_timestamp_from_unix_ms(int64_t ms) {
    static const uint64_t uuid_epoch_offset = 0x01B21DD213814000ULL;
    if (ms >= 0) {
        return uuid_epoch_offset + (uint64_t)ms * 10000ULL;
    }
    uint64_t delta = (uint64_t)(0 - ms) * 10000ULL;
    return uuid_epoch_offset > delta ? uuid_epoch_offset - delta : 0;
}

static uint64_t w_uuid_timestamp_from_unix_seconds(double seconds) {
    static const uint64_t uuid_epoch_offset = 0x01B21DD213814000ULL;
    if (seconds >= 0.0) return uuid_epoch_offset + (uint64_t)(seconds * 10000000.0);
    double delta = -seconds * 10000000.0;
    return delta < (double)uuid_epoch_offset ? uuid_epoch_offset - (uint64_t)delta : 0;
}

static uint64_t w_uuid_timestamp_from_int(int64_t value) {
    static const int64_t unix_ms_floor = 1000000000000LL;
    static const uint64_t uuid_epoch_offset = 0x01B21DD213814000ULL;
    if (value >= (int64_t)uuid_epoch_offset) return (uint64_t)value;  /* already UUID 100ns ticks */
    if (value >= unix_ms_floor || value <= -unix_ms_floor) return w_uuid_timestamp_from_unix_ms(value);
    return w_uuid_timestamp_from_unix_seconds((double)value);
}

static WValue w_uuid_option(WValue options, const char *name) {
    if (!w_is_hash(options)) return W_NIL;
    return w_hash_get(options, w_symbol(name));
}

static WValue w_uuid_option_any(WValue options, const char *a, const char *b, const char *c) {
    WValue v = w_uuid_option(options, a);
    if (v != W_NIL) return v;
    if (b != NULL) {
        v = w_uuid_option(options, b);
        if (v != W_NIL) return v;
    }
    if (c != NULL) {
        v = w_uuid_option(options, c);
        if (v != W_NIL) return v;
    }
    return W_NIL;
}

static int w_uuid_parse_mac_text(const char *s, size_t len, uint8_t node[6]) {
    char hex[12];
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        char c = s[i];
        if (c == ':' || c == '-' || c == '.') continue;
        if (hex_nibble(c) < 0 || n >= sizeof(hex)) return 0;
        hex[n++] = c;
    }
    if (n != sizeof(hex)) return 0;
    for (int i = 0; i < 6; i++) {
        int hi = hex_nibble(hex[i * 2]);
        int lo = hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) return 0;
        node[i] = (uint8_t)((hi << 4) | lo);
    }
    return 1;
}

static int w_uuid_node_from_value(WValue value, uint8_t node[6]) {
    if (value == W_NIL) return 0;
    if (w_is_mac(value)) {
        WNetAddr *addr = (WNetAddr *)w_as_ptr(value);
        memcpy(node, addr->bytes, 6);
        return 1;
    }
    if (w_is_bytes(value)) {
        WArray *a = w_as_array(value);
        if (a->size != 6) {
            w_raise(w_string("UUID.v1/v2: MAC byte array must be exactly 6 bytes"));
            return 0;
        }
        memcpy(node, ((const uint8_t *)a->slots) + a->start, 6);
        return 1;
    }
    if (w_is_array(value)) {
        WArray *a = w_as_array(value);
        if (a->size != 6) {
            w_raise(w_string("UUID.v1/v2: MAC array must be exactly 6 bytes"));
            return 0;
        }
        for (int i = 0; i < 6; i++) {
            int64_t byte;
            if (a->ebits == 65) {
                byte = w_to_i64(a->slots[a->start + i]);
            } else if (a->ebits == 64) {
                byte = ((int64_t *)a->slots)[a->start + i];
            } else if (a->ebits == 8) {
                byte = ((uint8_t *)a->slots)[a->start + i];
            } else {
                w_raise(w_string("UUID.v1/v2: unsupported MAC array element width"));
                return 0;
            }
            if (byte < 0 || byte > 255) {
                w_raise(w_string("UUID.v1/v2: MAC byte out of range"));
                return 0;
            }
            node[i] = (uint8_t)byte;
        }
        return 1;
    }
    if (w_is_rope(value) || w_is_stringy(value)) {
        char inline_buf[6];
        const char *s;
        size_t len;
        w_str_data(value, inline_buf, &s, &len);
        if (w_uuid_parse_mac_text(s, len, node)) return 1;
    }
    return 0;
}

static int w_uuid_timestamp_from_value(WValue value, uint64_t *timestamp) {
    if (value == W_NIL) return 0;
    if (w_is_instant(value)) {
        *timestamp = w_uuid_timestamp_from_unix_ms(w_unbox_instant(value));
        return 1;
    }
    if (w_is_int(value) || w_is_bigint(value)) {
        *timestamp = w_uuid_timestamp_from_int(w_to_i64(value));
        return 1;
    }
    if (w_is_double(value)) {
        *timestamp = w_uuid_timestamp_from_unix_seconds(w_as_double(value));
        return 1;
    }
    return 0;
}

static void w_uuid_options_fields(WValue options, uint64_t *timestamp, uint16_t *clock_seq, uint8_t node[6]) {
    WValue time_v = W_NIL;
    WValue node_v = W_NIL;
    if (w_is_hash(options)) {
        time_v = w_uuid_option_any(options, "time", "at", "timestamp");
        node_v = w_uuid_option_any(options, "mac", "node", NULL);
    } else if (options != W_NIL) {
        uint8_t candidate_node[6];
        uint64_t candidate_time;
        if (w_uuid_node_from_value(options, candidate_node)) {
            memcpy(node, candidate_node, 6);
            node_v = options;
        } else if (w_uuid_timestamp_from_value(options, &candidate_time)) {
            *timestamp = candidate_time;
            time_v = options;
        } else {
            w_raise(w_string("UUID.v1/v2: expected nil, time, MAC, or options hash"));
            return;
        }
    }

    int has_timestamp = 0;
    uint64_t parsed_timestamp = 0;
    int has_node = 0;
    uint8_t parsed_node[6];

    if (time_v != W_NIL) {
        if (!w_uuid_timestamp_from_value(time_v, &parsed_timestamp)) {
            w_raise(w_string("UUID.v1/v2: invalid time option"));
            return;
        }
        has_timestamp = 1;
    }

    if (node_v != W_NIL) {
        if (!w_uuid_node_from_value(node_v, parsed_node)) {
            w_raise(w_string("UUID.v1/v2: invalid MAC option"));
            return;
        }
        has_node = 1;
    }

    pthread_mutex_lock(&g_uuid_time_lock);
    if (has_timestamp) {
        *timestamp = parsed_timestamp;
    } else {
        *timestamp = w_uuid_100ns_now();
    }

    if (has_node) {
        memcpy(node, parsed_node, 6);
    } else {
        w_uuid_default_node(node);
    }

    w_uuid_ensure_clock_seq();
    if (*timestamp <= g_uuid_last_timestamp) {
        g_uuid_clock_seq = (uint16_t)((g_uuid_clock_seq + 1) & 0x3FFF);
    }
    g_uuid_last_timestamp = *timestamp;

    *clock_seq = g_uuid_clock_seq;
    pthread_mutex_unlock(&g_uuid_time_lock);
}

static void w_uuid_time_fields(WValue options, uint64_t *timestamp, uint16_t *clock_seq, uint8_t node[6]) {
    w_uuid_options_fields(options, timestamp, clock_seq, node);
}

WValue w_uuid_v1(WValue options) {
    uint64_t timestamp;
    uint16_t clock_seq;
    uint8_t node[6];
    uint8_t bytes[16];
    w_uuid_time_fields(options, &timestamp, &clock_seq, node);

    uint32_t time_low = (uint32_t)(timestamp & 0xFFFFFFFFULL);
    uint16_t time_mid = (uint16_t)((timestamp >> 32) & 0xFFFFU);
    uint16_t time_hi = (uint16_t)((timestamp >> 48) & 0x0FFFU);

    bytes[0] = (uint8_t)(time_low >> 24);
    bytes[1] = (uint8_t)(time_low >> 16);
    bytes[2] = (uint8_t)(time_low >> 8);
    bytes[3] = (uint8_t)time_low;
    bytes[4] = (uint8_t)(time_mid >> 8);
    bytes[5] = (uint8_t)time_mid;
    bytes[6] = (uint8_t)(time_hi >> 8);
    bytes[7] = (uint8_t)time_hi;
    bytes[8] = (uint8_t)(clock_seq >> 8);
    bytes[9] = (uint8_t)clock_seq;
    memcpy(bytes + 10, node, 6);

    w_uuid_set_version_variant(bytes, 1);
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_v2(WValue options) {
    int64_t local_identifier = 0;
    int64_t domain = 0;
    if (w_is_hash(options)) {
        WValue local_identifier_v = w_uuid_option_any(options, "local_identifier", "local_id", "id");
        WValue domain_v = w_uuid_option(options, "domain");
        if (local_identifier_v != W_NIL) local_identifier = w_to_i64(local_identifier_v);
        if (domain_v != W_NIL) domain = w_to_i64(domain_v);
    }
    if (local_identifier < 0 || local_identifier > 0xFFFFFFFFLL || domain < 0 || domain > 255) {
        w_raise(w_string("UUID.v2: local identifier or domain out of range"));
        return W_NIL;
    }

    WValue base = w_uuid_v1(options);
    uint8_t bytes[16];
    memcpy(bytes, w_as_ptr(base), 16);
    bytes[0] = (uint8_t)((uint64_t)local_identifier >> 24);
    bytes[1] = (uint8_t)((uint64_t)local_identifier >> 16);
    bytes[2] = (uint8_t)((uint64_t)local_identifier >> 8);
    bytes[3] = (uint8_t)local_identifier;
    bytes[9] = (uint8_t)domain;
    w_uuid_set_version_variant(bytes, 2);
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_v3(WValue namespace_uuid, WValue name) {
    uint8_t ns[16];
    w_uuid_arg_bytes(namespace_uuid, ns);
    const uint8_t *name_data;
    size_t name_len;
    char inline_buf[6];
    w_crypto_input_data(name, &name_data, &name_len, inline_buf);

    if (name_len > SIZE_MAX - 16) die("UUID name too large");
    uint8_t *buf = malloc(16 + name_len);
    memcpy(buf, ns, 16);
    if (name_len > 0) memcpy(buf + 16, name_data, name_len);
    uint8_t digest[16];
    w_md5_digest(buf, 16 + name_len, digest);
    free(buf);
    w_uuid_set_version_variant(digest, 3);
    return w_uuid_from_bytes(digest);
}

WValue w_uuid_v4(void) {
    uint8_t bytes[16];
    w_secure_random_fill(bytes, sizeof(bytes));
    w_uuid_set_version_variant(bytes, 4);
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_v5(WValue namespace_uuid, WValue name) {
    uint8_t ns[16];
    w_uuid_arg_bytes(namespace_uuid, ns);
    const uint8_t *name_data;
    size_t name_len;
    char inline_buf[6];
    w_crypto_input_data(name, &name_data, &name_len, inline_buf);

    if (name_len > SIZE_MAX - 16) die("UUID name too large");
    uint8_t *buf = malloc(16 + name_len);
    memcpy(buf, ns, 16);
    if (name_len > 0) memcpy(buf + 16, name_data, name_len);
    uint8_t digest[20];
    w_sha1_digest(buf, 16 + name_len, digest);
    free(buf);
    w_uuid_set_version_variant(digest, 5);
    return w_uuid_from_bytes(digest);
}

WValue w_uuid_v6(void) {
    uint64_t timestamp;
    uint16_t clock_seq;
    uint8_t node[6];
    uint8_t bytes[16];
    w_uuid_time_fields(W_NIL, &timestamp, &clock_seq, node);

    bytes[0] = (uint8_t)(timestamp >> 52);
    bytes[1] = (uint8_t)(timestamp >> 44);
    bytes[2] = (uint8_t)(timestamp >> 36);
    bytes[3] = (uint8_t)(timestamp >> 28);
    bytes[4] = (uint8_t)(timestamp >> 20);
    bytes[5] = (uint8_t)(timestamp >> 12);
    bytes[6] = (uint8_t)((timestamp >> 8) & 0x0F);
    bytes[7] = (uint8_t)timestamp;
    bytes[8] = (uint8_t)(clock_seq >> 8);
    bytes[9] = (uint8_t)clock_seq;
    memcpy(bytes + 10, node, 6);

    w_uuid_set_version_variant(bytes, 6);
    return w_uuid_from_bytes(bytes);
}

static uint64_t w_unix_ms_now(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
        return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)(tv.tv_usec / 1000);
}

WValue w_uuid_v7(void) {
    uint8_t bytes[16];
    uint64_t ms = w_unix_ms_now();
    bytes[0] = (uint8_t)(ms >> 40);
    bytes[1] = (uint8_t)(ms >> 32);
    bytes[2] = (uint8_t)(ms >> 24);
    bytes[3] = (uint8_t)(ms >> 16);
    bytes[4] = (uint8_t)(ms >> 8);
    bytes[5] = (uint8_t)ms;
    w_secure_random_fill(bytes + 6, 10);
    w_uuid_set_version_variant(bytes, 7);
    return w_uuid_from_bytes(bytes);
}

WValue w_uuid_v8(WValue custom) {
    uint8_t bytes[16];
    if (custom == W_NIL) {
        w_secure_random_fill(bytes, sizeof(bytes));
    } else if (w_is_bytes(custom)) {
        WArray *a = w_as_array(custom);
        if (a->size != 16) {
            w_raise(w_string("UUID.v8: custom bytes must be exactly 16 bytes"));
            return W_NIL;
        }
        memcpy(bytes, ((const uint8_t *)a->slots) + a->start, 16);
    } else {
        w_uuid_arg_bytes(custom, bytes);
    }
    w_uuid_set_version_variant(bytes, 8);
    return w_uuid_from_bytes(bytes);
}


#ifndef W_RUNTIME_UNITY_INCLUDE
#undef die
#undef dief
#undef w_string_n
#undef w_string_n_known_ascii
#endif
