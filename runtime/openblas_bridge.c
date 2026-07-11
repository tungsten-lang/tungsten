/* OpenBLAS / system CBLAS bridge for non-Apple platforms.
 *
 * Mirrors the Accelerate entry points in blas_bridge.c so the same
 * `@w_blas_*` symbols resolve on Linux when linked with -lopenblas.
 *
 * Build: linked by the compiler driver when IR references @w_blas_ and
 * the host is not macOS (see compiler/tungsten.w).
 */
#include "runtime.h"
#include "wvalue.h"
#include <cblas.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

WValue w_blas_sgemm_nn(WValue a_wval, WValue b_wval, WValue c_wval,
                       WValue m_wval, WValue n_wval, WValue k_wval) {
    WArray *a = (WArray *)w_as_ptr(a_wval);
    WArray *b = (WArray *)w_as_ptr(b_wval);
    WArray *c = (WArray *)w_as_ptr(c_wval);
    int M = (int)w_as_int(m_wval);
    int N = (int)w_as_int(n_wval);
    int K = (int)w_as_int(k_wval);
    float *Ap = (float *)a->slots + a->start;
    float *Bp = (float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                M, N, K, 1.0f, Ap, K, Bp, N, 0.0f, Cp, N);
    return c_wval;
}

WValue w_blas_dgemm_nn(WValue a_wval, WValue b_wval, WValue c_wval,
                       WValue m_wval, WValue n_wval, WValue k_wval) {
    WArray *a = (WArray *)w_as_ptr(a_wval);
    WArray *b = (WArray *)w_as_ptr(b_wval);
    WArray *c = (WArray *)w_as_ptr(c_wval);
    int M = (int)w_as_int(m_wval);
    int N = (int)w_as_int(n_wval);
    int K = (int)w_as_int(k_wval);
    double *Ap = (double *)a->slots + a->start;
    double *Bp = (double *)b->slots + b->start;
    double *Cp = (double *)c->slots + c->start;
    cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                M, N, K, 1.0, Ap, K, Bp, N, 0.0, Cp, N);
    return c_wval;
}

/* Reductions / elementwise: portable scalar loops (vDSP is Apple-only). */
static float *ob_f32(WValue v, int64_t *len) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len = (int64_t)a->size;
    return (float *)a->slots + a->start;
}

WValue w_blas_sum_f32(WValue a_wval, WValue n_wval) {
    int64_t len; float *a = ob_f32(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    double s = 0.0; for (int64_t i = 0; i < n; i++) s += a[i];
    return w_float(s);
}

WValue w_blas_dot_f32(WValue a_wval, WValue b_wval, WValue n_wval) {
    int64_t la, lb; float *a = ob_f32(a_wval, &la); float *b = ob_f32(b_wval, &lb);
    int64_t n = w_as_int(n_wval); int64_t lo = la < lb ? la : lb;
    if (n <= 0 || n > lo) n = lo;
    double s = 0.0; for (int64_t i = 0; i < n; i++) s += (double)a[i] * b[i];
    return w_float(s);
}

WValue w_blas_sumsq_f32(WValue a_wval, WValue n_wval) {
    int64_t len; float *a = ob_f32(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    double s = 0.0; for (int64_t i = 0; i < n; i++) s += (double)a[i] * a[i];
    return w_float(s);
}

WValue w_blas_vsin_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lo; float *a = ob_f32(a_wval, &la); float *o = ob_f32(out_wval, &lo);
    int64_t n = w_as_int(n_wval); int64_t m = la < lo ? la : lo;
    if (n <= 0 || n > m) n = m;
    for (int64_t i = 0; i < n; i++) o[i] = sinf(a[i]);
    return out_wval;
}
WValue w_blas_vcos_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lo; float *a = ob_f32(a_wval, &la); float *o = ob_f32(out_wval, &lo);
    int64_t n = w_as_int(n_wval); int64_t m = la < lo ? la : lo;
    if (n <= 0 || n > m) n = m;
    for (int64_t i = 0; i < n; i++) o[i] = cosf(a[i]);
    return out_wval;
}
WValue w_blas_vexp_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lo; float *a = ob_f32(a_wval, &la); float *o = ob_f32(out_wval, &lo);
    int64_t n = w_as_int(n_wval); int64_t m = la < lo ? la : lo;
    if (n <= 0 || n > m) n = m;
    for (int64_t i = 0; i < n; i++) o[i] = expf(a[i]);
    return out_wval;
}
WValue w_blas_vtanh_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lo; float *a = ob_f32(a_wval, &la); float *o = ob_f32(out_wval, &lo);
    int64_t n = w_as_int(n_wval); int64_t m = la < lo ? la : lo;
    if (n <= 0 || n > m) n = m;
    for (int64_t i = 0; i < n; i++) o[i] = tanhf(a[i]);
    return out_wval;
}
