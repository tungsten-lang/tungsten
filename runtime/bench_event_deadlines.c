/* Matched runtime benchmark, including private deadline-frontier operations.
 * Build the SAME harness against each checkout with DEADLINE_RUNTIME_DIR.
 * Each invocation is one cell; the alarm also bounds a broken scheduler. */
#include <runtime.c>
#include <sys/resource.h>

typedef struct {
    int fd;
    int rounds;
    int64_t deadline;
    int64_t lateness_ns;
    int completed;
} DeadlineBenchWait;

typedef struct {
    _Alignas(16) WClosure closure;
} DeadlineBenchClosure;

static int64_t bench_ticks_ns(int64_t ticks) {
#ifdef __APPLE__
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    return (int64_t)((__uint128_t)(uint64_t)ticks * tb.numer / tb.denom);
#else
    return ticks;
#endif
}

static double bench_cpu_ms(struct rusage *r) {
    return (r->ru_utime.tv_sec + r->ru_stime.tv_sec) * 1000.0 +
           (r->ru_utime.tv_usec + r->ru_stime.tv_usec) / 1000.0;
}

static WValue bench_wait(WValue *captures) {
    DeadlineBenchWait *wait = w_as_ptr(captures[0]);
    if (wait->rounds == 0) {
        if (w_socket_park_until(wait->fd, W_EVENT_READ, wait->deadline)) abort();
        wait->lateness_ns = bench_ticks_ns(__w_clock_ticks_raw() - wait->deadline);
        if (wait->lateness_ns < 0) abort();
        wait->completed = 1;
    } else {
        for (int i = 0; i < wait->rounds; i++) {
            if (!w_socket_park_until(wait->fd, W_EVENT_READ, wait->deadline)) abort();
            char byte;
            if (read(wait->fd, &byte, 1) != 1 || byte != 'x') abort();
            wait->completed++;
        }
    }
    return W_NIL;
}

static int bench_compare_i64(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s idle|ready|ready-untimed|frontier WAITERS MS|ROUNDS|ITERATIONS\n", argv[0]);
        return 2;
    }
    const char *mode = argv[1];
    int n = atoi(argv[2]), amount = atoi(argv[3]);
    if (n < 1 || n > 10000 || amount < 1 || amount > 1000000) return 2;
    alarm(20);
    struct rusage before, after;
    int64_t start, elapsed;
    int64_t *late = calloc((size_t)n, sizeof(*late));
    int completed = 0;
    long long operations = 0;

    if (strcmp(mode, "frontier") == 0) {
        WEventLoop *loop = w_event_init();
        WGoroutine *waits = calloc((size_t)n, sizeof(*waits));
        WGoroutine *out[256];
        if (!loop || !waits) abort();
        int64_t deadline = w_deadline_ticks_after_ms(60000);
        for (int i = 0; i < n; i++) {
            waits[i].state = G_WAITING;
            waits[i].wait_fd = -1;
            waits[i].wait_loop = loop;
            waits[i].wait_deadline_ticks = deadline + i;
            g_deadline_add(&waits[i]);
        }
        getrusage(RUSAGE_SELF, &before);
        start = __w_clock_ticks_raw();
        for (int i = 0; i < amount; i++) {
            if (g_next_deadline_timeout_ms(loop) <= 0) abort();
            if (g_wake_expired_deadlines(loop, out, 256) != 0) abort();
        }
        elapsed = bench_ticks_ns(__w_clock_ticks_raw() - start);
        getrusage(RUSAGE_SELF, &after);
        /* Exercise the real cleanup path before releasing fake waiters. */
        for (int i = 0; i < n; i++) {
            if (!g_try_wake_waiting(&waits[i], 0)) abort();
        }
        (void)g_wake_expired_deadlines(loop, out, 256);
        w_event_destroy(loop);
        free(waits);
        completed = n;
        operations = amount;
    } else if (strcmp(mode, "idle") == 0 || strcmp(mode, "ready") == 0 || strcmp(mode, "ready-untimed") == 0) {
        int rounds = strcmp(mode, "idle") == 0 ? 0 : amount;
        if (rounds > 128 || (!rounds && amount > 5000)) return 2;
        struct rlimit limit;
        if (getrlimit(RLIMIT_NOFILE, &limit) != 0) abort();
        rlim_t needed = (rlim_t)n * 2 + 64;
        if (limit.rlim_cur < needed) {
            if (limit.rlim_max < needed) return 3;
            limit.rlim_cur = needed;
            if (setrlimit(RLIMIT_NOFILE, &limit) != 0) return 3;
        }
        int (*fds)[2] = calloc((size_t)n, sizeof(*fds));
        DeadlineBenchWait *waits = calloc((size_t)n, sizeof(*waits));
        DeadlineBenchClosure *closures = calloc((size_t)n, sizeof(*closures));
        WValue *captures = calloc((size_t)n, sizeof(*captures));
        if (!fds || !waits || !closures || !captures || !late) abort();
        for (int i = 0; i < n; i++) {
            if (pipe(fds[i]) != 0) abort();
            if (fcntl(fds[i][0], F_SETFL, O_NONBLOCK) != 0) abort();
            waits[i].fd = fds[i][0];
            waits[i].rounds = rounds;
            if (rounds) {
                char bytes[128];
                memset(bytes, 'x', sizeof(bytes));
                if (write(fds[i][1], bytes, (size_t)rounds) != rounds) abort();
            }
            captures[i] = w_box_ptr(&waits[i], W_SUBTAG_GENERIC);
            closures[i].closure.fn_ptr = bench_wait;
            closures[i].closure.captures = &captures[i];
            closures[i].closure.capture_count = 1;
            w_goroutine_spawn(w_box_ptr(&closures[i].closure, W_SUBTAG_CLOSURE));
        }
        int64_t deadline = strcmp(mode, "ready-untimed") == 0 ? 0 : w_deadline_ticks_after_ms(rounds ? 10000 : amount);
        for (int i = 0; i < n; i++) waits[i].deadline = deadline;
        getrusage(RUSAGE_SELF, &before);
        start = __w_clock_ticks_raw();
        w_scheduler_run();
        elapsed = bench_ticks_ns(__w_clock_ticks_raw() - start);
        getrusage(RUSAGE_SELF, &after);
        for (int i = 0; i < n; i++) {
            if (waits[i].completed != (rounds ? rounds : 1)) abort();
            completed++;
            late[i] = waits[i].lateness_ns;
            close(fds[i][0]);
            close(fds[i][1]);
        }
        operations = (long long)n * (rounds ? rounds : 1);
        free(fds);
        free(waits);
        free(closures);
        free(captures);
    } else {
        return 2;
    }
    qsort(late, (size_t)n, sizeof(*late), bench_compare_i64);
    printf("{\"mode\":\"%s\",\"waiters\":%d,\"amount\":%d,\"completed\":%d,"
           "\"operations\":%lld,\"wall_ms\":%.6f,\"cpu_ms\":%.6f,"
           "\"voluntary_switches\":%ld,\"involuntary_switches\":%ld,"
           "\"p50_late_us\":%.3f,\"p99_late_us\":%.3f,\"max_late_us\":%.3f}\n",
           mode, n, amount, completed, operations, elapsed / 1e6,
           bench_cpu_ms(&after) - bench_cpu_ms(&before),
           after.ru_nvcsw - before.ru_nvcsw, after.ru_nivcsw - before.ru_nivcsw,
           late[n / 2] / 1000.0, late[(n - 1) * 99 / 100] / 1000.0,
           late[n - 1] / 1000.0);
    free(late);
    return 0;
}
