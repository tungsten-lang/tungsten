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
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

extern void dgetrf_(const int *m, const int *n, double *a, const int *lda,
                    int *ipiv, int *info);
extern void dgetrs_(const char *trans, const int *n, const int *nrhs,
                    const double *a, const int *lda, const int *ipiv,
                    double *b, const int *ldb, int *info);
extern void dpotrf_(const char *uplo, const int *n, double *a,
                    const int *lda, int *info);
extern void dpotrs_(const char *uplo, const int *n, const int *nrhs,
                    const double *a, const int *lda, double *b,
                    const int *ldb, int *info);

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

WValue w_blas_sgemm_view_scaled(WValue a_wval, WValue b_wval, WValue c_wval,
                                WValue m_wval, WValue n_wval, WValue k_wval,
                                WValue ao_wval, WValue bo_wval, WValue co_wval,
                                WValue ta_wval, WValue tb_wval,
                                WValue alpha_wval, WValue beta_wval) {
    WArray *a = w_as_array(a_wval), *b = w_as_array(b_wval), *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval), N = (int)w_as_int(n_wval), K = (int)w_as_int(k_wval);
    int64_t ao = w_as_int(ao_wval), bo = w_as_int(bo_wval), co = w_as_int(co_wval);
    int ta = (int)w_as_int(ta_wval), tb = (int)w_as_int(tb_wval);
    if (M < 0 || N < 0 || K < 0 || ao < 0 || bo < 0 || co < 0 || ao + (int64_t)M * K > a->size || bo + (int64_t)K * N > b->size ||
        co + (int64_t)M * N > c->size) {
        w_raise(w_string("sgemm_view_scaled: bad dimensions")); return W_NIL;
    }
    float *Ap = (float *)a->slots + a->start + ao;
    float *Bp = (float *)b->slots + b->start + bo;
    float *Cp = (float *)c->slots + c->start + co;
    cblas_sgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans, M, N, K,
                (float)w_as_double(alpha_wval), Ap, ta ? M : K,
                Bp, tb ? K : N, (float)w_as_double(beta_wval), Cp, N);
    return c_wval;
}

WValue w_blas_dgemm_view_scaled(WValue a_wval, WValue b_wval, WValue c_wval,
                                WValue m_wval, WValue n_wval, WValue k_wval,
                                WValue ao_wval, WValue bo_wval, WValue co_wval,
                                WValue ta_wval, WValue tb_wval,
                                WValue alpha_wval, WValue beta_wval) {
    WArray *a = w_as_array(a_wval), *b = w_as_array(b_wval), *c = w_as_array(c_wval);
    int M = (int)w_as_int(m_wval), N = (int)w_as_int(n_wval), K = (int)w_as_int(k_wval);
    int64_t ao = w_as_int(ao_wval), bo = w_as_int(bo_wval), co = w_as_int(co_wval);
    int ta = (int)w_as_int(ta_wval), tb = (int)w_as_int(tb_wval);
    if (M < 0 || N < 0 || K < 0 || ao < 0 || bo < 0 || co < 0 || ao + (int64_t)M * K > a->size || bo + (int64_t)K * N > b->size ||
        co + (int64_t)M * N > c->size) {
        w_raise(w_string("dgemm_view_scaled: bad dimensions")); return W_NIL;
    }
    double *Ap = (double *)a->slots + a->start + ao;
    double *Bp = (double *)b->slots + b->start + bo;
    double *Cp = (double *)c->slots + c->start + co;
    cblas_dgemm(CblasRowMajor, ta ? CblasTrans : CblasNoTrans,
                tb ? CblasTrans : CblasNoTrans, M, N, K,
                w_as_double(alpha_wval), Ap, ta ? M : K,
                Bp, tb ? K : N, w_as_double(beta_wval), Cp, N);
    return c_wval;
}

