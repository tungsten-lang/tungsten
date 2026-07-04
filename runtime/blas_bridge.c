/* BLAS bridge — Apple Accelerate framework (real implementations).
 *
 * Split out of runtime.c so `-framework Accelerate` is linked only when a
 * program's IR references @w_blas_ (same conditional-bridge scheme as
 * metal.m / hid_bridge.m): runtime.c carries WEAK raising stubs; when the
 * compile driver passes this file, these strong definitions override them.
 *
 * Suppress the deprecation warning on the original cblas_sgemm — using
 * the ACCELERATE_NEW_LAPACK API would require the ILP64 LAPACK variant
 * to be linked, which not all toolchains provide. The original is fully
 * functional and on the same AMX-tuned code path. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <Accelerate/Accelerate.h>
#include "runtime.h"
#include "wvalue.h"

/* No ebits validation: the caller (core/blas.w::sgemm wrapper, or the
 * compiler when it inlines this call) is responsible for passing the
 * right types. If you hand it the wrong array type, you get garbage or
 * a crash — same contract as a direct cblas_sgemm call from C. */
WValue w_blas_sgemm_nn(WValue a_wval, WValue b_wval, WValue c_wval,
                       WValue m_wval, WValue n_wval, WValue k_wval) {
    WArray *a = (WArray *)w_as_ptr(a_wval);
    WArray *b = (WArray *)w_as_ptr(b_wval);
    WArray *c = (WArray *)w_as_ptr(c_wval);
    int64_t M = w_as_int(m_wval);
    int64_t N = w_as_int(n_wval);
    int64_t K = w_as_int(k_wval);
    float *Ap = (float *)a->slots + a->start;
    float *Bp = (float *)b->slots + b->start;
    float *Cp = (float *)c->slots + c->start;
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                (int)M, (int)N, (int)K, 1.0f, Ap, (int)K, Bp, (int)N, 0.0f, Cp, (int)N);
    return c_wval;
}

WValue w_blas_dgemm_nn(WValue a_wval, WValue b_wval, WValue c_wval,
                       WValue m_wval, WValue n_wval, WValue k_wval) {
    WArray *a = (WArray *)w_as_ptr(a_wval);
    WArray *b = (WArray *)w_as_ptr(b_wval);
    WArray *c = (WArray *)w_as_ptr(c_wval);
    int64_t M = w_as_int(m_wval);
    int64_t N = w_as_int(n_wval);
    int64_t K = w_as_int(k_wval);
    double *Ap = (double *)a->slots + a->start;
    double *Bp = (double *)b->slots + b->start;
    double *Cp = (double *)c->slots + c->start;
    cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                (int)M, (int)N, (int)K, 1.0, Ap, (int)K, Bp, (int)N, 0.0, Cp, (int)N);
    return c_wval;
}

/* ---- vDSP reductions over an f32 array (whole array, start-offset aware) ----
 * n<=0 ⇒ operate over the array's full length. All return a boxed Float. */
static inline float *blas_f32_ptr(WValue v, int64_t *len_out) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len_out = (int64_t)a->size;
    return (float *)a->slots + a->start;
}

WValue w_blas_sum_f32(WValue a_wval, WValue n_wval) {
    int64_t len; float *a = blas_f32_ptr(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    float r = 0.0f; vDSP_sve(a, 1, &r, (vDSP_Length)n);
    return w_float((double)r);
}

WValue w_blas_dot_f32(WValue a_wval, WValue b_wval, WValue n_wval) {
    int64_t la, lb; float *a = blas_f32_ptr(a_wval, &la); float *b = blas_f32_ptr(b_wval, &lb);
    int64_t n = w_as_int(n_wval); int64_t lo = la < lb ? la : lb;
    if (n <= 0 || n > lo) n = lo;
    float r = 0.0f; vDSP_dotpr(a, 1, b, 1, &r, (vDSP_Length)n);
    return w_float((double)r);
}

WValue w_blas_sumsq_f32(WValue a_wval, WValue n_wval) {
    int64_t len; float *a = blas_f32_ptr(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    float r = 0.0f; vDSP_svesq(a, 1, &r, (vDSP_Length)n);
    return w_float((double)r);
}

/* ---- vDSP elementwise transcendentals: out[i] = f(a[i]) over n elems ----
 * `out` may alias `a`. n<=0 ⇒ full length (min of a/out). Returns out_wval. */
static int64_t blas_pair_n(WValue a_wval, WValue out_wval, WValue n_wval,
                           float **a_out, float **out_out) {
    int64_t la, lo; *a_out = blas_f32_ptr(a_wval, &la); *out_out = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval); int64_t mn = la < lo ? la : lo;
    if (n <= 0 || n > mn) n = mn;
    return n;
}

WValue w_blas_vsin_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvsinf(o, a, &n); return out_wval;
}
WValue w_blas_vcos_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvcosf(o, a, &n); return out_wval;
}
WValue w_blas_vexp_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvexpf(o, a, &n); return out_wval;
}
WValue w_blas_vtanh_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvtanhf(o, a, &n); return out_wval;
}
#pragma clang diagnostic pop
