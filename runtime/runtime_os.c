#ifndef W_RUNTIME_UNITY_INCLUDE
#ifdef __linux__
#define _GNU_SOURCE
#endif
#include "runtime_internal.h"
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
extern char **environ;
#ifdef __APPLE__
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#endif
#define die w_rt_die
#define dief w_rt_dief
#define as_str w_rt_as_str
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#define w_bytes_ascii_p w_rt_bytes_ascii_p
#define as_mmap w_rt_as_mmap
#define w_sandbox_on w_rt_sandbox_on
#define w_string_take w_rt_string_take
#endif

static int w_child_own_group(void);

/* ---- Process API (spawn / wait / kill) ------------------------------------
 * Real child-process control for portfolio solvers and worker pools, where
 * __w_system's boolean collapse of the exit status is unusable: SAT solvers
 * speak in exit codes (10 SAT / 20 UNSAT), and a coordinator must be able to
 * poll many children and kill losers by process group. Each child is spawned
 * into its OWN process group (pgid == pid) so a kill reaches the child and
 * everything it spawned, and never this process. */

/* argv comes as an Array of strings; execs directly (no shell). Returns the
 * pid, or -errno style negative on failure. */
WValue __w_proc_spawn(WValue argv_val) {
    w_sandbox_gate("proc_spawn", "");
    WArray *arr = w_as_array(argv_val);
    int argc = (int)arr->size;
    if (argc < 1) return w_int(-1);
    char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
    if (!argv) return w_int(-1);
    memset(argv, 0, sizeof(char *) * (argc + 1));
    for (int i = 0; i < argc; i++) {
        WValue s = arr->slots[arr->start + i];
        /* as_str() may return one of a small ring of thread-local buffers for
         * inline strings. Keeping those pointers while converting later
         * arguments lets the ring wrap and silently changes earlier argv
         * entries. posix_spawnp() needs stable strings, so take ownership of
         * every argument before asking as_str() for the next one. */
        const char *text = as_str(s);
        argv[i] = strdup(text);
        if (!argv[i]) {
            for (int j = 0; j < i; j++) free(argv[j]);
            free(argv);
            return w_int(-1);
        }
    }

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return w_int(-1);
    }
    int own_group = w_child_own_group();
    short flags = own_group ? POSIX_SPAWN_SETPGROUP : 0;
    if (posix_spawnattr_setflags(&attr, flags) != 0 ||
        (own_group && posix_spawnattr_setpgroup(&attr, 0) != 0)) {
        posix_spawnattr_destroy(&attr);
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return w_int(-1);
    }
    pid_t pid = -1;
    int err = posix_spawnp(&pid, argv[0], NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    if (err != 0) return w_int(-(int64_t)err);
    return w_int((int64_t)pid);
}

/* Replace THIS process with argv (PATH search, no shell). Unlike
 * __w_proc_spawn the new program inherits the terminal, process group, and
 * descriptors, so an interactive child stays the foreground job: a spawned
 * child sits in its own process group and is stopped (SIGTTIN/SIGTTOU) on
 * its first terminal access. Used by delegate_compiler_image for bin/wit.
 * Returns only on failure, as -errno. */
WValue __w_proc_exec(WValue argv_val) {
    w_sandbox_gate("proc_exec", "");
    WArray *arr = w_as_array(argv_val);
    int argc = (int)arr->size;
    if (argc < 1) return w_int(-1);
    char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
    if (!argv) return w_int(-1);
    memset(argv, 0, sizeof(char *) * (argc + 1));
    for (int i = 0; i < argc; i++) {
        /* Same as_str() ring-buffer hazard as __w_proc_spawn: own each
         * argument before converting the next. */
        const char *text = as_str(arr->slots[arr->start + i]);
        argv[i] = strdup(text);
        if (!argv[i]) {
            for (int j = 0; j < i; j++) free(argv[j]);
            free(argv);
            return w_int(-1);
        }
    }
    execvp(argv[0], argv);
    int err = errno;
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    return w_int(-(int64_t)err);
}

/* Wait for one child. block=0 polls (WNOHANG). Returns:
 *   -1  still running (poll only)
 *   -2  wait failed (no such child)
 *   >=0 exit code, or 256+signal when signal-terminated. */
WValue __w_proc_wait(WValue pid_val, WValue block_val) {
    w_sandbox_gate("proc_wait", "");
    pid_t pid = (pid_t)w_as_int(pid_val);
    int block = (int)w_as_int(block_val);
    int status = 0;
    for (;;) {
        pid_t r = waitpid(pid, &status, block ? 0 : WNOHANG);
        if (r == pid) break;
        if (r == 0) return w_int(-1);
        if (r == -1 && errno == EINTR) continue;
        return w_int(-2);
    }
    if (WIFEXITED(status)) return w_int((int64_t)WEXITSTATUS(status));
    if (WIFSIGNALED(status)) return w_int(256 + (int64_t)WTERMSIG(status));
    return w_int(-2);
}

/* Signal the child's whole process group (it leads its own). */
WValue __w_proc_kill(WValue pid_val, WValue sig_val) {
    w_sandbox_gate("proc_kill", "");
    pid_t pid = (pid_t)w_as_int(pid_val);
    int sig = (int)w_as_int(sig_val);
    if (pid <= 1) return W_FALSE;
    return kill(getpgid(pid) == pid ? -pid : pid, sig) == 0 ? W_TRUE : W_FALSE;
}

/* Liveness probe: signal 0 to the process (not the group). */
WValue __w_proc_alive(WValue pid_val) {
    if (w_sandbox_stub("proc_alive", "")) return W_FALSE;
    pid_t pid = (pid_t)w_as_int(pid_val);
    if (pid <= 1) return W_FALSE;
    return kill(pid, 0) == 0 ? W_TRUE : W_FALSE;
}

/* Foreground child for the compiler driver's `run` / `-e`: exec argv
 * directly (no shell) with everything inherited — process group included,
 * so terminal signals reach parent and child together, matching the old
 * in-process interpreter. Returns the raw disposition: the exit code,
 * 256+signal for a signal death, or -errno when the spawn itself fails.
 * Plain (un-prefixed) name: this is a ccall target, and ccall links the
 * literal symbol (see w_eputs). */
WValue w_run_argv(WValue argv_val) {
    w_sandbox_gate("proc_spawn", "");
    WArray *arr = w_as_array(argv_val);
    int argc = (int)arr->size;
    if (argc < 1) return w_int(-1);
    char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
    if (!argv) return w_int(-1);
    memset(argv, 0, sizeof(char *) * (argc + 1));
    for (int i = 0; i < argc; i++) {
        /* Own every argument before the next as_str() call — the inline-string
         * ring buffer hazard documented at __w_proc_spawn. */
        const char *text = as_str(arr->slots[arr->start + i]);
        argv[i] = strdup(text);
        if (!argv[i]) {
            for (int j = 0; j < i; j++) free(argv[j]);
            free(argv);
            return w_int(-1);
        }
    }
    pid_t pid = -1;
    int spawn_error = posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    if (spawn_error != 0) return w_int(-(int64_t)spawn_error);
    int status = 0;
    while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}
    if (WIFEXITED(status)) return w_int((int64_t)WEXITSTATUS(status));
    if (WIFSIGNALED(status)) return w_int(256 + (int64_t)WTERMSIG(status));
    return w_int(-1);
}

/* rename(2) from two WValue strings, for atomic publish of temp files
 * without forking a shell. The first path is copied out before the second
 * as_str() call so the thread-local ring buffer cannot alias the two. */
WValue __w_rename(WValue old_val, WValue new_val) {
    w_sandbox_gate("rename", as_str(old_val));
    char oldp[4096];
    snprintf(oldp, sizeof oldp, "%s", as_str(old_val));
    const char *newp = as_str(new_val);
    if (rename(oldp, newp) == 0) return W_TRUE;
    return W_FALSE;
}

/* Create a unique temporary directory below TMPDIR (or /tmp). `prefix` is a
 * filename component supplied by trusted application code, not a path. */
WValue __w_mkdtemp(WValue prefix_val) {
    w_sandbox_gate("mkdtemp", "");
    const char *base = getenv("TMPDIR");
    if (!base || !*base) base = "/tmp";
    const char *prefix = as_str(prefix_val);
    if (!prefix || !*prefix || strchr(prefix, '/')) return W_NIL;
    char path[4096];
    size_t n = strlen(base);
    int sep = n > 0 && base[n - 1] == '/' ? 0 : 1;
    int wrote = snprintf(path, sizeof path, "%s%s%s-XXXXXX",
                         base, sep ? "/" : "", prefix);
    if (wrote < 0 || (size_t)wrote >= sizeof path) return W_NIL;
    return mkdtemp(path) ? w_string(path) : W_NIL;
}

WValue __w_mkdtemp_in(WValue parent_val, WValue prefix_val) {
    char parent[3072];
    snprintf(parent, sizeof parent, "%s", as_str(parent_val));
    const char *prefix = as_str(prefix_val);
    if (!*parent || !prefix || !*prefix || strchr(prefix, '/')) return W_NIL;
    size_t n = strlen(parent);
    int sep = parent[n - 1] == '/' ? 0 : 1;
    char path[4096];
    int wrote = snprintf(path, sizeof path, "%s%s%s-XXXXXX",
                         parent, sep ? "/" : "", prefix);
    if (wrote < 0 || (size_t)wrote >= sizeof path) return W_NIL;
    return mkdtemp(path) ? w_string(path) : W_NIL;
}

/* Reserve a unique temporary file beside `destination`, ensuring the final
 * rename stays on the same filesystem. The caller owns unlinking it. */
WValue __w_temp_file_for(WValue destination_val) {
    w_sandbox_gate("temp_file_for", as_str(destination_val));
    const char *destination = as_str(destination_val);
    char path[4096];
    int wrote = snprintf(path, sizeof path, "%s.tmp.XXXXXX", destination);
    if (wrote < 0 || (size_t)wrote >= sizeof path) return W_NIL;
    int fd = mkstemp(path);
    if (fd < 0) return W_NIL;
    if (close(fd) != 0) {
        unlink(path);
        return W_NIL;
    }
    return w_string(path);
}

/* Atomically reserve a mode-0600 temporary file and return its path. The
 * caller owns unlinking it; core/Tempfile.create provides the ensure-backed
 * scoped cleanup form. Prefix is a filename component, never a path. */
WValue __w_tempfile_create(WValue prefix_val, WValue directory_val) {
    const char *prefix = as_str(prefix_val);
    if (!prefix || !*prefix || strchr(prefix, '/')) return W_NIL;

    const char *directory = NULL;
    if (directory_val != W_NIL) directory = as_str(directory_val);
    if (!directory || !*directory) directory = getenv("TMPDIR");
    if (!directory || !*directory) directory = "/tmp";
    w_sandbox_gate("tempfile_create", directory);

    char path[4096];
    size_t n = strlen(directory);
    int sep = n > 0 && directory[n - 1] == '/' ? 0 : 1;
    int wrote = snprintf(path, sizeof path, "%s%s%s-XXXXXX",
                         directory, sep ? "/" : "", prefix);
    if (wrote < 0 || (size_t)wrote >= sizeof path) return W_NIL;
    int fd = mkstemp(path);
    if (fd < 0) return W_NIL;
    int ok = fchmod(fd, S_IRUSR | S_IWUSR) == 0;
    if (close(fd) != 0) ok = 0;
    if (!ok) {
        unlink(path);
        return W_NIL;
    }
    return w_string(path);
}

/* Durability and cleanup helpers used by atomic artifact publishers. */
WValue __w_fsync_path(WValue path_val) {
    w_sandbox_gate("fsync_path", as_str(path_val));
    const char *path = as_str(path_val);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return W_FALSE;
    int ok = fsync(fd) == 0;
    if (close(fd) != 0) ok = 0;
    return ok ? W_TRUE : W_FALSE;
}

WValue __w_fsync_parent(WValue path_val) {
    w_sandbox_gate("fsync_parent", as_str(path_val));
    const char *source = as_str(path_val);
    char parent[4096];
    size_t len = strlen(source);
    if (len == 0 || len >= sizeof parent) return W_FALSE;
    memcpy(parent, source, len + 1);
    char *slash = strrchr(parent, '/');
    if (!slash) {
        parent[0] = '.';
        parent[1] = '\0';
    } else if (slash == parent) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
    int fd = open(parent, O_RDONLY);
    if (fd < 0) return W_FALSE;
    int ok = fsync(fd) == 0;
    if (close(fd) != 0) ok = 0;
    return ok ? W_TRUE : W_FALSE;
}

