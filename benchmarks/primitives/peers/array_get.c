#include <stdio.h>
#include <time.h>
#include <stdint.h>
// Sequential element read over a fixed [1024] stack array, nested reps times.
// `tab[k]+r` varies each outer pass so the reduction can't be shortcut; the
// volatile seed keeps the contents runtime-unknown. Mirrors array_get.w.
int main(void){ struct timespec t0,t1; volatile int64_t vseed=976562; int64_t reps=vseed;
 static int64_t tab[1024];
 for(int j=0;j<1024;j++) tab[j]=(int64_t)j*2654435761LL+reps;
 clock_gettime(CLOCK_MONOTONIC,&t0);
 int64_t chk=reps;
 for(int64_t r=0;r<reps;r++) for(int k=0;k<1024;k++) chk^=tab[k]+r;
 clock_gettime(CLOCK_MONOTONIC,&t1);
 int64_t ops=reps*1024;
 double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
 printf("%lld\nops: %lld\nelapsed: %.6fs\n",(long long)chk,(long long)ops,el); return 0; }
