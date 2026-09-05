/* Matched scheduler benchmark: public runtime APIs only, no runtime.c include.
 * Each process runs one cell. Setup is untimed; MP includes submission and
 * completion notification, while cooperative cells time w_scheduler_run().
 * "ready" reads an already-readable socket BEFORE considering a park.
 * "ready-park" deliberately forces a park and is a separate stress workload.
 */
#include <runtime.h>
#include <event_loop.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

#define REQUIRE(x) do { if (!(x)) { \
    fprintf(stderr, "check failed at line %d: %s (errno=%d)\n", __LINE__, #x, errno); \
    abort(); \
} } while (0)

enum BenchMode { COOP, MP, SHARDED, READY, READY_PARK, DEADLINE };
typedef struct {
    _Alignas(64) WClosure closure;
    WValue capture;
    uint64_t checksum;
    uint64_t completed;
    _Atomic uint64_t mp_progress;
    int fd;
    int peer;
    int id;
    int rounds;
    enum BenchMode mode;
} BenchTask;
static _Atomic int mp_finished;
static _Atomic int sharded_ready, sharded_go;
static int64_t one_ms_ticks;
typedef struct {
    _Alignas(64) pthread_t thread;
    BenchTask *tasks;
    int first, count;
    uint64_t completed, checksum;
} BenchWorker;