WValue __w_unlink(WValue path_val) {
    w_sandbox_gate("unlink", as_str(path_val));
    return unlink(as_str(path_val)) == 0 || errno == ENOENT ? W_TRUE : W_FALSE;
}

WValue __w_file_unlink_strict(WValue path_val) {
    w_sandbox_gate("file_unlink", as_str(path_val));
    return unlink(as_str(path_val)) == 0 ? W_TRUE : W_FALSE;
}

WValue __w_rmdir(WValue path_val) {
    return rmdir(as_str(path_val)) == 0 || errno == ENOENT ? W_TRUE : W_FALSE;
}

WValue __w_append_file_to(WValue destination_val, WValue source_val) {
    w_sandbox_gate("append_file_to", as_str(destination_val));
    char destination[4096];
    snprintf(destination, sizeof destination, "%s", as_str(destination_val));
    const char *source = as_str(source_val);
    FILE *in = fopen(source, "rb");
    if (!in) return W_FALSE;
    FILE *out = fopen(destination, "ab");
    if (!out) {
        fclose(in);
        return W_FALSE;
    }
    unsigned char buffer[262144];
    int ok = 1;
    size_t count;
    while ((count = fread(buffer, 1, sizeof buffer, in)) > 0) {
        if (fwrite(buffer, 1, count, out) != count) {
            ok = 0;
            break;
        }
    }
    if (ferror(in)) ok = 0;
    if (fflush(out) != 0) ok = 0;
    if (fclose(in) != 0) ok = 0;
    if (fclose(out) != 0) ok = 0;
    return ok ? W_TRUE : W_FALSE;
}

/* Shell-free mkdir -p for coordinator work directories. */
WValue __w_mkdir_p(WValue path_val) {
    w_sandbox_gate("mkdir_p", as_str(path_val));
    const char *source = as_str(path_val);
    char path[4096];
    size_t len = strlen(source);
    if (len == 0 || len >= sizeof path) return W_FALSE;
    memcpy(path, source, len + 1);
    while (len > 1 && path[len - 1] == '/') path[--len] = '\0';
    for (char *p = path + 1; *p; p++) {
        if (*p != '/') continue;
        *p = '\0';
        if (mkdir(path, 0700) != 0 && errno != EEXIST) return W_FALSE;
        *p = '/';
    }
    if (mkdir(path, 0700) != 0 && errno != EEXIST) return W_FALSE;
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode) ? W_TRUE : W_FALSE;
}

/* ---- Dir bridges: the bare file_pwd/file_chdir/file_mkdir/file_rmdir
 * builtins that core/dir.w and core/directory.w call. Mirrors the Ruby
 * interpreter's builtins (implementations/ruby .. builtins.rb). ---- */

WValue __w_file_pwd(void) {
    char buf[4096];
    if (!getcwd(buf, sizeof buf)) return W_NIL;
    return w_string(buf);
}

WValue __w_file_chdir(WValue path_val) {
    const char *path = as_str(path_val);
    w_sandbox_gate("file_chdir", path);
    if (chdir(path) != 0)
        dief("chdir failed for '%s': %s", path, strerror(errno));
    return __w_file_pwd();
}

/* opts is nil or the keyword hash ({recursive: true} from Dir.mkdir_p);
 * core/dir.w normalizes the *opts splat down to one slot. */
WValue __w_file_mkdir(WValue path_val, WValue opts) {
    const char *path = as_str(path_val);
    w_sandbox_gate("file_mkdir", path);
    if (w_is_hash(opts) && w_truthy(w_hash_get(opts, w_symbol("recursive"))))
        return __w_mkdir_p(path_val);
    return mkdir(path, 0777) == 0 || errno == EEXIST ? W_TRUE : W_FALSE;
}

WValue __w_file_rmdir(WValue path_val) {
    const char *path = as_str(path_val);
    w_sandbox_gate("file_rmdir", path);
    return rmdir(path) == 0 ? W_TRUE : W_FALSE;
}

/* Process-environment access. Runtime-mediated operations serialize with each
 * other so snapshots cannot observe one of our own half-completed mutations.
 * Code outside Tungsten that calls libc getenv/setenv concurrently remains
 * outside this contract, as it is on POSIX generally. */
static pthread_mutex_t g_env_lock = PTHREAD_MUTEX_INITIALIZER;
#define W_ENV_CACHE_SIZE 128
#define W_ENV_CACHE_MASK (W_ENV_CACHE_SIZE - 1)
typedef struct {
    WValue key;
    WValue val;
    uint32_t epoch;
} WEnvCacheEntry;
static _Atomic uint32_t g_env_epoch = 1;
static _Thread_local WEnvCacheEntry tls_env_cache[W_ENV_CACHE_SIZE];

static void w_env_require_name(WValue value) {
    if (!(w_is_string(value) || w_is_rope(value)))
        w_raise(w_string("environment variable name must be a String"));
    char inline_buf[6];
    const char *name;
    size_t size;
    w_str_data(value, inline_buf, &name, &size);
    if (size == 0 || memchr(name, '=', size) != NULL || memchr(name, '\0', size) != NULL)
        w_raise(w_string("environment variable name must be non-empty and cannot contain '=' or NUL"));
}

static void w_env_require_value(WValue value) {
    if (!(w_is_string(value) || w_is_rope(value)))
        w_raise(w_string("environment variable value must be a String"));
    char inline_buf[6];
    const char *data;
    size_t size;
    w_str_data(value, inline_buf, &data, &size);
    if (memchr(data, '\0', size) != NULL)
        w_raise(w_string("environment variable value cannot contain NUL"));
}

WValue w_setenv(WValue name_val, WValue value_val) {
    w_env_require_name(name_val);
    w_env_require_value(value_val);
    const char *name_src = as_str(name_val);
    w_sandbox_gate("setenv", name_src);
    char *name = strdup(name_src);
    const char *value = as_str(value_val);
    pthread_mutex_lock(&g_env_lock);
    int rc = setenv(name, value, 1);
    int saved_errno = errno;
    atomic_fetch_add_explicit(&g_env_epoch, 1, memory_order_release);
    pthread_mutex_unlock(&g_env_lock);
    free(name);
    if (rc != 0) {
        char message[320];
        snprintf(message, sizeof message, "cannot set environment variable: %s", strerror(saved_errno));
        w_raise(w_string(message));
    }
    return value_val;
}

WValue w_unsetenv(WValue name_val) {
    w_env_require_name(name_val);
    const char *name = as_str(name_val);
    w_sandbox_gate("unsetenv", name);
    pthread_mutex_lock(&g_env_lock);
    const char *old = getenv(name);
    WValue result = old ? w_string(old) : W_NIL;
    int rc = unsetenv(name);
    int saved_errno = errno;
    atomic_fetch_add_explicit(&g_env_epoch, 1, memory_order_release);
    pthread_mutex_unlock(&g_env_lock);
    if (rc != 0) {
        char message[320];
        snprintf(message, sizeof message, "cannot delete environment variable: %s", strerror(saved_errno));
        w_raise(w_string(message));
    }
    return result;
}

WValue w_env_keys(void) {
    WValue result = w_array_new_empty();
    if (w_sandbox_stub("env", "*")) return result;
    extern char **environ;
    pthread_mutex_lock(&g_env_lock);
    for (char **entry = environ; entry && *entry; entry++) {
        const char *separator = strchr(*entry, '=');
        if (separator)
            w_array_push(result, w_string_n(*entry, (size_t)(separator - *entry)));
    }
    pthread_mutex_unlock(&g_env_lock);
    return result;
}

WValue w_env_to_h(void) {
    WValue result = w_hash_new();
    if (w_sandbox_stub("env", "*")) return result;
    extern char **environ;
    pthread_mutex_lock(&g_env_lock);
    for (char **entry = environ; entry && *entry; entry++) {
        const char *separator = strchr(*entry, '=');
        if (!separator) continue;
        WValue key = w_string_n(*entry, (size_t)(separator - *entry));
        WValue value = w_string(separator + 1);
        w_hash_set(result, key, value);
    }
    pthread_mutex_unlock(&g_env_lock);
    return result;
}

WValue __w_capture(WValue cmd_val) {
    const char *cmd = as_str(cmd_val);
    w_sandbox_gate("capture", cmd);
    FILE *fp = popen(cmd, "r");
    if (!fp) return w_string("");

    size_t cap = 256, len = 0;
    char *buf = malloc(cap);
    size_t n;
    while ((n = fread(buf + len, 1, cap - len, fp)) > 0) {
        len += n;
        if (len == cap) { cap *= 2; buf = realloc(buf, cap); }
    }
    pclose(fp);
    buf[len] = '\0';
    WValue result = w_string(buf);
    free(buf);
    return result;
}

/* ---- Foreign function call ----
 * ccall() is resolved at compile time: the lowering emits a direct call to the
 * named C function, and the emitter auto-declares it. No runtime dispatch needed.
 * The runtime w_ccall fallback is kept for dynamic/interpreted use cases.
 */

/* ---- Monotonic clock ---- */

WValue __w_clock_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    int64_t ms = (int64_t)now.tv_sec * 1000 + (int64_t)now.tv_nsec / 1000000;
    return w_int(ms);
}

WValue __w_clock(void) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ticks = mach_absolute_time();
    double nanos = (double)ticks * (double)tb.numer / (double)tb.denom;
    return w_float(nanos / 1e9);
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return w_float((double)now.tv_sec + (double)now.tv_nsec / 1e9);
#endif
}

int64_t __w_clock_ticks_raw(void) {
#ifdef __APPLE__
    return (int64_t)mach_absolute_time();
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000000000LL + (int64_t)now.tv_nsec;
#endif
}

int64_t __w_deadline_ticks_after_seconds(int64_t seconds) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ticks_per_second = (1000000000ULL * (uint64_t)tb.denom) / (uint64_t)tb.numer;
    return __w_clock_ticks_raw() + seconds * (int64_t)ticks_per_second;
#else
    return __w_clock_ticks_raw() + seconds * 1000000000LL;
#endif
}

int64_t __w_deadline_ticks_after_ms(int64_t ms) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ticks_per_ms = (1000000ULL * (uint64_t)tb.denom) / (uint64_t)tb.numer;
    return __w_clock_ticks_raw() + ms * (int64_t)ticks_per_ms;
#else
    return __w_clock_ticks_raw() + ms * 1000000LL;
#endif
}

int64_t __w_clock_ns_raw(void) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ticks = mach_absolute_time();
    uint64_t denom = (uint64_t)tb.denom;
    uint64_t numer = (uint64_t)tb.numer;
    uint64_t whole_part = (ticks / denom) * numer;
    uint64_t remainder_part = (ticks % denom) * numer / denom;
    return (int64_t)(whole_part + remainder_part);
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000000000LL + (int64_t)now.tv_nsec;
#endif
}

WValue __w_elapsed_seconds_since_ns(int64_t start_ns) {
    int64_t elapsed_ns = __w_clock_ns_raw() - start_ns;
    return w_float((double)elapsed_ns / 1e9);
}

WValue __w_elapsed_seconds_since_ticks(int64_t start_ticks) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t elapsed_ticks = (uint64_t)(__w_clock_ticks_raw() - start_ticks);
    double nanos = (double)elapsed_ticks * (double)tb.numer / (double)tb.denom;
    return w_float(nanos / 1e9);
#else
    int64_t elapsed_ns = __w_clock_ticks_raw() - start_ticks;
    return w_float((double)elapsed_ns / 1e9);
#endif
}

WValue __w_env(WValue name_val) {
    int cacheable_key = 0;
    size_t cache_idx = 0;
    if (w_is_string(name_val)) {
        int mode = (int)((name_val >> 1) & 7);
        if (mode >= 1 && mode <= 6 && !w_sandbox_on()) {
            cacheable_key = 1;
            cache_idx = (size_t)((name_val * UINT64_C(0x9e3779b97f4a7c15)) >> 57) & W_ENV_CACHE_MASK;
            uint32_t epoch = atomic_load_explicit(&g_env_epoch, memory_order_acquire);
            if (tls_env_cache[cache_idx].key == name_val && tls_env_cache[cache_idx].epoch == epoch)
                return tls_env_cache[cache_idx].val;
        }
    }
    w_env_require_name(name_val);
    const char *name = as_str(name_val);
    if (w_sandbox_stub("env", name)) return W_NIL;
    pthread_mutex_lock(&g_env_lock);
    uint32_t epoch = atomic_load_explicit(&g_env_epoch, memory_order_relaxed);
    const char *val = getenv(name);
    WValue result;
    int cacheable_val = 0;
    if (!val) {
        result = W_NIL;
        cacheable_val = 1;
    } else {
        size_t vlen = strlen(val);
        result = w_string_n(val, vlen);
        if (((result >> 1) & 7) <= 6) {
            cacheable_val = 1;
        }
    }
    pthread_mutex_unlock(&g_env_lock);
    if (cacheable_key && cacheable_val && !w_sandbox_on()) {
        tls_env_cache[cache_idx].key = name_val;
        tls_env_cache[cache_idx].val = result;
        tls_env_cache[cache_idx].epoch = epoch;
    }
    return result;
}

