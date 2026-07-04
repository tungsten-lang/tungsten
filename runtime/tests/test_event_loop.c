/*
 * test_event_loop.c — Phase 6: Event loop + non-blocking I/O tests
 *
 * Tests:
 * 1. Event loop init/destroy
 * 2. Non-blocking accept: goroutine parks, client connects, poll wakes goroutine
 * 3. Non-blocking read: goroutine parks, client sends, poll wakes goroutine
 * 4. Multiple goroutines on different fds, all wake correctly
 * 5. M:P scheduler + event loop: goroutines doing socket I/O on loopback
 * 6. Two cooperative scheduler threads with fd deadline timeouts
 */

#include "../runtime.h"
#include "../event_loop.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <signal.h>
#include <time.h>

static int pass_count = 0;
static int test_count = 0;

#define ASSERT(cond, msg) do { \
    test_count++; \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
    } else { \
        pass_count++; \
    } \
} while(0)

/* Helper: create a listening socket on a random port, return fd + port */
static int make_listener(int *out_port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;  /* OS picks a port */
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    listen(fd, 128);

    socklen_t len = sizeof(addr);
    getsockname(fd, (struct sockaddr *)&addr, &len);
    *out_port = ntohs(addr.sin_port);

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    return fd;
}

/* Helper: connect to loopback:port */
static int connect_to(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    return fd;
}

/* ---- Test 1: Event loop init/destroy ---- */
static void test_init_destroy(void) {
    printf("\nTest 1: Event loop init/destroy\n");
    WEventLoop *el = w_event_init();
    ASSERT(el != NULL, "event loop created");
    w_event_destroy(el);
    printf("  Event loop init/destroy: OK\n");
}

/* ---- Test 2: Non-blocking accept with event polling ---- */
static void test_nonblocking_accept(void) {
    printf("\nTest 2: Non-blocking accept via event loop\n");

    WEventLoop *el = w_event_init();
    int port;
    int listener_fd = make_listener(&port);

    /* Try accept — should EAGAIN since no client yet */
    struct sockaddr_in ca;
    socklen_t cl = sizeof(ca);
    int conn = accept(listener_fd, (struct sockaddr *)&ca, &cl);
    ASSERT(conn < 0 && (errno == EAGAIN || errno == EWOULDBLOCK),
           "accept returns EAGAIN on empty non-blocking socket");

    /* Register interest: when listener becomes readable, wake "goroutine" */
    /* We use a fake goroutine pointer as a tag since we're testing the event loop directly */
    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.wait_fd = listener_fd;

    w_event_register(el, listener_fd, W_EVENT_READ, &fake_g);

    /* Poll with short timeout — should return 0 (no events yet) */
    WGoroutine *woken[8];
    int n = w_event_poll(el, 0, woken, 8);
    ASSERT(n == 0, "poll returns 0 before client connects");

    /* Client connects */
    int client = connect_to(port);

    /* Poll again — should wake our goroutine */
    n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1 after client connects");
    ASSERT(woken[0] == &fake_g, "woken goroutine is the one we registered");

    /* Now accept should succeed */
    conn = accept(listener_fd, (struct sockaddr *)&ca, &cl);
    ASSERT(conn >= 0, "accept succeeds after poll woke goroutine");

    close(conn);
    close(client);
    close(listener_fd);
    w_event_destroy(el);
    printf("  Non-blocking accept: OK\n");
}

/* ---- Test 3: Non-blocking read with event polling ---- */
static void test_nonblocking_read(void) {
    printf("\nTest 3: Non-blocking read via event loop\n");

    WEventLoop *el = w_event_init();
    int port;
    int listener_fd = make_listener(&port);

    /* Connect a client */
    int client = connect_to(port);

    /* Wait for connection to arrive at listener */
    struct pollfd pfd = { .fd = listener_fd, .events = POLLIN };
    poll(&pfd, 1, 200);

    struct sockaddr_in ca;
    socklen_t cl = sizeof(ca);
    int server_conn = accept(listener_fd, (struct sockaddr *)&ca, &cl);
    ASSERT(server_conn >= 0, "accepted connection");
    fcntl(server_conn, F_SETFL, fcntl(server_conn, F_GETFL) | O_NONBLOCK);

    /* Try read — should EAGAIN */
    char buf[256];
    ssize_t bytes = read(server_conn, buf, sizeof(buf));
    ASSERT(bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK),
           "read returns EAGAIN on empty connection");

    /* Register for read events */
    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    w_event_register(el, server_conn, W_EVENT_READ, &fake_g);

    /* Client sends data */
    const char *msg = "Hello from client";
    write(client, msg, strlen(msg));

    /* Poll — should wake */
    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1 after client sends data");
    ASSERT(woken[0] == &fake_g, "correct goroutine woken");

    /* Now read should succeed */
    bytes = read(server_conn, buf, sizeof(buf) - 1);
    ASSERT(bytes > 0, "read succeeds after poll");
    buf[bytes] = '\0';
    ASSERT(strcmp(buf, "Hello from client") == 0, "read correct data");

    close(server_conn);
    close(client);
    close(listener_fd);
    w_event_destroy(el);
    printf("  Non-blocking read: OK\n");
}

