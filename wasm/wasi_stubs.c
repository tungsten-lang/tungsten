/* wasm32-wasi stubs for everything the Tungsten runtime references that WASI
 * (or a public, sandboxed REPL) cannot provide. Every stub is INERT and fails
 * politely: it sets errno and returns the POSIX failure value, so runtime.c's
 * normal error paths turn it into a catchable Tungsten error — never a trap.
 *
 * Groups:
 *   1. processes        fork/exec/spawn/wait/popen/system      -> ENOSYS
 *   2. signals          sigaction & friends                    -> no-ops
 *   3. sockets / DNS    socket/connect/getaddrinfo/...         -> ENOSYS
 *   4. dlopen family    dladdr                                 -> not found
 *   5. stack switching  ucontext (goroutines)                  -> ENOSYS
 *   6. backtraces       execinfo                               -> empty
 *   7. runtime files left out of the wasm build (event loop, terminal input,
 *      Metal/BLAS/HID bridges)                                 -> see below
 */
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <spawn.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <execinfo.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <unistd.h>
#include "runtime.h"

/* ---- 1. processes --------------------------------------------------- */
static int w_wasi_nosys(void) { errno = ENOSYS; return -1; }

pid_t fork(void) { return w_wasi_nosys(); }
pid_t vfork(void) { return w_wasi_nosys(); }
pid_t waitpid(pid_t pid, int *status, int options) { (void)pid; (void)status; (void)options; errno = ECHILD; return -1; }
pid_t wait(int *status) { (void)status; errno = ECHILD; return -1; }
int execv(const char *p, char *const a[]) { (void)p; (void)a; return w_wasi_nosys(); }
int execvp(const char *p, char *const a[]) { (void)p; (void)a; return w_wasi_nosys(); }
int execve(const char *p, char *const a[], char *const e[]) { (void)p; (void)a; (void)e; return w_wasi_nosys(); }
int execl(const char *p, const char *a, ...) { (void)p; (void)a; return w_wasi_nosys(); }
int execlp(const char *p, const char *a, ...) { (void)p; (void)a; return w_wasi_nosys(); }
int system(const char *cmd) { (void)cmd; return w_wasi_nosys(); }
FILE *popen(const char *cmd, const char *mode) { (void)cmd; (void)mode; errno = ENOSYS; return NULL; }
int pclose(FILE *f) { (void)f; return w_wasi_nosys(); }
int pipe(int fds[2]) { (void)fds; return w_wasi_nosys(); }
int dup(int fd) { (void)fd; return w_wasi_nosys(); }
int dup2(int a, int b) { (void)a; (void)b; return w_wasi_nosys(); }
int kill(pid_t pid, int sig) { (void)pid; (void)sig; return w_wasi_nosys(); }
pid_t setsid(void) { return w_wasi_nosys(); }
int setpgid(pid_t a, pid_t b) { (void)a; (void)b; return w_wasi_nosys(); }
pid_t getppid(void) { return 1; }

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *fa,
                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    (void)pid; (void)path; (void)fa; (void)attr; (void)argv; (void)envp; return ENOSYS;
}
int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *fa,
                 const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    (void)pid; (void)file; (void)fa; (void)attr; (void)argv; (void)envp; return ENOSYS;
}
int posix_spawn_file_actions_init(posix_spawn_file_actions_t *fa) { (void)fa; return 0; }
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *fa) { (void)fa; return 0; }
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *fa, int fd, int newfd) { (void)fa; (void)fd; (void)newfd; return 0; }
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *fa, int fd) { (void)fa; (void)fd; return 0; }
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *fa, int fd, const char *path, int oflag, mode_t mode) {
    (void)fa; (void)fd; (void)path; (void)oflag; (void)mode; return 0;
}
int posix_spawnattr_init(posix_spawnattr_t *attr) { (void)attr; return 0; }
int posix_spawnattr_destroy(posix_spawnattr_t *attr) { (void)attr; return 0; }
int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags) { (void)attr; (void)flags; return 0; }
int posix_spawnattr_setpgroup(posix_spawnattr_t *attr, pid_t pgroup) { (void)attr; (void)pgroup; return 0; }
int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr, const sigset_t *s) { (void)attr; (void)s; return 0; }
int posix_spawnattr_setsigmask(posix_spawnattr_t *attr, const sigset_t *s) { (void)attr; (void)s; return 0; }

