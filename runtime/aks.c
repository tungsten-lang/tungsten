/* AKS primality test — optional linked file
 * If not linked, __w_prime_aks_u64 is a weak symbol returning -1.
 * Includes Miller-Rabin fallback for fast deterministic testing of all u64. */

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

static uint64_t mod_mul_u64(uint64_t a, uint64_t b, uint64_t mod) {
  __uint128_t product = ((__uint128_t)a) * ((__uint128_t)b);
  return (uint64_t)(product % mod);
}

static uint64_t mod_pow_u64(uint64_t base, uint64_t exp, uint64_t mod) {
  uint64_t result = 1ULL;
  uint64_t value = base % mod;
  uint64_t power = exp;

  while (power > 0ULL) {
    if ((power & 1ULL) != 0ULL) {
      result = mod_mul_u64(result, value, mod);
    }
    value = mod_mul_u64(value, value, mod);
    power >>= 1U;
  }

  return result;
}

static uint64_t gcd_u64(uint64_t a, uint64_t b) {
  uint64_t x = a;
  uint64_t y = b;
  while (y != 0ULL) {
    uint64_t tmp = x % y;
    x = y;
    y = tmp;
  }
  return x;
}

static uint64_t bit_length_u64(uint64_t value) {
  uint64_t bits = 0ULL;
  uint64_t current = value;
  while (current > 0ULL) {
    bits += 1ULL;
    current >>= 1U;
  }
  return bits;
}

static int pow_cmp_u64(uint64_t base, uint64_t exp, uint64_t target) {
  uint64_t value = 1ULL;
  for (uint64_t i = 0ULL; i < exp; i++) {
    if (value > target / base) {
      return 1;
    }
    value *= base;
  }

  if (value == target) {
    return 0;
  }
  return value < target ? -1 : 1;
}

static int is_perfect_power_u64(uint64_t n) {
  if (n < 4ULL) {
    return 0;
  }

  uint64_t max_exp = bit_length_u64(n);
  for (uint64_t exp = 2ULL; exp <= max_exp; exp++) {
    uint64_t low = 2ULL;
    uint64_t high = 2ULL;

    while (pow_cmp_u64(high, exp, n) < 0) {
      if (high > n / 2ULL) {
        high = n;
        break;
      }
      high <<= 1U;
    }

    while (low <= high) {
      uint64_t mid = low + (high - low) / 2ULL;
      int cmp = pow_cmp_u64(mid, exp, n);
      if (cmp == 0) {
        return 1;
      }
      if (cmp < 0) {
        low = mid + 1ULL;
      } else {
        if (mid == 0ULL) {
          break;
        }
        high = mid - 1ULL;
      }
    }
  }

  return 0;
}

static int multiplicative_order_gt_bound(uint64_t n, uint64_t r, uint64_t bound) {
  if (gcd_u64(n, r) != 1ULL) {
    return 0;
  }

  uint64_t n_mod_r = n % r;
  uint64_t current = 1ULL;
  for (uint64_t k = 1ULL; k <= bound; k++) {
    current = mod_mul_u64(current, n_mod_r, r);
    if (current == 1ULL) {
      return 0;
    }
  }

  return 1;
}

static uint64_t find_aks_r(uint64_t n, uint64_t bound) {
  for (uint64_t r = 2ULL; r < 65536ULL; r++) {
    if (multiplicative_order_gt_bound(n, r, bound)) {
      return r;
    }
  }
  return 0ULL;
}

static uint64_t euler_phi_u64(uint64_t n) {
  uint64_t result = n;
  uint64_t remaining = n;
  uint64_t p = 2ULL;

  while (p * p <= remaining) {
    if ((remaining % p) == 0ULL) {
      while ((remaining % p) == 0ULL) {
        remaining /= p;
      }
      result -= result / p;
    }
    p += 1ULL;
  }

  if (remaining > 1ULL) {
    result -= result / remaining;
  }

  return result;
}

static int poly_mul_mod_xr_minus_1(const uint64_t *lhs, const uint64_t *rhs,
                                   uint64_t r, uint64_t mod, uint64_t *out) {
  for (uint64_t i = 0ULL; i < r; i++) {
    out[i] = 0ULL;
  }

  for (uint64_t i = 0ULL; i < r; i++) {
    if (lhs[i] == 0ULL) {
      continue;
    }
    for (uint64_t j = 0ULL; j < r; j++) {
      if (rhs[j] == 0ULL) {
        continue;
      }
      uint64_t idx = i + j;
      if (idx >= r) {
        idx -= r;
      }
      uint64_t term = mod_mul_u64(lhs[i], rhs[j], mod);
      out[idx] = (uint64_t)(((__uint128_t)out[idx] + term) % mod);
    }
  }

  return 1;
}

