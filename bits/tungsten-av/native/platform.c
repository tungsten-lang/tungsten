/* POSIX plumbing for the native Tungsten AV library. Policy lives in the Tungsten library. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "runtime.h"
#include "wvalue.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
#include <sys/clonefile.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#endif
extern double w_num_to_f64(WValue);
static const char *av_str(WValue v) {
  static _Thread_local char buffers[8][65536]; static _Thread_local unsigned slot;
  char small[6]; const char *s; size_t n; w_str_data(v,small,&s,&n);
  if(n>=sizeof buffers[0] || memchr(s,0,n)) { w_raise(w_string("AV: invalid or oversized process/path string")); return ""; }
  char *b=buffers[slot++%8]; memcpy(b,s,n); b[n]=0; return b;
}
static WValue av_error(const char *s) { char b[1024]; snprintf(b,sizeof b,"AV: %s: %s",s,strerror(errno)); w_raise(w_string(b)); return W_NIL; }
static double av_clock(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
WValue w_av_pid(void) { return w_int(getpid()); }
WValue w_av_now(void) { struct timespec t; clock_gettime(CLOCK_REALTIME,&t); return w_float(t.tv_sec+t.tv_nsec/1e9); }
WValue w_av_pause(WValue ms) { double t=w_num_to_f64(ms); struct timespec ts={(time_t)(t/1000),(long)(fmod(t,1000)*1000000)}; nanosleep(&ts,NULL); return W_NIL; }
WValue w_av_lock(WValue path) { int fd=open(av_str(path),O_CREAT|O_RDWR|O_CLOEXEC,0600); if(fd<0) return av_error("open lock"); if(flock(fd,LOCK_EX|LOCK_NB)<0) { close(fd); return w_int(-1); } return w_int(fd); }
WValue w_av_unlock(WValue fd) { close((int)w_as_int(fd)); return W_NIL; }
WValue w_av_sync(WValue path) { int fd=open(av_str(path),O_RDONLY|O_CLOEXEC); if(fd<0) return av_error("open for sync"); int r=fsync(fd); close(fd); if(r<0) return av_error("fsync"); return W_NIL; }
WValue w_av_free(WValue path) { struct statvfs s; if(statvfs(av_str(path),&s)<0) return av_error("statvfs"); return w_int((int64_t)s.f_bavail*s.f_frsize); }
WValue w_av_memory(void) {
#ifdef __APPLE__
  mach_msg_type_number_t count=HOST_VM_INFO64_COUNT; vm_statistics64_data_t v; vm_size_t page; host_page_size(mach_host_self(),&page);
  uint64_t physical=0; size_t len=sizeof physical; sysctlbyname("hw.memsize",&physical,&len,NULL,0);
  if(host_statistics64(mach_host_self(),HOST_VM_INFO64,(host_info64_t)&v,&count)==KERN_SUCCESS) { uint64_t n=(v.free_count+v.inactive_count+v.speculative_count)*(uint64_t)page; return w_int(n<physical/2?n:physical/2); }
#endif
  return w_int(2LL*1024*1024*1024);
}
WValue w_av_sha256(WValue path) {
#ifdef __APPLE__
  int fd=open(av_str(path),O_RDONLY|O_CLOEXEC); if(fd<0) return av_error("open SHA256 input"); CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); unsigned char block[65536],digest[32]; ssize_t n;
  while((n=read(fd,block,sizeof block))>0) CC_SHA256_Update(&ctx,block,(CC_LONG)n);
  int saved=errno; close(fd); errno=saved; if(n<0) return av_error("read SHA256 input"); CC_SHA256_Final(digest,&ctx); char hex[65]; for(int i=0;i<32;i++) snprintf(hex+2*i,3,"%02x",digest[i]); return w_string(hex);
#else
  w_raise(w_string("native AV file hashing requires macOS")); return W_NIL;
#endif
}
WValue w_av_copy(WValue src,WValue dst) {
  const char *s=av_str(src),*d=av_str(dst); int cloned=0;
#ifdef __APPLE__
  if(clonefile(s,d,0)==0) cloned=1;
#endif
  if(!cloned) { int in=open(s,O_RDONLY|O_CLOEXEC); if(in<0) return av_error("open copy input"); int out=open(d,O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC,0600); if(out<0) { close(in); return av_error("create copy"); } unsigned char block[65536]; ssize_t n; int failed=0;
    while((n=read(in,block,sizeof block))>0) { ssize_t p=0; while(p<n) { ssize_t k=write(out,block+p,n-p); if(k<0&&errno==EINTR) continue; if(k<=0) { failed=1; break; } p+=k; } if(failed) break; }
    if(n<0) failed=1; if(fsync(out)<0) failed=1; close(in); close(out); if(failed) { unlink(d); return av_error("copy"); }
  } else { WValue r=w_av_sync(dst); (void)r; }
  return w_string(cloned?"clone":"copy");
}
static volatile sig_atomic_t av_cancel=0;
static void av_signal(int sig) { av_cancel=sig; }
WValue w_av_run(WValue args,WValue cwd,WValue environment,WValue outpath,WValue errpath,WValue timeout) {
  WArray *a=w_as_array(args),*e=w_as_array(environment); if(a->size<1) { errno=EINVAL; return av_error("empty argv"); }
  char **argv=calloc(a->size+1,sizeof(char *)); if(!argv) return av_error("argv allocation");
  for(int i=0;i<a->size;i++) argv[i]=strdup(av_str(((WValue *)a->slots)[a->start+i]));
  int out=open(av_str(outpath),O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC,0600),err=open(av_str(errpath),O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC,0600);
  if(out<0||err<0) { if(out>=0)close(out); if(err>=0)close(err); for(int i=0;i<a->size;i++)free(argv[i]);free(argv);return av_error("open process logs"); }
  struct sigaction act={0},oldint,oldterm; act.sa_handler=av_signal; sigemptyset(&act.sa_mask); av_cancel=0; sigaction(SIGINT,&act,&oldint); sigaction(SIGTERM,&act,&oldterm);
  /* Build child environment in the parent; posix_spawn avoids running the
   * language allocator or framework state after fork in a threaded process. */
  extern char **environ;size_t inherited=0;while(environ[inherited])inherited++;
  char **envp=calloc(inherited+e->size+2,sizeof(char *));size_t envn=0;
  if(!envp){sigaction(SIGINT,&oldint,NULL);sigaction(SIGTERM,&oldterm,NULL);close(out);close(err);for(int i=0;i<a->size;i++)free(argv[i]);free(argv);return av_error("environment allocation");}
  for(size_t i=0;i<inherited;i++){
    int override=!strncmp(environ[i],"TUNGSTEN_INHERIT_PROCESS_GROUP=",strlen("TUNGSTEN_INHERIT_PROCESS_GROUP="));
    for(int j=0;j<e->size;j++){WArray *pair=w_as_array(e->slots[e->start+j]);const char *key=av_str(pair->slots[pair->start]);size_t n=strlen(key);if(!strncmp(environ[i],key,n)&&environ[i][n]=='=')override=1;}
    if(!override)envp[envn++]=strdup(environ[i]);
  }
  envp[envn++]=strdup("TUNGSTEN_INHERIT_PROCESS_GROUP=1");
  for(int j=0;j<e->size;j++){WArray *pair=w_as_array(e->slots[e->start+j]);const char *key=av_str(pair->slots[pair->start]),*value=av_str(pair->slots[pair->start+1]);size_t n=strlen(key)+strlen(value)+2;envp[envn]=malloc(n);if(envp[envn])snprintf(envp[envn],n,"%s=%s",key,value);envn++;}
  posix_spawnattr_t attr;posix_spawn_file_actions_t actions;posix_spawnattr_init(&attr);posix_spawn_file_actions_init(&actions);
  sigset_t defaults;sigemptyset(&defaults);sigaddset(&defaults,SIGINT);sigaddset(&defaults,SIGTERM);
  posix_spawnattr_setsigdefault(&attr,&defaults);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_SETSIGDEF);posix_spawnattr_setpgroup(&attr,0);
