/* Correctness and throughput harness for runtime/sha256_hw.c.
 *
 *   cc -O3 -DW_SHA256_HW_TEST -o /tmp/t sha256_hw.c test_sha256_hw.c && /tmp/t
 *
 * Three checks, in increasing strength:
 *   1. FIPS 180-4 vectors — pins the compression function itself.
 *   2. The Bitcoin genesis block — pins the miner's midstate reuse, the
 *      little-endian nonce placement and the target comparison against a
 *      value the whole world agrees on.
 *   3. Hardware vs software digests over 1000 consecutive nonces — pins the
 *      accelerated path to the portable one on inputs no vector covers.
 */

#ifndef W_SHA256_HW_TEST

/* Not a test build. Keep the translation unit non-empty but inert so a
 * runtime source glob can pick this file up without dragging a second main()
 * into the bit. */
typedef int w_sha256_hw_test_not_built;

#else

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int w_sha256_hw_available(void);
void w_sha256_hw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_hw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash, uint32_t *out_best,
                         uint32_t *out_best_hash);

void w_sha256_sw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_sw_mine(const uint32_t *midstate, const uint8_t *tail,
                         const uint32_t *target_be, uint32_t start,
                         int64_t count, uint32_t *out_hash, uint32_t *out_best,
                         uint32_t *out_best_hash);

