/*
 * test_iouring.c — io_uring completion I/O tests (Linux only)
 *
 * Tests Phase 1 (basic RECV/SEND/ACCEPT), Phase 4 (provided buffers,
 * multi-shot recv, SEND_ZC), and Phase 5 (registered send buffers,
 * multi-shot accept, linked SQEs).
 *
 * Compile: clang -O2 -DUSE_IOURING -luring test_iouring.c ../runtime.c \
 *          ../event_iouring.c ../event_epoll.c ../event_kqueue.c \
 *          ../tls.c -lssl -lcrypto -lm -o test_iouring
 */

#if defined(__linux__) && defined(USE_IOURING)

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
#include <errno.h>

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

/* Helper: create a non-blocking socketpair */
static void make_socketpair(int fds[2]) {
    socketpair(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0, fds);
}

/* Helper: create a listening socket on a random port */
static int make_listener(int *out_port) {
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    listen(fd, 128);
    socklen_t len = sizeof(addr);
    getsockname(fd, (struct sockaddr *)&addr, &len);
    *out_port = ntohs(addr.sin_port);
    return fd;
}

static int connect_to(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
        .sin_port = htons(port)
    };
    connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    return fd;
}

/* ---- Test 1: submit_recv + poll ---- */
static void test_submit_recv(void) {
    printf("\nTest 1: submit_recv + poll\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.id = 1;

    char buf[256];
    int rc = w_event_submit_recv(el, fds[0], buf, sizeof(buf), &fake_g);
    ASSERT(rc == 0, "submit_recv returns 0");

    /* Send data on other end */
    write(fds[1], "hello", 5);

    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1 woken goroutine");
    ASSERT(woken[0] == &fake_g, "correct goroutine woken");
    ASSERT(fake_g.io_result == 5, "io_result = 5 bytes");
    ASSERT(memcmp(buf, "hello", 5) == 0, "data matches");

    close(fds[0]); close(fds[1]);
    w_event_destroy(el);
    printf("  submit_recv: OK\n");
}

/* ---- Test 2: submit_send + poll ---- */
static void test_submit_send(void) {
    printf("\nTest 2: submit_send + poll\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.id = 2;

    int rc = w_event_submit_send(el, fds[0], "world", 5, &fake_g);
    ASSERT(rc == 0, "submit_send returns 0");

    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1");
    ASSERT(fake_g.io_result == 5, "io_result = 5 bytes sent");

    /* Verify data arrived */
    char buf[256];
    ssize_t nr = read(fds[1], buf, sizeof(buf));
    ASSERT(nr == 5, "5 bytes received");
    ASSERT(memcmp(buf, "world", 5) == 0, "data matches");

    close(fds[0]); close(fds[1]);
    w_event_destroy(el);
    printf("  submit_send: OK\n");
}

/* ---- Test 3: submit_accept + poll ---- */
static void test_submit_accept(void) {
    printf("\nTest 3: submit_accept + poll\n");
    WEventLoop *el = w_event_init();
    int port;
    int listener = make_listener(&port);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.id = 3;

    struct sockaddr_in addr;
    socklen_t addrlen = sizeof(addr);
    int rc = w_event_submit_accept(el, listener, (struct sockaddr *)&addr, &addrlen, &fake_g);
    ASSERT(rc == 0, "submit_accept returns 0");

    /* Connect a client */
    int client = connect_to(port);

    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1");
    ASSERT(fake_g.io_result >= 0, "io_result is a valid fd");

    if (fake_g.io_result >= 0) close(fake_g.io_result);
    close(client);
    close(listener);
    w_event_destroy(el);
    printf("  submit_accept: OK\n");
}

/* ---- Test 4: EOF handling ---- */
static void test_eof(void) {
    printf("\nTest 4: EOF handling\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));

    /* Close sender, then submit recv */
    close(fds[1]);

    char buf[256];
    w_event_submit_recv(el, fds[0], buf, sizeof(buf), &fake_g);

    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n == 1, "poll returns 1");
    ASSERT(fake_g.io_result == 0, "io_result = 0 (EOF)");

    close(fds[0]);
    w_event_destroy(el);
    printf("  EOF: OK\n");
}

/* ---- Test 5: CQE advance correctness ---- */
static void test_cqe_advance(void) {
    printf("\nTest 5: CQE advance correctness\n");
    WEventLoop *el = w_event_init();

    /* Submit 4 operations on 4 socketpairs */
    int pairs[4][2];
    WGoroutine gs[4];
    char bufs[4][64];

    for (int i = 0; i < 4; i++) {
        make_socketpair(pairs[i]);
        memset(&gs[i], 0, sizeof(WGoroutine));
        gs[i].id = 10 + i;
        w_event_submit_recv(el, pairs[i][0], bufs[i], 64, &gs[i]);
        write(pairs[i][1], "test", 4);
    }

    /* Harvest all 4 CQEs */
    WGoroutine *woken[8];
    int total = 0;
    for (int attempt = 0; attempt < 5 && total < 4; attempt++) {
        int n = w_event_poll(el, 50, woken + total, 8 - total);
        if (n > 0) total += n;
    }
    ASSERT(total == 4, "all 4 goroutines woken");

    /* Verify ring isn't stalled — submit another op */
    WGoroutine g5;
    memset(&g5, 0, sizeof(g5));
    char buf5[64];
    int fds2[2];
    make_socketpair(fds2);
    w_event_submit_recv(el, fds2[0], buf5, 64, &g5);
    write(fds2[1], "ok", 2);
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n >= 1, "ring not stalled after draining");

    for (int i = 0; i < 4; i++) { close(pairs[i][0]); close(pairs[i][1]); }
    close(fds2[0]); close(fds2[1]);
    w_event_destroy(el);
    printf("  CQE advance: OK\n");
}

/* ---- Test 6: Provided buffer ring (multi-shot recv) ---- */
static void test_provided_buffers(void) {
    printf("\nTest 6: Provided buffer ring + multi-shot recv\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.io_buf_id = -1;

    int rc = w_event_submit_recv_multishot(el, fds[0], &fake_g);
    if (rc < 0) {
        printf("  SKIP: multi-shot recv not supported\n");
        close(fds[0]); close(fds[1]);
        w_event_destroy(el);
        return;
    }

    /* Send data */
    write(fds[1], "provided", 8);

    WGoroutine *woken[8];
    int n = w_event_poll(el, 200, woken, 8);
    ASSERT(n >= 1, "poll returns at least 1");
    ASSERT(fake_g.io_result == 8, "io_result = 8 bytes");
    ASSERT(fake_g.io_buf_id >= 0, "buffer ID assigned");

    if (fake_g.io_buf_id >= 0) {
        /* Return buffer */
        w_event_return_buf(el, fake_g.io_buf_id);
        fake_g.io_buf_id = -1;
    }

    close(fds[0]); close(fds[1]);
    w_event_destroy(el);
    printf("  Provided buffers: OK\n");
}

/* ---- Test 7: SEND_ZC two-CQE protocol ---- */
static void test_send_zc(void) {
    printf("\nTest 7: SEND_ZC two-CQE protocol\n");
    WEventLoop *el = w_event_init();

    /* SEND_ZC requires TCP sockets (not AF_UNIX socketpairs) */
    int port;
    int listener = make_listener(&port);
    int client = connect_to(port);
    usleep(10000);
    struct sockaddr_in ca;
    socklen_t cl = sizeof(ca);
    int server_fd = accept(listener, (struct sockaddr *)&ca, &cl);
    if (server_fd < 0) {
        printf("  SKIP: accept failed\n");
        close(client); close(listener); w_event_destroy(el); return;
    }
    fcntl(server_fd, F_SETFL, fcntl(server_fd, F_GETFL) | O_NONBLOCK);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));
    fake_g.io_buf_id = -1;

    int rc = w_event_submit_send_zc(el, server_fd, "zerocopy", 8, &fake_g);
    if (rc < 0) {
        printf("  SKIP: SEND_ZC not supported\n");
        close(server_fd); close(client); close(listener); w_event_destroy(el);
        return;
    }

    ASSERT(fake_g.io_zc_pending == 1, "zc_pending set");

    /* Poll until goroutine is woken (may need multiple polls for completion + NOTIF) */
    WGoroutine *woken[8];
    int woke = 0;
    for (int attempt = 0; attempt < 10 && !woke; attempt++) {
        int n = w_event_poll(el, 100, woken, 8);
        for (int i = 0; i < n; i++) {
            if (woken[i] == &fake_g) woke = 1;
        }
    }
    ASSERT(woke, "goroutine eventually woken");
    ASSERT(fake_g.io_zc_pending == 0, "zc_pending cleared");
    ASSERT(fake_g.io_result == 8, "io_result = 8 bytes");

    /* Verify data arrived */
    char buf[64];
    ssize_t nr = read(client, buf, sizeof(buf));
    ASSERT(nr == 8, "8 bytes received");
    ASSERT(memcmp(buf, "zerocopy", 8) == 0, "data matches");

    close(server_fd); close(client); close(listener);
    w_event_destroy(el);
    printf("  SEND_ZC: OK\n");
}