WValue __w_runtime_identity(void) {
    static _Atomic WValue cached_id = 0;
    WValue id = atomic_load_explicit(&cached_id, memory_order_relaxed);
    if (__builtin_expect(id == 0, 0)) {
        const char *s = "compiled-runtime";
        id = w_string_n_known_ascii(s, 16, 1);
        if (((id >> 1) & 7) <= 6)
            atomic_store_explicit(&cached_id, id, memory_order_relaxed);
    }
    return id;
}

WValue __w_print(WValue v) {
    return w_print(v);
}

/* Print to stderr: lets a CLI keep stdout clean for machine-readable
 * payloads (e.g. a proof streamed to `-`) while still reporting status. */
WValue __w_eprint(WValue v) {
    WValue s = w_to_s(v);
    fprintf(stderr, "%s", as_str(s));
    return W_NIL;
}

/* Stable file identity for alias detection (symlinks, hardlinks): packs
 * (device, inode); nil when the path does not exist. */
/* Strict DIMACS CNF parser into caller-provided flat i64 buffers — the
 * boxed line/token splitting cost ~200ms on 200k-clause files and its
 * output was immediately re-walked into flat mirrors anyway. Validation
 * matches the .w parser exactly: single well-formed header, `cnf` kind,
 * digit-only counts, literals within the declared bound, the exact token
 * `0` as terminator (no signed/padded zero), `c`-token comments, a `%`
 * trailer ending the clause section, and a declared-vs-parsed count match.
 *
 * hdr: [0]=nvars [1]=declared [2]=parsed clauses [3]=total lits
 *      [4]=error code (0 ok) [5]=error line (1-based)
 * offs[k]/lens[k] index into lits for clause k.
 * Error codes: 1 no/dup header, 2 bad header, 3 bad token, 4 bound,
 * 5 unterminated, 6 count mismatch, 7 buffer overflow, 8 xnf. */
/* DIMACS character classes: one table load replaces the four-way
 * delimiter comparison the scanner used to do per character. */
#define DC_SPACE 1u   /* ' ', '\t', '\r' */
#define DC_NL    2u   /* '\n' */
#define DC_DIGIT 4u
static const uint8_t w_dimacs_cls[256] = {
    ['\t'] = DC_SPACE, ['\r'] = DC_SPACE, [' '] = DC_SPACE, ['\n'] = DC_NL,
    ['0'] = DC_DIGIT, ['1'] = DC_DIGIT, ['2'] = DC_DIGIT, ['3'] = DC_DIGIT,
    ['4'] = DC_DIGIT, ['5'] = DC_DIGIT, ['6'] = DC_DIGIT, ['7'] = DC_DIGIT,
    ['8'] = DC_DIGIT, ['9'] = DC_DIGIT,
};
#define DC_BREAK (DC_SPACE | DC_NL)

/* Each prior digit leaves v <= 2000000000. One more multiply/add fits
 * int64_t, so the range check can follow accumulation without signed overflow. */
/* Inline the one strict scanner at two constant-mode call sites. This keeps
 * count-only mode out of the ordinary fill loop without duplicating grammar. */
static inline __attribute__((always_inline)) WValue w_dimacs_scan_ext(
        const char *tx, size_t tlen, int64_t *lits, int64_t *offs,
        int64_t *lens, int64_t *hdr, int64_t hdr_cap, int64_t lcap, int64_t ccap, int count_only) {
    int64_t nvars = 0, declared = 0, ncl = 0, nlits = 0, cur_off = 0, cur_len = 0;
    int64_t longest = 0, wc0 = 0, wc1 = 0, wc2 = 0, wc3 = 0, wc4 = 0, wc5 = 0, first_empty = 0;
    int have_header = 0, done = 0, line_started = 0;
    int64_t lineno = 1;
    size_t i = 0;
    const uint8_t *cls = w_dimacs_cls;
    hdr[0] = hdr[1] = hdr[2] = hdr[3] = hdr[4] = hdr[5] = 0;
    if (hdr_cap >= 14) {
        hdr[6] = hdr[7] = hdr[8] = hdr[9] = hdr[10] = hdr[11] = hdr[12] = hdr[13] = 0;
    }
#define P_ERR(code) { hdr[4] = (code); hdr[5] = lineno; return W_NIL; }
#define AT_BREAK(pos) ((pos) >= tlen || (cls[(unsigned char)tx[pos]] & DC_BREAK))
    while (i < tlen && !done) {
        unsigned char c = (unsigned char)tx[i];
        uint8_t k = cls[c];
        if (k & DC_SPACE) { i++; continue; }
        if (k & DC_NL) { i++; lineno++; line_started = 0; continue; }

        if (!line_started) {
            /* `%` ends the clause section wherever it opens a line. */
            if (c == '%') { done = 1; break; }
            /* Keywords only as whole tokens: `cat 1 0` is malformed input,
             * not a comment. */
            if (c == 'c' && AT_BREAK(i + 1)) {
                while (i < tlen && tx[i] != '\n') i++;
                continue;
            }
            if (c == 'p' && AT_BREAK(i + 1)) {
                if (have_header) P_ERR(1);
                i++;                       /* past 'p' */
                int had_space = 0;
                while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) { had_space = 1; i++; }
                if (!had_space) P_ERR(2);
                if (i + 3 > tlen || tx[i] != 'c' || tx[i+1] != 'n' || tx[i+2] != 'f') P_ERR(2);
                i += 3;
                if (i >= tlen || !(cls[(unsigned char)tx[i]] & DC_SPACE)) P_ERR(2);
                int64_t vals[2];
                for (int vi = 0; vi < 2; vi++) {
                    had_space = 0;
                    while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) { had_space = 1; i++; }
                    if (!had_space) P_ERR(2);
                    if (i >= tlen || !(cls[(unsigned char)tx[i]] & DC_DIGIT)) P_ERR(2);
                    int64_t v = 0;
                    while (i < tlen && (cls[(unsigned char)tx[i]] & DC_DIGIT)) {
                        int digit = tx[i] - '0';
                        v = v * 10 + digit;
                        if (v > 2000000000LL) P_ERR(2);
                        i++;
                    }
                    vals[vi] = v;
                }
                while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) i++;
                if (i < tlen && tx[i] != '\n') P_ERR(2);
                nvars = vals[0]; declared = vals[1]; have_header = 1;
                if (declared + 2 > ccap) P_ERR(7);
                continue;
            }
            if (!have_header) P_ERR(1);
            if (c == 'x' && AT_BREAK(i + 1)) P_ERR(8);
        }
        if (!have_header) P_ERR(1);
        line_started = 1;

        /* Literal: optional sign, then digits, then a delimiter. One pass. */
        int neg = 0, signed_tok = 0;
        if (c == '-' || c == '+') { neg = (c == '-'); signed_tok = 1; i++; }
        size_t digit_start = i;
        int64_t v = 0;
        /* Eight decimal digits fit the literal bound. Check input length
         * once for this common prefix, then check overflow on longer tokens. */
        if (tlen - i >= 8) {
            for (unsigned j = 0; j < 8; j++) {
                unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                if (digit > 9) goto end_digits;
                v = v * 10 + digit;
                i++;
            }
        }
        while (i < tlen) {
            unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
            if (digit > 9) break;
            v = v * 10 + digit;
            if (v > 2000000000LL) P_ERR(4);
            i++;
        }
    end_digits:
        if (i == digit_start) P_ERR(3);
        /* Trailing junk inside the token is a bad token. */
        if (!AT_BREAK(i)) P_ERR(3);

        if (v == 0) {
            /* The terminator is the exact token `0`: -0, +0 and 00 are not. */
            if (i - digit_start != 1 || signed_tok) P_ERR(3);
            if (ncl >= declared) P_ERR(6);
            if (!count_only) {
                offs[ncl] = cur_off;
                if (lens) lens[ncl] = cur_len;
            }
            if (hdr_cap >= 14) {
                if (cur_len > longest) longest = cur_len;
                if (cur_len == 0) { wc0++; if (first_empty == 0) first_empty = ncl + 1; }
                else if (cur_len == 1) wc1++;
                else if (cur_len == 2) wc2++;
                else if (cur_len == 3) wc3++;
                else if (cur_len == 4) wc4++;
                else if (cur_len == 5) wc5++;
            }
            ncl++; cur_off = nlits; cur_len = 0;
        } else {
            if (v > nvars) P_ERR(4);
            if (nlits + 1 > lcap) P_ERR(7);
            if (!count_only) lits[nlits] = neg ? -v : v;
            nlits++;
            cur_len++;
        }
        /* The literal scanner has already validated this delimiter. */
        if (i < tlen) {
            if (tx[i] == '\n') { lineno++; line_started = 0; }
            i++;
        }
    }
    if (!have_header) P_ERR(1);
    if (cur_len != 0) P_ERR(5);
    if (ncl != declared) P_ERR(6);
    if (!count_only && ncl < ccap) offs[ncl] = nlits;
    hdr[0] = nvars; hdr[1] = declared; hdr[2] = ncl; hdr[3] = nlits;
    if (hdr_cap >= 14) {
        hdr[6] = longest; hdr[7] = wc0; hdr[8] = wc1; hdr[9] = wc2;
        hdr[10] = wc3; hdr[11] = wc4; hdr[12] = wc5; hdr[13] = first_empty;
    }
    return W_NIL;
#undef AT_BREAK
#undef P_ERR
}

static inline WValue w_dimacs_scan(
        const char *tx, size_t tlen, int64_t *lits, int64_t *offs,
        int64_t *lens, int64_t *hdr, int64_t lcap, int64_t ccap, int count_only) {
    return w_dimacs_scan_ext(tx, tlen, lits, offs, lens, hdr, 6, lcap, ccap, count_only);
}

