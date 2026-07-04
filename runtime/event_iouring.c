/*
 * event_iouring.c — Linux io_uring + epoll hybrid event loop backend
 *
 * Architecture:
 *   epoll:    readiness notifications (fast for poll/wake patterns)
 *   io_uring: completion I/O for kTLS sockets + advanced features
 *
 * Phases:
 *   1: Basic RECV/SEND/ACCEPT completion ops
 *   4: Provided buffer ring + multi-shot recv + SEND_ZC
 *   5: Registered send buffers + multi-shot accept + linked SQEs
 *
 * Build with: -DUSE_IOURING -luring
 */

#if defined(__linux__) && defined(USE_IOURING)

#include "event_loop.h"
#include "runtime.h"
#include <string.h>
#include <liburing.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <sys/eventfd.h>

#define URING_ENTRIES    1024

/* Phase 4: provided recv buffer ring */
#define RECV_BUF_COUNT   512
#define RECV_BUF_SIZE    8192
#define RECV_BUF_BGID    0

/* Phase 5: registered send buffer pool */
#define SEND_BUF_COUNT   512
#define SEND_BUF_SIZE    4096

struct WEventLoop {
    /* Readiness backend (epoll) */
    int epfd;

    /* Completion backend (io_uring) */
    struct io_uring ring;
    int has_uring;
    int sqpoll;
    int uring_efd;       /* eventfd bridging io_uring→epoll */

    /* Phase 4: provided recv buffer ring */
    struct io_uring_buf_ring *recv_ring;
    void *recv_base;     /* mmap'd contiguous recv buffers */
    int has_recv_ring;

    /* Phase 5: registered send buffer pool */
    void *send_base;     /* mmap'd contiguous send buffers */
    struct iovec *send_iovecs;
    int send_free[SEND_BUF_COUNT];
    int send_free_top;   /* -1 = empty */
    int has_send_bufs;

    /* Feature probing */
    int has_send_zc;     /* IORING_OP_SEND_ZC available */
};

/* ==== Init / Destroy ==== */

