/*
 * test_integration.c — Phase 7e: End-to-end HTTP server integration test
 *
 * Tests:
 * 1. Start an HTTP server using runtime socket + goroutine APIs
 * 2. Client sends HTTP requests, verifies "Hello World" responses
 * 3. Multiple concurrent clients
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

static const char *HTTP_RESPONSE =
    "HTTP/1.1 200 OK\r\n"
    "Content-Length: 12\r\n"
    "\r\n"
    "Hello World\n";

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

/* Handler goroutine: read request, respond, close */
static WValue http_handler_fn(WValue *captures) {
    WValue conn = captures[0];
    /* Read the request (discard it) */
    WValue req = w_socket_read(conn, w_int(4096));
    (void)req;
    /* Send HTTP response */
    w_socket_write(conn, w_string(HTTP_RESPONSE));
    w_socket_close(conn);
    return W_NIL;
}

/* Acceptor goroutine: accept connections, spawn handlers */
static volatile int server_accepted = 0;

static WValue acceptor_fn(WValue *captures) {
    WValue listener = captures[0];
    int max_conns = (int)w_as_int(captures[1]);

    for (int i = 0; i < max_conns; i++) {
        WValue conn = w_socket_accept(listener);

        WValue *caps = calloc(1,sizeof(WValue));
        caps[0] = conn;
        WClosure *cl = calloc(1,sizeof(WClosure));
        cl->fn_ptr = http_handler_fn;
        cl->captures = caps;
        cl->capture_count = 1;
        w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));
        __sync_fetch_and_add(&server_accepted, 1);
    }
    return W_NIL;
}

/* Client thread: send HTTP requests, verify responses */
static volatile int client_successes = 0;

static void *client_thread_fn(void *arg) {
    int port = *(int *)arg;
    usleep(50000);  /* let server start */

    for (int i = 0; i < 5; i++) {
        int fd = connect_to(port);

        const char *request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        write(fd, request, strlen(request));
        shutdown(fd, SHUT_WR);

        char buf[1024];
        ssize_t total = 0;
        while (1) {
            ssize_t n = read(fd, buf + total, sizeof(buf) - total - 1);
            if (n <= 0) break;
            total += n;
        }
        buf[total] = '\0';
        close(fd);

        /* Verify response contains "Hello World" */
        if (strstr(buf, "Hello World") != NULL &&
            strstr(buf, "200 OK") != NULL) {
            __sync_fetch_and_add(&client_successes, 1);
        } else {
            fprintf(stderr, "  FAIL: bad response on request %d: %.100s\n", i, buf);
        }
    }
    return NULL;
}

static void test_http_server(void) {
    printf("\nTest 1: HTTP server with goroutines\n");

    /* Create listener */
    WValue listener = w_socket_tcp_listen("127.0.0.1", 0, 128);
    WSocket *ls = (WSocket *)w_as_ptr(listener);
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    getsockname(ls->fd, (struct sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);

    /* Spawn acceptor goroutine */
    WValue *caps = calloc(1,sizeof(WValue) * 2);
    caps[0] = listener;
    caps[1] = w_int(5);  /* accept 5 connections */
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = acceptor_fn;
    cl->captures = caps;
    cl->capture_count = 2;
    w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));

    /* Start client thread */
    client_successes = 0;
    pthread_t client;
    pthread_create(&client, NULL, client_thread_fn, &port);

    /* Drive scheduler */
    for (int i = 0; i < 3000 && client_successes < 5; i++) {
        w_scheduler_run();
        usleep(1000);
    }

    pthread_join(client, NULL);

    ASSERT(client_successes == 5, "all 5 HTTP requests returned Hello World");
    w_socket_close(listener);
    printf("  HTTP server: OK\n");
}

/* Test 2: Multiple concurrent client threads */
#define NUM_CLIENTS 3
#define REQUESTS_PER_CLIENT 3

static volatile int multi_successes = 0;

static void *multi_client_fn(void *arg) {
    int port = *(int *)arg;
    usleep(50000);

    for (int i = 0; i < REQUESTS_PER_CLIENT; i++) {
        int fd = connect_to(port);
        const char *request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        write(fd, request, strlen(request));
        shutdown(fd, SHUT_WR);

        char buf[1024];
        ssize_t total = 0;
        while (total < (ssize_t)sizeof(buf) - 1) {
            ssize_t n = read(fd, buf + total, sizeof(buf) - total - 1);
            if (n <= 0) break;
            total += n;
        }
        buf[total] = '\0';
        close(fd);

        if (strstr(buf, "Hello World") != NULL) {
            __sync_fetch_and_add(&multi_successes, 1);
        }
    }
    return NULL;
}

static void test_concurrent_clients(void) {
    printf("\nTest 2: Concurrent clients\n");

    int total_expected = NUM_CLIENTS * REQUESTS_PER_CLIENT;

    WValue listener = w_socket_tcp_listen("127.0.0.1", 0, 128);
    WSocket *ls = (WSocket *)w_as_ptr(listener);
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    getsockname(ls->fd, (struct sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);

    /* Spawn acceptor */
    WValue *caps = calloc(1,sizeof(WValue) * 2);
    caps[0] = listener;
    caps[1] = w_int(total_expected);
    WClosure *cl = calloc(1,sizeof(WClosure));
    cl->fn_ptr = acceptor_fn;
    cl->captures = caps;
    cl->capture_count = 2;
    server_accepted = 0;
    w_goroutine_spawn(w_box_ptr(cl, W_SUBTAG_CLOSURE));

    /* Start multiple client threads */
    multi_successes = 0;
    pthread_t clients[NUM_CLIENTS];
    for (int i = 0; i < NUM_CLIENTS; i++) {
        pthread_create(&clients[i], NULL, multi_client_fn, &port);
    }

    /* Drive scheduler */
    for (int i = 0; i < 5000 && multi_successes < total_expected; i++) {
        w_scheduler_run();
        usleep(1000);
    }

    for (int i = 0; i < NUM_CLIENTS; i++) {
        pthread_join(clients[i], NULL);
    }

    ASSERT(multi_successes == total_expected,
           "all concurrent HTTP requests succeeded");
    w_socket_close(listener);
    printf("  Concurrent clients: OK\n");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    printf("=== Phase 7: Integration Tests ===\n");

    test_http_server();
    test_concurrent_clients();

    printf("\n=== Results: %d/%d passed ===\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}