/* Narrow-buffer single-threaded strict DIMACS scanner (int32_t output arrays). */
static inline WValue w_dimacs_scan_i32(
        const char *tx, size_t tlen, int32_t *lits, int32_t *offs,
        int32_t *lens, int64_t *hdr, int64_t lcap, int64_t ccap) {
    int64_t nvars = 0, declared = 0, ncl = 0, nlits = 0, cur_off = 0, cur_len = 0;
    int have_header = 0, done = 0, line_started = 0;
    int64_t lineno = 1;
    size_t i = 0;
    const uint8_t *cls = w_dimacs_cls;
    hdr[0] = hdr[1] = hdr[2] = hdr[3] = hdr[4] = hdr[5] = 0;
#define P32_ERR(code) { hdr[4] = (code); hdr[5] = lineno; return W_NIL; }
#define AT32_BREAK(pos) ((pos) >= tlen || (cls[(unsigned char)tx[pos]] & DC_BREAK))
    while (i < tlen && !done) {
        unsigned char c = (unsigned char)tx[i];
        uint8_t k = cls[c];
        if (k & DC_SPACE) { i++; continue; }
        if (k & DC_NL) { i++; lineno++; line_started = 0; continue; }

        if (!line_started) {
            if (c == '%') { done = 1; break; }
            if (c == 'c' && AT32_BREAK(i + 1)) {
                while (i < tlen && tx[i] != '\n') i++;
                continue;
            }
            if (c == 'p' && AT32_BREAK(i + 1)) {
                if (have_header) P32_ERR(1);
                i++;
                int had_space = 0;
                while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) { had_space = 1; i++; }
                if (!had_space) P32_ERR(2);
                if (i + 3 > tlen || tx[i] != 'c' || tx[i+1] != 'n' || tx[i+2] != 'f') P32_ERR(2);
                i += 3;
                if (i >= tlen || !(cls[(unsigned char)tx[i]] & DC_SPACE)) P32_ERR(2);
                int64_t vals[2];
                for (int vi = 0; vi < 2; vi++) {
                    had_space = 0;
                    while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) { had_space = 1; i++; }
                    if (!had_space) P32_ERR(2);
                    if (i >= tlen || !(cls[(unsigned char)tx[i]] & DC_DIGIT)) P32_ERR(2);
                    int64_t v = 0;
                    while (i < tlen && (cls[(unsigned char)tx[i]] & DC_DIGIT)) {
                        int digit = tx[i] - '0';
                        v = v * 10 + digit;
                        if (v > 2000000000LL) P32_ERR(2);
                        i++;
                    }
                    vals[vi] = v;
                }
                while (i < tlen && (cls[(unsigned char)tx[i]] & DC_SPACE)) i++;
                if (i < tlen && tx[i] != '\n') P32_ERR(2);
                nvars = vals[0]; declared = vals[1]; have_header = 1;
                if (declared + 2 > ccap || declared > 2147483645LL) P32_ERR(7);
                continue;
            }
            if (!have_header) P32_ERR(1);
            if (c == 'x' && AT32_BREAK(i + 1)) P32_ERR(8);
        }
        if (!have_header) P32_ERR(1);
        line_started = 1;

        int neg = 0, signed_tok = 0;
        if (c == '-' || c == '+') { neg = (c == '-'); signed_tok = 1; i++; }
        size_t digit_start = i;
        int64_t v = 0;
        if (tlen - i >= 8) {
            for (unsigned j = 0; j < 8; j++) {
                unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                if (digit > 9) goto end_digits_32;
                v = v * 10 + digit;
                i++;
            }
        }
        while (i < tlen) {
            unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
            if (digit > 9) break;
            v = v * 10 + digit;
            if (v > 2000000000LL) P32_ERR(4);
            i++;
        }
    end_digits_32:
        if (i == digit_start) P32_ERR(3);
        if (!AT32_BREAK(i)) P32_ERR(3);

        if (v == 0) {
            if (i - digit_start != 1 || signed_tok) P32_ERR(3);
            if (ncl >= declared) P32_ERR(6);
            offs[ncl] = (int32_t)cur_off;
            if (lens) lens[ncl] = (int32_t)cur_len;
            ncl++; cur_off = nlits; cur_len = 0;
        } else {
            if (v > nvars) P32_ERR(4);
            if (nlits + 1 > lcap || nlits >= 2147483647LL) P32_ERR(7);
            lits[nlits] = (int32_t)(neg ? -v : v);
            nlits++;
            cur_len++;
        }
        if (i < tlen) {
            if (tx[i] == '\n') { lineno++; line_started = 0; }
            i++;
        }
    }
    if (!have_header) P32_ERR(1);
    if (cur_len != 0) P32_ERR(5);
    if (ncl != declared) P32_ERR(6);
    if (ncl < ccap) offs[ncl] = (int32_t)nlits;
    hdr[0] = nvars; hdr[1] = declared; hdr[2] = ncl; hdr[3] = nlits;
    return W_NIL;
#undef AT32_BREAK
#undef P32_ERR
}

#if !defined(__wasm__)
#define W_DIMACS_MAX_THREADS 8
#define W_DIMACS_PAR_MIN_BYTES (16ULL << 20)

typedef struct {
    const char *tx;
    size_t start;
    size_t end;
    int64_t nvars;
    int64_t ncl;
    int64_t nlits;
    int64_t base_cl;
    int64_t base_lit;
    int64_t longest;
    int64_t wc[6];
    int64_t first_empty_local;
    int abort;
    int bits;
    void *lits;
    void *offs;
    void *lens;
} WDimacsChunkArg;

static int w_dimacs_thread_count(size_t body_bytes) {
    const char *seq = getenv("WASSAT_SEQUENTIAL");
    if (seq && seq[0] == '1' && seq[1] == '\0') return 1;
    if (body_bytes < W_DIMACS_PAR_MIN_BYTES) return 1;
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    int k = ncpu > 1 ? (int)ncpu : 1;
    if (k > W_DIMACS_MAX_THREADS) k = W_DIMACS_MAX_THREADS;
    size_t max_by_size = body_bytes / (4ULL << 20);
    if ((size_t)k > max_by_size) k = (int)max_by_size;
    return k < 2 ? 1 : k;
}

/* Locate the clause body right after a newline-terminated `p cnf` header.
 * Any non-standard prefix returns 0 so the strict serial scanner handles it. */
static int w_dimacs_find_body(const char *tx, size_t tlen, size_t *out_body,
                              int64_t *out_nvars, int64_t *out_declared) {
    const uint8_t *cls = w_dimacs_cls;
    size_t limit = tlen < (1ULL << 20) ? tlen : (1ULL << 20);
    size_t i = 0;
    int line_started = 0;
    while (i < limit) {
        unsigned char c = (unsigned char)tx[i];
        uint8_t k = cls[c];
        if (k & DC_SPACE) { i++; continue; }
        if (k & DC_NL) { i++; line_started = 0; continue; }
        if (!line_started) {
            if (c == 'c' && (i + 1 >= tlen || (cls[(unsigned char)tx[i + 1]] & DC_BREAK))) {
                while (i < limit && tx[i] != '\n') i++;
                continue;
            }
            if (c == 'p' && i + 1 < limit && (cls[(unsigned char)tx[i + 1]] & DC_SPACE)) {
                i++;
                while (i < limit && (cls[(unsigned char)tx[i]] & DC_SPACE)) i++;
                if (i + 4 > limit || tx[i] != 'c' || tx[i+1] != 'n' || tx[i+2] != 'f') return 0;
                i += 3;
                if (!(cls[(unsigned char)tx[i]] & DC_SPACE)) return 0;
                int64_t vals[2];
                for (int vi = 0; vi < 2; vi++) {
                    int had_sp = 0;
                    while (i < limit && (cls[(unsigned char)tx[i]] & DC_SPACE)) { had_sp = 1; i++; }
                    if (!had_sp || i >= limit || !(cls[(unsigned char)tx[i]] & DC_DIGIT)) return 0;
                    int64_t v = 0;
                    while (i < limit && (cls[(unsigned char)tx[i]] & DC_DIGIT)) {
                        v = v * 10 + (tx[i] - '0');
                        if (v > 2000000000LL) return 0;
                        i++;
                    }
                    vals[vi] = v;
                }
                while (i < limit && (cls[(unsigned char)tx[i]] & DC_SPACE)) i++;
                if (i >= limit || tx[i] != '\n') return 0;
                if (vals[1] <= 0) return 0;
                *out_body = i + 1;
                *out_nvars = vals[0];
                *out_declared = vals[1];
                return 1;
            }
        }
        return 0;
    }
    return 0;
}

/* Advance a nominal split position to the end of a clause-terminating line
 * (`... 0\n`) so even multi-line clauses rarely cross a chunk boundary. */
static size_t w_dimacs_align_split(const char *tx, size_t body_start, size_t tlen, size_t pos) {
    const uint8_t *cls = w_dimacs_cls;
    size_t scan_lim = pos + 65536 < tlen ? pos + 65536 : tlen;
    size_t first_nl = 0;
    size_t p = pos;
    while (p < scan_lim) {
        if (tx[p] == '\n') {
            if (first_nl == 0) first_nl = p + 1;
            size_t ls = p;
            while (ls > body_start && tx[ls - 1] != '\n') ls--;
            size_t s = ls;
            while (s < p && (cls[(unsigned char)tx[s]] & DC_SPACE)) s++;
            if (s < p && tx[s] != 'c' && tx[s] != '%' && tx[s] != 'p') {
                size_t e = p;
                while (e > s && (cls[(unsigned char)tx[e - 1]] & DC_SPACE)) e--;
                if (e > s && tx[e - 1] == '0' && (e - 1 == s || (cls[(unsigned char)tx[e - 2]] & DC_SPACE))) {
                    return p + 1;
                }
            }
        }
        p++;
    }
    if (first_nl != 0) return first_nl;
    while (p < tlen && tx[p] != '\n') p++;
    return p < tlen ? p + 1 : tlen;
}

static void *w_dimacs_count_chunk_worker(void *raw) {
    WDimacsChunkArg *arg = (WDimacsChunkArg *)raw;
    const char *tx = arg->tx;
    size_t i = arg->start;
    size_t end = arg->end;
    int64_t nvars = arg->nvars;
    int64_t ncl = 0, nlits = 0, cur_len = 0;
    int line_started = 0;
    const uint8_t *cls = w_dimacs_cls;
#define CHUNK_BREAK(pos) ((pos) >= end || (cls[(unsigned char)tx[pos]] & DC_BREAK))
    while (i < end) {
        unsigned char c = (unsigned char)tx[i];
        uint8_t k = cls[c];
        if (k & DC_SPACE) { i++; continue; }
        if (k & DC_NL) { i++; line_started = 0; continue; }
        if (!line_started) {
            if (c == '%') { arg->abort = 1; return NULL; }
            if (c == 'c' && CHUNK_BREAK(i + 1)) {
                while (i < end && tx[i] != '\n') i++;
                continue;
            }
            if ((c == 'p' || c == 'x') && CHUNK_BREAK(i + 1)) {
                arg->abort = 1;
                return NULL;
            }
        }
        line_started = 1;
        int signed_tok = 0;
        if (c == '-' || c == '+') { signed_tok = 1; i++; }
        size_t digit_start = i;
        int64_t v = 0;
        if (end - i >= 8) {
            for (unsigned j = 0; j < 8; j++) {
                unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                if (digit > 9) goto chunk_end_digits;
                v = v * 10 + digit;
                i++;
            }
        }
        while (i < end) {
            unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
            if (digit > 9) break;
            v = v * 10 + digit;
            if (v > 2000000000LL) { arg->abort = 1; return NULL; }
            i++;
        }
    chunk_end_digits:
        if (i == digit_start || !CHUNK_BREAK(i)) { arg->abort = 1; return NULL; }
        if (v == 0) {
            if (i - digit_start != 1 || signed_tok) { arg->abort = 1; return NULL; }
            if (cur_len > arg->longest) arg->longest = cur_len;
            if (cur_len <= 5) {
                arg->wc[cur_len]++;
                if (cur_len == 0 && arg->first_empty_local == 0) arg->first_empty_local = ncl + 1;
            }
            ncl++;
            cur_len = 0;
        } else {
            if (v > nvars) { arg->abort = 1; return NULL; }
            nlits++;
            cur_len++;
        }
        if (i < end) {
            if (tx[i] == '\n') line_started = 0;
            i++;
        }
    }
#undef CHUNK_BREAK
    if (cur_len != 0) { arg->abort = 1; return NULL; }
    arg->ncl = ncl;
    arg->nlits = nlits;
    return NULL;
}

static void *w_dimacs_fill_chunk_worker(void *raw) {
    WDimacsChunkArg *arg = (WDimacsChunkArg *)raw;
    const char *tx = arg->tx;
    size_t i = arg->start;
    size_t end = arg->end;
    int64_t ncl = arg->base_cl;
    int64_t nlits = arg->base_lit;
    int64_t cur_off = nlits;
    int64_t cur_len = 0;
    int line_started = 0;
    const uint8_t *cls = w_dimacs_cls;
    if (arg->bits == 32) {
        int32_t *lits = (int32_t *)arg->lits;
        int32_t *offs = (int32_t *)arg->offs;
        int32_t *lens = (int32_t *)arg->lens;
        while (i < end) {
            unsigned char c = (unsigned char)tx[i];
            uint8_t k = cls[c];
            if (k & DC_SPACE) { i++; continue; }
            if (k & DC_NL) { i++; line_started = 0; continue; }
            if (!line_started && c == 'c') {
                while (i < end && tx[i] != '\n') i++;
                continue;
            }
            line_started = 1;
            int neg = 0;
            if (c == '-' || c == '+') { neg = (c == '-'); i++; }
            int64_t v = 0;
            if (end - i >= 8) {
                for (unsigned j = 0; j < 8; j++) {
                    unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                    if (digit > 9) goto fill32_done;
                    v = v * 10 + digit;
                    i++;
                }
            }
            while (i < end) {
                unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                if (digit > 9) break;
                v = v * 10 + digit;
                i++;
            }
        fill32_done:
            if (v == 0) {
                offs[ncl] = (int32_t)cur_off;
                if (lens) lens[ncl] = (int32_t)cur_len;
                ncl++;
                cur_off = nlits;
                cur_len = 0;
            } else {
                lits[nlits] = (int32_t)(neg ? -v : v);
                nlits++;
                cur_len++;
            }
            if (i < end) {
                if (tx[i] == '\n') line_started = 0;
                i++;
            }
        }
    } else {
        int64_t *lits = (int64_t *)arg->lits;
        int64_t *offs = (int64_t *)arg->offs;
        int64_t *lens = (int64_t *)arg->lens;
        while (i < end) {
            unsigned char c = (unsigned char)tx[i];
            uint8_t k = cls[c];
            if (k & DC_SPACE) { i++; continue; }
            if (k & DC_NL) { i++; line_started = 0; continue; }
            if (!line_started && c == 'c') {
                while (i < end && tx[i] != '\n') i++;
                continue;
            }
            line_started = 1;
            int neg = 0;
            if (c == '-' || c == '+') { neg = (c == '-'); i++; }
            int64_t v = 0;
            if (end - i >= 8) {
                for (unsigned j = 0; j < 8; j++) {
                    unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                    if (digit > 9) goto fill64_done;
                    v = v * 10 + digit;
                    i++;
                }
            }
            while (i < end) {
                unsigned digit = (unsigned)((unsigned char)tx[i] - '0');
                if (digit > 9) break;
                v = v * 10 + digit;
                i++;
            }
        fill64_done:
            if (v == 0) {
                offs[ncl] = cur_off;
                if (lens) lens[ncl] = cur_len;
                ncl++;
                cur_off = nlits;
                cur_len = 0;
            } else {
                lits[nlits] = neg ? -v : v;
                nlits++;
                cur_len++;
            }
            if (i < end) {
                if (tx[i] == '\n') line_started = 0;
                i++;
            }
        }
    }
    return NULL;
}

