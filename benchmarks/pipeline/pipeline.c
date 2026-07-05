/* Fused map-filter-reduce pipeline benchmark (C, hand-written loop).
 *
 * The baseline: what an optimizing compiler does when you write the
 * loop by hand. Tungsten's fused pipeline aims to land here from
 * functional `/select/sq:sum` syntax.
 *
 * Each rep uses a SHIFTED range (1+r .. N+r) so the REPS loop is not
 * loop-invariant — otherwise -O3 hoists it and runs a single pass. N/REPS
 * come from argv (defaults 1000000/100). */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    uint64_t n    = argc > 1 ? strtoull(argv[1], NULL, 10) : 1000000;
    int      reps = argc > 2 ? atoi(argv[2])               : 100;

    uint64_t total = 0;
    for (uint64_t r = 0; r < (uint64_t)reps; r++) {
        uint64_t lo = 1 + r, hi = n + r;
        for (uint64_t x = lo; x <= hi; x++) {
            if (x % 2 == 0) {
                total += x * x;
            }
        }
    }
    printf("%llu\n", (unsigned long long)total);
    return 0;
}
