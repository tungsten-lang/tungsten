// NxN matrix-multiply algorithm sweep — schoolbook vs Strassen vs Accelerate.
//
// Built at Tungsten's --release flags (-O3 -DNDEBUG -march=native -mtune=native
// -flto). Tungsten emits LLVM IR -> clang with these flags, so same-flags C is
// a faithful stand-in for Tungsten's backend codegen for a general matmul.
//
// Row-major, double precision. Strassen is verified against schoolbook each
// run (max abs err printed); dgemm against schoolbook.

#define ACCELERATE_NEW_LAPACK 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <Accelerate/Accelerate.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// C = A*B, schoolbook, ikj order so the inner loop is a contiguous FMA stream.
static void school(const double *A, const double *B, double *C, int n) {
    memset(C, 0, (size_t)n * n * sizeof(double));
    for (int i = 0; i < n; i++) {
        const double *Ai = A + (size_t)i * n;
        double *Ci = C + (size_t)i * n;
        for (int k = 0; k < n; k++) {
            double a = Ai[k];
            const double *Bk = B + (size_t)k * n;
            for (int j = 0; j < n; j++) Ci[j] += a * Bk[j];
        }
    }
}

// Strassen, recursive, square power-of-two; base case -> schoolbook. Quadrants
// are gathered into contiguous scratch so the recursion is stride-clean.
#define STRASSEN_BASE 64
static void strassen(const double *A, const double *B, double *C, int n) {
    if (n <= STRASSEN_BASE) { school(A, B, C, n); return; }
    int h = n / 2; size_t hh = (size_t)h * h;
    double *q = malloc(hh * 8 * sizeof(double));
    double *a11=q,*a12=q+hh,*a21=q+2*hh,*a22=q+3*hh;
    double *b11=q+4*hh,*b12=q+5*hh,*b21=q+6*hh,*b22=q+7*hh;
    for (int i=0;i<h;i++) for (int j=0;j<h;j++) {
        a11[(size_t)i*h+j]=A[(size_t)i*n+j];      a12[(size_t)i*h+j]=A[(size_t)i*n+j+h];
        a21[(size_t)i*h+j]=A[(size_t)(i+h)*n+j];  a22[(size_t)i*h+j]=A[(size_t)(i+h)*n+j+h];
        b11[(size_t)i*h+j]=B[(size_t)i*n+j];      b12[(size_t)i*h+j]=B[(size_t)i*n+j+h];
        b21[(size_t)i*h+j]=B[(size_t)(i+h)*n+j];  b22[(size_t)i*h+j]=B[(size_t)(i+h)*n+j+h];
    }
    double *t1=malloc(hh*sizeof(double)),*t2=malloc(hh*sizeof(double));
    double *m1=malloc(hh*sizeof(double)),*m2=malloc(hh*sizeof(double)),*m3=malloc(hh*sizeof(double));
    double *m4=malloc(hh*sizeof(double)),*m5=malloc(hh*sizeof(double)),*m6=malloc(hh*sizeof(double)),*m7=malloc(hh*sizeof(double));
    #define A2(X,Y,Z) for(size_t z=0;z<hh;z++)(Z)[z]=(X)[z]+(Y)[z]
    #define S2(X,Y,Z) for(size_t z=0;z<hh;z++)(Z)[z]=(X)[z]-(Y)[z]
    A2(a11,a22,t1); A2(b11,b22,t2); strassen(t1,t2,m1,h);
    A2(a21,a22,t1);                 strassen(t1,b11,m2,h);
    S2(b12,b22,t2);                 strassen(a11,t2,m3,h);
    S2(b21,b11,t2);                 strassen(a22,t2,m4,h);
    A2(a11,a12,t1);                 strassen(t1,b22,m5,h);
    S2(a21,a11,t1); A2(b11,b12,t2); strassen(t1,t2,m6,h);
    S2(a12,a22,t1); A2(b21,b22,t2); strassen(t1,t2,m7,h);
    for (int i=0;i<h;i++) for (int j=0;j<h;j++) {
        size_t z=(size_t)i*h+j;
        C[(size_t)i*n+j]       = m1[z]+m4[z]-m5[z]+m7[z];
        C[(size_t)i*n+j+h]     = m3[z]+m5[z];
        C[(size_t)(i+h)*n+j]   = m2[z]+m4[z];
        C[(size_t)(i+h)*n+j+h] = m1[z]-m2[z]+m3[z]+m6[z];
    }
    free(q);free(t1);free(t2);free(m1);free(m2);free(m3);free(m4);free(m5);free(m6);free(m7);
}

static double maxdiff(const double *X, const double *Y, int n) {
    double d=0; for (size_t i=0;i<(size_t)n*n;i++){double e=fabs(X[i]-Y[i]); if(e>d)d=e;} return d;
}

int main(void) {
    int sizes[] = {8,16,32,64,128,256,512};
    int ns = sizeof(sizes)/sizeof(int);
    printf("%5s %11s %10s %12s %10s %10s %10s\n",
           "N","school ms","school GF","strassen ms","strass GF","dgemm ms","dgemm GF");
    for (int s=0;s<ns;s++) {
        int n=sizes[s]; size_t nn=(size_t)n*n;
        double *A=malloc(nn*sizeof(double)),*B=malloc(nn*sizeof(double));
        double *C=malloc(nn*sizeof(double)),*D=malloc(nn*sizeof(double)),*E=malloc(nn*sizeof(double));
        for (size_t i=0;i<nn;i++){A[i]=sin(0.001*i)+0.5; B[i]=cos(0.002*i)+0.5;}
        double flops=2.0*n*n*n;
        long target=(long)(2.0e8/(double)n/n/n); if(target<1)target=1;
        double t,best;

        school(A,B,C,n);  // warmup + reference
        best=1e30; for(int r=0;r<3;r++){t=now_s(); for(long it=0;it<target;it++) school(A,B,C,n); t=now_s()-t; if(t<best)best=t;}
        double sch_ms=best/target*1e3, sch_gf=flops/(best/target)/1e9;

        strassen(A,B,D,n);  // warmup
        best=1e30; for(int r=0;r<3;r++){t=now_s(); for(long it=0;it<target;it++) strassen(A,B,D,n); t=now_s()-t; if(t<best)best=t;}
        double str_ms=best/target*1e3, str_gf=flops/(best/target)/1e9;

        cblas_dgemm(CblasRowMajor,CblasNoTrans,CblasNoTrans,n,n,n,1.0,A,n,B,n,0.0,E,n);  // warmup (Accelerate lazy-init)
        long bt=target*4; if(bt<4)bt=4;
        best=1e30; for(int r=0;r<3;r++){t=now_s(); for(long it=0;it<bt;it++) cblas_dgemm(CblasRowMajor,CblasNoTrans,CblasNoTrans,n,n,n,1.0,A,n,B,n,0.0,E,n); t=now_s()-t; if(t<best)best=t;}
        double dg_ms=best/bt*1e3, dg_gf=flops/(best/bt)/1e9;

        printf("%5d %11.4f %10.2f %12.4f %10.2f %10.4f %10.2f   [strassen err %.1e, dgemm err %.1e]\n",
               n,sch_ms,sch_gf,str_ms,str_gf,dg_ms,dg_gf, maxdiff(C,D,n), maxdiff(C,E,n));
        free(A);free(B);free(C);free(D);free(E);
    }
    return 0;
}