static uint64_t clock_ns(void) {
    struct timespec now;
    REQUIRE(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static double cpu_ms(const struct rusage *r) {
    return (r->ru_utime.tv_sec + r->ru_stime.tv_sec) * 1000.0 +
           (r->ru_utime.tv_usec + r->ru_stime.tv_usec) / 1000.0;
}

static WValue bench_body(WValue *captures) {
    BenchTask *task = w_as_ptr(captures[0]);
    uint64_t sum = 0;
    int64_t ready_deadline = task->mode == READY || task->mode == READY_PARK
        ? __w_deadline_ticks_after_seconds(30) : 0;
    for (int i = 0; i < task->rounds; i++) {
        if (task->mode == MP) {
            /* Detect repeat/lost execution; keep this cost OUT of coop cells. */
            REQUIRE(atomic_fetch_add_explicit(&task->mp_progress, 1,
                    memory_order_relaxed) == (uint64_t)i);
        }
        if (task->mode == READY || task->mode == READY_PARK) {
            unsigned char byte = 0;
            if (task->mode == READY_PARK)
                REQUIRE(w_socket_park_until(task->fd, W_EVENT_READ, ready_deadline) == 1);
            REQUIRE(w_socket_read_fd_until(task->fd, (int64_t)(uintptr_t)&byte,
                                          1, ready_deadline) == 1);
            REQUIRE(byte == (unsigned char)(1 + (i & 127)));
            sum += byte;
        } else if (task->mode == DEADLINE) {
            int64_t deadline = __w_clock_ticks_raw() + one_ms_ticks;
            REQUIRE(w_socket_park_until(task->fd, W_EVENT_READ, deadline) == 0);
            REQUIRE(__w_clock_ticks_raw() >= deadline);
            sum += (uint64_t)i + (uint64_t)task->id + 1;
        } else {
            sum += (uint64_t)i + (uint64_t)task->id + 1;
        }
        task->completed++;
        w_goroutine_yield();
    }
    task->checksum = sum;
    if (task->mode == MP)
        atomic_fetch_add_explicit(&mp_finished, 1, memory_order_release);
    return W_NIL;
}

static void *bench_sharded_worker(void *opaque) {
    BenchWorker *worker = opaque;
    for (int i = worker->first; i < worker->first + worker->count; i++)
        w_goroutine_spawn(w_box_ptr(&worker->tasks[i].closure, W_SUBTAG_CLOSURE));
    atomic_fetch_add_explicit(&sharded_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&sharded_go, memory_order_acquire)) sched_yield();
    w_scheduler_run();
    for (int i = worker->first; i < worker->first + worker->count; i++) {
        worker->completed += worker->tasks[i].completed;
        worker->checksum += worker->tasks[i].checksum;
    }
    return NULL;
}

static int bounded_int(const char *s, int low, int high) {
    char *end = NULL;
    errno = 0;
    long n = strtol(s, &end, 10);
    if (errno || *end || n < low || n > high) return 0;
    return (int)n;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: %s coop|mp|sharded|ready|ready-park|deadline TASKS ROUNDS WORKERS\n", argv[0]);
        return 2;
    }
    enum BenchMode mode;
    if (!strcmp(argv[1], "coop")) mode = COOP;
    else if (!strcmp(argv[1], "mp")) mode = MP;
    else if (!strcmp(argv[1], "sharded")) mode = SHARDED;
    else if (!strcmp(argv[1], "ready")) mode = READY;
    else if (!strcmp(argv[1], "ready-park")) mode = READY_PARK;
    else if (!strcmp(argv[1], "deadline")) mode = DEADLINE;
    else return 2;
    int tasks = bounded_int(argv[2], 1, 4096);
    int rounds = bounded_int(argv[3], 1, 100000000);
    int workers = bounded_int(argv[4], 1, 64);
    if (!tasks || !rounds || !workers ||
        ((mode == READY || mode == READY_PARK) && rounds > 4096) ||
        (mode == DEADLINE && rounds > 5000) ||
        (mode != MP && mode != SHARDED && workers != 1) ||
        (mode == SHARDED && (tasks < workers || tasks % workers))) return 2;
    /* External runner also times out and kills the complete process group. */
    alarm(30);
    one_ms_ticks = 1000000;
#ifdef __APPLE__
    mach_timebase_info_data_t tb;
    REQUIRE(mach_timebase_info(&tb) == KERN_SUCCESS);
    one_ms_ticks = (int64_t)((UINT64_C(1000000) * tb.denom + tb.numer - 1) / tb.numer);
#endif
    BenchTask *args = NULL;
    REQUIRE(posix_memalign((void **)&args, _Alignof(BenchTask),
                          sizeof(*args) * (size_t)tasks) == 0);
    memset(args, 0, sizeof(*args) * (size_t)tasks);
    if (mode == READY || mode == READY_PARK || mode == DEADLINE) {
        struct rlimit lim;
        REQUIRE(getrlimit(RLIMIT_NOFILE, &lim) == 0);
        rlim_t needed = (rlim_t)tasks * 2 + 64;
        if (lim.rlim_cur < needed) {
            REQUIRE(lim.rlim_max >= needed);
            lim.rlim_cur = needed;
            REQUIRE(setrlimit(RLIMIT_NOFILE, &lim) == 0);
        }
    }
    for (int i = 0; i < tasks; i++) {
        BenchTask *task = &args[i];
        task->id = i;
        task->rounds = rounds;
        task->mode = mode;
        task->fd = task->peer = -1;
        atomic_init(&task->mp_progress, 0);
        task->capture = w_box_ptr(task, W_SUBTAG_GENERIC);
        task->closure.fn_ptr = bench_body;
        task->closure.captures = &task->capture;
        task->closure.capture_count = 1;
        if (mode == READY || mode == READY_PARK || mode == DEADLINE) {
            int fds[2];
            REQUIRE(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
            task->fd = fds[0];
            task->peer = fds[1];
            REQUIRE(fcntl(task->fd, F_SETFL, O_NONBLOCK) == 0);
            if (mode != DEADLINE) {
                unsigned char payload[4096];
                for (int j = 0; j < rounds; j++) payload[j] = (unsigned char)(1 + (j & 127));
                REQUIRE(write(task->peer, payload, (size_t)rounds) == rounds);
            }
        }
    }
    BenchWorker *shards = NULL;
    if (mode == MP) w_scheduler_start(w_box_int(workers));
    else if (mode == SHARDED) {
        /* Initialize the shared arena before independent cooperative workers.
         * Their run queues/event loops remain thread-local, as in Forge. */
        w_scheduler_init();
        REQUIRE(posix_memalign((void **)&shards, _Alignof(BenchWorker),
                              sizeof(*shards) * (size_t)workers) == 0);
        memset(shards, 0, sizeof(*shards) * (size_t)workers);
        for (int i = 0; i < workers; i++) {
            shards[i].tasks = args;
            shards[i].first = i * (tasks / workers);
            shards[i].count = tasks / workers;
            REQUIRE(pthread_create(&shards[i].thread, NULL, bench_sharded_worker, &shards[i]) == 0);
        }
        while (atomic_load_explicit(&sharded_ready, memory_order_acquire) != workers)
            sched_yield();
    } else for (int i = 0; i < tasks; i++)
        w_goroutine_spawn(w_box_ptr(&args[i].closure, W_SUBTAG_CLOSURE));
    struct rusage before, after;
    REQUIRE(getrusage(RUSAGE_SELF, &before) == 0);
    uint64_t start = clock_ns();
    if (mode == MP) {
        for (int i = 0; i < tasks; i++)
            w_goroutine_spawn(w_box_ptr(&args[i].closure, W_SUBTAG_CLOSURE));
        struct timespec poll = { .tv_nsec = 100000 };
        while (atomic_load_explicit(&mp_finished, memory_order_acquire) != tasks)
            nanosleep(&poll, NULL);
    } else if (mode == SHARDED) {
        atomic_store_explicit(&sharded_go, 1, memory_order_release);
        for (int i = 0; i < workers; i++) REQUIRE(pthread_join(shards[i].thread, NULL) == 0);
    } else w_scheduler_run();
    uint64_t elapsed = clock_ns() - start;
    REQUIRE(getrusage(RUSAGE_SELF, &after) == 0);
    if (mode == MP) w_scheduler_stop();
    uint64_t checksum = 0, completed = 0, expected_checksum = 0;
    for (int i = 0; i < tasks; i++) {
        REQUIRE(args[i].completed == (uint64_t)rounds);
        if (mode == MP) REQUIRE(atomic_load(&args[i].mp_progress) == (uint64_t)rounds);
        uint64_t expected = 0;
        if (mode == READY || mode == READY_PARK)
            for (int j = 0; j < rounds; j++) expected += 1 + (j & 127);
        else expected = (uint64_t)rounds * ((uint64_t)rounds - 1) / 2 +
                        (uint64_t)rounds * ((uint64_t)i + 1);
        REQUIRE(args[i].checksum == expected);
        expected_checksum += expected;
        checksum += args[i].checksum;
        completed += args[i].completed;
        if (args[i].fd >= 0) { close(args[i].fd); close(args[i].peer); }
    }
    if (mode == SHARDED) {
        for (int i = 0; i < workers; i++) {
            uint64_t count = (uint64_t)shards[i].count, first = (uint64_t)shards[i].first;
            uint64_t want = count * (uint64_t)rounds * ((uint64_t)rounds - 1) / 2 +
                (uint64_t)rounds * count * (2 * first + count + 1) / 2;
            REQUIRE(shards[i].completed == count * (uint64_t)rounds);
            REQUIRE(shards[i].checksum == want);
        }
    }
    printf("{\"mode\":\"%s\",\"tasks\":%d,\"rounds\":%d,\"workers\":%d,"
           "\"completed\":%" PRIu64 ",\"checksum\":%" PRIu64 ","
           "\"expected_checksum\":%" PRIu64 ",\"wall_ms\":%.6f,\"ns_per_op\":%.6f,"
           "\"cpu_ms\":%.6f,\"voluntary_switches\":%ld,\"involuntary_switches\":%ld",
           argv[1], tasks, rounds, workers, completed, checksum, expected_checksum,
           elapsed / 1e6, (double)elapsed / completed,
           cpu_ms(&after) - cpu_ms(&before), after.ru_nvcsw - before.ru_nvcsw,
           after.ru_nivcsw - before.ru_nivcsw);
    if (mode == SHARDED) {
        printf(",\"worker_checksums\":[");
        for (int i = 0; i < workers; i++) printf("%s%" PRIu64, i ? "," : "", shards[i].checksum);
        printf("]");
    }
    printf("}\n");
    free(shards);
    free(args);
    return 0;
}
