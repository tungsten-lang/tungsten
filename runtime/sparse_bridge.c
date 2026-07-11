/* Apple SparseBLAS + Sparse Solvers bridge (Accelerate).
 *
 * Linked when IR references @w_sparse_ (same gating idea as blas_bridge).
 *   SpMV:    sparse_matrix_vector_product_dense_float (Sparse/BLAS.h)
 *   Factor:  SparseFactor(SparseFactorizationQR, …)   (Sparse/Solve.h)
 *   Solve:   SparseSolve(factor, b, x)
 *
 * COO → SparseConvertFromCoordinate → factor → solve → SparseCleanup.
 */
#include "runtime.h"
#include "wvalue.h"
#include <Accelerate/Accelerate.h>
#include <vecLib/Sparse/BLAS.h>
#include <string.h>
#include <stdlib.h>

static int32_t *i32_ptr(WValue v, int64_t *len) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len = (int64_t)a->size;
    return ((int32_t *)a->slots) + a->start;
}

static float *f32_ptr(WValue v, int64_t *len) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len = (int64_t)a->size;
    return (float *)a->slots + a->start;
}

static double *f64_ptr(WValue v, int64_t *len) {
    WArray *a = (WArray *)w_as_ptr(v);
    *len = (int64_t)a->size;
    return (double *)a->slots + a->start;
}

/* Build opaque sparse matrix from CSR, SpMV into y, destroy matrix.
 * indptr: i32 length rows+1; indices: i32 nnz; data: f32 nnz;
 * x: f32 cols; y: f32 rows (overwritten). */
WValue w_sparse_spmv_f32(WValue rows_w, WValue cols_w,
                         WValue indptr_w, WValue indices_w, WValue data_w,
                         WValue x_w, WValue y_w) {
    int rows = (int)w_as_int(rows_w);
    int cols = (int)w_as_int(cols_w);
    int64_t lip, lix, ld, lx, ly;
    int32_t *indptr = i32_ptr(indptr_w, &lip);
    int32_t *indices = i32_ptr(indices_w, &lix);
    float *data = f32_ptr(data_w, &ld);
    float *x = f32_ptr(x_w, &lx);
    float *y = f32_ptr(y_w, &ly);
    if (lip < rows + 1 || ly < rows || lx < cols) {
        w_raise(w_string("sparse_spmv: dimension mismatch"));
        return W_NIL;
    }
    sparse_matrix_float A = sparse_matrix_create_float(rows, cols);
    if (!A) {
        w_raise(w_string("sparse_spmv: sparse_matrix_create_float failed"));
        return W_NIL;
    }
    for (int i = 0; i < rows; i++) {
        int p0 = indptr[i];
        int p1 = indptr[i + 1];
        for (int p = p0; p < p1; p++) {
            if (p < 0 || p >= ld || p >= lix) continue;
            sparse_insert_entry_float(A, data[p], i, indices[p]);
        }
    }
    /* zero y then y = A x */
    for (int i = 0; i < rows; i++) y[i] = 0.0f;
    sparse_status st = sparse_matrix_vector_product_dense_float(
        CblasNoTrans, 1.0f, A, x, 1, y, 1);
    sparse_matrix_destroy(A);
    if (st != SPARSE_SUCCESS) {
        w_raise(w_string("sparse_spmv: SparseBLAS product failed"));
        return W_NIL;
    }
    return y_w;
}

/* QR factor + solve: Ax = b for general (non-symmetric) sparse A.
 *
 * Inputs (all typed WArrays):
 *   row, col : i32 COO indices, length nnz
 *   data     : f64 values, length nnz
 *   b        : f64 RHS, length rows
 *   x        : f64 solution buffer, length cols (written)
 *
 * Returns x on success. Uses Apple Sparse Solvers:
 *   SparseConvertFromCoordinate → SparseFactor(QR) → SparseSolve → SparseCleanup
 */
