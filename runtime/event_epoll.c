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
#include <sys/eventfd.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

struct WEventLoop {
    int epfd;
    int wake_fd;
    WEventDeadlineQueue deadlines;
};

WEventDeadlineQueue *w_event_deadline_queue(WEventLoop *el) { return &el->deadlines; }

WEventLoop *w_event_init(void) {
    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) return NULL;

    WEventLoop *el = malloc(sizeof(WEventLoop));
    if (!el) { close(epfd); return NULL; }
    el->epfd = epfd;
    el->wake_fd = -1;
    if (w_event_deadline_queue_init(&el->deadlines) != 0) {
        close(epfd);
        free(el);
        return NULL;
    }
    el->wake_fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    struct epoll_event wake = { .events = EPOLLIN, .data.ptr = el };
    if (el->wake_fd < 0 || epoll_ctl(epfd, EPOLL_CTL_ADD, el->wake_fd, &wake) < 0) {
        w_event_destroy(el);
        return NULL;
    }
    return el;
}

void w_event_destroy(WEventLoop *el) {
    if (!el) return;
    if (el->wake_fd >= 0) close(el->wake_fd);
    close(el->epfd);
    w_event_deadline_queue_destroy(&el->deadlines);
    free(el);
}

int w_event_wake(WEventLoop *el) {
    uint64_t one = 1;
    ssize_t result;
    do { result = write(el->wake_fd, &one, sizeof(one)); }
    while (result < 0 && errno == EINTR);
    /* A saturated eventfd is already readable: the wake is not lost. */
    return result == sizeof(one) || (result < 0 && errno == EAGAIN) ? 0 : -1;
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
    if (max_out <= 0) return 0;
    struct epoll_event events[64];
    int nevents = max_out < 64 ? max_out : 64;
    int requested_timeout = timeout_ms;
    timeout_ms = w_event_deadline_prepare_poll(el, timeout_ms, NULL);

    int n = epoll_wait(el->epfd, events, nevents, timeout_ms);
    int poll_errno = errno;
    w_event_deadline_finish_poll(el, requested_timeout);
    if (n < 0) {
        errno = poll_errno;
        if (poll_errno == EINTR) return 0;
        return -1;
    }

    /* Deduplicate: same goroutine may be ready for both read+write */
    int count = 0;
    for (int i = 0; i < n && count < max_out; i++) {
        if (events[i].data.ptr == el) {
            uint64_t value;
            while (read(el->wake_fd, &value, sizeof(value)) < 0 && errno == EINTR) {}
            continue;
        }
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

/* basic completion I/O */
int w_event_submit_recv(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_send(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
int w_event_submit_accept(WEventLoop *el, int fd, struct sockaddr *addr, socklen_t *addrlen, WGoroutine *g) {
    (void)el; (void)fd; (void)addr; (void)addrlen; (void)g; return -1;
}

/* multi-shot recv + zero-copy send */
int w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g) {
    (void)el; (void)fd; (void)g; return -1;
}
int w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    (void)el; (void)fd; (void)buf; (void)len; (void)g; return -1;
}
void w_event_return_buf(WEventLoop *el, int buf_id) {
    (void)el; (void)buf_id;
}

/* registered send buffers + multi-shot accept */
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
