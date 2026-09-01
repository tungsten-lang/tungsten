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
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
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
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
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

WValue w_blas_sgemm_view(WValue a_wval, WValue b_wval, WValue c_wval,
                         WValue m_wval, WValue n_wval, WValue k_wval,
                         WValue ao_wval, WValue bo_wval,
                         WValue ta_wval, WValue tb_wval) {
    WArray *a = w_as_array(a_wval), *b = w_as_array(b_wval), *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval), N = (int)w_as_int(n_wval), K = (int)w_as_int(k_wval);
    int ta = (int)w_as_int(ta_wval), tb = (int)w_as_int(tb_wval);
    float *Ap = (float *)a->slots + a->start + w_as_int(ao_wval);
    float *Bp = (float *)b->slots + b->start + w_as_int(bo_wval);
    float *Cp = (float *)c->slots + c->start;
    cblas_sgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans, M, N, K, 1.0f,
                Ap, ta ? M : K, Bp, tb ? K : N, 0.0f, Cp, N);
    return c_wval;
}

WValue w_blas_dgemm_view(WValue a_wval, WValue b_wval, WValue c_wval,
                         WValue m_wval, WValue n_wval, WValue k_wval,
                         WValue ao_wval, WValue bo_wval,
                         WValue ta_wval, WValue tb_wval) {
    WArray *a = w_as_array(a_wval), *b = w_as_array(b_wval), *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval), N = (int)w_as_int(n_wval), K = (int)w_as_int(k_wval);
    int ta = (int)w_as_int(ta_wval), tb = (int)w_as_int(tb_wval);
    double *Ap = (double *)a->slots + a->start + w_as_int(ao_wval);
    double *Bp = (double *)b->slots + b->start + w_as_int(bo_wval);
    double *Cp = (double *)c->slots + c->start;
    cblas_dgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans, M, N, K, 1.0,
                Ap, ta ? M : K, Bp, tb ? K : N, 0.0, Cp, N);
    return c_wval;
}

/* Reductions / elementwise: portable scalar loops (vDSP is Apple-only). */
static float *ob_f32(WValue v, int64_t *len) {
    WArray *a = w_as_array(v);
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

/* dgeev via OpenBLAS's bundled LAPACK — same manual-prototype contract
 * as the Accelerate bridge (see blas_bridge.c). */
static double *oblas_f64_ptr(WValue v, int64_t *len_out) {
    WArray *a = w_as_array(v);
    *len_out = (int64_t)a->size;
    return (double *)a->slots + a->start;
}

extern void dgeev_(const char *jobvl, const char *jobvr, const int *n,
                   double *a, const int *lda, double *wr, double *wi,
                   double *vl, const int *ldvl, double *vr, const int *ldvr,
                   double *work, const int *lwork, int *info);

WValue w_blas_dgeev(WValue a_wval, WValue wr_wval, WValue wi_wval, WValue n_wval) {
    int64_t la, lr, li;
    double *A = oblas_f64_ptr(a_wval, &la);
    double *WR = oblas_f64_ptr(wr_wval, &lr);
    double *WI = oblas_f64_ptr(wi_wval, &li);
    int n = (int)w_as_int(n_wval);
    if (n <= 0 || la < (int64_t)n * n || lr < n || li < n) {
        w_raise(w_string("dgeev: bad dimensions"));
        return w_int(-1);
    }
    int lda = n, ldv = 1, info = 0;
    int lwork = -1;
    double wkopt = 0.0;
    dgeev_("N", "N", &n, A, &lda, WR, WI, NULL, &ldv, NULL, &ldv, &wkopt, &lwork, &info);
    if (info != 0) return w_int((int64_t)info);
    lwork = (int)wkopt;
    if (lwork < 4 * n) lwork = 4 * n;
    double *work = (double *)malloc((size_t)lwork * sizeof(double));
    if (!work) {
        w_raise(w_string("dgeev: out of memory"));
        return w_int(-1);
    }
    dgeev_("N", "N", &n, A, &lda, WR, WI, NULL, &ldv, NULL, &ldv, work, &lwork, &info);
    free(work);
    return w_int((int64_t)info);
}