/* ---- Test 4: Multiple goroutines on different fds ---- */
static void test_multiple_fds(void) {
    printf("\nTest 4: 10 goroutines on different fds\n");

    WEventLoop *el = w_event_init();
    int ports[10];
    int listeners[10];
    int clients[10];
    WGoroutine fakes[10];

    for (int i = 0; i < 10; i++) {
        listeners[i] = make_listener(&ports[i]);
        memset(&fakes[i], 0, sizeof(WGoroutine));
        w_event_register(el, listeners[i], W_EVENT_READ, &fakes[i]);
    }

    /* Connect to all 10 listeners */
    for (int i = 0; i < 10; i++) {
        clients[i] = connect_to(ports[i]);
    }

    /* Small delay for connections to propagate */
    usleep(5000);

    /* Poll — should wake all 10 */
    WGoroutine *woken[16];
    int total = 0;
    /* May need multiple polls to get all events */
    for (int attempt = 0; attempt < 5 && total < 10; attempt++) {
        int n = w_event_poll(el, 50, woken + total, 16 - total);
        if (n > 0) total += n;
    }
    ASSERT(total == 10, "all 10 goroutines woken");

    /* Verify each unique goroutine was woken */
    int seen[10] = {0};
    for (int i = 0; i < total; i++) {
        for (int j = 0; j < 10; j++) {
            if (woken[i] == &fakes[j]) seen[j] = 1;
        }
    }
    int all_seen = 1;
    for (int i = 0; i < 10; i++) {
        if (!seen[i]) all_seen = 0;
    }
    ASSERT(all_seen, "each goroutine woken exactly once");

    for (int i = 0; i < 10; i++) {
        close(clients[i]);
        close(listeners[i]);
    }
    w_event_destroy(el);
    printf("  Multiple fds: OK\n");
}

/* ---- Test 5: Goroutines doing non-blocking I/O via scheduler ---- */

/* Handler goroutine: read, echo back, close */
static WValue echo_handler_fn(WValue *captures) {
    WValue conn = captures[0];
    WValue data = w_socket_read(conn, w_int(4096));
    if (data != W_NIL) {
        w_socket_write(conn, data);
    }
    w_socket_close(conn);
    return W_NIL;
}

static volatile int test5_accepted = 0;

/* Acceptor goroutine: accept loop, spawn handler per connection */
static WValue acceptor_fn(WValue *captures) {
    WValue listener = captures[0];
    int count = 3;
    for (int i = 0; i < count; i++) {
        WValue conn = w_socket_accept(listener);
        /* Spawn handler goroutine for this connection */
        WValue *caps = calloc(1,sizeof(WValue));
        caps[0] = conn;
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = echo_handler_fn;
        cl->captures = caps;
        cl->capture_count = 1;
        w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
        __sync_fetch_and_add(&test5_accepted, 1);
    }
    return W_NIL;
}

static volatile int test5_echoes = 0;

/* Client thread: connect, send, read echo, verify */
static void *test5_client_thread(void *arg) {
    int port = *(int *)arg;
    usleep(50000);  /* 50ms: let acceptor goroutine start and park */

    for (int i = 0; i < 3; i++) {
        int fd = connect_to(port);
        const char *msg = "echo test";
        write(fd, msg, strlen(msg));
        shutdown(fd, SHUT_WR);

        char buf[256];
        ssize_t total = 0;
        while (1) {
            ssize_t n = read(fd, buf + total, sizeof(buf) - total - 1);
            if (n <= 0) break;
            total += n;
        }
        buf[total] = '\0';
        close(fd);

        if (strcmp(buf, "echo test") == 0) {
            __sync_fetch_and_add(&test5_echoes, 1);
        } else {
            fprintf(stderr, "  FAIL: echo mismatch on conn %d: got '%s'\n", i, buf);
        }
    }
    return NULL;
}