static const uint32_t IV[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                               0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

static int failures = 0;

static void check(const char *what, const char *got, const char *want) {
  int ok = strcmp(got, want) == 0;
  if (!ok) failures++;
  printf("  [%s] %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) printf("        got  %s\n        want %s\n", got, want);
}

/* ---- helpers ------------------------------------------------------------ */

static void hex_to_bytes(const char *hex, uint8_t *out, size_t n) {
  for (size_t i = 0; i < n; i++) {
    unsigned v;
    sscanf(hex + 2 * i, "%2x", &v);
    out[i] = (uint8_t)v;
  }
}

/* Big-endian hex of an 8-word digest: FIPS order. */
static void digest_hex(const uint32_t d[8], char out[65]) {
  for (int i = 0; i < 8; i++) sprintf(out + i * 8, "%08x", d[i]);
}

/* Byte-reversed hex: how Bitcoin displays hashes (lib/sha256.w:sha256_hex_le). */
static void digest_hex_le(const uint32_t d[8], char out[65]) {
  char *p = out;
  for (int i = 7; i >= 0; i--)
    for (int b = 0; b < 4; b++) p += sprintf(p, "%02x", (d[i] >> (b * 8)) & 0xFF);
}

/* SHA-256 with padding, built on the block API under test. */
static void sha256(const uint8_t *msg, size_t n, uint32_t out[8],
                   void (*compress)(uint32_t *, const uint8_t *, size_t)) {
  uint8_t block[128];
  size_t full = n / 64, rest = n - full * 64, padlen = rest >= 56 ? 128 : 64;
  uint64_t bits = (uint64_t)n * 8;
  memcpy(out, IV, 32);
  if (full) compress(out, msg, full);
  memset(block, 0, sizeof block);
  memcpy(block, msg + full * 64, rest);
  block[rest] = 0x80;
  for (int i = 0; i < 8; i++) block[padlen - 1 - i] = (uint8_t)(bits >> (i * 8));
  compress(out, block, padlen / 64);
}

/* nBits -> 256-bit target as 8 big-endian words (lib/bitcoin.w). */
static void target_from_bits(uint32_t bits, uint32_t target[8]) {
  uint8_t tb[32] = {0};
  int exponent = (int)((bits >> 24) & 0xFF);
  uint32_t mantissa = bits & 0x00FFFFFF;
  for (int i = 0; i < 3; i++) {
    int pos = exponent - 3 + i;
    if (pos >= 0 && pos < 32) tb[31 - pos] = (uint8_t)((mantissa >> (i * 8)) & 0xFF);
  }
  for (int i = 0; i < 8; i++)
    target[i] = ((uint32_t)tb[i * 4] << 24) | ((uint32_t)tb[i * 4 + 1] << 16) |
                ((uint32_t)tb[i * 4 + 2] << 8) | tb[i * 4 + 3];
}

static double now_sec(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

/* ---- 1. FIPS 180-4 vectors ---------------------------------------------- */

static void test_fips(void) {
  uint32_t d[8];
  char hex[65];

  printf("1. FIPS 180-4 vectors\n");

  sha256((const uint8_t *)"", 0, d, w_sha256_hw_compress);
  digest_hex(d, hex);
  check("SHA256(\"\")            hw", hex,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  sha256((const uint8_t *)"", 0, d, w_sha256_sw_compress);
  digest_hex(d, hex);
  check("SHA256(\"\")            sw", hex,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

  sha256((const uint8_t *)"abc", 3, d, w_sha256_hw_compress);
  digest_hex(d, hex);
  check("SHA256(\"abc\")         hw", hex,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  sha256((const uint8_t *)"abc", 3, d, w_sha256_sw_compress);
  digest_hex(d, hex);
  check("SHA256(\"abc\")         sw", hex,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

  /* Two-block vector: forces the multi-block loop and the spill-over padding
   * block, neither of which the single-block vectors above reach. */
  {
    const char *m = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    sha256((const uint8_t *)m, strlen(m), d, w_sha256_hw_compress);
    digest_hex(d, hex);
    check("SHA256(56-byte vector) hw", hex,
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  }
}

/* ---- 2. Bitcoin genesis block ------------------------------------------- */

static const char *GENESIS_HEX =
    "01000000"
    "0000000000000000000000000000000000000000000000000000000000000000"
    "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a"
    "29ab5f49"
    "ffff001d"
    "1dac2b7c";

static void test_genesis(void) {
  uint8_t header[80];
  uint32_t midstate[8], target[8], out[8];
  char hex[65], buf[32];
  int64_t nonce;

  printf("2. Bitcoin genesis block\n");

  hex_to_bytes(GENESIS_HEX, header, 80);
  target_from_bits(0x1d00ffff, target);

  /* Midstate: the chaining state after header bytes 0..63. Block 1 is
   * constant for the whole nonce range, which is the entire point. */
  memcpy(midstate, IV, 32);
  w_sha256_hw_compress(midstate, header, 1);

  nonce = w_sha256_hw_mine(midstate, header + 64, target, 2083236880, 40, out, NULL, NULL);
  sprintf(buf, "%lld", (long long)nonce);
  check("winning nonce         hw", buf, "2083236893");
  digest_hex_le(out, hex);
  check("display hash          hw", hex,
        "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f");

  memset(out, 0, sizeof out);
  nonce = w_sha256_sw_mine(midstate, header + 64, target, 2083236880, 40, out, NULL, NULL);
  sprintf(buf, "%lld", (long long)nonce);
  check("winning nonce         sw", buf, "2083236893");
  digest_hex_le(out, hex);
  check("display hash          sw", hex,
        "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f");

  /* A range that excludes the winner must report failure, not the nearest
   * hit — the early-reject path has to be exhaustive, not approximate. */
  nonce = w_sha256_hw_mine(midstate, header + 64, target, 2083236880, 13, out, NULL, NULL);
  sprintf(buf, "%lld", (long long)nonce);
  check("miss reports -1       hw", buf, "-1");
}

/* ---- 3. hardware vs software parity ------------------------------------- */

static void test_parity(void) {
  uint8_t header[80];
  uint32_t midstate[8], loose[8], a[8], b[8];
  char ha[65], hb[65];
  int mismatches = 0;
  const uint32_t N = 1000;

  printf("3. hw/sw digest parity over %u nonces\n", N);

  hex_to_bytes(GENESIS_HEX, header, 80);
  memcpy(midstate, IV, 32);
  w_sha256_hw_compress(midstate, header, 1);

  /* An all-ones target matches everything, so mine(count=1) degenerates into
   * "hash this one nonce and hand me the digest" — the only way to compare
   * per-nonce digests through the public API. */
  for (int i = 0; i < 8; i++) loose[i] = 0xFFFFFFFFu;

  for (uint32_t n = 0; n < N; n++) {
    /* Start well away from zero so the nonce words are dense, and step by a
     * large odd stride so all four nonce bytes vary. */
    uint32_t nonce = 0x9E3779B9u * n + 2083236880u;
    int64_t ra = w_sha256_hw_mine(midstate, header + 64, loose, nonce, 1, a, NULL, NULL);
    int64_t rb = w_sha256_sw_mine(midstate, header + 64, loose, nonce, 1, b, NULL, NULL);
    if (ra != (int64_t)nonce || rb != (int64_t)nonce || memcmp(a, b, sizeof a) != 0) {
      if (mismatches++ == 0) {
        digest_hex(a, ha);
        digest_hex(b, hb);
        printf("        first mismatch at nonce %u\n        hw %s\n        sw %s\n",
               nonce, ha, hb);
      }
    }
  }
  sprintf(ha, "%d", mismatches);
  check("mismatching digests", ha, "0");
}

/* ---- 4. interleaving edge cases -----------------------------------------
 *
 * The hardware search advances several nonces in lockstep, which introduces
 * three failure modes a serial loop cannot have: reporting a hit from a lane
 * that is not the lowest, mishandling a range whose length is not a multiple
 * of the interleave width, and letting lanes past the winner contaminate the
 * best-so-far outputs. Each gets a check, and none of them may assume what
 * the width actually is. */

static uint32_t be32(uint32_t x) {
  return (x >> 24) | ((x >> 8) & 0xFF00u) | ((x << 8) & 0xFF0000u) | (x << 24);
}

static void test_interleave(void) {
  uint8_t header[80];
  uint32_t midstate[8], loose[8], target[8], a[8], b[8];
  char buf[32];
  int bad;

  printf("4. interleaving edge cases\n");

  hex_to_bytes(GENESIS_HEX, header, 80);
  memcpy(midstate, IV, 32);
  w_sha256_hw_compress(midstate, header, 1);
  for (int i = 0; i < 8; i++) loose[i] = 0xFFFFFFFFu;
  target_from_bits(0x1d00ffff, target);

  /* An all-ones target makes EVERY candidate a hit, so every lane of every
   * group fires at once. The answer must still be the first nonce of the
   * range and its digest, for every range length across several groups. */
  bad = 0;
  for (int n = 1; n <= 40; n++) {
    int64_t r = w_sha256_hw_mine(midstate, header + 64, loose, 500000u, n, a,
                                 NULL, NULL);
    w_sha256_sw_mine(midstate, header + 64, loose, 500000u, 1, b, NULL, NULL);
    if (r != 500000 || memcmp(a, b, sizeof a) != 0) bad++;
  }
  sprintf(buf, "%d", bad);
  check("lowest nonce wins, lengths 1..40", buf, "0");

  /* Slide the genesis winner across every lane index and every distance from
   * the end of the range, so it lands in a full group and in the tail. The
   * range one short of it must still report -1. */
  bad = 0;
  for (int off = 0; off <= 20; off++) {
    uint32_t s = 2083236893u - (uint32_t)off;
    if (w_sha256_hw_mine(midstate, header + 64, target, s, off + 1, a, NULL,
                         NULL) != 2083236893)
      bad++;
    if (off > 0 && w_sha256_hw_mine(midstate, header + 64, target, s, off, NULL,
                                    NULL, NULL) != -1)
      bad++;
  }
  sprintf(buf, "%d", bad);
  check("winner at every lane offset", buf, "0");

  /* out_best is the running minimum of bswap32(H7) over everything scanned,
   * and out_best_hash is that candidate's digest. Computed independently here
   * one nonce at a time through the software path.
   *
   * Only the hardware path implements these two out params: w_sha256_sw_mine
   * initialises `best` and never updates it, and ignores out_best_hash
   * outright — which is exactly the unused-parameter warning that file has
   * always emitted. On a target without the crypto extension the public entry
   * forwards to it, so say so rather than fail. */
  if (!w_sha256_hw_available()) {
    printf("  [SKIP] out_best / out_best_hash — no hardware path here, and the "
           "software fallback does not implement them\n");
  } else {
    const uint32_t s = 12345678u;
    const int n = 37; /* deliberately not a multiple of any plausible width */
    uint32_t want = 0xFFFFFFFFu, want_hash[8] = {0};
    uint32_t got = 0, got_hash[8] = {0};
    char hx[65], hy[65];

    for (int i = 0; i < n; i++) {
      uint32_t v;
      w_sha256_sw_mine(midstate, header + 64, loose, s + (uint32_t)i, 1, b,
                       NULL, NULL);
      v = be32(b[7]);
      if (v < want) {
        want = v;
        memcpy(want_hash, b, sizeof want_hash);
      }
    }
    if (w_sha256_hw_mine(midstate, header + 64, target, s, n, NULL, &got,
                         got_hash) != -1)
      check("out_best scan returns -1", "hit", "-1");
    sprintf(buf, "%08x", got);
    sprintf(hx, "%08x", want);
    check("out_best is the running minimum", buf, hx);
    digest_hex(got_hash, hx);
    digest_hex(want_hash, hy);
    check("out_best_hash matches that candidate", hx, hy);
  }
}

/* ---- 5. throughput ------------------------------------------------------ */

static void bench(const char *label,
                  int64_t (*mine)(const uint32_t *, const uint8_t *,
                                  const uint32_t *, uint32_t, int64_t, uint32_t *,
                                  uint32_t *, uint32_t *),
                  uint32_t count) {
  uint8_t header[80];
  uint32_t midstate[8], target[8];
  double t0, dt;
  int64_t r;

  hex_to_bytes(GENESIS_HEX, header, 80);
  memcpy(midstate, IV, 32);
  w_sha256_hw_compress(midstate, header, 1);
  /* Difficulty-1. Its top word is zero, so nothing in the scanned range can
   * win and every candidate takes the reject path — which is what a real
   * search spends all of its time on. */
  target_from_bits(0x1d00ffff, target);

  t0 = now_sec();
  r = mine(midstate, header + 64, target, 1, count, NULL, NULL, NULL);
  dt = now_sec() - t0;
  printf("  %-24s %10.0f H/s   (%u nonces in %.3fs, result %lld)\n", label,
         (double)count / dt, count, dt, (long long)r);
}

int main(void) {
  printf("w_sha256_hw_available() = %d\n\n", w_sha256_hw_available());

  test_fips();
  test_genesis();
  test_parity();
  test_interleave();

  printf("5. throughput, single-threaded, non-matching target\n");
  bench("hardware (w_sha256_hw)", w_sha256_hw_mine, 20000000);
  bench("software (w_sha256_sw)", w_sha256_sw_mine, 2000000);

  printf("\n%s\n", failures ? "FAILURES" : "all checks passed");
  return failures ? 1 : 0;
}

#endif /* W_SHA256_HW_TEST */