/* ---- Test 8: Registered send buffers ---- */
static void test_send_buffers(void) {
    printf("\nTest 8: Registered send buffers\n");
    WEventLoop *el = w_event_init();

    int bid = w_event_send_buf_alloc(el);
    if (bid < 0) {
        printf("  SKIP: registered send buffers not available\n");
        w_event_destroy(el);
        return;
    }

    void *ptr = w_event_send_buf_ptr(el, bid);
    ASSERT(ptr != NULL, "buffer pointer valid");
    memcpy(ptr, "fixed-send", 10);

    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));

    int rc = w_event_submit_send_fixed(el, fds[0], bid, 10, &fake_g);
    ASSERT(rc == 0, "submit_send_fixed returns 0");

    WGoroutine *woken[8];
    int n = w_event_poll(el, 100, woken, 8);
    ASSERT(n >= 1, "poll returns 1");
    ASSERT(fake_g.io_result == 10, "10 bytes sent");

    char buf[64];
    ssize_t nr = read(fds[1], buf, sizeof(buf));
    ASSERT(nr == 10, "10 bytes received");
    ASSERT(memcmp(buf, "fixed-send", 10) == 0, "data matches");

    w_event_send_buf_free(el, bid);

    /* Verify reuse */
    int bid2 = w_event_send_buf_alloc(el);
    ASSERT(bid2 == bid, "freed buffer reused");
    w_event_send_buf_free(el, bid2);

    close(fds[0]); close(fds[1]);
    w_event_destroy(el);
    printf("  Send buffers: OK\n");
}