static int w_dimacs_build_parallel_plan(const char *tx, size_t tlen,
                                        WDimacsChunkArg *args, int *out_nchunks,
                                        int64_t *out_nvars, int64_t *out_declared,
                                        int64_t *out_nlits) {
    size_t body_start = 0;
    int64_t nvars = 0, declared = 0;
    if (!w_dimacs_find_body(tx, tlen, &body_start, &nvars, &declared)) return 0;
    size_t body_bytes = tlen - body_start;
    int want_k = w_dimacs_thread_count(body_bytes);
    if (want_k < 2) return 0;
    size_t bounds[W_DIMACS_MAX_THREADS + 1];
    bounds[0] = body_start;
    int nchunks = 0;
    for (int k = 1; k < want_k; k++) {
        size_t nom = body_start + (body_bytes * (size_t)k) / (size_t)want_k;
        size_t aligned = w_dimacs_align_split(tx, body_start, tlen, nom);
        if (aligned > bounds[nchunks] && aligned < tlen) {
            nchunks++;
            bounds[nchunks] = aligned;
        }
    }
    nchunks++;
    bounds[nchunks] = tlen;
    if (nchunks < 2) return 0;

    pthread_t tids[W_DIMACS_MAX_THREADS];
    int spawned[W_DIMACS_MAX_THREADS];
    for (int k = 0; k < nchunks; k++) {
        memset(&args[k], 0, sizeof(args[k]));
        args[k].tx = tx;
        args[k].start = bounds[k];
        args[k].end = bounds[k + 1];
        args[k].nvars = nvars;
        spawned[k] = 0;
    }
    for (int k = 1; k < nchunks; k++) {
        if (pthread_create(&tids[k], NULL, w_dimacs_count_chunk_worker, &args[k]) == 0) {
            spawned[k] = 1;
        } else {
            w_dimacs_count_chunk_worker(&args[k]);
        }
    }
    w_dimacs_count_chunk_worker(&args[0]);
    for (int k = 1; k < nchunks; k++) {
        if (spawned[k]) pthread_join(tids[k], NULL);
    }

    int64_t total_ncl = 0, total_nlits = 0;
    for (int k = 0; k < nchunks; k++) {
        if (args[k].abort) return 0;
        args[k].base_cl = total_ncl;
        args[k].base_lit = total_nlits;
        total_ncl += args[k].ncl;
        total_nlits += args[k].nlits;
    }
    if (total_ncl != declared) return 0;
    *out_nchunks = nchunks;
    *out_nvars = nvars;
    *out_declared = declared;
    *out_nlits = total_nlits;
    return 1;
}

static void w_dimacs_store_shape_hdr(const WDimacsChunkArg *args, int nchunks,
                                     int64_t *hdr, size_t hdr_cap) {
    if (hdr_cap < 14) return;
    int64_t longest = 0, wc[6] = {0, 0, 0, 0, 0, 0}, first_empty = 0;
    for (int k = 0; k < nchunks; k++) {
        if (args[k].longest > longest) longest = args[k].longest;
        for (int w = 0; w < 6; w++) wc[w] += args[k].wc[w];
        if (first_empty == 0 && args[k].first_empty_local > 0) {
            first_empty = args[k].base_cl + args[k].first_empty_local;
        }
    }
    hdr[6] = longest;
    hdr[7] = wc[0]; hdr[8] = wc[1]; hdr[9] = wc[2];
    hdr[10] = wc[3]; hdr[11] = wc[4]; hdr[12] = wc[5];
    hdr[13] = first_empty;
}

static void w_dimacs_exec_fill(WDimacsChunkArg *args, int nchunks, int bits,
                               void *lits, void *offs, void *lens,
                               int64_t total_ncl, int64_t total_nlits) {
    pthread_t tids[W_DIMACS_MAX_THREADS];
    int spawned[W_DIMACS_MAX_THREADS];
    for (int k = 0; k < nchunks; k++) {
        args[k].bits = bits;
        args[k].lits = lits;
        args[k].offs = offs;
        args[k].lens = lens;
        spawned[k] = 0;
    }
    for (int k = 1; k < nchunks; k++) {
        if (pthread_create(&tids[k], NULL, w_dimacs_fill_chunk_worker, &args[k]) == 0) {
            spawned[k] = 1;
        } else {
            w_dimacs_fill_chunk_worker(&args[k]);
        }
    }
    w_dimacs_fill_chunk_worker(&args[0]);
    for (int k = 1; k < nchunks; k++) {
        if (spawned[k]) pthread_join(tids[k], NULL);
    }
    if (bits == 32) {
        ((int32_t *)offs)[total_ncl] = (int32_t)total_nlits;
    } else {
        ((int64_t *)offs)[total_ncl] = total_nlits;
    }
}
#endif

/* The scanner accepts a String or an open read-only Mmap. Passing nil for
 * all three output buffers performs the same strict validation/count pass
 * without materializing the formula. This sizes large mapped inputs exactly. */
WValue __w_parse_dimacs(WValue text_val, WValue lits_val, WValue offs_val,
                        WValue lens_val, WValue hdr_val) {
    char inline_buf[6];
    const char *tx; size_t tlen;
    WMmap *mapping = as_mmap(text_val);
    if (mapping) {
        if (mapping->closed) w_raise(w_string("DIMACS: mmap is closed"));
        tx = (const char *)mapping->data;
        tlen = (size_t)mapping->size;
    } else {
        w_str_data(text_val, inline_buf, &tx, &tlen);
    }
    if (!w_is_array(hdr_val)) w_raise(w_string("DIMACS: header must be an i64 array"));
    WArray *ha = w_as_array(w_check_array_ebits(hdr_val, 64, 0, w_string("CNF")));
    if (ha->size < 6) w_raise(w_string("DIMACS: header buffer is too small"));
    int64_t *hdr = (int64_t *)ha->slots + ha->start;
    if (lits_val == W_NIL && offs_val == W_NIL && lens_val == W_NIL) {
#if !defined(__wasm__)
        if (tlen >= W_DIMACS_PAR_MIN_BYTES) {
            WDimacsChunkArg args[W_DIMACS_MAX_THREADS];
            int nchunks = 0;
            int64_t nvars = 0, declared = 0, nlits = 0;
            if (w_dimacs_build_parallel_plan(tx, tlen, args, &nchunks, &nvars, &declared, &nlits)) {
                hdr[0] = nvars; hdr[1] = declared; hdr[2] = declared; hdr[3] = nlits;
                hdr[4] = 0; hdr[5] = 0;
                w_dimacs_store_shape_hdr(args, nchunks, hdr, ha->size);
                return W_NIL;
            }
        }
#endif
        return w_dimacs_scan_ext(tx, tlen, NULL, NULL, NULL, hdr, ha->size, INT64_MAX, INT64_MAX, 1);
    }
    if (!w_is_array(lits_val) || !w_is_array(offs_val) || !w_is_array(lens_val))
        w_raise(w_string("DIMACS: supply three i64 output arrays or three nil buffers"));
    WArray *la = w_as_array(w_check_array_ebits(lits_val, 64, 0, w_string("CNF")));
    WArray *oa = w_as_array(w_check_array_ebits(offs_val, 64, 0, w_string("CNF")));
    WArray *na = w_as_array(w_check_array_ebits(lens_val, 64, 0, w_string("CNF")));
    int64_t *lits = (int64_t *)la->slots + la->start;
    int64_t *offs = (int64_t *)oa->slots + oa->start;
    int64_t *lens = (int64_t *)na->slots + na->start;
    int64_t ccap = oa->size < na->size ? oa->size : na->size;
#if !defined(__wasm__)
    if (tlen >= W_DIMACS_PAR_MIN_BYTES) {
        WDimacsChunkArg args[W_DIMACS_MAX_THREADS];
        int nchunks = 0;
        int64_t nvars = 0, declared = 0, nlits = 0;
        if (w_dimacs_build_parallel_plan(tx, tlen, args, &nchunks, &nvars, &declared, &nlits) &&
            declared + 2 <= ccap && nlits <= (int64_t)la->size) {
            w_dimacs_exec_fill(args, nchunks, 64, lits, offs, lens, declared, nlits);
            hdr[0] = nvars; hdr[1] = declared; hdr[2] = declared; hdr[3] = nlits;
            hdr[4] = 0; hdr[5] = 0;
            w_dimacs_store_shape_hdr(args, nchunks, hdr, ha->size);
            return W_NIL;
        }
    }
#endif
    return w_dimacs_scan_ext(tx, tlen, lits, offs, lens, hdr, ha->size, la->size, ccap, 0);
}

WValue __w_parse_dimacs_i32(WValue text_val, WValue lits_val, WValue offs_val,
                            WValue lens_val, WValue hdr_val) {
    char inline_buf[6];
    const char *tx; size_t tlen;
    WMmap *mapping = as_mmap(text_val);
    if (mapping) {
        if (mapping->closed) w_raise(w_string("DIMACS: mmap is closed"));
        tx = (const char *)mapping->data;
        tlen = (size_t)mapping->size;
    } else {
        w_str_data(text_val, inline_buf, &tx, &tlen);
    }
    if (!w_is_array(hdr_val)) w_raise(w_string("DIMACS: header must be an i64 array"));
    WArray *ha = w_as_array(w_check_array_ebits(hdr_val, 64, 0, w_string("CNF")));
    if (ha->size < 6) w_raise(w_string("DIMACS: header buffer is too small"));
    int64_t *hdr = (int64_t *)ha->slots + ha->start;
    if (!w_is_array(lits_val) || !w_is_array(offs_val) || (lens_val != W_NIL && !w_is_array(lens_val)))
        w_raise(w_string("DIMACS: supply i32 output arrays"));
    WArray *la = w_as_array(w_check_array_ebits(lits_val, 32, 0, w_string("CNF")));
    WArray *oa = w_as_array(w_check_array_ebits(offs_val, 32, 0, w_string("CNF")));
    WArray *na = lens_val == W_NIL ? NULL : w_as_array(w_check_array_ebits(lens_val, 32, 0, w_string("CNF")));
    int32_t *lits = (int32_t *)la->slots + la->start;
    int32_t *offs = (int32_t *)oa->slots + oa->start;
    int32_t *lens = na ? ((int32_t *)na->slots + na->start) : NULL;
    int64_t ccap = (na && na->size < oa->size) ? na->size : oa->size;
#if !defined(__wasm__)
    if (tlen >= W_DIMACS_PAR_MIN_BYTES) {
        WDimacsChunkArg args[W_DIMACS_MAX_THREADS];
        int nchunks = 0;
        int64_t nvars = 0, declared = 0, nlits = 0;
        if (w_dimacs_build_parallel_plan(tx, tlen, args, &nchunks, &nvars, &declared, &nlits) &&
            declared + 2 <= ccap && declared <= 2147483645LL &&
            nlits <= (int64_t)la->size && nlits <= 2147483647LL) {
            w_dimacs_exec_fill(args, nchunks, 32, lits, offs, lens, declared, nlits);
            hdr[0] = nvars; hdr[1] = declared; hdr[2] = declared; hdr[3] = nlits;
            hdr[4] = 0; hdr[5] = 0;
            w_dimacs_store_shape_hdr(args, nchunks, hdr, ha->size);
            return W_NIL;
        }
    }
#endif
    return w_dimacs_scan_i32(tx, tlen, lits, offs, lens, hdr, la->size, ccap);
}

