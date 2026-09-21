/* Force-included (-include) ahead of every runtime source for wasm32-wasi.
 *
 * wasi-libc already covers most of POSIX (with the _WASI_EMULATED_* switches
 * the build passes). This header declares only what it leaves out, so
 * runtime.c compiles UNMODIFIED; every function declared here is defined in
 * wasm/wasi_stubs.c as an inert stub that fails politely (ENOSYS / NULL / -1).
 * A public REPL must not reach processes, sockets, signals or dlopen anyway. */
#ifndef TUNGSTEN_WASI_COMPAT_H
#define TUNGSTEN_WASI_COMPAT_H
#ifdef __wasi__

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <signal.h>
#include <dlfcn.h>
#include <sys/socket.h>

/* ---- signals: wasi-libc's emulation has signal()/raise() but no sigaction -- */
#ifndef SA_RESTART
#define SA_RESTART 0x10000000
#define SA_SIGINFO 4
#define SA_NODEFER 0x40000000
#define SA_RESETHAND 0x80000000
#define SA_ONSTACK 0x08000000
typedef struct { int si_signo, si_errno, si_code; void *si_addr; } w_wasi_siginfo_t;
#define siginfo_t w_wasi_siginfo_t
struct sigaction {
    union {
        void (*sa_handler)(int);
        void (*sa_sigaction)(int, siginfo_t *, void *);
    } __sa_handler;
    sigset_t sa_mask;
    int sa_flags;
};
#define sa_handler   __sa_handler.sa_handler
#define sa_sigaction __sa_handler.sa_sigaction
int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact);
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int signum);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int pthread_sigmask(int how, const sigset_t *set, sigset_t *oldset);
int kill(pid_t pid, int sig);
#ifndef SIG_BLOCK
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2
#endif
#endif

/* ---- return addresses: wasm code is not addressable, and clang rejects the
 * builtin outright off Emscripten. runtime.c only prints it as a debugging
 * hint (`caller=main+N`) in two fatal messages. */
#define __builtin_return_address(level) ((void *)0)

/* ---- dladdr ---------------------------------------------------------- */
typedef struct {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
} Dl_info;
int dladdr(const void *addr, Dl_info *info);

/* ---- socket options wasi-libc does not name --------------------------- */
#ifndef SO_REUSEADDR
#define SO_REUSEADDR 2
#endif
#ifndef SO_RCVTIMEO
#define SO_RCVTIMEO 66
#endif
#ifndef SO_SNDTIMEO
#define SO_SNDTIMEO 67
#endif
#ifndef SO_SNDBUF
#define SO_SNDBUF 7
#endif
#ifndef SO_RCVBUF
#define SO_RCVBUF 8
#endif
#ifndef SO_ERROR
#define SO_ERROR 4
#endif
#ifndef SO_KEEPALIVE
#define SO_KEEPALIVE 9
#endif
#ifndef SO_REUSEPORT
#define SO_REUSEPORT 15
#endif

/* ---- ccall_nobox ABI adapters -------------------------------------------
 * `ccall_nobox` call sites pass every argument as a raw i64. Natively a C
 * callee declared with int / uint32_t / pointer parameters still works
 * (arguments travel in full-width registers); WebAssembly type-checks calls,
 * so such a callee would link as a trapping stub. The C definitions below are
 * renamed here and re-exported under their public names with an all-i64
 * signature by wasm/wasi_stubs.c. The link runs with --fatal-warnings, so a
 * new mismatch fails the BUILD (add it here) instead of trapping at run time. */
#define w_body_arena_get        w_body_arena_get__c
#define w_location_file_offset  w_location_file_offset__c
#define w_big_array_view        w_big_array_view__c

#endif /* __wasi__ */
#endif
