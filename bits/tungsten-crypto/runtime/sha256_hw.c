/* Hardware-accelerated SHA-256 and Bitcoin nonce search.
 *
 * This is the C counterpart of lib/sha256.w and lib/miner.w. Those files are
 * the specification; everything here reproduces their semantics exactly, and
 * the parity test in test_sha256_hw.c pins that claim to the genesis block.
 *
 * Standalone by construction: nothing here includes a Tungsten header or
 * calls into the Tungsten runtime, so `cc -O3 -c sha256_hw.c` works on its
 * own and the object drops into any link line.
 *
 * Two implementations of the same arithmetic live side by side:
 *
 *   w_sha256_sw_*   portable C. Always compiled. Serves as the fallback on
 *                   targets without the crypto extension and as the oracle
 *                   the accelerated path is differentially tested against.
 *   w_sha256_hw_*   ARMv8 SHA-256 extension (FEAT_SHA256). Compiled only
 *                   when the toolchain is actually targeting a CPU that has
 *                   it; otherwise the public entry points forward to the
 *                   software path.
 *
 * Byte order, stated once
 * -----------------------
 * A "word" in this file is a host uint32_t holding a SHA-256 schedule or
 * chaining word by VALUE, i.e. what FIPS 180-4 calls big-endian. The only
 * places byte order enters are (a) loading message bytes, where a big-endian
 * load is needed, and (b) the Bitcoin target comparison, where the protocol
 * reads the 32 digest bytes as a LITTLE-endian 256-bit integer — so the most
 * significant 32 bits of the compared value are bswap32(H7) and the least
 * significant are bswap32(H0). See lib/bitcoin.w:btc_meets_target.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

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

int w_sha256_hw_available(void);
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

int w_sha256_hw_available(void) {
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
