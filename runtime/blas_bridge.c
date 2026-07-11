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
WValue w_blas_vlog_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvlogf(o, a, &n); return out_wval;
}
WValue w_blas_vsqrt_f32(WValue a_wval, WValue out_wval, WValue n_wval) {
    float *a, *o; int n = (int)blas_pair_n(a_wval, out_wval, n_wval, &a, &o);
    vvsqrtf(o, a, &n); return out_wval;
}

/* ---- BLAS 1 / 2 + vDSP vector arithmetic (f32 typed arrays) ---- */

WValue w_blas_saxpy(WValue a_wval, WValue x_wval, WValue y_wval, WValue n_wval) {
    int64_t lx, ly;
    float *x = blas_f32_ptr(x_wval, &lx);
    float *y = blas_f32_ptr(y_wval, &ly);
    int64_t n = w_as_int(n_wval);
    int64_t lo = lx < ly ? lx : ly;
    if (n <= 0 || n > lo) n = lo;
    float alpha = (float)w_as_double(a_wval);
    cblas_saxpy((int)n, alpha, x, 1, y, 1);
    return y_wval;
}

WValue w_blas_sgemv_n(WValue a_wval, WValue x_wval, WValue y_wval,
                      WValue m_wval, WValue n_wval) {
    int64_t la, lx, ly;
    float *A = blas_f32_ptr(a_wval, &la);
    float *x = blas_f32_ptr(x_wval, &lx);
    float *y = blas_f32_ptr(y_wval, &ly);
    int M = (int)w_as_int(m_wval);
    int N = (int)w_as_int(n_wval);
    /* y = A x  (row-major A is M×N) */
    cblas_sgemv(CblasRowMajor, CblasNoTrans, M, N, 1.0f, A, N, x, 1, 0.0f, y, 1);
    return y_wval;
}

WValue w_blas_vadd_f32(WValue a_wval, WValue b_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lb, lo;
    float *a = blas_f32_ptr(a_wval, &la);
    float *b = blas_f32_ptr(b_wval, &lb);
    float *o = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    int64_t mn = la < lb ? la : lb;
    if (lo < mn) mn = lo;
    if (n <= 0 || n > mn) n = mn;
    vDSP_vadd(a, 1, b, 1, o, 1, (vDSP_Length)n);
    return out_wval;
}

WValue w_blas_vmul_f32(WValue a_wval, WValue b_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lb, lo;
    float *a = blas_f32_ptr(a_wval, &la);
    float *b = blas_f32_ptr(b_wval, &lb);
    float *o = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    int64_t mn = la < lb ? la : lb;
    if (lo < mn) mn = lo;
    if (n <= 0 || n > mn) n = mn;
    vDSP_vmul(a, 1, b, 1, o, 1, (vDSP_Length)n);
    return out_wval;
}

WValue w_blas_vsmul_f32(WValue a_wval, WValue s_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lo;
    float *a = blas_f32_ptr(a_wval, &la);
    float *o = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    int64_t mn = la < lo ? la : lo;
    if (n <= 0 || n > mn) n = mn;
    float s = (float)w_as_double(s_wval);
    vDSP_vsmul(a, 1, &s, o, 1, (vDSP_Length)n);
    return out_wval;
}

WValue w_blas_vfill_f32(WValue out_wval, WValue s_wval, WValue n_wval) {
    int64_t lo;
    float *o = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    if (n <= 0 || n > lo) n = lo;
    float s = (float)w_as_double(s_wval);
    vDSP_vfill(&s, o, 1, (vDSP_Length)n);
    return out_wval;
}

/* ---- Dense linear algebra (pure C) ---------------------------------
 * Deliberately NOT calling Accelerate clapack_* / dgesv_ / dpotrf_.
 * Those symbols are deprecated (macOS 13.3+) and absent or gated behind
 * ACCELERATE_NEW_LAPACK on newer Xcodes — pulling them into this file
 * broke bootstrap on hosts that only ship the new LAPACK headers.
 * GEMM still uses cblas_*; solve/Cholesky are small portable C here.
 * core/sci/linalg.w has a pure-Tungsten path as well. */
#include <stdlib.h>
#include <math.h>

static double *blas_f64_ptr(WValue v, int64_t *len_out) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len_out = (int64_t)a->size;
    return (double *)a->slots + a->start;
}

/* dgesv: GE with partial pivoting. A is n×n row-major f64, b length n.
 * Overwrites A and b. Returns info (0 = ok, >0 = singular pivot). */
WValue w_blas_dgesv(WValue a_wval, WValue b_wval, WValue n_wval) {
    int64_t la, lb;
    double *A = blas_f64_ptr(a_wval, &la);
    double *B = blas_f64_ptr(b_wval, &lb);
    int n = (int)w_as_int(n_wval);
    if (n <= 0 || la < (int64_t)n * n || lb < n) {
        w_raise(w_string("dgesv: bad dimensions"));
        return w_int(-1);
    }
    for (int k = 0; k < n; k++) {
        int piv = k;
        double maxv = fabs(A[k * n + k]);
        for (int i = k + 1; i < n; i++) {
            double v = fabs(A[i * n + k]);
            if (v > maxv) { maxv = v; piv = i; }
        }
        if (maxv == 0.0) return w_int((int64_t)(k + 1));
        if (piv != k) {
            for (int j = 0; j < n; j++) {
                double t = A[k * n + j];
                A[k * n + j] = A[piv * n + j];
                A[piv * n + j] = t;
            }
            double tb = B[k]; B[k] = B[piv]; B[piv] = tb;
        }
        for (int i = k + 1; i < n; i++) {
            double f = A[i * n + k] / A[k * n + k];
            A[i * n + k] = f;
            for (int j = k + 1; j < n; j++)
                A[i * n + j] -= f * A[k * n + j];
            B[i] -= f * B[k];
        }
    }
    for (int i = n - 1; i >= 0; i--) {
        double s = B[i];
        for (int j = i + 1; j < n; j++) s -= A[i * n + j] * B[j];
        B[i] = s / A[i * n + i];
    }
    return w_int(0);
}

/* dpotrf: Cholesky upper of SPD A (n×n row-major). Overwrites A with U.
 * Returns info (0 = ok, >0 = not SPD at diagonal). */
WValue w_blas_dpotrf(WValue a_wval, WValue n_wval) {
    int64_t la;
    double *A = blas_f64_ptr(a_wval, &la);
    int n = (int)w_as_int(n_wval);
    if (n <= 0 || la < (int64_t)n * n) {
        w_raise(w_string("dpotrf: bad dimensions"));
        return w_int(-1);
    }
    for (int i = 0; i < n; i++) {
        for (int j = i; j < n; j++) {
            double s = A[i * n + j];
            for (int k = 0; k < i; k++)
                s -= A[k * n + i] * A[k * n + j];
            if (i == j) {
                if (s <= 0.0) return w_int((int64_t)(i + 1));
                A[i * n + i] = sqrt(s);
            } else {
                A[i * n + j] = s / A[i * n + i];
                A[j * n + i] = 0.0; /* strict upper stored on upper triangle */
            }
        }
    }
    return w_int(0);
}
