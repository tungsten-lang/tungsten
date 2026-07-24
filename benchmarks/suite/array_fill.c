#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdint.h>
int main(void){
  struct timespec t0,t1; clock_gettime(CLOCK_MONOTONIC,&t0);
  long n=1000000, rounds=200;
  int64_t *a=malloc(n*sizeof(int64_t));
  int64_t chk=0;
  for(int64_t r=0;r<rounds;r++){
    for(int64_t i=0;i<n;i++) a[i]=i*2654435761LL+r;
    chk^=a[(r*7)%n];
  }
  clock_gettime(CLOCK_MONOTONIC,&t1);
  double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
  printf("%lld\n",(long long)chk); printf("elapsed: %.6fs\n",el);
  free(a); return 0;
}