static void test_goroutine_io(void) {
    printf("\nTest 5: Goroutines doing non-blocking socket I/O\n");

    /* Create a listening socket via runtime */
    WValue listener = w_socket_tcp_listen("127.0.0.1", 0, 128);
    WSocket *ls = (WSocket *)w_as_ptr(listener);

    /* Get the port */
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    getsockname(ls->fd, (struct sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);

    /* Spawn 1 acceptor goroutine (correct pattern: 1 acceptor per listener) */
    WValue *caps = calloc(1,sizeof(WValue));
    caps[0] = listener;
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = acceptor_fn;
    cl->captures = caps;
    cl->capture_count = 1;
    w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));

    /* Start a client thread */
    test5_echoes = 0;
    pthread_t client_thread;
    pthread_create(&client_thread, NULL, test5_client_thread, &port);

    /* Run cooperative scheduler in a loop — drive goroutines + event loop */
    for (int i = 0; i < 2000 && test5_echoes < 3; i++) {
        w_scheduler_run();
        usleep(1000);  /* 1ms between scheduler ticks */
    }

    pthread_join(client_thread, NULL);

    ASSERT(test5_echoes == 3, "all 3 echo round-trips completed");
    w_socket_close(listener);
    printf("  Goroutine I/O: OK\n");
}

/* ---- Test 6: Two cooperative schedulers waking their own fd deadlines ---- */

typedef struct DeadlineThreadArg {
    int id;
    int fds[2];
    volatile int done;
    volatile int timed_out;
    volatile long scheduler_elapsed_ms;
} DeadlineThreadArg;

static long timespec_diff_ms(struct timespec start, struct timespec end) {
    long sec = (long)(end.tv_sec - start.tv_sec);
    long nsec = (long)(end.tv_nsec - start.tv_nsec);
    return sec * 1000L + nsec / 1000000L;
}

static WValue deadline_wait_fn(WValue *captures) {
    DeadlineThreadArg *arg = (DeadlineThreadArg *)w_as_ptr(captures[0]);
    int ok = w_socket_park_until(arg->fds[0], W_EVENT_READ, __w_deadline_ticks_after_seconds(1));
    arg->timed_out = ok ? 0 : 1;
    arg->done = 1;
    return W_NIL;
}

static void *deadline_scheduler_thread(void *raw) {
    DeadlineThreadArg *arg = (DeadlineThreadArg *)raw;
    arg->fds[0] = -1;
    arg->fds[1] = -1;

    if (pipe(arg->fds) != 0) {
        arg->done = -1;
        return NULL;
    }

    fcntl(arg->fds[0], F_SETFL, fcntl(arg->fds[0], F_GETFL) | O_NONBLOCK);

    WValue *caps = calloc(1, sizeof(WValue));
    caps[0] = w_box_ptr(arg, W_SUBTAG_GENERIC);
    WClosure *cl = calloc(1, sizeof(WClosure));
    cl->fn_ptr = deadline_wait_fn;
    cl->captures = caps;
    cl->capture_count = 1;

    struct timespec start;
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
    w_scheduler_run();
    clock_gettime(CLOCK_MONOTONIC, &end);
    arg->scheduler_elapsed_ms = timespec_diff_ms(start, end);

    close(arg->fds[0]);
    close(arg->fds[1]);
    return NULL;
}

static void test_two_scheduler_threads_deadline_timeout(void) {
    printf("\nTest 6: Two cooperative schedulers with fd deadlines\n");

    DeadlineThreadArg *args[2];
    pthread_t threads[2];
    memset(args, 0, sizeof(args));

    alarm(10);
    for (int i = 0; i < 2; i++) {
        args[i] = calloc(1, sizeof(DeadlineThreadArg));
        args[i]->id = i;
        int err = pthread_create(&threads[i], NULL, deadline_scheduler_thread, args[i]);
        ASSERT(err == 0, "deadline scheduler thread created");
    }

    for (int i = 0; i < 2; i++) {
        pthread_join(threads[i], NULL);
    }
    alarm(0);

    for (int i = 0; i < 2; i++) {
        ASSERT(args[i]->done == 1, "deadline goroutine completed");
        ASSERT(args[i]->timed_out == 1, "deadline goroutine woke by timeout");
        ASSERT(args[i]->scheduler_elapsed_ms >= 500, "scheduler waited for the fd deadline");
        ASSERT(args[i]->scheduler_elapsed_ms < 5000, "scheduler returned promptly after deadline");
        free(args[i]);
    }

    printf("  Two scheduler deadline timeouts: OK\n");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);  /* unbuffered stdout for test output */

    printf("=== Phase 6: Event Loop + Non-blocking I/O ===\n");

    test_init_destroy();
    test_nonblocking_accept();
    test_nonblocking_read();
    test_multiple_fds();
    test_goroutine_io();
    test_two_scheduler_threads_deadline_timeout();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}
