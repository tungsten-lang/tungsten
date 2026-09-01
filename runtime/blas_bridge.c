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
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
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
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
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

/* Row-major GEMM over packed matrices or their zero-copy transpose views.
 * Offsets are in elements, relative to the WArray's own start. A logical
 * transpose view has strides [1, rows], so the corresponding base matrix is
 * passed to CBLAS with Trans and the leading dimension derived from the
 * logical shape. */
WValue w_blas_sgemm_view(WValue a_wval, WValue b_wval, WValue c_wval,
                         WValue m_wval, WValue n_wval, WValue k_wval,
                         WValue ao_wval, WValue bo_wval,
                         WValue ta_wval, WValue tb_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval);
    int N = (int)w_as_int(n_wval);
    int K = (int)w_as_int(k_wval);
    int ta = (int)w_as_int(ta_wval);
    int tb = (int)w_as_int(tb_wval);
    float *Ap = (float *)a->slots + a->start + w_as_int(ao_wval);
    float *Bp = (float *)b->slots + b->start + w_as_int(bo_wval);
    float *Cp = (float *)c->slots + c->start;
    cblas_sgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans,
                M, N, K, 1.0f, Ap, ta ? M : K, Bp, tb ? K : N,
                0.0f, Cp, N);
    return c_wval;
}

WValue w_blas_dgemm_view(WValue a_wval, WValue b_wval, WValue c_wval,
                         WValue m_wval, WValue n_wval, WValue k_wval,
                         WValue ao_wval, WValue bo_wval,
                         WValue ta_wval, WValue tb_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    WArray *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval);
    int N = (int)w_as_int(n_wval);
    int K = (int)w_as_int(k_wval);
    int ta = (int)w_as_int(ta_wval);
    int tb = (int)w_as_int(tb_wval);
    double *Ap = (double *)a->slots + a->start + w_as_int(ao_wval);
    double *Bp = (double *)b->slots + b->start + w_as_int(bo_wval);
    double *Cp = (double *)c->slots + c->start;
    cblas_dgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans,
                M, N, K, 1.0, Ap, ta ? M : K, Bp, tb ? K : N,
                0.0, Cp, N);
    return c_wval;
}

/* ---- LAPACK (classic interface; same AMX-tuned Accelerate path) ----
 *
 * All three take ROW-MAJOR f64 buffers. LAPACK is column-major, so the
 * buffer is handed over as-is and interpreted as the TRANSPOSE:
 *   - solve: dgetrf factors A^T, then dgetrs with trans='T' solves
 *     (A^T)^T x = A x = b. No transpose copy anywhere.
 *   - det: det(A^T) = det(A); product of U's diagonal, sign from pivots.
 *   - cholesky: A symmetric, so the buffer IS A either way; uplo='U'
 *     computes U_cm with U^T U = A, and reading the buffer row-major
 *     yields exactly the lower factor L = U^T with L L^T = A.
 * The matrix argument is CLOBBERED (LU / Cholesky factors). */

WValue w_blas_dgesv_rowmajor(WValue a_wval, WValue b_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *b = w_as_array(b_wval);
    __CLPK_integer n = (__CLPK_integer)w_as_int(n_wval);
    double *Ap = (double *)a->slots + a->start;
    double *Bp = (double *)b->slots + b->start;
    __CLPK_integer info = 0, nrhs = 1;
    __CLPK_integer *ipiv = (__CLPK_integer *)malloc(sizeof(__CLPK_integer) * (size_t)(n > 0 ? n : 1));
    dgetrf_(&n, &n, Ap, &n, ipiv, &info);
    if (info == 0)
        dgetrs_("T", &n, &nrhs, Ap, &n, ipiv, Bp, &n, &info);
    free(ipiv);
    return w_int((int64_t)info);
}

WValue w_blas_dget_det(WValue a_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval);
    __CLPK_integer n = (__CLPK_integer)w_as_int(n_wval);
    double *Ap = (double *)a->slots + a->start;
    __CLPK_integer info = 0;
    __CLPK_integer *ipiv = (__CLPK_integer *)malloc(sizeof(__CLPK_integer) * (size_t)(n > 0 ? n : 1));
    dgetrf_(&n, &n, Ap, &n, ipiv, &info);
    double det = 1.0;
    if (info > 0) {
        det = 0.0; /* singular: a zero pivot appeared */
    } else {
        for (__CLPK_integer i = 0; i < n; i++) {
            det *= Ap[(size_t)i * (size_t)n + (size_t)i];
            if (ipiv[i] != i + 1)
                det = -det;
        }
    }
    free(ipiv);
    return w_float(det);
}

