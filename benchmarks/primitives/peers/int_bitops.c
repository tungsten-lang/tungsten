#include <stdio.h>
#include <time.h>
#include <stdint.h>
int main(void){ struct timespec t0,t1; int64_t n=300000000,s=1;
 clock_gettime(CLOCK_MONOTONIC,&t0);
 for(int64_t i=0;i<n;i++) s=(s<<13)^(s>>7)^i;
 clock_gettime(CLOCK_MONOTONIC,&t1);
 double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
 printf("%lld\nops: %lld\nelapsed: %.6fs\n",(long long)s,(long long)n,el); return 0; }
