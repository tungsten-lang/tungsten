#include <regex.h>
#include <stdio.h>
#include <time.h>
int main(void){
  const char *subj = "the order id is 4521-9837 today";
  regex_t re; regmatch_t m[3];
  regcomp(&re, "([0-9]+)-([0-9]+)", REG_EXTENDED);
  long n = 5000000, hits = 0;
  regexec(&re, subj, 3, m, 0); /* warm */
  struct timespec a,b; clock_gettime(CLOCK_MONOTONIC,&a);
  for(long i=0;i<n;i++) if(regexec(&re, subj, 3, m, 0)==0) hits++;
  clock_gettime(CLOCK_MONOTONIC,&b);
  double ms=(b.tv_sec-a.tv_sec)*1e3+(b.tv_nsec-a.tv_nsec)/1e6;
  printf("posix (libc C): %.0f ms / %ld matches = %.0f ns/match  (hits %ld)\n", ms, n, ms*1e6/n, hits);
  return 0;
}