/* Two-step zero-over-allocation parallel parse for large mapped files:
 * Step 1 (`__w_dimacs_plan`) validates and counts in parallel, saving chunk
 * slices into `plan` (`i64[64]`) so Step 2 (`__w_dimacs_fill_plan`) fills
 * exact-sized `i32[]` or `i64[]` output arrays without rescanning Pass 1. */
WValue __w_dimacs_plan(WValue text_val, WValue hdr_val, WValue plan_val) {
    char inline_buf[6];
    const char *tx; size_t tlen;
    WMmap *mapping = as_mmap(text_val);
    if (mapping) {
        if (mapping->closed) w_raise(w_string("DIMACS: mmap is closed"));
        tx = (const char *)mapping->data;
        tlen = (size_t)mapping->size;
    } else {
        w_str_data(text_val, inline_buf, &tx, &tlen);
    }
    if (!w_is_array(hdr_val) || !w_is_array(plan_val))
        w_raise(w_string("DIMACS: header and plan must be i64 arrays"));
    WArray *ha = w_as_array(w_check_array_ebits(hdr_val, 64, 0, w_string("CNF")));
    WArray *pa = w_as_array(w_check_array_ebits(plan_val, 64, 0, w_string("CNF")));
    if (ha->size < 6 || pa->size < 48) w_raise(w_string("DIMACS: plan buffer is too small"));
    int64_t *hdr = (int64_t *)ha->slots + ha->start;
    int64_t *plan = (int64_t *)pa->slots + pa->start;
    plan[0] = 0;
#if !defined(__wasm__)
    if (tlen >= W_DIMACS_PAR_MIN_BYTES) {
        WDimacsChunkArg args[W_DIMACS_MAX_THREADS];
        int nchunks = 0;
        int64_t nvars = 0, declared = 0, nlits = 0;
        if (w_dimacs_build_parallel_plan(tx, tlen, args, &nchunks, &nvars, &declared, &nlits)) {
            hdr[0] = nvars; hdr[1] = declared; hdr[2] = declared; hdr[3] = nlits;
            hdr[4] = 0; hdr[5] = 0;
            w_dimacs_store_shape_hdr(args, nchunks, hdr, ha->size);
            plan[0] = nchunks;
            plan[1] = nvars;
            plan[2] = declared;
            plan[3] = nlits;
            plan[4] = (int64_t)tlen;
            for (int k = 0; k < nchunks; k++) {
                plan[8 + 4 * k + 0] = (int64_t)args[k].start;
                plan[8 + 4 * k + 1] = (int64_t)args[k].end;
                plan[8 + 4 * k + 2] = args[k].base_cl;
                plan[8 + 4 * k + 3] = args[k].base_lit;
            }
            return w_int(1);
        }
    }
#endif
    w_dimacs_scan_ext(tx, tlen, NULL, NULL, NULL, hdr, ha->size, INT64_MAX, INT64_MAX, 1);
    return w_int(0);
}

WValue __w_dimacs_fill_plan(WValue text_val, WValue lits_val, WValue offs_val,
                            WValue lens_val, WValue hdr_val, WValue plan_val,
                            WValue bits_val) {
    char inline_buf[6];
    const char *tx; size_t tlen;
    WMmap *mapping = as_mmap(text_val);
    if (mapping) {
        if (mapping->closed) w_raise(w_string("DIMACS: mmap is closed"));
        tx = (const char *)mapping->data;
        tlen = (size_t)mapping->size;
    } else {
        w_str_data(text_val, inline_buf, &tx, &tlen);
    }
    int bits = (int)w_as_int(bits_val);
    if (bits != 32 && bits != 64) w_raise(w_string("DIMACS: invalid element width"));
    WArray *ha = w_as_array(w_check_array_ebits(hdr_val, 64, 0, w_string("CNF")));
    WArray *pa = w_as_array(w_check_array_ebits(plan_val, 64, 0, w_string("CNF")));
    if (ha->size < 6 || pa->size < 48) w_raise(w_string("DIMACS: plan buffer is too small"));
    int64_t *hdr = (int64_t *)ha->slots + ha->start;
    int64_t *plan = (int64_t *)pa->slots + pa->start;
    WArray *la = w_as_array(w_check_array_ebits(lits_val, bits, 0, w_string("CNF")));
    WArray *oa = w_as_array(w_check_array_ebits(offs_val, bits, 0, w_string("CNF")));
    WArray *na = lens_val == W_NIL ? NULL : w_as_array(w_check_array_ebits(lens_val, bits, 0, w_string("CNF")));
    int64_t ccap = (na && na->size < oa->size) ? na->size : oa->size;
#if !defined(__wasm__)
    int nchunks = (int)plan[0];
    if (nchunks >= 2 && nchunks <= W_DIMACS_MAX_THREADS && (size_t)plan[4] == tlen &&
        plan[2] + 2 <= ccap && plan[3] <= (int64_t)la->size &&
        (bits == 64 || (plan[2] <= 2147483645LL && plan[3] <= 2147483647LL))) {
        WDimacsChunkArg args[W_DIMACS_MAX_THREADS];
        for (int k = 0; k < nchunks; k++) {
            memset(&args[k], 0, sizeof(args[k]));
            args[k].tx = tx;
            args[k].start = (size_t)plan[8 + 4 * k + 0];
            args[k].end = (size_t)plan[8 + 4 * k + 1];
            args[k].base_cl = plan[8 + 4 * k + 2];
            args[k].base_lit = plan[8 + 4 * k + 3];
        }
        if (bits == 32) {
            w_dimacs_exec_fill(args, nchunks, 32,
                               (int32_t *)la->slots + la->start,
                               (int32_t *)oa->slots + oa->start,
                               na ? ((int32_t *)na->slots + na->start) : NULL,
                               plan[2], plan[3]);
        } else {
            w_dimacs_exec_fill(args, nchunks, 64,
                               (int64_t *)la->slots + la->start,
                               (int64_t *)oa->slots + oa->start,
                               na ? ((int64_t *)na->slots + na->start) : NULL,
                               plan[2], plan[3]);
        }
        hdr[0] = plan[1]; hdr[1] = plan[2]; hdr[2] = plan[2]; hdr[3] = plan[3];
        hdr[4] = 0; hdr[5] = 0;
        return W_NIL;
    }
#endif
    if (bits == 32) {
        return w_dimacs_scan_i32(tx, tlen,
                                 (int32_t *)la->slots + la->start,
                                 (int32_t *)oa->slots + oa->start,
                                 na ? ((int32_t *)na->slots + na->start) : NULL,
                                 hdr, la->size, ccap);
    }
    return w_dimacs_scan(tx, tlen,
                         (int64_t *)la->slots + la->start,
                         (int64_t *)oa->slots + oa->start,
                         na ? ((int64_t *)na->slots + na->start) : NULL,
                         hdr, la->size, ccap, 0);
}

/* Stream a DIMACS SAT witness (`s SATISFIABLE\nv ... 0\n`) straight to stdout
 * using a 256 KB buffer and an ASCII base-10 odometer (zero integer divisions
 * on canonical 1..nv models). `kind`: 0 = i8[] sign table (`sign[v * stride]`),
 * 1 = i64[] signed literals, 2 = boxed Array of signed literals. */
WValue __w_write_dimacs_model(WValue src_val, WValue kind_val, WValue nv_val,
                              WValue stride_val) {
    int kind = (int)w_as_int(kind_val);
    int64_t nv = w_as_int(nv_val);
    int64_t stride = w_as_int(stride_val);
    if (nv < 0) nv = 0;
    const int8_t *sign_arr = NULL;
    const int64_t *i64_arr = NULL;
    const int32_t *i32_arr = NULL;
    const WValue *w64_arr = NULL;
    if (!w_is_array(src_val)) w_raise(w_string("model: expected Array"));
    if (kind == 0) {
        WArray *sa = w_as_array(w_check_array_ebits(src_val, 8, 0, w_string("model")));
        sign_arr = (const int8_t *)sa->slots + sa->start;
    } else {
        WArray *ma = w_as_array(src_val);
        int eb = ma->ebits;
        if (eb == 64 || eb == -64 || eb == 66) {
            i64_arr = (const int64_t *)ma->slots + ma->start;
            kind = 1;
        } else if (eb == 32 || eb == -32 || eb == 33) {
            i32_arr = (const int32_t *)ma->slots + ma->start;
            kind = 3;
        } else {
            w64_arr = ma->slots + ma->start;
            kind = 2;
        }
    }

    enum { W_MODEL_BUF_CAP = 262144, W_MODEL_LINE_MAX = 4096 };
    char *buf = (char *)malloc(W_MODEL_BUF_CAP + 64);
    if (!buf) w_raise(w_string("model: out of memory"));
    memcpy(buf, "s SATISFIABLE\nv", 15);
    size_t pos = 15;
    int64_t line_len = 1;
    char dig[16];
    memset(dig, 0, sizeof(dig));
    dig[0] = '1';
    int digits = 1;

    for (int64_t v = 1; v <= nv; v++) {
        int neg = 0;
        int fast_v = 1;
        int64_t lit = v;
        if (kind == 0) {
            neg = (sign_arr[v * stride] < 0);
        } else {
            lit = (kind == 1) ? i64_arr[v - 1] : ((kind == 3) ? (int64_t)i32_arr[v - 1] : w_as_int(w64_arr[v - 1]));
            neg = (lit < 0);
            int64_t mag = neg ? -lit : lit;
            if (mag != v) fast_v = 0;
        }

        if (fast_v) {
            int dlen = neg ? (digits + 1) : digits;
            int tlen = dlen + 1;
            if (line_len > 1 && line_len + tlen + 2 > W_MODEL_LINE_MAX) {
                buf[pos] = '\n';
                buf[pos + 1] = 'v';
                pos += 2;
                line_len = 1;
            }
            buf[pos] = ' ';
            pos++;
            if (neg) {
                buf[pos] = '-';
                pos++;
            }
            memcpy(buf + pos, dig, 16);
            pos += (size_t)digits;
            line_len += tlen;
        } else {
            uint64_t mag = (uint64_t)(neg ? -lit : lit);
            char tmp[24];
            int td = 0;
            do {
                tmp[td++] = (char)('0' + (mag % 10));
                mag /= 10;
            } while (mag > 0);
            int dlen = neg ? (td + 1) : td;
            int tlen = dlen + 1;
            if (line_len > 1 && line_len + tlen + 2 > W_MODEL_LINE_MAX) {
                buf[pos] = '\n';
                buf[pos + 1] = 'v';
                pos += 2;
                line_len = 1;
            }
            buf[pos++] = ' ';
            if (neg) buf[pos++] = '-';
            for (int r = td - 1; r >= 0; r--) buf[pos++] = tmp[r];
            line_len += tlen;
        }

        if (pos >= W_MODEL_BUF_CAP) {
            (void)fwrite(buf, 1, pos, stdout);
            pos = 0;
        }

        int k = digits - 1;
        if ((unsigned char)dig[k] < '9') {
            dig[k]++;
        } else {
            while (k >= 0 && dig[k] == '9') {
                dig[k] = '0';
                k--;
            }
            if (k >= 0) {
                dig[k]++;
            } else {
                dig[0] = '1';
                dig[digits] = '0';
                digits++;
            }
        }
    }

    buf[pos] = ' ';
    buf[pos + 1] = '0';
    buf[pos + 2] = '\n';
    pos += 3;
    (void)fwrite(buf, 1, pos, stdout);
    fflush(stdout);
    free(buf);
    return W_NIL;
}

WValue __w_fast_exit(WValue code_val) {
    int code = (int)w_as_int(code_val);
    fflush(NULL);
    _exit(code);
    return W_NIL;
}

WValue __w_file_id(WValue path_val) {
    const char *path = as_str(path_val);
    if (w_sandbox_stub("file_id", path)) return W_NIL;
    struct stat st;
    if (stat(path, &st) != 0) return W_NIL;
    char identity[96];
    snprintf(identity, sizeof identity, "%llu:%llu",
             (unsigned long long)st.st_dev, (unsigned long long)st.st_ino);
    return w_string(identity);
}


