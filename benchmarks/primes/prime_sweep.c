/* prime_sweep — empirical trial-division-vs-Miller-Rabin data for Int#prime?.
 *
 * Replicates the two heavy u64 tiers of the runtime intrinsic
 * (runtime/runtime.c `w_prime_test_u64`) in isolation and times each on the
 * largest prime <= 10^k. These are worst-case inputs for trial division: the
 * divisor scan runs all the way to sqrt(n).
 *
 *   cc -O3 -march=native -o prime_sweep prime_sweep.c && ./prime_sweep
 *
 * Result (Apple M-series): prime-divisor trial division is much faster than
 * the old 6k+-1 wheel below the 10^8 runtime cutoff, while the 3-base
 * Miller-Rabin tier wins once n is well into the 10^8-10^9 band. The runtime
 * keeps the 10^8 cutoff because sequential counting workloads below that
 * range benefit from early small factors and cheap trial exits.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define NOINLINE __attribute__((noinline))

static uint16_t trial_primes[4000];
static size_t trial_prime_count = 0;

static void init_trial_primes(void) {
  enum { LIMIT = 31623 };
  unsigned char composite[LIMIT + 1];
  memset(composite, 0, sizeof(composite));
  for (int p = 2; p * p <= LIMIT; p++) {
    if (!composite[p]) {
      for (int q = p * p; q <= LIMIT; q += p) composite[q] = 1;
    }
  }
  for (int p = 41; p <= LIMIT; p++) {
    if (!composite[p]) trial_primes[trial_prime_count++] = (uint16_t)p;
  }
}

static NOINLINE uint64_t mulmod(uint64_t a, uint64_t b, uint64_t m) {
  return (uint64_t)(((__uint128_t)a * b) % m);
}

static NOINLINE uint64_t powmod(uint64_t b, uint64_t e, uint64_t m) {
  uint64_t r = 1 % m;
  b %= m;
  while (e) {
    if (e & 1) r = mulmod(r, b, m);
    b = mulmod(b, b, m);
    e >>= 1;
  }
  return r;
}

static NOINLINE int mr_round(uint64_t n, uint64_t d, int s, uint64_t a) {
  uint64_t x = powmod(a, d, n);
  if (x == 1 || x == n - 1) return 1;
  for (int r = 1; r < s; r++) {
    x = mulmod(x, x, n);
    if (x == n - 1) return 1;
  }
  return 0;
}

static int mr_runtime_tier(uint64_t n) {
  if (n < 2) return 0;
  int s = __builtin_ctzll(n - 1);
  uint64_t d = (n - 1) >> s;
  if (n < 4759123141ULL) {
    static const uint64_t b3[] = {2, 7, 61};
    for (size_t i = 0; i < 3; i++) {
      if (!mr_round(n, d, s, b3[i])) return 0;
    }
    return 1;
  }
  if (n < 1122004669633ULL) {
    static const uint64_t b4[] = {2, 13, 23, 1662803};
    for (size_t i = 0; i < 4; i++) {
      if (!mr_round(n, d, s, b4[i])) return 0;
    }
    return 1;
  }
  static const uint64_t b7[] = {2, 325, 9375, 28178, 450775, 9780504, 1795265022};
  for (size_t i = 0; i < 7; i++) {
    uint64_t a = b7[i] % n;
    if (a != 0 && !mr_round(n, d, s, a)) return 0;
  }
  return 1;
}

static int trial_only(uint64_t n) {
  if (n < 2) return 0;
  for (size_t i = 0; i < trial_prime_count; i++) {
    uint64_t p = trial_primes[i];
    if (p * p > n) break;
    if (n % p == 0) return 0;
  }
  return 1;
}

static double bench(int (*f)(uint64_t), uint64_t n, long iters) {
  struct timespec t0, t1;
  volatile int sink = 0;
  volatile uint64_t vn = n;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (long k = 0; k < iters; k++) sink ^= f(vn);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  (void)sink;
  return (t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec);
}

int main(void) {
  init_trial_primes();
  uint64_t primes[] = {97ULL,997ULL,9973ULL,99991ULL,999983ULL,9999991ULL,
                       99999989ULL,999999937ULL};
  const char *lbl[] = {"1e2","1e3","1e4","1e5","1e6","1e7","1e8","1e9"};
  printf("%-6s %14s %14s %10s  winner\n", "mag", "trial ns/op", "MR ns/op", "ratio");
  for (int i = 0; i < 8; i++) {
    uint64_t n = primes[i];
    long it = 200000;
    double t = bench(trial_only, n, it) / it;
    double m = bench(mr_runtime_tier, n, it) / it;
    printf("%-6s %14.1f %14.1f %10.2f  %s\n", lbl[i], t, m, t / m, t < m ? "trial" : "MR");
  }
  return 0;
}