WValue w_sparse_solve_qr_f64(WValue rows_w, WValue cols_w,
                             WValue row_w, WValue col_w, WValue data_w,
                             WValue b_w, WValue x_w) {
    int rows = (int)w_as_int(rows_w);
    int cols = (int)w_as_int(cols_w);
    int64_t lrow, lcol, ld, lb, lx;
    int32_t *row = i32_ptr(row_w, &lrow);
    int32_t *col = i32_ptr(col_w, &lcol);
    double *data = f64_ptr(data_w, &ld);
    double *b = f64_ptr(b_w, &lb);
    double *x = f64_ptr(x_w, &lx);
    if (rows <= 0 || cols <= 0) {
        w_raise(w_string("sparse_solve_qr: non-positive dimensions"));
        return W_NIL;
    }
    if (lrow != lcol || lrow != ld || lrow < 1) {
        w_raise(w_string("sparse_solve_qr: COO length mismatch"));
        return W_NIL;
    }
    if (lb < rows || lx < cols) {
        w_raise(w_string("sparse_solve_qr: b/x length mismatch"));
        return W_NIL;
    }

    SparseAttributes_t attributes;
    memset(&attributes, 0, sizeof(attributes));
    /* SparseOrdinary (kind=0): general rectangular/square matrix. */

    SparseMatrix_Double A = SparseConvertFromCoordinate(
        rows, cols, (long)lrow, /*blockSize=*/1, attributes,
        (const int *)row, (const int *)col, (const double *)data);

    SparseOpaqueFactorization_Double F =
        SparseFactor(SparseFactorizationQR, A);
    if (F.status != SparseStatusOK) {
        SparseCleanup(F);
        SparseCleanup(A);
        w_raise(w_string("sparse_solve_qr: SparseFactor(QR) failed"));
        return W_NIL;
    }

    /* SparseSolve with separate b and x: b length m, x length n. */
    DenseVector_Double bv = { .count = rows, .data = b };
    DenseVector_Double xv = { .count = cols, .data = x };
    /* zero x first (solver writes solution here) */
    for (int i = 0; i < cols; i++) x[i] = 0.0;
    SparseSolve(F, bv, xv);

    SparseCleanup(F);
    SparseCleanup(A);
    return x_w;
}

/* SPD Cholesky path: A must be square symmetric positive-definite.
 * COO may list either triangle (or both); SparseConvert sums duplicates.
 * attributes.kind = SparseSymmetric, triangle = SparseUpper (default). */
WValue w_sparse_solve_chol_f64(WValue n_w,
                               WValue row_w, WValue col_w, WValue data_w,
                               WValue b_w, WValue x_w) {
    int n = (int)w_as_int(n_w);
    int64_t lrow, lcol, ld, lb, lx;
    int32_t *row = i32_ptr(row_w, &lrow);
    int32_t *col = i32_ptr(col_w, &lcol);
    double *data = f64_ptr(data_w, &ld);
    double *b = f64_ptr(b_w, &lb);
    double *x = f64_ptr(x_w, &lx);
    if (n <= 0 || lrow != lcol || lrow != ld || lrow < 1 || lb < n || lx < n) {
        w_raise(w_string("sparse_solve_chol: bad dimensions / COO"));
        return W_NIL;
    }

    SparseAttributes_t attributes;
    memset(&attributes, 0, sizeof(attributes));
    attributes.kind = SparseSymmetric;
    attributes.triangle = SparseUpperTriangle;

    SparseMatrix_Double A = SparseConvertFromCoordinate(
        n, n, (long)lrow, 1, attributes,
        (const int *)row, (const int *)col, (const double *)data);

    SparseOpaqueFactorization_Double F =
        SparseFactor(SparseFactorizationCholesky, A);
    if (F.status != SparseStatusOK) {
        SparseCleanup(F);
        SparseCleanup(A);
        w_raise(w_string("sparse_solve_chol: SparseFactor(Cholesky) failed"));
        return W_NIL;
    }

    /* copy b → x then solve in place */
    for (int i = 0; i < n; i++) x[i] = b[i];
    DenseVector_Double xb = { .count = n, .data = x };
    SparseSolve(F, xb);

    SparseCleanup(F);
    SparseCleanup(A);
    return x_w;
}