/* Sign and log-magnitude of det via LU — the result-only form: never
 * overflows/underflows where det itself would. out[0] = sign (-1/0/+1),
 * out[1] = log|det| (-inf when singular). Matrix buffer is clobbered. */
WValue w_blas_dget_slogdet(WValue a_wval, WValue n_wval, WValue out_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *o = w_as_array(out_wval);
    __CLPK_integer n = (__CLPK_integer)w_as_int(n_wval);
    double *Ap = (double *)a->slots + a->start;
    double *Op = (double *)o->slots + o->start;
    __CLPK_integer info = 0;
    __CLPK_integer *ipiv = (__CLPK_integer *)malloc(sizeof(__CLPK_integer) * (size_t)(n > 0 ? n : 1));
    dgetrf_(&n, &n, Ap, &n, ipiv, &info);
    double sign = 1.0, logabs = 0.0;
    if (info > 0) {
        sign = 0.0;
        logabs = -INFINITY;
    } else {
        for (__CLPK_integer i = 0; i < n; i++) {
            double d = Ap[(size_t)i * (size_t)n + (size_t)i];
            if (d < 0.0) { sign = -sign; d = -d; }
            logabs += log(d);
            if (ipiv[i] != i + 1) sign = -sign;
        }
    }
    free(ipiv);
    Op[0] = sign;
    Op[1] = logabs;
    return out_wval;
}

WValue w_blas_dpotrf_lower(WValue a_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval);
    __CLPK_integer n = (__CLPK_integer)w_as_int(n_wval);
    double *Ap = (double *)a->slots + a->start;
    __CLPK_integer info = 0;
    dpotrf_("U", &n, Ap, &n, &info);
    if (info == 0) {
        /* zero the strictly-upper (row-major) part the factor leaves untouched */
        for (__CLPK_integer i = 0; i < n; i++)
            for (__CLPK_integer j = i + 1; j < n; j++)
                Ap[(size_t)i * (size_t)n + (size_t)j] = 0.0;
    }
    return w_int((int64_t)info);
}

/* ---- vDSP reductions over an f32 array (whole array, start-offset aware) ----
 * n<=0 ⇒ operate over the array's full length. All return a boxed Float. */
static inline float *blas_f32_ptr(WValue v, int64_t *len_out) {
    WArray *a = w_as_array(v);
    *len_out = (int64_t)a->size;
    return (float *)a->slots + a->start;
}

