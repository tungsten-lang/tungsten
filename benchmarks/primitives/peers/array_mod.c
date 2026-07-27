#include <stdio.h>
#include <time.h>
#include <stdint.h>
// Wraparound (masked-index) array read: `tab[i & 1023]` in a flat loop. The
// volatile n keeps the trip count runtime-unknown (a constant lets LLVM
// restructure by period). Mirrors array_mod.w.
int main(void){ struct timespec t0,t1; volatile int64_t vn=1000000000; int64_t n=vn,chk=0;
 static int64_t tab[1024];
 for(int j=0;j<1024;j++) tab[j]=(int64_t)j*2654435761LL;
 clock_gettime(CLOCK_MONOTONIC,&t0);
 for(int64_t i=0;i<n;i++) chk^=tab[i&1023];
 clock_gettime(CLOCK_MONOTONIC,&t1);
 double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
 printf("%lld\nops: %lld\nelapsed: %.6fs\n",(long long)chk,(long long)n,el); return 0; }
