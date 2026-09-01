/* Compare Accelerate's values-only symmetric eigensolver drivers.
 *
 * Each timed operation includes the same input copy plus the driver's
 * workspace query/allocation, matching w_blas_dsyev_values rather than
 * measuring an artificially warmed private workspace.  The source matrix is
 * deterministic, symmetric, and strictly diagonally dominant.
 * Set PERF30_EIGH_N and optionally PERF30_EIGH_ITERATIONS to focus one size. */
#include <Accelerate/Accelerate.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef int lapack_int;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1.0e-9;
}

static uint64_t next_u64(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * UINT64_C(2685821657736338717);
}

static double random_signed(uint64_t *state) {
    return ((double)(next_u64(state) >> 11) * (1.0 / 9007199254740992.0)) * 2.0 - 1.0;
}

static void fill_symmetric(double *a, int n) {
    uint64_t state = UINT64_C(0x4d595df4d0f33173) ^ (uint64_t)n;
    for (int j = 0; j < n; ++j) {
        for (int i = 0; i <= j; ++i) {
            double v = i == j ? (double)(n + i + 1) : random_signed(&state) * 0.25;
            a[(size_t)j * n + i] = v;
            a[(size_t)i * n + j] = v;
        }
    }
}

static int run_dsyev(const double *src, double *a, double *w, int n) {
    memcpy(a, src, sizeof(double) * (size_t)n * n);
    lapack_int nn = n, lda = n, info = 0, lwork = -1;
    double query = 0.0;
    dsyev_("N", "U", &nn, a, &lda, w, &query, &lwork, &info);
    if (info != 0) return info;
    lwork = (lapack_int)query;
    if (lwork < 1) lwork = 1;
    double *work = malloc(sizeof(double) * (size_t)lwork);
    if (!work) return -1000;
    dsyev_("N", "U", &nn, a, &lda, w, work, &lwork, &info);
    free(work);
    return info;
}

static int run_dsyevd(const double *src, double *a, double *w, int n) {
    memcpy(a, src, sizeof(double) * (size_t)n * n);
    lapack_int nn = n, lda = n, info = 0, lwork = -1, liwork = -1;
    lapack_int iquery = 0;
    double query = 0.0;
    dsyevd_("N", "U", &nn, a, &lda, w, &query, &lwork, &iquery, &liwork, &info);
    if (info != 0) return info;
    lwork = (lapack_int)query;
    liwork = iquery;
    if (lwork < 1) lwork = 1;
    if (liwork < 1) liwork = 1;
    double *work = malloc(sizeof(double) * (size_t)lwork);
    lapack_int *iwork = malloc(sizeof(lapack_int) * (size_t)liwork);
    if (!work || !iwork) {
        free(work);
        free(iwork);
        return -1000;
    }
    dsyevd_("N", "U", &nn, a, &lda, w, work, &lwork, iwork, &liwork, &info);
    free(work);
    free(iwork);
    return info;
}

static int run_dsyevr(const double *src, double *a, double *w, int n) {
    memcpy(a, src, sizeof(double) * (size_t)n * n);
    lapack_int nn = n, lda = n, info = 0, count = 0, ldz = 1;
    lapack_int il = 0, iu = 0, lwork = -1, liwork = -1;
    double vl = 0.0, vu = 0.0, abstol = 0.0, query = 0.0, z = 0.0;
    lapack_int iquery = 0;
    lapack_int *isuppz = malloc(sizeof(lapack_int) * (size_t)(2 * (n > 0 ? n : 1)));
    if (!isuppz) return -1000;
    dsyevr_("N", "A", "U", &nn, a, &lda, &vl, &vu, &il, &iu, &abstol,
            &count, w, &z, &ldz, isuppz, &query, &lwork, &iquery, &liwork, &info);
    if (info != 0) {
        free(isuppz);
        return info;
    }
    lwork = (lapack_int)query;
    liwork = iquery;
    if (lwork < 1) lwork = 1;
    if (liwork < 1) liwork = 1;
    double *work = malloc(sizeof(double) * (size_t)lwork);
    lapack_int *iwork = malloc(sizeof(lapack_int) * (size_t)liwork);
    if (!work || !iwork) {
        free(isuppz);
        free(work);
        free(iwork);
        return -1000;
    }
    dsyevr_("N", "A", "U", &nn, a, &lda, &vl, &vu, &il, &iu, &abstol,
            &count, w, &z, &ldz, isuppz, work, &lwork, iwork, &liwork, &info);
    free(isuppz);
    free(work);
    free(iwork);
    return info != 0 ? info : (count == n ? 0 : -2000 - count);
}

