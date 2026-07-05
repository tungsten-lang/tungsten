/* Polynomial ranged-sum benchmark — multi-term polynomials (C, fixed u64).
 *
 * IMPORTANT: C has no built-in big integers. These sums exceed 2^64
 * almost immediately (x^7 / x^20 overflow at once; even the degree-1/2
 * sums overflow once accumulated over reps), so this program computes
 * everything MOD 2^64 — the printed values are WRONG. It exists only as a
 * pure native-loop SPEED reference: even hand-written, -O3, it is
 * O(N·REPS·terms) and cannot match the closed form, while also being
 * unable to represent the answer.
 *
 * N/REPS from argv (defaults 1000000/100). */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

static inline uint64_t ipow(uint64_t base, int e) {
    uint64_t r = 1;
    while (e-- > 0) r *= base;   /* wraps mod 2^64 */
    return r;
}

int main(int argc, char **argv) {
    uint64_t n    = argc > 1 ? strtoull(argv[1], NULL, 10) : 1000000;
    int      reps = argc > 2 ? atoi(argv[2])               : 100;

    uint64_t t1 = 0, t2 = 0, t3 = 0, t7 = 0, t20 = 0;
    for (uint64_t r = 0; r < (uint64_t)reps; r++) {
        uint64_t lo = 1 + r, hi = n + r;
        for (uint64_t x = lo; x <= hi; x++) {
            t1  += 2 * x + 3;
            t2  += 5 * ipow(x, 2) - 3 * x + 1;
            t3  += 4 * ipow(x, 3) - 2 * ipow(x, 2) + 7 * x - 5;
            t7  += 92 * ipow(x, 7) + 13 * ipow(x, 3) - 5 * x + 8;
            t20 += ipow(x, 20) + 17 * ipow(x, 13) - 4 * ipow(x, 5) + 2 * x + 9;
        }
    }
    /* Values are mod 2^64 (overflowed) — speed reference only. */
    printf("%llu\n%llu\n%llu\n%llu\n%llu\n",
           (unsigned long long)t1, (unsigned long long)t2, (unsigned long long)t3,
           (unsigned long long)t7, (unsigned long long)t20);
    return 0;
}