#ifdef __APPLE__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  /* The _np spelling supports the macOS 15 deployment target too. */
  int spawn_error=posix_spawn_file_actions_addchdir_np(&actions,av_str(cwd));
#ifdef __APPLE__
#pragma clang diagnostic pop
#endif
  if(!spawn_error)spawn_error=posix_spawn_file_actions_addopen(&actions,0,"/dev/null",O_RDONLY,0);
  if(!spawn_error)spawn_error=posix_spawn_file_actions_adddup2(&actions,out,1);
  if(!spawn_error)spawn_error=posix_spawn_file_actions_adddup2(&actions,err,2);
  if(!spawn_error)spawn_error=posix_spawn_file_actions_addclose(&actions,out);
  if(!spawn_error)spawn_error=posix_spawn_file_actions_addclose(&actions,err);
  pid_t pid=-1;if(!spawn_error)spawn_error=posix_spawnp(&pid,argv[0],&actions,&attr,argv,envp);
  posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr);close(out);close(err);
  for(int i=0;i<a->size;i++)free(argv[i]);free(argv);for(size_t i=0;i<envn;i++)free(envp[i]);free(envp);
  if(spawn_error){sigaction(SIGINT,&oldint,NULL);sigaction(SIGTERM,&oldterm,NULL);errno=spawn_error;return av_error("spawn");}
  double start=av_clock(),seconds=w_num_to_f64(timeout);int status=0,timed=0; struct rusage usage={0};
  for(;;) { pid_t r=wait4(pid,&status,WNOHANG,&usage); if(r==pid)break; if(r<0&&errno!=EINTR){status=127<<8;break;} if(av_cancel||(seconds>0&&av_clock()-start>seconds)) { timed=!av_cancel; kill(-pid,SIGTERM); struct timespec pause={0,20000000}; double until=av_clock()+0.5; while(av_clock()<until)nanosleep(&pause,NULL);kill(-pid,SIGKILL);while(wait4(pid,&status,0,&usage)<0&&errno==EINTR){}break;} struct timespec pause={0,20000000};nanosleep(&pause,NULL); }
  /* Reap/stop any background descendants even after their leader exited. */
  kill(-pid,SIGKILL);sigaction(SIGINT,&oldint,NULL);sigaction(SIGTERM,&oldterm,NULL);
  int code=timed?124:av_cancel?128+av_cancel:WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
  WValue result=w_array_new_empty();result=w_array_push(result,w_int(code));