WEventLoop *w_event_init(void) {
    WEventLoop *el = calloc(1, sizeof(WEventLoop));
    if (!el) return NULL;
    el->uring_efd = -1;
    el->send_free_top = -1;

    /* Always create epoll for readiness */
    el->epfd = epoll_create1(EPOLL_CLOEXEC);
    if (el->epfd < 0) { free(el); return NULL; }

    /* Try io_uring (SQPOLL → basic → fail) */
    struct io_uring_params params;
    memset(&params, 0, sizeof(params));
    params.flags = IORING_SETUP_SQPOLL;
    params.sq_thread_idle = 2000;

    if (io_uring_queue_init_params(URING_ENTRIES, &el->ring, &params) == 0) {
        el->has_uring = 1;
        el->sqpoll = 1;
    } else if (io_uring_queue_init(URING_ENTRIES, &el->ring, 0) == 0) {
        el->has_uring = 1;
        el->sqpoll = 0;
    }

    if (!el->has_uring) return el;  /* epoll-only mode */

    /* Bridge: eventfd so CQE arrivals wake epoll_wait */
    el->uring_efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (el->uring_efd >= 0) {
        io_uring_register_eventfd(&el->ring, el->uring_efd);
        struct epoll_event ev = { .events = EPOLLIN, .data.ptr = NULL };
        epoll_ctl(el->epfd, EPOLL_CTL_ADD, el->uring_efd, &ev);
    }

    /* Phase 4: provided recv buffer ring */
    int ret;
    el->recv_ring = io_uring_setup_buf_ring(&el->ring, RECV_BUF_COUNT, RECV_BUF_BGID, 0, &ret);
    if (el->recv_ring) {
        el->recv_base = mmap(NULL, (size_t)RECV_BUF_COUNT * RECV_BUF_SIZE,
                             PROT_READ | PROT_WRITE,
                             MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
        if (el->recv_base != MAP_FAILED) {
            for (int i = 0; i < RECV_BUF_COUNT; i++) {
                io_uring_buf_ring_add(el->recv_ring,
                    (char *)el->recv_base + (size_t)i * RECV_BUF_SIZE,
                    RECV_BUF_SIZE, i,
                    io_uring_buf_ring_mask(RECV_BUF_COUNT), i);
            }
            io_uring_buf_ring_advance(el->recv_ring, RECV_BUF_COUNT);
            el->has_recv_ring = 1;
        } else {
            el->recv_base = NULL;
        }
    }

    /* Phase 5: registered send buffer pool */
    el->send_base = mmap(NULL, (size_t)SEND_BUF_COUNT * SEND_BUF_SIZE,
                         PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    if (el->send_base != MAP_FAILED) {
        el->send_iovecs = calloc(SEND_BUF_COUNT, sizeof(struct iovec));
        for (int i = 0; i < SEND_BUF_COUNT; i++) {
            el->send_iovecs[i].iov_base = (char *)el->send_base + (size_t)i * SEND_BUF_SIZE;
            el->send_iovecs[i].iov_len = SEND_BUF_SIZE;
        }
        ret = io_uring_register_buffers(&el->ring, el->send_iovecs, SEND_BUF_COUNT);
        if (ret == 0) {
            el->has_send_bufs = 1;
            el->send_free_top = SEND_BUF_COUNT - 1;
            for (int i = 0; i < SEND_BUF_COUNT; i++)
                el->send_free[i] = i;
        } else {
            free(el->send_iovecs);
            el->send_iovecs = NULL;
            munmap(el->send_base, (size_t)SEND_BUF_COUNT * SEND_BUF_SIZE);
            el->send_base = NULL;
        }
    } else {
        el->send_base = NULL;
    }

    /* Probe SEND_ZC support (available since Linux 6.0) */
    struct io_uring_probe *probe = io_uring_get_probe_ring(&el->ring);
    if (probe) {
        el->has_send_zc = io_uring_opcode_supported(probe, IORING_OP_SEND_ZC);
        io_uring_free_probe(probe);
    }

    return el;
}

void w_event_destroy(WEventLoop *el) {
    if (!el) return;
    if (el->uring_efd >= 0) close(el->uring_efd);
    close(el->epfd);
    if (el->has_uring) {
        if (el->has_send_bufs) {
            io_uring_unregister_buffers(&el->ring);
            free(el->send_iovecs);
        }
        io_uring_queue_exit(&el->ring);
    }
    if (el->recv_base) munmap(el->recv_base, (size_t)RECV_BUF_COUNT * RECV_BUF_SIZE);
    if (el->send_base) munmap(el->send_base, (size_t)SEND_BUF_COUNT * SEND_BUF_SIZE);
    free(el);
}

/* ==== Readiness API (epoll) ==== */

void w_event_register(WEventLoop *el, int fd, int events, WGoroutine *g) {
    struct epoll_event ev;
    ev.events = EPOLLONESHOT;
    ev.data.ptr = g;
    if (events & W_EVENT_READ)  ev.events |= EPOLLIN;
    if (events & W_EVENT_WRITE) ev.events |= EPOLLOUT;
    if (epoll_ctl(el->epfd, EPOLL_CTL_MOD, fd, &ev) < 0)
        epoll_ctl(el->epfd, EPOLL_CTL_ADD, fd, &ev);
}

void w_event_unregister(WEventLoop *el, int fd) {
    epoll_ctl(el->epfd, EPOLL_CTL_DEL, fd, NULL);
}

/* ==== Helper: get SQE with emergency flush ==== */

static struct io_uring_sqe *get_sqe(WEventLoop *el) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(&el->ring);
    if (!sqe) {
        io_uring_submit(&el->ring);  /* emergency flush */
        sqe = io_uring_get_sqe(&el->ring);
    }
    return sqe;
}

/* ==== Phase 1: Basic completion I/O ==== */

int w_event_submit_recv(WEventLoop *el, int fd, void *buf, size_t len, WGoroutine *g) {
    if (!el->has_uring) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_recv(sqe, fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

int w_event_submit_send(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    if (!el->has_uring) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_send(sqe, fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

int w_event_submit_accept(WEventLoop *el, int fd, struct sockaddr *addr,
                           socklen_t *addrlen, WGoroutine *g) {
    if (!el->has_uring) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_accept(sqe, fd, addr, addrlen, 0);
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

/* ==== Phase 4: Multi-shot recv with provided buffers ==== */

int w_event_submit_recv_multishot(WEventLoop *el, int fd, WGoroutine *g) {
    if (!el->has_uring || !el->has_recv_ring) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;

    io_uring_prep_recv_multishot(sqe, fd, NULL, 0, 0);
    sqe->flags |= IOSQE_BUFFER_SELECT;
    sqe->buf_group = RECV_BUF_BGID;
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

void w_event_return_buf(WEventLoop *el, int buf_id) {
    if (!el->has_recv_ring || buf_id < 0 || buf_id >= RECV_BUF_COUNT) return;
    io_uring_buf_ring_add(el->recv_ring,
        (char *)el->recv_base + (size_t)buf_id * RECV_BUF_SIZE,
        RECV_BUF_SIZE, buf_id,
        io_uring_buf_ring_mask(RECV_BUF_COUNT), 0);
    io_uring_buf_ring_advance(el->recv_ring, 1);
}

/* ==== Phase 4: Zero-copy send (SEND_ZC) ==== */

int w_event_submit_send_zc(WEventLoop *el, int fd, const void *buf, size_t len, WGoroutine *g) {
    if (!el->has_uring || !el->has_send_zc) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;

    io_uring_prep_send_zc(sqe, fd, buf, len, 0, 0);
    io_uring_sqe_set_data(sqe, g);
    g->io_zc_pending = 1;  /* expect completion CQE + notification CQE */
    io_uring_submit(&el->ring);
    return 0;
}

/* ==== Phase 5: Registered send buffer pool ==== */

int w_event_send_buf_alloc(WEventLoop *el) {
    if (!el->has_send_bufs || el->send_free_top < 0) return -1;
    return el->send_free[el->send_free_top--];
}

void w_event_send_buf_free(WEventLoop *el, int buf_id) {
    if (!el->has_send_bufs || buf_id < 0 || buf_id >= SEND_BUF_COUNT) return;
    if (el->send_free_top >= SEND_BUF_COUNT - 1) return;  /* pool full (double-free guard) */
    el->send_free[++el->send_free_top] = buf_id;
}

void *w_event_send_buf_ptr(WEventLoop *el, int buf_id) {
    if (!el->send_base || buf_id < 0 || buf_id >= SEND_BUF_COUNT) return NULL;
    return (char *)el->send_base + (size_t)buf_id * SEND_BUF_SIZE;
}

int w_event_submit_send_fixed(WEventLoop *el, int fd, int buf_id, size_t len, WGoroutine *g) {
    if (!el->has_uring || !el->has_send_bufs) return -1;
    if (buf_id < 0 || buf_id >= SEND_BUF_COUNT) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;

    /* Use send for sockets. write_fixed (IORING_OP_WRITE_FIXED) uses file
     * offset semantics that don't work on sockets. The registered buffers
     * still benefit from MAP_POPULATE (pages pre-faulted, no page faults). */
    void *buf = (char *)el->send_base + (size_t)buf_id * SEND_BUF_SIZE;
    io_uring_prep_send(sqe, fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

/* ==== Phase 5: Multi-shot accept ==== */

int w_event_submit_accept_multishot(WEventLoop *el, int fd, struct sockaddr *addr,
                                     socklen_t *addrlen, WGoroutine *g) {
    if (!el->has_uring) return -1;
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;

    io_uring_prep_multishot_accept(sqe, fd, addr, addrlen, 0);
    io_uring_sqe_set_data(sqe, g);
    io_uring_submit(&el->ring);
    return 0;
}

/* ==== Phase 5: Linked SQE chains ==== */

/* Persistent timespec for linked timeouts — must outlive the SQE because
 * the kernel reads this pointer asynchronously (especially with SQPOLL).
 * Stack-allocated timespec would be a use-after-free. */
static __thread struct __kernel_timespec g_link_timeout_ts;

int w_event_submit_recv_timeout(WEventLoop *el, int fd, void *buf, size_t len,
                                 WGoroutine *g, int timeout_ms) {
    if (!el->has_uring) return -1;

    /* SQE 1: recv (linked to timeout) */
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_recv(sqe, fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, g);
    sqe->flags |= IOSQE_IO_LINK;

    /* SQE 2: linked timeout — uses thread-local persistent storage */
    sqe = get_sqe(el);
    if (!sqe) return -1;
    g_link_timeout_ts.tv_sec = timeout_ms / 1000;
    g_link_timeout_ts.tv_nsec = (long long)(timeout_ms % 1000) * 1000000LL;
    io_uring_prep_link_timeout(sqe, &g_link_timeout_ts, 0);
    io_uring_sqe_set_data(sqe, NULL);  /* timeout CQE ignored */

    io_uring_submit(&el->ring);
    return 0;
}

int w_event_submit_send_and_close(WEventLoop *el, int fd, const void *buf,
                                    size_t len, WGoroutine *g) {
    if (!el->has_uring) return -1;

    /* SQE 1: send (linked to close) */
    struct io_uring_sqe *sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_send(sqe, fd, buf, len, 0);
    io_uring_sqe_set_data(sqe, g);
    sqe->flags |= IOSQE_IO_LINK;

    /* SQE 2: close */
    sqe = get_sqe(el);
    if (!sqe) return -1;
    io_uring_prep_close(sqe, fd);
    io_uring_sqe_set_data(sqe, NULL);  /* close CQE ignored */

    io_uring_submit(&el->ring);
    return 0;
}

/* ==== Poll: harvest epoll readiness + io_uring completions ==== */

static int harvest_cqes(WEventLoop *el, WGoroutine **out, int count, int max_out) {
    struct io_uring_cqe *cqe;
    unsigned cqe_seen = 0;
    unsigned head;
    io_uring_for_each_cqe(&el->ring, head, cqe) {
        if (count >= max_out) break;

        WGoroutine *g = (WGoroutine *)io_uring_cqe_get_data(cqe);
        if (!g) { cqe_seen++; continue; }

        /* Deduplicate FIRST — before touching goroutine state.
         * Multi-shot ops (accept) generate multiple CQEs for the same
         * goroutine.  If this goroutine is already queued, stop: leave
         * this CQE and all subsequent ones unconsumed so io_result from
         * the FIRST CQE is preserved and no fds are lost. */
        int dup = 0;
        for (int j = 0; j < count; j++) {
            if (out[j] == g) { dup = 1; break; }
        }
        if (dup) break;

        /* SEND_ZC two-CQE protocol */
        if (g->io_zc_pending) {
            if (cqe->flags & IORING_CQE_F_NOTIF) {
                g->io_zc_pending = 0;
            } else {
                g->io_result = cqe->res;
                if (cqe->flags & IORING_CQE_F_MORE) {
                    cqe_seen++;
                    continue;
                }
                g->io_zc_pending = 0;
            }
        } else {
            g->io_result = cqe->res;
        }

        if (cqe->flags & IORING_CQE_F_BUFFER) {
            g->io_buf_id = cqe->flags >> IORING_CQE_BUFFER_SHIFT;
        } else {
            g->io_buf_id = -1;
        }

        out[count++] = g;
        cqe_seen++;
    }
    if (cqe_seen > 0) io_uring_cq_advance(&el->ring, cqe_seen);
    return count;
}

int w_event_poll(WEventLoop *el, int timeout_ms, WGoroutine **out, int max_out) {
    int count = 0;

    /* Check for pending CQEs first — no syscall, just shared memory scan.
     * This picks up CQEs left unconsumed from previous polls (e.g. multi-shot
     * accept generates CQEs faster than we can wake goroutines one at a time). */
    if (el->has_uring) {
        count = harvest_cqes(el, out, count, max_out);
    }

    /* epoll_wait: readiness events + io_uring eventfd notifications.
     * Limit nevents to available out[] slots + 1 for the eventfd, so we
     * never consume (and disarm via EPOLLONESHOT) more events than we can
     * deliver. Without this limit, goroutines whose events are consumed
     * but not processed become orphaned with disarmed fds. */
    struct epoll_event events[64];
    int slots = max_out - count;
    int nevents = (slots + 1) < 64 ? (slots + 1) : 64;  /* +1 for eventfd */
    if (nevents < 1) nevents = 1;  /* always check for at least the eventfd */

    int n = epoll_wait(el->epfd, events, nevents, count > 0 ? 0 : timeout_ms);
    if (n < 0) {
        if (errno == EINTR) return count;
        return count > 0 ? count : -1;
    }

    for (int i = 0; i < n; i++) {
        if (events[i].data.ptr == NULL) {
            uint64_t val;
            (void)read(el->uring_efd, &val, sizeof(val));
            continue;
        }
        if (count >= max_out) break;  /* shouldn't happen with limited nevents, but safe */
        WGoroutine *g = (WGoroutine *)events[i].data.ptr;
        int dup = 0;
        for (int j = 0; j < count; j++) {
            if (out[j] == g) { dup = 1; break; }
        }
        if (!dup) out[count++] = g;
    }

    /* Harvest any new CQEs that arrived during epoll_wait */
    if (el->has_uring) {
        count = harvest_cqes(el, out, count, max_out);
    }

    return count;
}

#endif /* __linux__ && USE_IOURING */