static int poly_pow_x_plus_a_mod(uint64_t n, uint64_t a, uint64_t r,
                                 uint64_t *out) {
  uint64_t *result = calloc((size_t)r, sizeof(uint64_t));
  uint64_t *base = calloc((size_t)r, sizeof(uint64_t));
  uint64_t *tmp = calloc((size_t)r, sizeof(uint64_t));
  if (result == NULL || base == NULL || tmp == NULL) {
    free(result);
    free(base);
    free(tmp);
    return 0;
  }

  result[0] = 1ULL % n;
  base[0] = a % n;
  base[1ULL % r] = (base[1ULL % r] + 1ULL) % n;

  uint64_t exp = n;
  while (exp > 0ULL) {
    if ((exp & 1ULL) != 0ULL) {
      poly_mul_mod_xr_minus_1(result, base, r, n, tmp);
      uint64_t *swap = result;
      result = tmp;
      tmp = swap;
    }
    exp >>= 1U;
    if (exp > 0ULL) {
      poly_mul_mod_xr_minus_1(base, base, r, n, tmp);
      uint64_t *swap = base;
      base = tmp;
      tmp = swap;
    }
  }

  for (uint64_t i = 0ULL; i < r; i++) {
    out[i] = result[i];
  }

  free(result);
  free(base);
  free(tmp);
  return 1;
}

static int aks_congruence_holds_u64(uint64_t n, uint64_t a, uint64_t r) {
  uint64_t *lhs = calloc((size_t)r, sizeof(uint64_t));
  uint64_t *rhs = calloc((size_t)r, sizeof(uint64_t));
  if (lhs == NULL || rhs == NULL) {
    free(lhs);
    free(rhs);
    return 0;
  }

  int ok = poly_pow_x_plus_a_mod(n, a, r, lhs);
  if (ok == 0) {
    free(lhs);
    free(rhs);
    return 0;
  }

  rhs[0] = a % n;
  uint64_t idx = n % r;
  rhs[idx] = (rhs[idx] + 1ULL) % n;

  for (uint64_t i = 0ULL; i < r; i++) {
    if (lhs[i] != rhs[i]) {
      free(lhs);
      free(rhs);
      return 0;
    }
  }

  free(lhs);
  free(rhs);
  return 1;
}

/* Miller-Rabin with deterministic bases covering all u64 */
static int is_prime_fallback_u64(uint64_t n) {
  static const uint64_t small_primes[] = {
      2ULL,  3ULL,  5ULL,  7ULL,  11ULL, 13ULL,
      17ULL, 19ULL, 23ULL, 29ULL, 31ULL, 37ULL};
  static const uint64_t mr_bases[] = {
      2ULL,       325ULL,     9375ULL,   28178ULL,
      450775ULL,  9780504ULL, 1795265022ULL};

  if (n < 2ULL) {
    return 0;
  }

  for (size_t i = 0; i < sizeof(small_primes) / sizeof(small_primes[0]); i++) {
    uint64_t p = small_primes[i];
    if (n == p) {
      return 1;
    }
    if ((n % p) == 0ULL) {
      return 0;
    }
  }

  uint64_t d = n - 1ULL;
  unsigned int s = 0U;
  while ((d & 1ULL) == 0ULL) {
    d >>= 1U;
    s += 1U;
  }

  for (size_t i = 0; i < sizeof(mr_bases) / sizeof(mr_bases[0]); i++) {
    uint64_t a = mr_bases[i] % n;
    if (a == 0ULL) {
      continue;
    }

    uint64_t x = mod_pow_u64(a, d, n);
    if (x == 1ULL || x == n - 1ULL) {
      continue;
    }

    int composite = 1;
    for (unsigned int r = 1U; r < s; r++) {
      x = mod_mul_u64(x, x, n);
      if (x == n - 1ULL) {
        composite = 0;
        break;
      }
    }

    if (composite) {
      return 0;
    }
  }

  return 1;
}

/* Full AKS primality test.
 * Returns 1 if prime, 0 if composite. Falls back to Miller-Rabin if
 * no suitable AKS witness r is found (always correct for u64). */
int __w_prime_aks_u64(uint64_t n) {
  if (n < 2ULL) {
    return 0;
  }

  if (n == 2ULL || n == 3ULL) {
    return 1;
  }

  if (is_perfect_power_u64(n)) {
    return 0;
  }

  uint64_t log2_n = bit_length_u64(n);
  uint64_t bound = log2_n * log2_n;
  uint64_t r = find_aks_r(n, bound);
  if (r == 0ULL) {
    return is_prime_fallback_u64(n);
  }

  for (uint64_t a = 2ULL; a <= r; a++) {
    uint64_t g = gcd_u64(a, n);
    if (g > 1ULL && g < n) {
      return 0;
    }
  }

  if (n <= r) {
    return 1;
  }

  uint64_t phi_r = euler_phi_u64(r);
  uint64_t limit = (uint64_t)(sqrt((double)phi_r) * (double)log2_n);
  if (limit < 1ULL) {
    limit = 1ULL;
  }

  for (uint64_t a = 1ULL; a <= limit; a++) {
    if (aks_congruence_holds_u64(n, a, r) == 0) {
      return 0;
    }
  }

  return 1;
}
