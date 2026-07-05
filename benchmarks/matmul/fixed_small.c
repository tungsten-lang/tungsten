// Fixed 3x3 / 4x4 schoolbook throughput in C at Tungsten's --release flags.
// This is the "ideal" the Tungsten Mat3/Mat4 `*` operator is measured against
// (tungsten_matmul.w) — the fully-unrolled, FMA-fused, no-allocation lower
// bound. The gap between this and Tungsten's Mat3/Mat4 is pure abstraction
// overhead (operator dispatch + per-call heap allocation), not arithmetic.

#include <stdio.h>
#include <time.h>

static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec + t.tv_nsec*1e-9; }

static inline void mm3(const double *a, const double *b, double *c){
    for (int i=0;i<3;i++) for (int j=0;j<3;j++)
        c[i*3+j] = a[i*3+0]*b[0*3+j] + a[i*3+1]*b[1*3+j] + a[i*3+2]*b[2*3+j];
}
static inline void mm4(const double *a, const double *b, double *c){
    for (int i=0;i<4;i++) for (int j=0;j<4;j++)
        c[i*4+j] = a[i*4+0]*b[0*4+j] + a[i*4+1]*b[1*4+j] + a[i*4+2]*b[2*4+j] + a[i*4+3]*b[3*4+j];
}

int main(void){
    double a3[9],b3[9],c3[9]; for (int i=0;i<9;i++){a3[i]=i+1; b3[i]=9-i;}
    double a4[16],b4[16],c4[16]; for (int i=0;i<16;i++){a4[i]=i*0.5+1; b4[i]=16-i;}
    long N=200000000; double acc=0,t;
    // `a3[0]=c3[0]*1e-12+1` keeps each result live (defeats DCE) without
    // perturbing the values meaningfully.
    t=now(); for (long i=0;i<N;i++){ mm3(a3,b3,c3); a3[0]=c3[0]*1e-12+1; acc+=c3[0]; } t=now()-t;
    printf("3x3 schoolbook: %.3f ns/op  (%.0f M matmul/s)   acc=%.3g\n", t/N*1e9, N/t/1e6, acc);
    acc=0;
    t=now(); for (long i=0;i<N;i++){ mm4(a4,b4,c4); a4[0]=c4[0]*1e-12+1; acc+=c4[0]; } t=now()-t;
    printf("4x4 schoolbook: %.3f ns/op  (%.0f M matmul/s)   acc=%.3g\n", t/N*1e9, N/t/1e6, acc);
    return 0;
}
