/*
 * event_epoll.c — Linux epoll event loop backend
 *
 * Same API as event_kqueue.c, backed by epoll.
 * Uses EPOLLONESHOT so goroutines must re-register after wakeup.
 */

#if defined(__linux__) && !defined(USE_IOURING)

#include "event_loop.h"
#include "runtime.h"
#include <sys/epoll.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

struct WEventLoop {
    int epfd;
};

WEventLoop *w_event_init(void) {
    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) return NULL;

    WEventLoop *el = malloc(sizeof(WEventLoop));
    el->epfd = epfd;
    return el;
}

void w_event_destroy(WEventLoop *el) {
    if (!el) return;
    close(el->epfd);
    free(el);
}

void w_event_register(WEventLoop *el, int fd, int events, WGoroutine *g) {
    struct epoll_event ev;
    ev.events = EPOLLONESHOT;
    ev.data.ptr = g;

    if (events & W_EVENT_READ)  ev.events |= EPOLLIN;
    if (events & W_EVENT_WRITE) ev.events |= EPOLLOUT;

    /* Try EPOLL_CTL_MOD first (re-arm), fall back to EPOLL_CTL_ADD */
    if (epoll_ctl(el->epfd, EPOLL_CTL_MOD, fd, &ev) < 0) {
        epoll_ctl(el->epfd, EPOLL_CTL_ADD, fd, &ev);
    }
}

void w_event_unregister(WEventLoop *el, int fd) {
    epoll_ctl(el->epfd, EPOLL_CTL_DEL, fd, NULL);
}

int w_event_poll(WEventLoop *el, int timeout_ms, WGoroutine **out, int max_out) {
    struct epoll_event events[64];
    int nevents = max_out < 64 ? max_out : 64;

    int n = epoll_wait(el->epfd, events, nevents, timeout_ms);
    if (n < 0) {
        if (errno == EINTR) return 0;
        return -1;
    }

    /* Deduplicate: same goroutine may be ready for both read+write */
    int count = 0;
    for (int i = 0; i < n && count < max_out; i++) {
        WGoroutine *g = (WGoroutine *)events[i].data.ptr;
        if (!g) continue;

        int dup = 0;
        for (int j = 0; j < count; j++) {
            if (out[j] == g) { dup = 1; break; }
        }
        if (!dup) {
            out[count++] = g;
        }
    }
    return count;
}

/* ---- Completion API stubs (io_uring only — never called on epoll) ---- */

/* Phase 1 */
int w_event_submit_recv(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_send(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_accept(WEventLoop *el, int fd, struct sockaddr *addr, socklen_t *addrlen, WGoroutine *g) {
    (void)el; (void)fd; (void)addr; (void)addrlen; (void)g; return -1;
}

/* Phase 4 */
int w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g) {
    (void)el; (void)fd; (void)g; return -1;
}
int w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
void w_event_return_buf(WEventLoop *el, int buf_id) {
    (void)el; (void)buf_id;
}

/* Phase 5 */
int w_event_send_buf_alloc(WEventLoop *el) { (void)el; return -1; }
void w_event_send_buf_free(WEventLoop *el, int buf_id) { (void)el; (void)buf_id; }
void *w_event_send_buf_ptr(WEventLoop *el, int buf_id) { (void)el; (void)buf_id; return NULL; }
int w_event_submit_send_fixed(WEventLoop *el, int fd, int buf_id, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf_id; (void)len; (void)g; return -1;
}
int w_event_submit_accept_multishot(WEventLoop *el, int fd, struct sockaddr *addr, socklen_t *addrlen, WGoroutine *g) {
    (void)el; (void)fd; (void)addr; (void)addrlen; (void)g; return -1;
}
int w_event_submit_recv_timeout(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g, int timeout_ms) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; (void)timeout_ms; return -1;
}
int w_event_submit_send_and_close(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}

#endif /* __linux__ */
