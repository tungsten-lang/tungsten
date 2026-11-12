/* Compile the bridge under its actual precise/fast build flags, then check
 * slogdet's raw IEEE result bits from a strict test driver. This remains
 * meaningful when the bridge uses fast math: the test never assumes finiteness.
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "runtime.h"
#include "wvalue.h"

extern WValue w_blas_dget_slogdet(WValue, WValue, WValue);
static int checks;

static int run_case(const char *name, const double *values, int n,
                    double sign, double magnitude, int singular) {
    WValue matrix = w_array_new_uninit_sized(64, (int64_t)n * n);
    WValue result = w_array_new_uninit_sized(64, 2);
    WArray *a = w_as_array(matrix);
    memcpy(a->slots, values, (size_t)n * n * sizeof(double));
    if (w_blas_dget_slogdet(matrix, w_int(n), result) != result) return 1;
    double *out = (double *)w_as_array(result)->slots;
    uint64_t bits;
    memcpy(&bits, &out[1], sizeof(bits));
    int valid = out[0] == sign;
    if (singular) valid &= bits == UINT64_C(0xfff0000000000000);
    else valid &= isfinite(out[1]) && fabs(out[1] - magnitude) < 1e-10;
    if (!valid) {
        fprintf(stderr, "FAIL %s: sign %.17g logabs %.17g bits %016llx\n",
                name, out[0], out[1], (unsigned long long)bits);
        return 1;
    }
    printf("PASS %s\n", name);
    ++checks;
    return 0;
}

int main(void) {
    const double zero[] = {0.0};
    const double singular[] = {1.0, 2.0, 2.0, 4.0};
    const double allzero[] = {0.0, 0.0, 0.0, 0.0};
    const double positive[] = {4.0, 1.0, 1.0, 3.0};
    const double negative[] = {1.0, 0.0, 0.0, -2.0};
    const double pivot[] = {0.0, 1.0, 2.0, 3.0};
    const double huge[] = {1e200, 0.0, 0.0, 1e200};
    const double tiny[] = {1e-200, 0.0, 0.0, 1e-200};
    if (run_case("zero 1x1 returns zero and exact negative infinity", zero, 1, 0.0, 0.0, 1) ||
        run_case("singular 2x2 returns zero and exact negative infinity", singular, 2, 0.0, 0.0, 1) ||
        run_case("zero 2x2 returns zero and exact negative infinity", allzero, 2, 0.0, 0.0, 1) ||
        run_case("positive determinant", positive, 2, 1.0, log(11.0), 0) ||
        run_case("negative determinant", negative, 2, -1.0, log(2.0), 0) ||
        run_case("pivot changes determinant sign", pivot, 2, -1.0, log(2.0), 0) ||
        run_case("overflow-sized determinant keeps finite log", huge, 2, 1.0, 400.0*log(10.0), 0) ||
        run_case("underflow-sized determinant keeps finite log", tiny, 2, 1.0, -400.0*log(10.0), 0)) return 1;
    printf("blas slogdet: %d passed\n", checks);
    return 0;
}