/* ---- 2. signals ----------------------------------------------------- */
int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact) {
    (void)signum; (void)act;
    if (oldact) memset(oldact, 0, sizeof(*oldact));
    return 0;
}
int sigemptyset(sigset_t *set) { if (set) memset(set, 0, sizeof(*set)); return 0; }
int sigfillset(sigset_t *set) { if (set) memset(set, 0xff, sizeof(*set)); return 0; }
int sigaddset(sigset_t *set, int signum) { (void)set; (void)signum; return 0; }
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset) { (void)how; (void)set; (void)oldset; return 0; }
int pthread_sigmask(int how, const sigset_t *set, sigset_t *oldset) { (void)how; (void)set; (void)oldset; return 0; }

/* ---- 3. DNS --------------------------------------------------------- */
int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    (void)node; (void)service; (void)hints;
    if (res) *res = NULL;
    return EAI_FAIL;
}
void freeaddrinfo(struct addrinfo *res) { (void)res; }
const char *gai_strerror(int errcode) { (void)errcode; return "networking is unavailable on wasm32-wasi"; }
int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen,
                char *serv, socklen_t servlen, int flags) {
    (void)sa; (void)salen; (void)host; (void)hostlen; (void)serv; (void)servlen; (void)flags;
    return EAI_FAIL;
}

/* ---- 4. dladdr ------------------------------------------------------ */
int dladdr(const void *addr, Dl_info *info) { (void)addr; (void)info; return 0; }

/* ---- 5. stack switching (goroutines) -------------------------------- */
int getcontext(ucontext_t *ucp) { (void)ucp; return w_wasi_nosys(); }
int setcontext(const ucontext_t *ucp) { (void)ucp; return w_wasi_nosys(); }
int swapcontext(ucontext_t *o, const ucontext_t *n) { (void)o; (void)n; return w_wasi_nosys(); }
void makecontext(ucontext_t *ucp, void (*func)(void), int argc, ...) { (void)ucp; (void)func; (void)argc; }

/* ---- 6. backtraces -------------------------------------------------- */
int backtrace(void **buffer, int size) { (void)buffer; (void)size; return 0; }
char **backtrace_symbols(void *const *buffer, int size) { (void)buffer; (void)size; return NULL; }
void backtrace_symbols_fd(void *const *buffer, int size, int fd) { (void)buffer; (void)size; (void)fd; }

/* ---- 7. runtime sources left out of the wasm build --------------------
 * event_kqueue.c / event_epoll.c: no event loop. Only goroutine scheduling
 * reaches these, and goroutines cannot start (see group 5). */
void w_event_unregister(WEventLoop *el, int fd) { (void)el; (void)fd; }
int w_event_wake(WEventLoop *el) { (void)el; return -1; }
WEventDeadlineQueue *w_event_deadline_queue(WEventLoop *el) { (void)el; return NULL; }

/* terminal_input.c (termios): the only entry the image references. The host
 * shim decides: it reports stdout as a non-tty, so output carries no ANSI. */
WValue w_isatty_stdout(void) { return isatty(1) ? W_TRUE : W_FALSE; }

/* Odds and ends wasi-libc leaves out. */
int mkstemp(char *tmpl) { (void)tmpl; errno = EROFS; return -1; }
int pthread_atfork(void (*a)(void), void (*b)(void), void (*c)(void)) { (void)a; (void)b; (void)c; return 0; }
int getifaddrs(struct ifaddrs **ifap) { if (ifap) *ifap = NULL; errno = ENOSYS; return -1; }
void freeifaddrs(struct ifaddrs *ifa) { (void)ifa; }
/* `sleep` with no duration blocks forever natively; nothing could ever wake a
 * single-threaded wasm instance, so end the run instead of spinning. */
int pause(void) {
    fputs("\nerror: sleep without a duration would block forever (wasm32-wasi)\n", stderr);
    exit(1);
}

/* ---- 8. ccall_nobox ABI adapters (see wasm/compat/wasi_compat.h) ------ */
#undef w_body_arena_get
#undef w_location_file_offset
#undef w_big_array_view
WValue w_body_arena_get(int64_t offset, int64_t i) {
    return w_body_arena_get__c((uint32_t)offset, (uint32_t)i);
}
WValue w_location_file_offset(int64_t file_id, int64_t offset) {
    return w_location_file_offset__c((int)file_id, (int)offset);
}
WValue w_big_array_view(int64_t data, int64_t ebits, int64_t length) {
    return w_big_array_view__c((uint8_t *)(uintptr_t)data, ebits, length);
}

