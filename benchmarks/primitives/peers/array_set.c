#include <stdio.h>
#include <time.h>
#include <stdint.h>
// Sequential element write over a fixed [1024] stack array, nested reps times.
// The loop-carried chk + final read-back keep the stores from being dead-code
// eliminated; the volatile seed keeps reps runtime-unknown. Mirrors array_set.w.
int main(void){ struct timespec t0,t1; volatile int64_t vseed=976562; int64_t reps=vseed;
 static int64_t tab[1024];
 clock_gettime(CLOCK_MONOTONIC,&t0);
 int64_t chk=reps;
 for(int64_t r=0;r<reps;r++) for(int64_t k=0;k<1024;k++){ tab[k]=chk^k; chk=chk+1; }
 clock_gettime(CLOCK_MONOTONIC,&t1);
 int64_t out=chk^tab[0]^tab[1023];
 int64_t ops=reps*1024;
 double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
 printf("%lld\nops: %lld\nelapsed: %.6fs\n",(long long)out,(long long)ops,el); return 0; }
