#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
int main(void){ struct timespec t0,t1; clock_gettime(CLOCK_MONOTONIC,&t0);
  long n=400000; const char*w="abcdefghijklmnopqrstuvwxyz"; size_t wl=26,cap=64,len=0; char*s=malloc(cap);
  for(long i=0;i<n;i++){ while(len+wl>cap){cap*=2;s=realloc(s,cap);} memcpy(s+len,w,wl); len+=wl; }
  clock_gettime(CLOCK_MONOTONIC,&t1); double el=(t1.tv_sec-t0.tv_sec)+(t1.tv_nsec-t0.tv_nsec)/1e9;
  printf("%zu\n",len); printf("elapsed: %.6fs\n",el); free(s); return 0; }