/* ---- Dynamic loading (foundation for --jit / --hot eval backends) ----
 * Load freshly-compiled native code into the running process and call into it.
 * Handles and function pointers are passed as boxed ints; user pointers fit in
 * the low 48 bits on the platforms we target, so they round-trip through w_int.
 */

/* dlopen a shared library; returns an opaque handle (int) or nil on failure. */
WValue w_dlopen(WValue path_val) {
    const char *path = as_str(path_val);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) return W_NIL;
    return w_int((int64_t)(intptr_t)h);
}

/* Resolve a symbol in a handle; returns its address (int) or nil if absent. */
WValue w_dlsym(WValue handle_val, WValue name_val) {
    void *h = (void *)(intptr_t)w_to_i64(handle_val);
    const char *name = as_str(name_val);
    void *sym = dlsym(h, name);
    if (!sym) return W_NIL;
    return w_int((int64_t)(intptr_t)sym);
}

/* Close a previously-opened handle. */
WValue w_dlclose(WValue handle_val) {
    void *h = (void *)(intptr_t)w_to_i64(handle_val);
    if (h) dlclose(h);
    return W_NIL;
}

/* Call a resolved no-arg function returning int64 (used by the C-level test and
 * for snippets that don't need a boxed result). */
WValue w_dlcall_i64(WValue fn_val) {
    void *sym = (void *)(intptr_t)w_to_i64(fn_val);
    int64_t (*fn)(void) = (int64_t (*)(void))sym;
    return w_int(fn());
}

/* Call a resolved no-arg function that itself returns a WValue (a compiled
 * Tungsten snippet linked against this runtime). */
WValue w_dlcall(WValue fn_val) {
    void *sym = (void *)(intptr_t)w_to_i64(fn_val);
    WValue (*fn)(void) = (WValue (*)(void))sym;
    return fn();
}

/* Persistent native REPL bindings. A session executes snippets on one host
 * thread; separately loaded objects resolve these symbols from that host, so
 * values survive object unload/reload without replaying their initializers. */
static __thread WValue w_repl_state = W_NIL;

WValue w_repl_state_get(WValue name) {
    if (w_repl_state == W_NIL) return W_NIL;
    return w_hash_get(w_repl_state, name);
}

WValue w_repl_state_set(WValue name, WValue value) {
    if (w_repl_state == W_NIL) {
        w_repl_state = w_hash_new();
        w_gc_register_reuse_slot(&w_repl_state);
    }
    w_hash_set(w_repl_state, name, value);
    return value;
}

W_RT_INTERNAL void w_rt_gc_scan_os_thread_roots(WGCRootVisitor root_fn, void *ctx) {
    if (w_repl_state != W_NIL) root_fn(w_repl_state, ctx);
}

/* Resolve a Tungsten fn by its SOURCE name inside a loaded snippet dylib.
 * Tungsten fns get internal linkage + a hashed symbol (@__wy_…), so they can't
 * be dlsym'd directly — but the compiler emits __w_fn_meta (kept by llvm.used,
 * external linkage) mapping each fn pointer to its source name for backtraces.
 * We dlsym that table and scan it. Returns the fn address (boxed int) or nil. */
WValue w_dlfind_fn(WValue handle_val, WValue name_val) {
    void *h = (void *)(intptr_t)w_to_i64(handle_val);
    const char *want = as_str(name_val);
    WFnMeta *meta = (WFnMeta *)dlsym(h, "__w_fn_meta");
    int32_t *count = (int32_t *)dlsym(h, "__w_fn_meta_count");
    if (meta && count) {
        for (int i = 0; i < *count; i++) {
            if (meta[i].name && strcmp(meta[i].name, want) == 0) {
                return w_int((int64_t)(intptr_t)meta[i].fn_addr);
            }
        }
    }
    WFnMeta *smeta = (WFnMeta *)dlsym(h, "__w_fn_sym_meta");
    int32_t *scount = (int32_t *)dlsym(h, "__w_fn_sym_meta_count");
    if (smeta && scount) {
        for (int i = 0; i < *scount; i++) {
            if (smeta[i].name && strcmp(smeta[i].name, want) == 0 && smeta[i].fn_addr) {
                void *fn = dlsym(h, (const char *)smeta[i].fn_addr);
                if (fn) return w_int((int64_t)(intptr_t)fn);
            }
        }
    }
    return W_NIL;
}

/* ---- In-memory JIT object loader (macOS / arm64) ----
 * Load a relocatable Mach-O object (`clang -c snippet.ll -o snippet.o`) straight
 * into executable memory and call into it, WITHOUT dlopen. dlopen on macOS pays a
 * ~120ms dyld closure-build per fresh dylib; this path skips it entirely (~3ms).
 *
 * TWO regions, because W^X + writable data: executable sections (__text) go in an
 * R-X region, everything else (__const, __cstring, __bss — crucially the inline
 * caches `_.ic`, which w_method_call_cached WRITES on a miss) goes in an R-W
 * region. A per-section base map (sect_base[]) lets relocations resolve across the
 * split. We handle every arm64 relocation a Tungsten snippet emits:
 *   BRANCH26  — BL calls to runtime fns, routed through a 16-byte far-call stub
 *               (host runtime is usually >128MB past BL's ±128MB reach)
 *   UNSIGNED  — 64-bit absolute pointers (the __w_fn_meta table, vtables)
 *   PAGE21    — ADRP page-address (e.g. the address of an inline cache)
 *   PAGEOFF12 — the paired ADD/LDR/STR low-12-bits (size-scaled for loads/stores)
 *   ADDEND    — a pair entry supplying a symbol+offset addend for the adjacent reloc
 * then mprotect the code region R-X and scan __w_fn_meta for the wanted fn. Any
 * other reloc type / failure returns nil so the caller falls back to w_dlopen. */
#if defined(__APPLE__) && defined(__aarch64__)
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/arm64/reloc.h>
#include <libkern/OSCacheControl.h>