typedef int (*driver_fn)(const double *, double *, double *, int);

static double time_driver(driver_fn fn, const double *src, double *a, double *w,
                          int n, int iterations) {
    double start = now_seconds();
    int checksum = 0;
    for (int i = 0; i < iterations; ++i) checksum |= fn(src, a, w, n);
    double elapsed = now_seconds() - start;
    if (checksum != 0) {
        fprintf(stderr, "driver failed at n=%d: %d\n", n, checksum);
        exit(2);
    }
    return elapsed * 1.0e6 / iterations;
}

static int compare_double(const void *left, const void *right) {
    double a = *(const double *)left, b = *(const double *)right;
    return a < b ? -1 : a > b;
}

static double median(double *samples, int count) {
    qsort(samples, (size_t)count, sizeof(double), compare_double);
    return samples[count / 2];
}

int main(void) {
    const int sizes[] = {8, 16, 32, 64, 96, 128, 192, 224, 240, 256, 272, 288, 320, 384, 512, 768, 1024};
    const int counts[] = {20000, 10000, 5000, 1500, 750, 400, 150, 120, 100, 80, 70, 60, 50, 30, 12, 5, 2};
    const char *only_size = getenv("PERF30_EIGH_N");
    const char *iteration_override = getenv("PERF30_EIGH_ITERATIONS");
    enum { rounds = 7 };
    puts("n,iterations,dsyev_us,dsyevd_us,dsyevr_us,max_abs_dsyevd,max_abs_dsyevr");
    for (size_t si = 0; si < sizeof(sizes) / sizeof(sizes[0]); ++si) {
        int n = sizes[si], iterations = counts[si];
        if (only_size && n != atoi(only_size)) continue;
        if (iteration_override) iterations = atoi(iteration_override);
        if (iterations <= 0) return 5;
        size_t matrix_count = (size_t)n * n;
        double *src = malloc(sizeof(double) * matrix_count);
        double *a = malloc(sizeof(double) * matrix_count);
        double *w0 = malloc(sizeof(double) * (size_t)n);
        double *w1 = malloc(sizeof(double) * (size_t)n);
        double *w2 = malloc(sizeof(double) * (size_t)n);
        if (!src || !a || !w0 || !w1 || !w2) return 3;
        fill_symmetric(src, n);
        if (run_dsyev(src, a, w0, n) || run_dsyevd(src, a, w1, n) || run_dsyevr(src, a, w2, n)) return 4;
        double max_d = 0.0, max_r = 0.0;
        for (int i = 0; i < n; ++i) {
            double dd = fabs(w1[i] - w0[i]);
            double dr = fabs(w2[i] - w0[i]);
            if (dd > max_d) max_d = dd;
            if (dr > max_r) max_r = dr;
        }
        double sy[rounds], sd[rounds], sr[rounds];
        for (int round = 0; round < rounds; ++round) {
            /* Rotate order to avoid consistently rewarding the first driver. */
            int order = round % 3;
            if (order == 0) {
                sy[round] = time_driver(run_dsyev, src, a, w0, n, iterations);
                sd[round] = time_driver(run_dsyevd, src, a, w1, n, iterations);
                sr[round] = time_driver(run_dsyevr, src, a, w2, n, iterations);
            } else if (order == 1) {
                sd[round] = time_driver(run_dsyevd, src, a, w1, n, iterations);
                sr[round] = time_driver(run_dsyevr, src, a, w2, n, iterations);
                sy[round] = time_driver(run_dsyev, src, a, w0, n, iterations);
            } else {
                sr[round] = time_driver(run_dsyevr, src, a, w2, n, iterations);
                sy[round] = time_driver(run_dsyev, src, a, w0, n, iterations);
                sd[round] = time_driver(run_dsyevd, src, a, w1, n, iterations);
            }
        }
        printf("%d,%d,%.6f,%.6f,%.6f,%.3e,%.3e\n", n, iterations,
               median(sy, rounds), median(sd, rounds), median(sr, rounds), max_d, max_r);
        fflush(stdout);
        free(src); free(a); free(w0); free(w1); free(w2);
    }
    return 0;
}

#pragma clang diagnostic pop