WValue w_blas_dgetrf_rowmajor(WValue a_wval, WValue piv_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *piv = w_as_array(piv_wval);
    int n = (int)w_as_int(n_wval);
    if (n <= 0 || a->size < (int64_t)n * n || piv->size < n) {
        w_raise(w_string("dgetrf_rowmajor: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start;
    int *ipiv = (int *)piv->slots + piv->start;
    int info = 0;
    dgetrf_(&n, &n, ap, &n, ipiv, &info);
    return w_int(info);
}

WValue w_blas_dgetrs_rowmajor(WValue factor_wval, WValue piv_wval,
                              WValue rhs_wval, WValue n_wval) {
    WArray *factor = w_as_array(factor_wval), *piv = w_as_array(piv_wval);
    WArray *rhs = w_as_array(rhs_wval);
    int n = (int)w_as_int(n_wval);
    if (n <= 0 || factor->size < (int64_t)n * n || piv->size < n || rhs->size < n) {
        w_raise(w_string("dgetrs_rowmajor: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)factor->slots + factor->start;
    int *ipiv = (int *)piv->slots + piv->start;
    double *bp = (double *)rhs->slots + rhs->start;
    int info = 0, nrhs = 1;
    dgetrs_("T", &n, &nrhs, ap, &n, ipiv, bp, &n, &info);
    return w_int(info);
}

WValue w_blas_dgetrs_many_rowmajor(WValue factor_wval, WValue piv_wval,
                                   WValue rhs_wval, WValue n_wval,
                                   WValue nrhs_wval) {
    WArray *factor = w_as_array(factor_wval), *piv = w_as_array(piv_wval);
    WArray *rhs = w_as_array(rhs_wval);
    int n = (int)w_as_int(n_wval), nrhs = (int)w_as_int(nrhs_wval);
    if (n <= 0 || nrhs <= 0 || factor->size < (int64_t)n * n ||
        piv->size < n || rhs->size < (int64_t)n * nrhs) {
        w_raise(w_string("dgetrs_many_rowmajor: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)factor->slots + factor->start;
    int *ipiv = (int *)piv->slots + piv->start;
    double *bp = (double *)rhs->slots + rhs->start;
    int info = 0;
    dgetrs_("T", &n, &nrhs, ap, &n, ipiv, bp, &n, &info);
    return w_int(info);
}

WValue w_blas_dpotrf_lower(WValue a_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval);
    int n = (int)w_as_int(n_wval), info = 0;
    if (n <= 0 || a->size < (int64_t)n * n) {
        w_raise(w_string("dpotrf_lower: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start;
    dpotrf_("U", &n, ap, &n, &info);
    if (info == 0)
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j < n; j++) ap[(size_t)i * n + j] = 0.0;
    return w_int(info);
}

WValue w_blas_dpotrs_rowmajor(WValue factor_wval, WValue rhs_wval,
                              WValue n_wval, WValue nrhs_wval) {
    WArray *factor = w_as_array(factor_wval), *rhs = w_as_array(rhs_wval);
    int n = (int)w_as_int(n_wval), nrhs = (int)w_as_int(nrhs_wval);
    if (n <= 0 || nrhs <= 0 || factor->size < (int64_t)n * n ||
        rhs->size < (int64_t)n * nrhs) {
        w_raise(w_string("dpotrs_rowmajor: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)factor->slots + factor->start;
    double *bp = (double *)rhs->slots + rhs->start;
    int info = 0;
    dpotrs_("U", &n, &nrhs, ap, &n, bp, &n, &info);
    return w_int(info);
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

WValue w_blas_reduce_view(WValue dtype_wval, WValue a_wval,
                          WValue offset_wval, WValue n_wval,
                          WValue kind_wval) {
    WArray *a = w_as_array(a_wval);
    int64_t dtype = w_as_int(dtype_wval), offset = w_as_int(offset_wval);
    int64_t n = w_as_int(n_wval), kind = w_as_int(kind_wval);
    if (offset < 0 || n < 0 || offset + n > a->size || kind < 0 || kind > 1) {
        w_raise(w_string("blas_reduce_view: invalid offset, length, or kind"));
        return W_NIL;
    }
    double result = 0.0;
    if (dtype == 64) {
        double *p = (double *)a->slots + a->start + offset;
        if (kind == 0) for (int64_t i = 0; i < n; i++) result += p[i];
        else if (n > 0) { result = p[0]; for (int64_t i = 1; i < n; i++) if (p[i] > result) result = p[i]; }
    } else if (dtype == 3) {
        float *p = (float *)a->slots + a->start + offset;
        if (kind == 0) for (int64_t i = 0; i < n; i++) result += (double)p[i];
        else if (n > 0) { float best = p[0]; for (int64_t i = 1; i < n; i++) if (p[i] > best) best = p[i]; result = best; }
    } else {
        w_raise(w_string("blas_reduce_view: dtype must be f32 or f64"));
        return W_NIL;
    }
    return w_float(result);
}

WValue w_blas_reduce_last(WValue dtype_wval, WValue a_wval, WValue out_wval,
                          WValue offset_wval, WValue rows_wval,
                          WValue cols_wval, WValue kind_wval) {
    WArray *a = w_as_array(a_wval), *out = w_as_array(out_wval);
    int64_t dtype = w_as_int(dtype_wval), offset = w_as_int(offset_wval);
    int64_t rows = w_as_int(rows_wval), cols = w_as_int(cols_wval), kind = w_as_int(kind_wval);
    if (offset < 0 || rows < 0 || cols < 0 || offset + rows * cols > a->size ||
        rows > out->size || kind < 0 || kind > 1) {
        w_raise(w_string("blas_reduce_last: invalid shape, offset, or kind"));
        return W_NIL;
    }
    if (dtype == 64) {
        double *p = (double *)a->slots + a->start + offset, *o = (double *)out->slots + out->start;
        for (int64_t r = 0; r < rows; r++) {
            double value = 0.0, *rp = p + r * cols;
            if (kind == 0) for (int64_t c = 0; c < cols; c++) value += rp[c];
            else if (cols > 0) { value = rp[0]; for (int64_t c = 1; c < cols; c++) if (rp[c] > value) value = rp[c]; }
            o[r] = value;
        }
    } else if (dtype == 3) {
        float *p = (float *)a->slots + a->start + offset, *o = (float *)out->slots + out->start;
        for (int64_t r = 0; r < rows; r++) {
            double value = 0.0; float *rp = p + r * cols;
            if (kind == 0) for (int64_t c = 0; c < cols; c++) value += (double)rp[c];
            else if (cols > 0) { value = rp[0]; for (int64_t c = 1; c < cols; c++) if (rp[c] > value) value = rp[c]; }
            o[r] = (float)value;
        }
    } else {
        w_raise(w_string("blas_reduce_last: dtype must be f32 or f64"));
        return W_NIL;
    }
    return out_wval;
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

WValue w_blas_unary_view(WValue dtype_wval, WValue a_wval,
                         WValue out_wval, WValue offset_wval,
                         WValue n_wval, WValue kind_wval) {
    WArray *a = w_as_array(a_wval), *out = w_as_array(out_wval);
    int64_t dtype = w_as_int(dtype_wval), offset = w_as_int(offset_wval);
    int64_t n = w_as_int(n_wval), kind = w_as_int(kind_wval);
    if (offset < 0 || n < 0 || offset + n > a->size || n > out->size || kind < 0 || kind > 5) {
        w_raise(w_string("blas_unary_view: invalid offset, length, or kind"));
        return W_NIL;
    }
    if (dtype == 64) {
        double *p = (double *)a->slots + a->start + offset, *o = (double *)out->slots + out->start;
        for (int64_t i = 0; i < n; i++) {
            switch (kind) {
            case 0: o[i] = 0.0 - p[i]; break;
            case 1: o[i] = p[i] < 0.0 ? 0.0 : p[i]; break;
            case 2: o[i] = fabs(p[i]); break;
            case 3: o[i] = sqrt(p[i]); break;
            case 4: o[i] = p[i] * p[i]; break;
            case 5: o[i] = exp(p[i]); break;
            }
        }
    } else if (dtype == 3) {
        float *p = (float *)a->slots + a->start + offset, *o = (float *)out->slots + out->start;
        for (int64_t i = 0; i < n; i++) {
            switch (kind) {
            case 0: o[i] = 0.0f - p[i]; break;
            case 1: o[i] = p[i] < 0.0f ? 0.0f : p[i]; break;
            case 2: o[i] = fabsf(p[i]); break;
            case 3: o[i] = sqrtf(p[i]); break;
            case 4: o[i] = p[i] * p[i]; break;
            case 5: o[i] = expf(p[i]); break;
            }
        }
    } else {
        w_raise(w_string("blas_unary_view: dtype must be f32 or f64"));
        return W_NIL;
    }
    return out_wval;
}

static double *oblas_f64_ptr(WValue v, int64_t *len_out);

WValue w_blas_dot_f64(WValue a_wval, WValue b_wval, WValue n_wval) {
    int64_t la, lb;
    double *a = oblas_f64_ptr(a_wval, &la), *b = oblas_f64_ptr(b_wval, &lb);
    int64_t n = w_as_int(n_wval), limit = la < lb ? la : lb;
    if (n <= 0 || n > limit) n = limit;
    return w_float(cblas_ddot((int)n, a, 1, b, 1));
}

WValue w_blas_norm_f64(WValue a_wval, WValue n_wval) {
    int64_t len; double *a = oblas_f64_ptr(a_wval, &len);
    int64_t n = w_as_int(n_wval); if (n <= 0 || n > len) n = len;
    return w_float(cblas_dnrm2((int)n, a, 1));
}

WValue w_blas_daxpy(WValue alpha_wval, WValue x_wval, WValue y_wval, WValue n_wval) {
    int64_t lx, ly;
    double *x = oblas_f64_ptr(x_wval, &lx), *y = oblas_f64_ptr(y_wval, &ly);
    int64_t n = w_as_int(n_wval), limit = lx < ly ? lx : ly;
    if (n <= 0 || n > limit) n = limit;
    cblas_daxpy((int)n, w_as_double(alpha_wval), x, 1, y, 1);
    return y_wval;
}

WValue w_blas_dscal(WValue alpha_wval, WValue x_wval, WValue n_wval) {
    int64_t len;
    double *x = oblas_f64_ptr(x_wval, &len);
    int64_t n = w_as_int(n_wval);
    if (n <= 0 || n > len) n = len;
    cblas_dscal((int)n, w_as_double(alpha_wval), x, 1);
    return x_wval;
}

WValue w_blas_dgemv_n(WValue a_wval, WValue x_wval, WValue y_wval,
                      WValue m_wval, WValue n_wval) {
    int64_t la, lx, ly;
    double *a = oblas_f64_ptr(a_wval, &la), *x = oblas_f64_ptr(x_wval, &lx);
    double *y = oblas_f64_ptr(y_wval, &ly);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    if (m < 0 || n < 0 || la < (int64_t)m * n || lx < n || ly < m) {
        w_raise(w_string("dgemv: bad dimensions")); return W_NIL;
    }
    cblas_dgemv(CblasRowMajor, CblasNoTrans, m, n, 1.0, a, n, x, 1, 0.0, y, 1);
    return y_wval;
}

WValue w_blas_dsymv_upper(WValue a_wval, WValue x_wval, WValue y_wval,
                          WValue n_wval) {
    int64_t la, lx, ly;
    double *a = oblas_f64_ptr(a_wval, &la), *x = oblas_f64_ptr(x_wval, &lx);
    double *y = oblas_f64_ptr(y_wval, &ly);
    int n = (int)w_as_int(n_wval);
    if (n < 0 || la < (int64_t)n * n || lx < n || ly < n) {
        w_raise(w_string("dsymv: bad dimensions")); return W_NIL;
    }
    cblas_dsymv(CblasRowMajor, CblasUpper, n, 1.0, a, n, x, 1, 0.0, y, 1);
    return y_wval;
}

WValue w_blas_dsyrk_upper(WValue a_wval, WValue c_wval,
                          WValue n_wval, WValue k_wval,
                          WValue alpha_wval, WValue beta_wval) {
    int64_t la, lc;
    double *a = oblas_f64_ptr(a_wval, &la), *c = oblas_f64_ptr(c_wval, &lc);
    int n = (int)w_as_int(n_wval), k = (int)w_as_int(k_wval);
    if (n < 0 || k < 0 || la < (int64_t)n * k || lc < (int64_t)n * n) {
        w_raise(w_string("dsyrk: bad dimensions")); return W_NIL;
    }
    cblas_dsyrk(CblasRowMajor, CblasUpper, CblasNoTrans, n, k,
                w_as_double(alpha_wval), a, k, w_as_double(beta_wval), c, n);
    return c_wval;
}

WValue w_blas_dtrsm_left_lower(WValue a_wval, WValue b_wval,
                               WValue m_wval, WValue n_wval,
                               WValue alpha_wval) {
    int64_t la, lb;
    double *a = oblas_f64_ptr(a_wval, &la), *b = oblas_f64_ptr(b_wval, &lb);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    if (m < 0 || n < 0 || la < (int64_t)m * m || lb < (int64_t)m * n) {
        w_raise(w_string("dtrsm: bad dimensions")); return W_NIL;
    }
    cblas_dtrsm(CblasRowMajor, CblasLeft, CblasLower, CblasNoTrans,
                CblasNonUnit, m, n, w_as_double(alpha_wval), a, m, b, n);
    return b_wval;
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
extern void dgeqrf_(const int *m, const int *n, double *a, const int *lda,
                    double *tau, double *work, const int *lwork, int *info);
extern void dorgqr_(const int *m, const int *n, const int *k, double *a,
                    const int *lda, const double *tau, double *work,
                    const int *lwork, int *info);
extern void dormqr_(const char *side, const char *trans, const int *m,
                    const int *n, const int *k, const double *a,
                    const int *lda, const double *tau, double *c,
                    const int *ldc, double *work, const int *lwork,
                    int *info);
extern void dtrtrs_(const char *uplo, const char *trans, const char *diag,
                    const int *n, const int *nrhs, const double *a,
                    const int *lda, double *b, const int *ldb, int *info);
extern void dsyev_(const char *jobz, const char *uplo, const int *n, double *a,
                   const int *lda, double *w, double *work,
                   const int *lwork, int *info);
extern void dgesdd_(const char *jobz, const int *m, const int *n, double *a,
                    const int *lda, double *s, double *u, const int *ldu,
                    double *vt, const int *ldvt, double *work,
                    const int *lwork, int *iwork, int *info);
extern void dgelsy_(const int *m, const int *n, const int *nrhs, double *a,
                    const int *lda, double *b, const int *ldb, int *jpvt,
                    const double *rcond, int *rank, double *work,
                    const int *lwork, int *info);

WValue w_blas_dgeqrf_qr(WValue a_wval, WValue q_wval, WValue r_wval,
                        WValue m_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *q = w_as_array(q_wval), *r = w_as_array(r_wval);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    if (m < n || n < 0 || a->size < (int64_t)m * n ||
        q->size < (int64_t)m * n || r->size < (int64_t)n * n) {
        w_raise(w_string("dgeqrf_qr: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start, *qp = (double *)q->slots + q->start;
    double *rp = (double *)r->slots + r->start;
    int info = 0, lwork = -1; double query = 0.0;
    double *tau = (double *)malloc(sizeof(double) * (size_t)(n > 0 ? n : 1));
    if (!tau) { w_raise(w_string("dgeqrf_qr: out of memory")); return w_int(-1); }
    dgeqrf_(&m, &n, ap, &m, tau, &query, &lwork, &info);
    if (info != 0) { free(tau); return w_int(info); }
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { free(tau); w_raise(w_string("dgeqrf_qr: out of memory")); return w_int(-1); }
    dgeqrf_(&m, &n, ap, &m, tau, work, &lwork, &info); free(work);
    if (info != 0) { free(tau); return w_int(info); }
    for (int i = 0; i < n; i++) for (int j = 0; j < n; j++)
        rp[(size_t)i * n + j] = j < i ? 0.0 : ap[(size_t)i + (size_t)j * m];
    lwork = -1; query = 0.0;
    dorgqr_(&m, &n, &n, ap, &m, tau, &query, &lwork, &info);
    if (info == 0) {
        lwork = (int)query; if (lwork < 1) lwork = 1;
        work = (double *)malloc(sizeof(double) * (size_t)lwork);
        if (!work) { free(tau); w_raise(w_string("dgeqrf_qr: out of memory")); return w_int(-1); }
        dorgqr_(&m, &n, &n, ap, &m, tau, work, &lwork, &info); free(work);
    }
    free(tau); if (info != 0) return w_int(info);
    for (int i = 0; i < m; i++) for (int j = 0; j < n; j++)
        qp[(size_t)i * n + j] = ap[(size_t)i + (size_t)j * m];
    return w_int(0);
}

WValue w_blas_dgeqrf_factor(WValue a_wval, WValue tau_wval,
                            WValue m_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *tau = w_as_array(tau_wval);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    if (m < n || n <= 0 || a->size < (int64_t)m * n || tau->size < n) {
        w_raise(w_string("dgeqrf_factor: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start;
    double *tp = (double *)tau->slots + tau->start;
    int info = 0, lwork = -1; double query = 0.0;
    dgeqrf_(&m, &n, ap, &m, tp, &query, &lwork, &info);
    if (info != 0) return w_int(info);
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { w_raise(w_string("dgeqrf_factor: out of memory")); return w_int(-1); }
    dgeqrf_(&m, &n, ap, &m, tp, work, &lwork, &info); free(work);
    return w_int(info);
}

WValue w_blas_dgeqrf_solve(WValue factor_wval, WValue tau_wval,
                           WValue rhs_wval, WValue m_wval,
                           WValue n_wval, WValue nrhs_wval) {
    WArray *factor = w_as_array(factor_wval), *tau = w_as_array(tau_wval);
    WArray *rhs = w_as_array(rhs_wval);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    int nrhs = (int)w_as_int(nrhs_wval);
    if (m < n || n <= 0 || nrhs <= 0 || factor->size < (int64_t)m * n ||
        tau->size < n || rhs->size < (int64_t)m * nrhs) {
        w_raise(w_string("dgeqrf_solve: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)factor->slots + factor->start;
    double *tp = (double *)tau->slots + tau->start;
    double *bp = (double *)rhs->slots + rhs->start;
    int info = 0, lwork = -1; double query = 0.0;
    dormqr_("L", "T", &m, &nrhs, &n, ap, &m, tp, bp, &m,
            &query, &lwork, &info);
    if (info != 0) return w_int(info);
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { w_raise(w_string("dgeqrf_solve: out of memory")); return w_int(-1); }
    dormqr_("L", "T", &m, &nrhs, &n, ap, &m, tp, bp, &m,
            work, &lwork, &info); free(work);
    if (info != 0) return w_int(info);
    dtrtrs_("U", "N", "N", &n, &nrhs, ap, &m, bp, &m, &info);
    return w_int(info);
}

WValue w_blas_dsyev_values(WValue a_wval, WValue values_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *values = w_as_array(values_wval);
    int n = (int)w_as_int(n_wval);
    if (n < 0 || a->size < (int64_t)n * n || values->size < n) {
        w_raise(w_string("dsyev_values: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start, *wp = (double *)values->slots + values->start;
    int info = 0, lwork = -1; double query = 0.0;
    dsyev_("N", "U", &n, ap, &n, wp, &query, &lwork, &info);
    if (info != 0) return w_int(info);
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { w_raise(w_string("dsyev_values: out of memory")); return w_int(-1); }
    dsyev_("N", "U", &n, ap, &n, wp, work, &lwork, &info); free(work);
    return w_int(info);
}

WValue w_blas_dgesdd_values(WValue a_wval, WValue values_wval,
                            WValue m_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *values = w_as_array(values_wval);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval), mn = m < n ? m : n;
    if (m < 0 || n < 0 || a->size < (int64_t)m * n || values->size < mn) {
        w_raise(w_string("dgesdd_values: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start, *sp = (double *)values->slots + values->start;
    int info = 0, lwork = -1, one = 1; double query = 0.0, dummy = 0.0;
    int *iwork = (int *)malloc(sizeof(int) * (size_t)(8 * (mn > 0 ? mn : 1)));
    if (!iwork) { w_raise(w_string("dgesdd_values: out of memory")); return w_int(-1); }
    dgesdd_("N", &m, &n, ap, &m, sp, &dummy, &one, &dummy, &one, &query, &lwork, iwork, &info);
    if (info != 0) { free(iwork); return w_int(info); }
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { free(iwork); w_raise(w_string("dgesdd_values: out of memory")); return w_int(-1); }
    dgesdd_("N", &m, &n, ap, &m, sp, &dummy, &one, &dummy, &one, work, &lwork, iwork, &info);
    free(work); free(iwork); return w_int(info);
}

WValue w_blas_dgelsy(WValue a_wval, WValue b_wval,
                     WValue m_wval, WValue n_wval) {
    WArray *a = w_as_array(a_wval), *b = w_as_array(b_wval);
    int m = (int)w_as_int(m_wval), n = (int)w_as_int(n_wval);
    if (m < n || n < 0 || a->size < (int64_t)m * n || b->size < m) {
        w_raise(w_string("dgelsy: bad dimensions")); return w_int(-1);
    }
    double *ap = (double *)a->slots + a->start, *bp = (double *)b->slots + b->start;
    int nrhs = 1, rank = 0, info = 0, lwork = -1;
    int *jpvt = (int *)calloc((size_t)(n > 0 ? n : 1), sizeof(int));
    if (!jpvt) { w_raise(w_string("dgelsy: out of memory")); return w_int(-1); }
    double rcond = DBL_EPSILON * (double)(m > n ? m : n), query = 0.0;
    dgelsy_(&m, &n, &nrhs, ap, &m, bp, &m, jpvt, &rcond, &rank, &query, &lwork, &info);
    if (info != 0) { free(jpvt); return w_int(info); }
    lwork = (int)query; if (lwork < 1) lwork = 1;
    double *work = (double *)malloc(sizeof(double) * (size_t)lwork);
    if (!work) { free(jpvt); w_raise(w_string("dgelsy: out of memory")); return w_int(-1); }
    dgelsy_(&m, &n, &nrhs, ap, &m, bp, &m, jpvt, &rcond, &rank, work, &lwork, &info);
    free(work); free(jpvt); return w_int(info == 0 ? rank : info);
}

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