#ifdef __APPLE__
  result=w_array_push(result,w_int(usage.ru_maxrss));
#else
  result=w_array_push(result,w_int(usage.ru_maxrss*1024));
#endif
  return result;
}
/* Streamed PCM statistics: no film-sized allocation. */
WValue w_av_pcm_stats(WValue path,WValue channel_value,WValue threshold_value) {
  int channels=(int)w_as_int(channel_value);if(channels<1||channels>2){errno=EINVAL;return av_error("PCM channels");} FILE *f=fopen(av_str(path),"rb");if(!f)return av_error("open PCM");double energy[2]={0},threshold=w_num_to_f64(threshold_value);int64_t frames=0,clip=0,run=0,longest=0;float block[8192];size_t n;
  while((n=fread(block,sizeof(float),8192,f))>0){if(n%channels){fclose(f);w_raise(w_string("partial PCM frame"));return W_NIL;}for(size_t i=0;i<n;i+=channels){double peak=0;for(int c=0;c<channels;c++){double x=block[i+c];if(!isfinite(x)){fclose(f);w_raise(w_string("nonfinite decoded audio"));return W_NIL;}energy[c]+=x*x;if(fabs(x)>=1.0-1.0/32768)clip++;if(fabs(x)>peak)peak=fabs(x);}frames++;if(peak<threshold){run++;if(run>longest)longest=run;}else run=0;}}
  if(ferror(f)){fclose(f);return av_error("read PCM");}fclose(f);WValue r=w_array_new_empty();r=w_array_push(r,w_int(frames));r=w_array_push(r,w_int(clip));r=w_array_push(r,w_int(longest));for(int c=0;c<channels;c++)r=w_array_push(r,w_float(energy[c]));return r;
}