/* ---- Test 9: Multi-shot accept ---- */
static void test_multishot_accept(void) {
    printf("\nTest 9: Multi-shot accept\n");
    WEventLoop *el = w_event_init();
    int port;
    int listener = make_listener(&port);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));

    struct sockaddr_in addr;
    socklen_t addrlen = sizeof(addr);
    int rc = w_event_submit_accept_multishot(el, listener, (struct sockaddr *)&addr, &addrlen, &fake_g);
    if (rc < 0) {
        printf("  SKIP: multi-shot accept not supported\n");
        close(listener);
        w_event_destroy(el);
        return;
    }

    /* Connect 3 clients */
    int clients[3];
    int accepted = 0;
    for (int i = 0; i < 3; i++) {
        clients[i] = connect_to(port);
        usleep(10000);

        WGoroutine *woken[8];
        int n = w_event_poll(el, 100, woken, 8);
        if (n > 0 && fake_g.io_result >= 0) {
            close(fake_g.io_result);
            accepted++;
        }
    }
    ASSERT(accepted == 3, "3 connections accepted from 1 SQE");

    for (int i = 0; i < 3; i++) close(clients[i]);
    close(listener);
    w_event_destroy(el);
    printf("  Multi-shot accept: OK\n");
}

/* ---- Test 10: Linked recv + timeout ---- */
static void test_linked_timeout(void) {
    printf("\nTest 10: Linked recv + timeout\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));

    char buf[256];
    int rc = w_event_submit_recv_timeout(el, fds[0], buf, sizeof(buf), &fake_g, 100);
    if (rc < 0) {
        printf("  SKIP: linked timeout not supported\n");
        close(fds[0]); close(fds[1]);
        w_event_destroy(el);
        return;
    }

    /* Don't send data — timeout should fire */
    WGoroutine *woken[8];
    int woke = 0;
    for (int attempt = 0; attempt < 10 && !woke; attempt++) {
        int n = w_event_poll(el, 200, woken, 8);
        for (int i = 0; i < n; i++) {
            if (woken[i] == &fake_g) woke = 1;
        }
    }
    ASSERT(woke, "goroutine woken after timeout");
    ASSERT(fake_g.io_result == -ECANCELED, "io_result = -ECANCELED (timeout)");

    close(fds[0]); close(fds[1]);
    w_event_destroy(el);
    printf("  Linked timeout: OK\n");
}

/* ---- Test 11: Linked send + close ---- */
static void test_send_and_close(void) {
    printf("\nTest 11: Linked send + close\n");
    WEventLoop *el = w_event_init();
    int fds[2];
    make_socketpair(fds);

    WGoroutine fake_g;
    memset(&fake_g, 0, sizeof(fake_g));

    int rc = w_event_submit_send_and_close(el, fds[0], "goodbye", 7, &fake_g);
    if (rc < 0) {
        printf("  SKIP: linked send+close not supported\n");
        close(fds[0]); close(fds[1]);
        w_event_destroy(el);
        return;
    }

    WGoroutine *woken[8];
    int woke = 0;
    for (int attempt = 0; attempt < 10 && !woke; attempt++) {
        int n = w_event_poll(el, 100, woken, 8);
        for (int i = 0; i < n; i++) {
            if (woken[i] == &fake_g) woke = 1;
        }
    }
    ASSERT(woke, "goroutine woken");
    ASSERT(fake_g.io_result == 7, "7 bytes sent");

    /* Verify data arrived and fd was closed (read returns data then EOF) */
    char buf[64];
    ssize_t nr = read(fds[1], buf, sizeof(buf));
    ASSERT(nr == 7, "7 bytes received");
    ASSERT(memcmp(buf, "goodbye", 7) == 0, "data matches");

    /* Second read should return 0 (EOF from close) */
    nr = read(fds[1], buf, sizeof(buf));
    ASSERT(nr == 0, "EOF after close");

    /* fds[0] already closed by io_uring — don't close again */
    close(fds[1]);
    w_event_destroy(el);
    printf("  Send + close: OK\n");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== io_uring Tests (Phase 1 + 4 + 5) ===\n");

    /* Phase 1: basic completion I/O */
    test_submit_recv();
    test_submit_send();
    test_submit_accept();
    test_eof();
    test_cqe_advance();

    /* Phase 4: provided buffers + multi-shot + SEND_ZC */
    test_provided_buffers();
    test_send_zc();

    /* Phase 5: registered send buffers + multi-shot accept + linked SQEs */
    test_send_buffers();
    test_multishot_accept();
    test_linked_timeout();
    test_send_and_close();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

#else /* !__linux__ || !USE_IOURING */

#include <stdio.h>
int main(void) {
    printf("io_uring tests skipped (not Linux or USE_IOURING not defined)\n");
    return 0;
}

#endif