WValue w_blas_sum_f32(WValue a_wval, WValue n_wval) {
    int64_t len; float *a = blas_f32_ptr(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    float r = 0.0f; vDSP_sve(a, 1, &r, (vDSP_Length)n);
    return w_float((double)r);
}

/* Packed Tensor reductions with an element offset. kind: 0=sum, 1=max.
 * f32 sum deliberately accumulates in double to preserve Tensor's previous
 * numeric behavior; f64 uses vDSP's vector reduction. */
WValue w_blas_reduce_view(WValue dtype_wval, WValue a_wval,
                          WValue offset_wval, WValue n_wval,
                          WValue kind_wval) {
    WArray *a = w_as_array(a_wval);
    int64_t dtype = w_as_int(dtype_wval);
    int64_t offset = w_as_int(offset_wval);
    int64_t n = w_as_int(n_wval);
    int64_t kind = w_as_int(kind_wval);
    if (offset < 0 || n < 0 || offset + n > a->size || kind < 0 || kind > 1) {
        w_raise(w_string("blas_reduce_view: invalid offset, length, or kind"));
        return W_NIL;
    }
    if (dtype == 64) {
        double *p = (double *)a->slots + a->start + offset;
        double result = 0.0;
        if (kind == 0)
            vDSP_sveD(p, 1, &result, (vDSP_Length)n);
        else if (n > 0) {
            result = p[0];
            for (int64_t i = 1; i < n; i++) if (p[i] > result) result = p[i];
        }
        return w_float(result);
    }
    if (dtype == 3) {
        float *p = (float *)a->slots + a->start + offset;
        double result = 0.0;
        if (kind == 0) {
            for (int64_t i = 0; i < n; i++) result += (double)p[i];
        } else if (n > 0) {
            float best = p[0];
            for (int64_t i = 1; i < n; i++) if (p[i] > best) best = p[i];
            result = (double)best;
        }
        return w_float(result);
    }
    w_raise(w_string("blas_reduce_view: dtype must be f32 or f64"));
    return W_NIL;
}

/* Reduce the packed last axis into a packed output array in one bridge call.
 * This removes one coordinate Array allocation per input element. */
WValue w_blas_reduce_last(WValue dtype_wval, WValue a_wval, WValue out_wval,
                          WValue offset_wval, WValue rows_wval,
                          WValue cols_wval, WValue kind_wval) {
    WArray *a = w_as_array(a_wval);
    WArray *out = w_as_array(out_wval);
    int64_t dtype = w_as_int(dtype_wval);
    int64_t offset = w_as_int(offset_wval);
    int64_t rows = w_as_int(rows_wval);
    int64_t cols = w_as_int(cols_wval);
    int64_t kind = w_as_int(kind_wval);
    if (offset < 0 || rows < 0 || cols < 0 || offset + rows * cols > a->size ||
        rows > out->size || kind < 0 || kind > 1) {
        w_raise(w_string("blas_reduce_last: invalid shape, offset, or kind"));
        return W_NIL;
    }
    if (dtype == 64) {
        double *p = (double *)a->slots + a->start + offset;
        double *o = (double *)out->slots + out->start;
        for (int64_t row = 0; row < rows; row++) {
            double result = 0.0;
            if (kind == 0)
                vDSP_sveD(p + row * cols, 1, &result, (vDSP_Length)cols);
            else if (cols > 0) {
                double *rp = p + row * cols;
                result = rp[0];
                for (int64_t col = 1; col < cols; col++) if (rp[col] > result) result = rp[col];
            }
            o[row] = result;
        }
        return out_wval;
    }
    if (dtype == 3) {
        float *p = (float *)a->slots + a->start + offset;
        float *o = (float *)out->slots + out->start;
        for (int64_t row = 0; row < rows; row++) {
            float *rp = p + row * cols;
            if (kind == 0) {
                double sum = 0.0;
                for (int64_t col = 0; col < cols; col++) sum += (double)rp[col];
                o[row] = (float)sum;
            } else if (cols > 0) {
                float best = rp[0];
                for (int64_t col = 1; col < cols; col++) if (rp[col] > best) best = rp[col];
                o[row] = best;
            }
        }
        return out_wval;
    }
    w_raise(w_string("blas_reduce_last: dtype must be f32 or f64"));
    return W_NIL;
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

static int64_t blas_pair_f64_n(WValue a_wval, WValue out_wval,
                               WValue n_wval, double **a_out,
                               double **out_out) {
    WArray *a = w_as_array(a_wval);
    WArray *out = w_as_array(out_wval);
    int64_t la = a->size;
    int64_t lo = out->size;
    *a_out = (double *)a->slots + a->start;
    *out_out = (double *)out->slots + out->start;
    int64_t n = w_as_int(n_wval);
    int64_t mn = la < lo ? la : lo;
    if (n <= 0 || n > mn) n = mn;
    return n;
}

#define W_BLAS_F64_UNARY(name, function)                                      \
WValue name(WValue a_wval, WValue out_wval, WValue n_wval) {                 \
    double *a, *o;                                                             \
    int n = (int)blas_pair_f64_n(a_wval, out_wval, n_wval, &a, &o);           \
    function(o, a, &n);                                                        \
    return out_wval;                                                           \
}

W_BLAS_F64_UNARY(w_blas_vsin_f64, vvsin)
W_BLAS_F64_UNARY(w_blas_vcos_f64, vvcos)
W_BLAS_F64_UNARY(w_blas_vexp_f64, vvexp)
W_BLAS_F64_UNARY(w_blas_vlog_f64, vvlog)
W_BLAS_F64_UNARY(w_blas_vsqrt_f64, vvsqrt)
W_BLAS_F64_UNARY(w_blas_vtan_f64, vvtan)

#undef W_BLAS_F64_UNARY

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

static double *blas_f64_ptr(WValue v, int64_t *len_out);

/* Elementwise binop over contiguous buffers: kind 0=add 1=sub 2=mul 3=div.
 * NOTE vDSP's vsub/vdiv take operands REVERSED (vDSP_vsub(B,..,A,..,C) is
 * C = A - B); both call sites below pass (b, a) to preserve a-op-b. */
WValue w_blas_ew_f32(WValue k_wval, WValue a_wval, WValue b_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lb, lo;
    float *a = blas_f32_ptr(a_wval, &la);
    float *b = blas_f32_ptr(b_wval, &lb);
    float *o = blas_f32_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    int64_t kind = w_as_int(k_wval);
    int64_t mn = la < lb ? la : lb;
    if (lo < mn) mn = lo;
    if (n <= 0 || n > mn) n = mn;
    switch (kind) {
    case 0: vDSP_vadd(a, 1, b, 1, o, 1, (vDSP_Length)n); break;
    case 1: vDSP_vsub(b, 1, a, 1, o, 1, (vDSP_Length)n); break;
    case 2: vDSP_vmul(a, 1, b, 1, o, 1, (vDSP_Length)n); break;
    case 3: vDSP_vdiv(b, 1, a, 1, o, 1, (vDSP_Length)n); break;
    default: break;
    }
    return out_wval;
}

WValue w_blas_ew_f64(WValue k_wval, WValue a_wval, WValue b_wval, WValue out_wval, WValue n_wval) {
    int64_t la, lb, lo;
    double *a = blas_f64_ptr(a_wval, &la);
    double *b = blas_f64_ptr(b_wval, &lb);
    double *o = blas_f64_ptr(out_wval, &lo);
    int64_t n = w_as_int(n_wval);
    int64_t kind = w_as_int(k_wval);
    int64_t mn = la < lb ? la : lb;
    if (lo < mn) mn = lo;
    if (n <= 0 || n > mn) n = mn;
    switch (kind) {
    case 0: vDSP_vaddD(a, 1, b, 1, o, 1, (vDSP_Length)n); break;
    case 1: vDSP_vsubD(b, 1, a, 1, o, 1, (vDSP_Length)n); break;
    case 2: vDSP_vmulD(a, 1, b, 1, o, 1, (vDSP_Length)n); break;
    case 3: vDSP_vdivD(b, 1, a, 1, o, 1, (vDSP_Length)n); break;
    default: break;
    }
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
    WArray *a = w_as_array(v);
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

/* dgeev: all eigenvalues of a general real n×n matrix via the LAPACK
 * dgeev_ FORTRAN symbol, manually prototyped — the deprecated clapack
 * HEADERS stay un-included (including them is what broke bootstrap on
 * new-LAPACK-only Xcodes); the legacy LP64 symbol itself is stable ABI.
 * A is row-major f64 and is DESTROYED. Eigenvalues only: A and Aᵀ share
 * a spectrum, so the row/column-major mismatch is harmless with
 * jobvl = jobvr = 'N'. wr/wi receive the real/imaginary parts.
 * Returns info (0 = ok, >0 = QR failed to converge at that index). */
extern int dgeev_(char *jobvl, char *jobvr, int *n,
                  double *a, int *lda, double *wr, double *wi,
                  double *vl, int *ldvl, double *vr, int *ldvr,
                  double *work, int *lwork, int *info);

WValue w_blas_dgeev(WValue a_wval, WValue wr_wval, WValue wi_wval, WValue n_wval) {
    int64_t la, lr, li;
    double *A = blas_f64_ptr(a_wval, &la);
    double *WR = blas_f64_ptr(wr_wval, &lr);
    double *WI = blas_f64_ptr(wi_wval, &li);
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

/* In-place complex FFT on split f32 re/im arrays via vDSP. Matches
 * core/fft.w's convention: forward = unscaled DFT (e^(-2*pi*i*j*k/n)),
 * inverse scaled by 1/n so ifft(fft(x)) == x. Power-of-2 lengths only —
 * the same contract FFT.fft_inplace enforces. FFT setups are cached per
 * log2n and never freed (create-once; first use per size is not
 * thread-safe, matching the bridge's single-threaded contract). */
WValue w_blas_fft_f32(WValue re_wval, WValue im_wval, WValue n_wval, WValue inv_wval) {
    int64_t lre, lim;
    float *re = blas_f32_ptr(re_wval, &lre);
    float *im = blas_f32_ptr(im_wval, &lim);
    int64_t n = w_as_int(n_wval);
    int inverse = (int)w_truthy(inv_wval);
    if (n <= 0 || (n & (n - 1)) != 0) {
        w_raise(w_string("fft_f32: length must be a power of 2"));
        return W_NIL;
    }
    if (lre < n || lim < n) {
        w_raise(w_string("fft_f32: re/im arrays shorter than n"));
        return W_NIL;
    }
    vDSP_Length log2n = 0;
    while (((int64_t)1 << log2n) < n) log2n++;
    static FFTSetup fft_setups[31];
    if (log2n >= 31) {
        w_raise(w_string("fft_f32: length too large"));
        return W_NIL;
    }
    if (fft_setups[log2n] == NULL)
        fft_setups[log2n] = vDSP_create_fftsetup(log2n, kFFTRadix2);
    if (fft_setups[log2n] == NULL) {
        w_raise(w_string("fft_f32: vDSP setup allocation failed"));
        return W_NIL;
    }
    DSPSplitComplex sc = { re, im };
    vDSP_fft_zip(fft_setups[log2n], &sc, 1, log2n,
                 inverse ? kFFTDirection_Inverse : kFFTDirection_Forward);
    if (inverse) {
        float s = 1.0f / (float)n;
        vDSP_vsmul(re, 1, &s, re, 1, (vDSP_Length)n);
        vDSP_vsmul(im, 1, &s, im, 1, (vDSP_Length)n);
    }
    return W_NIL;
}