/* ---- 9. mmap ----------------------------------------------------------
 * wasi-libc's emulated mmap is malloc+memset and rejects PROT_NONE, which the
 * runtime uses to RESERVE its string slab. Linear memory gives the same
 * contract more cheaply: `memory.grow` hands back zero pages the host commits
 * lazily, so an anonymous mapping costs nothing until it is touched.
 *   anonymous   -> fresh wasm pages (64 KiB granularity); munmap parks them on
 *                  a free list that the next anonymous map of that size reuses
 *   file-backed -> malloc + pread (read-only snapshots; the tree is read-only)
 * mprotect / madvise are no-ops: there is no page protection to change. */
#include <sys/mman.h>
#define W_WASM_PAGE 65536u
typedef struct WasiMapping {
    void *addr;
    size_t pages;      /* 0 = malloc-backed file snapshot */
    int free;
} WasiMapping;
static WasiMapping *w_wasi_maps;
static size_t w_wasi_map_count, w_wasi_map_cap;

static WasiMapping *w_wasi_map_slot(void) {
    if (w_wasi_map_count == w_wasi_map_cap) {
        size_t cap = w_wasi_map_cap ? w_wasi_map_cap * 2 : 16;
        WasiMapping *grown = realloc(w_wasi_maps, cap * sizeof(*grown));
        if (!grown) return NULL;
        w_wasi_maps = grown;
        w_wasi_map_cap = cap;
    }
    return &w_wasi_maps[w_wasi_map_count++];
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    (void)addr; (void)prot;
    if (length == 0 || (flags & MAP_FIXED)) { errno = EINVAL; return MAP_FAILED; }
    if (flags & MAP_ANONYMOUS) {
        size_t pages = (length + W_WASM_PAGE - 1) / W_WASM_PAGE;
        for (size_t i = 0; i < w_wasi_map_count; i++) {
            WasiMapping *m = &w_wasi_maps[i];
            if (m->free && m->pages == pages) {
                m->free = 0;
                memset(m->addr, 0, pages * W_WASM_PAGE);
                return m->addr;
            }
        }
        WasiMapping *slot = w_wasi_map_slot();
        if (!slot) { errno = ENOMEM; return MAP_FAILED; }
        size_t old = __builtin_wasm_memory_grow(0, pages);
        if (old == (size_t)-1) { w_wasi_map_count--; errno = ENOMEM; return MAP_FAILED; }
        slot->addr = (void *)(old * W_WASM_PAGE);
        slot->pages = pages;
        slot->free = 0;
        return slot->addr;
    }
    char *buf = malloc(length);
    if (!buf) { errno = ENOMEM; return MAP_FAILED; }
    size_t got = 0;
    while (got < length) {
        ssize_t n = pread(fd, buf + got, length - got, offset + (off_t)got);
        if (n < 0) { free(buf); return MAP_FAILED; }
        if (n == 0) break;
        got += (size_t)n;
    }
    memset(buf + got, 0, length - got);
    WasiMapping *slot = w_wasi_map_slot();
    if (!slot) { free(buf); errno = ENOMEM; return MAP_FAILED; }
    slot->addr = buf;
    slot->pages = 0;
    slot->free = 0;
    return buf;
}

int munmap(void *addr, size_t length) {
    (void)length;
    for (size_t i = 0; i < w_wasi_map_count; i++) {
        WasiMapping *m = &w_wasi_maps[i];
        if (m->addr != addr || m->free) continue;
        if (m->pages == 0) {
            free(m->addr);
            *m = w_wasi_maps[--w_wasi_map_count];
        } else {
            m->free = 1;
        }
        return 0;
    }
    errno = EINVAL;
    return -1;
}

int mprotect(void *addr, size_t length, int prot) { (void)addr; (void)length; (void)prot; return 0; }
int madvise(void *addr, size_t length, int advice) { (void)addr; (void)length; (void)advice; return 0; }
int msync(void *addr, size_t length, int flags) { (void)addr; (void)length; (void)flags; return 0; }
int mlock(const void *addr, size_t length) { (void)addr; (void)length; return 0; }
int munlock(const void *addr, size_t length) { (void)addr; (void)length; return 0; }