WValue w_jit_load_object(WValue path_val, WValue fn_name_val) {
    const char *path = as_str(path_val);
    const char *want = as_str(fn_name_val);

    FILE *f = fopen(path, "rb");
    if (!f) return W_NIL;
    fseek(f, 0, SEEK_END);
    long fsz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (fsz <= (long)sizeof(struct mach_header_64)) { fclose(f); return W_NIL; }
    uint8_t *fb = (uint8_t *)malloc((size_t)fsz);
    if (!fb) { fclose(f); return W_NIL; }
    if (fread(fb, 1, (size_t)fsz, f) != (size_t)fsz) { free(fb); fclose(f); return W_NIL; }
    fclose(f);

    struct mach_header_64 *mh = (struct mach_header_64 *)fb;
    if (mh->magic != MH_MAGIC_64) { free(fb); return W_NIL; }

    /* pass 1: collect sections + symtab */
    struct section_64 *sects[128];
    int nsect = 0;
    struct symtab_command *st = NULL;
    uint8_t *lc = fb + sizeof(*mh);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        struct load_command *c = (struct load_command *)lc;
        if (c->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *sg = (struct segment_command_64 *)lc;
            struct section_64 *s = (struct section_64 *)(lc + sizeof(*sg));
            for (uint32_t k = 0; k < sg->nsects && nsect < 128; k++) sects[nsect++] = &s[k];
        } else if (c->cmd == LC_SYMTAB) {
            st = (struct symtab_command *)lc;
        }
        lc += c->cmdsize;
    }
    if (!st) { free(fb); return W_NIL; }
    struct nlist_64 *syms = (struct nlist_64 *)(fb + st->symoff);
    char *strs = (char *)(fb + st->stroff);

    /* lay out each section into the code (executable) or data (writable) region,
     * honoring its alignment; reserve far-call stub space at the end of code. */
    const size_t MAX_STUBS = 4096;
    size_t sect_off[128];
    int    sect_code[128];
    size_t code_sz = 0, data_sz = 0;
    for (int i = 0; i < nsect; i++) {
        struct section_64 *s = sects[i];
        size_t al = (size_t)1 << s->align;
        if (al == 0) al = 1;
        int is_code = (s->flags & S_ATTR_PURE_INSTRUCTIONS) || (s->flags & S_ATTR_SOME_INSTRUCTIONS);
        sect_code[i] = is_code;
        size_t *cur = is_code ? &code_sz : &data_sz;
        *cur = (*cur + al - 1) & ~(al - 1);
        sect_off[i] = *cur;
        *cur += s->size;
    }
    code_sz = (code_sz + 15) & ~(size_t)15;
    size_t stub_region = code_sz;
    code_sz += MAX_STUBS * 16;

    size_t code_pages = (code_sz + 0x3fff) & ~(size_t)0x3fff; if (!code_pages) code_pages = 0x4000;
    size_t data_pages = (data_sz + 0x3fff) & ~(size_t)0x3fff; if (!data_pages) data_pages = 0x4000;
    /* Keep code and data adjacent in one mapping so ADRP (±4GB) always reaches data. */
    size_t total_pages = code_pages + data_pages;
    uint8_t *code = (uint8_t *)mmap(NULL, total_pages, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (code == MAP_FAILED) { free(fb); return W_NIL; }
    uint8_t *data = code + code_pages;

    uint8_t *sect_base[128];
    for (int i = 0; i < nsect; i++)
        sect_base[i] = (sect_code[i] ? code : data) + sect_off[i];

    /* copy section data (skip zerofill — ANON mmap already zeroed, e.g. __bss) */
    for (int i = 0; i < nsect; i++) {
        struct section_64 *s = sects[i];
        uint8_t styp = s->flags & SECTION_TYPE;
        if (styp == S_ZEROFILL || styp == S_GB_ZEROFILL) continue;
        memcpy(sect_base[i], fb + s->offset, s->size);
    }

    uint8_t *stub_base = code + stub_region;
    size_t stub_n = 0;
    int ok = 1;
    /* one stub per distinct far target (a big object calls the same runtime function
     * from thousands of sites): open-addressed target -> stub index */
    enum { STUB_TAB = 8192 };
    uint64_t *stub_key = (uint64_t *)calloc(STUB_TAB, sizeof(uint64_t));
    uint32_t *stub_idx = (uint32_t *)calloc(STUB_TAB, sizeof(uint32_t));
    if (!stub_key || !stub_idx) { free(stub_key); free(stub_idx); munmap(code, total_pages); free(fb); return W_NIL; }

    /* loaded address of symbol index `idx`: undefined → host (dlsym), else the
     * split base of its defining section + the symbol's offset within it. */
    #define JIT_RESOLVE(idx, outp) do { \
        struct nlist_64 *ns_ = &syms[idx]; \
        const char *nm_ = strs + ns_->n_un.n_strx; \
        if ((ns_->n_type & N_TYPE) == N_UNDF) { \
            void *h_ = dlsym(RTLD_DEFAULT, nm_ + 1); \
            if (!h_) ok = 0; else *(outp) = (uint64_t)(uintptr_t)h_; \
        } else if (ns_->n_sect >= 1 && ns_->n_sect <= nsect) { \
            int si_ = ns_->n_sect - 1; \
            *(outp) = (uint64_t)(uintptr_t)(sect_base[si_] + (ns_->n_value - sects[si_]->addr)); \
        } else ok = 0; \
    } while (0)

    for (int i = 0; i < nsect && ok; i++) {
        struct section_64 *s = sects[i];
        /* unwind and debug tables are never read in a loaded object (Tungsten raises
         * through setjmp/longjmp, not unwinding), so their relocations are left alone */
        if (strncmp(s->segname, "__LD", 16) == 0 || strncmp(s->segname, "__DWARF", 16) == 0 ||
            strncmp(s->sectname, "__eh_frame", 16) == 0) continue;
        struct relocation_info *r = (struct relocation_info *)(fb + s->reloff);
        for (uint32_t k = 0; k < s->nreloc && ok; k++) {
            struct relocation_info ri = r[k];
            if (ri.r_type == ARM64_RELOC_ADDEND) continue;  /* handled via neighbor below */
            if (!ri.r_extern) { ok = 0; break; }            /* section-based reloc: unsupported */

            /* an ADDEND pair entry shares this reloc's r_address and sits adjacent
             * (either side, depending on toolchain ordering); fold it in. */
            int64_t addend = 0;
            if (k > 0 && r[k - 1].r_type == ARM64_RELOC_ADDEND && r[k - 1].r_address == ri.r_address)
                addend = (int64_t)((int32_t)(r[k - 1].r_symbolnum << 8) >> 8);
            else if (k + 1 < s->nreloc && r[k + 1].r_type == ARM64_RELOC_ADDEND && r[k + 1].r_address == ri.r_address)
                addend = (int64_t)((int32_t)(r[k + 1].r_symbolnum << 8) >> 8);

            uint8_t *loc = sect_base[i] + ri.r_address;
            uint64_t target = 0;
            JIT_RESOLVE(ri.r_symbolnum, &target);
            if (!ok) break;
            uint64_t tgt = target + (uint64_t)addend;

            switch (ri.r_type) {
            case ARM64_RELOC_UNSIGNED: {
                uint64_t inl = *(uint64_t *)loc;            /* inline addend */
                *(uint64_t *)loc = tgt + inl;
                break;
            }
            case ARM64_RELOC_BRANCH26: {
                int64_t disp = (int64_t)tgt - (int64_t)(uintptr_t)loc;
                if (disp > (1 << 27) - 1 || disp < -(1 << 27)) {  /* out of BL ±128MB → stub */
                    uint64_t h = (tgt >> 2) * 0x9E3779B97F4A7C15ull;
                    size_t slot = (size_t)(h >> 51) & (STUB_TAB - 1);
                    while (stub_key[slot] != 0 && stub_key[slot] != tgt) slot = (slot + 1) & (STUB_TAB - 1);
                    uint8_t *stub;
                    if (stub_key[slot] == tgt) {
                        stub = stub_base + (size_t)stub_idx[slot] * 16;
                    } else {
                        if (stub_n >= MAX_STUBS) { ok = 0; break; }
                        stub = stub_base + stub_n * 16;
                        stub_key[slot] = tgt;
                        stub_idx[slot] = (uint32_t)stub_n;
                        stub_n++;
                        ((uint32_t *)stub)[0] = 0x58000050;   /* ldr x16, [pc, #8] */
                        ((uint32_t *)stub)[1] = 0xd61f0200;   /* br  x16          */
                        *(uint64_t *)(stub + 8) = tgt;
                    }
                    disp = (int64_t)(uintptr_t)stub - (int64_t)(uintptr_t)loc;
                }
                uint32_t ins = *(uint32_t *)loc;
                ins = (ins & 0xFC000000u) | (((uint32_t)(disp >> 2)) & 0x03FFFFFFu);
                *(uint32_t *)loc = ins;
                break;
            }
            case ARM64_RELOC_PAGE21: {                    /* ADRP */
                int64_t pd = (int64_t)(tgt & ~0xFFFULL) - (int64_t)((uintptr_t)loc & ~0xFFFULL);
                int64_t imm = pd >> 12;
                if (imm < -(1 << 20) || imm >= (1 << 20)) { ok = 0; break; }  /* ADRP ±4GB */
                uint32_t ins = *(uint32_t *)loc;
                ins = (ins & 0x9F00001Fu) | ((uint32_t)(imm & 0x3) << 29) | ((uint32_t)((imm >> 2) & 0x7FFFF) << 5);
                *(uint32_t *)loc = ins;
                break;
            }
            case ARM64_RELOC_PAGEOFF12: {                 /* ADD / LDR / STR low 12 bits */
                uint32_t off = (uint32_t)(tgt & 0xFFF);
                uint32_t ins = *(uint32_t *)loc;
                if ((ins & 0x3B000000u) == 0x39000000u) { /* LDR/STR unsigned-imm: scale by size */
                    uint32_t scale = ins >> 30;
                    off >>= scale;
                }
                ins = (ins & ~(0xFFFu << 10)) | ((off & 0xFFFu) << 10);
                *(uint32_t *)loc = ins;
                break;
            }
            default:
                ok = 0;  /* GOT/TLV/etc. — fall back to dlopen */
                break;
            }
        }
    }
    #undef JIT_RESOLVE
    free(stub_key);
    free(stub_idx);
    /* NB: keep `fb` alive — the symbol/string tables scanned below live in it,
     * not in the loaded regions (only section *data* was copied). */
    if (!ok) { munmap(code, total_pages); free(fb); return W_NIL; }

    if (mprotect(code, code_pages, PROT_READ | PROT_EXEC) != 0) {
        munmap(code, total_pages); free(fb); return W_NIL;
    }
    sys_icache_invalidate(code, code_pages);  /* data region stays R-W (inline caches) */

    /* locate __w_fn_meta / __w_fn_meta_count (or __w_fn_sym_meta), scan for `want` */
    uint64_t meta_a = 0, cnt_a = 0, smeta_a = 0, scnt_a = 0;
    for (uint32_t i = 0; i < st->nsyms; i++) {
        struct nlist_64 *ns = &syms[i];
        if ((ns->n_type & N_TYPE) == N_UNDF || ns->n_sect < 1 || ns->n_sect > nsect) continue;
        const char *nm = strs + ns->n_un.n_strx;
        uint64_t a = (uint64_t)(uintptr_t)(sect_base[ns->n_sect - 1] + (ns->n_value - sects[ns->n_sect - 1]->addr));
        if (!meta_a && strcmp(nm, "___w_fn_meta") == 0) meta_a = a;
        else if (!cnt_a && strcmp(nm, "___w_fn_meta_count") == 0) cnt_a = a;
        else if (!smeta_a && strcmp(nm, "___w_fn_sym_meta") == 0) smeta_a = a;
        else if (!scnt_a && strcmp(nm, "___w_fn_sym_meta_count") == 0) scnt_a = a;
    }
    WValue result = W_NIL;  /* regions intentionally leaked on success: code stays live */
    if (meta_a && cnt_a) {
        int cnt = *(int32_t *)(uintptr_t)cnt_a;
        WFnMeta *m = (WFnMeta *)(uintptr_t)meta_a;
        for (int i = 0; i < cnt; i++) {
            if (m[i].name && strcmp(m[i].name, want) == 0) {
                result = w_int((int64_t)(intptr_t)m[i].fn_addr);
                break;
            }
        }
    }
    if (result == W_NIL && smeta_a && scnt_a) {
        int cnt = *(int32_t *)(uintptr_t)scnt_a;
        WFnMeta *m = (WFnMeta *)(uintptr_t)smeta_a;
        for (int i = 0; i < cnt && result == W_NIL; i++) {
            if (m[i].name && strcmp(m[i].name, want) == 0 && m[i].fn_addr) {
                const char *want_sym = (const char *)m[i].fn_addr;
                for (uint32_t k = 0; k < st->nsyms; k++) {
                    struct nlist_64 *ns = &syms[k];
                    if ((ns->n_type & N_TYPE) == N_UNDF || ns->n_sect < 1 || ns->n_sect > nsect) continue;
                    const char *nm = strs + ns->n_un.n_strx;
                    if (strcmp(nm, want_sym) == 0 || (nm[0] == '_' && strcmp(nm + 1, want_sym) == 0)) {
                        uint64_t a = (uint64_t)(uintptr_t)(sect_base[ns->n_sect - 1] + (ns->n_value - sects[ns->n_sect - 1]->addr));
                        result = w_int((int64_t)(intptr_t)a);
                        break;
                    }
                }
            }
        }
    }
    if (result == W_NIL) {
        /* no metadata row: the function's profiler alias `w:<name>` (a hidden external
         * symbol in the object; a compiled JavaScript unit's jsu_init is found this way) */
        size_t wl = strlen(want);
        for (uint32_t k = 0; k < st->nsyms && result == W_NIL; k++) {
            struct nlist_64 *ns = &syms[k];
            if ((ns->n_type & N_TYPE) == N_UNDF || ns->n_sect < 1 || ns->n_sect > nsect) continue;
            const char *nm = strs + ns->n_un.n_strx;
            if (strncmp(nm, "_w:", 3) == 0 && strlen(nm + 3) == wl && memcmp(nm + 3, want, wl) == 0) {
                uint64_t a = (uint64_t)(uintptr_t)(sect_base[ns->n_sect - 1] + (ns->n_value - sects[ns->n_sect - 1]->addr));
                result = w_int((int64_t)(intptr_t)a);
            }
        }
    }
    free(fb);  /* now safe: meta scan done, loaded regions are independent */
    return result;
}
#else
WValue w_jit_load_object(WValue path_val, WValue fn_name_val) {
    (void)path_val; (void)fn_name_val;
    return W_NIL;  /* non-Apple/non-arm64: caller falls back to w_dlopen */
}
#endif

WValue w_read_bytes(WValue count_val) {
    int64_t count = w_as_int(count_val);
    /* Cap guards against a bogus/huge Content-Length; 64 MiB is generous for
     * any real stdin payload (e.g. an LSP didOpen document). */
    if (count <= 0 || count > (64 * 1024 * 1024)) return w_string("");
    char *buf = malloc(count + 1);
    if (!buf) return w_string("");
    /* Read via the buffered FILE* stdin — NOT a raw read(STDIN_FILENO). A raw
     * syscall bypasses stdin's buffer, so it desyncs with w_read_line_stdin
     * (getline), which buffers ahead: callers that read framed headers by line
     * then a fixed-size body (LSP) would get garbage. fread shares the buffer.
     * Loop to read exactly `count` bytes (fread may return short). */
    size_t total = 0;
    while (total < (size_t)count) {
        size_t n = fread(buf + total, 1, (size_t)count - total, stdin);
        if (n == 0) break; /* EOF or error */
        total += n;
    }
    buf[total] = '\0';
    if (total == 0) { free(buf); return w_string(""); }
    return w_string_take(buf, total);
}


typedef struct {
    pid_t pid;
    int own_group;
} WSystemChild;

/* A cancelled Thread must not strand the process it was waiting for.  Spawn
 * each shell as a process-group leader, then terminate and reap that whole
 * group from pthread cancellation cleanup.  GPU epoch commands often grow a
 * shell -> flipfleet child tree, so killing only the shell is insufficient. */
static void w_system_child_cleanup(void *arg) {
    WSystemChild *child = (WSystemChild *)arg;
    if (child->pid <= 0) return;

    int old_cancel_state;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old_cancel_state);

    pid_t pid = child->pid;
    int status;
    kill(child->own_group ? -pid : pid, SIGTERM);
    for (int attempt = 0; attempt < 10; attempt++) {
        pid_t waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid || (waited == -1 && errno == ECHILD)) {
            child->pid = -1;
            pthread_setcancelstate(old_cancel_state, NULL);
            return;
        }
        struct timespec grace = { .tv_sec = 0, .tv_nsec = 10000000 };
        nanosleep(&grace, NULL);
    }

    kill(child->own_group ? -pid : pid, SIGKILL);
    while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}
    child->pid = -1;
    pthread_setcancelstate(old_cancel_state, NULL);
}

/* An outer stage supervisor can own one group across Tungsten worker pools.
 * Default Process.spawn/system semantics retain a separate child group. */
static int w_child_own_group(void) {
    const char *inherit = getenv("TUNGSTEN_INHERIT_PROCESS_GROUP");
    return !(inherit && !strcmp(inherit, "1"));
}

/* posix_spawn instead of system(3): system() sets SIGINT/SIGQUIT to SIG_IGN
 * in THIS process for the child's whole lifetime, so a program with
 * long-running children (flipfleet GPU epochs, clang links) becomes
 * uninterruptible from the keyboard whenever any thread is inside system(). */
WValue __w_system(WValue cmd_val) {
    const char *cmd = as_str(cmd_val);
    w_sandbox_gate("system", cmd);
    char *spawn_argv[] = { "sh", "-c", (char *)cmd, NULL };
    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) return W_FALSE;
    int own_group = w_child_own_group();
    short flags = own_group ? POSIX_SPAWN_SETPGROUP : 0;
    if (posix_spawnattr_setflags(&attr, flags) != 0 ||
        (own_group && posix_spawnattr_setpgroup(&attr, 0) != 0)) {
        posix_spawnattr_destroy(&attr);
        return W_FALSE;
    }

    WSystemChild child = { .pid = -1, .own_group = own_group };
    int spawn_error = posix_spawn(&child.pid, "/bin/sh", NULL, &attr,
                                  spawn_argv, environ);
    posix_spawnattr_destroy(&attr);
    if (spawn_error != 0) return W_FALSE;

    int status;
    int wait_ok = 0;
    pthread_cleanup_push(w_system_child_cleanup, &child);
    for (;;) {
        pid_t waited = waitpid(child.pid, &status, 0);
        if (waited == child.pid) {
            child.pid = -1;
            wait_ok = 1;
            break;
        }
        if (waited == -1 && errno != EINTR) break;
    }
    pthread_cleanup_pop(wait_ok ? 0 : 1);

    if (wait_ok && WIFEXITED(status) && WEXITSTATUS(status) == 0) return W_TRUE;
    return W_FALSE;
}

