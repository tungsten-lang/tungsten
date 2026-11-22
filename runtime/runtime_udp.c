#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

/* ---- UDP sockets (core/udp_socket.w) ----
 *
 * The descriptor is a plain fd, boxed as an Int and owned by the UDPSocket
 * object, which also keeps the receive timeout; these functions keep no
 * state of their own. Every fd is non-blocking: a receive that finds no
 * datagram parks the calling goroutine on the event loop with
 * w_socket_park_until, exactly like Socket#read, so a waiting fiber never
 * blocks the process (outside a goroutine it falls back to poll(2)).
 *
 * Datagrams are byte-exact in both directions: send takes a String or a
 * ByteArray by its byte length (NULs included), and recv answers a String
 * (as Socket#read does) or a ByteArray. Host names resolve through
 * getaddrinfo in the socket's own family, so an IPv4 socket resolves names
 * the way Socket.connect does. */

static void w_udp_raise(const char *what) {
    char msg[160];
    snprintf(msg, sizeof msg, "udp: %s failed (%s)", what, strerror(errno));
    w_raise(w_string(msg));
}

static int w_udp_fd(WValue fd_val) {
    int64_t fd = w_as_int(fd_val);
    if (fd < 0 || fd > INT32_MAX) w_raise(w_string("udp: socket is closed"));
    return (int)fd;
}

/* The family the socket was created with: AF_INET or AF_INET6. */
static int w_udp_family(int fd) {
    struct sockaddr_storage ss;
    socklen_t len = sizeof(ss);
    memset(&ss, 0, sizeof(ss));
    if (getsockname(fd, (struct sockaddr *)&ss, &len) < 0) w_udp_raise("getsockname");
    return ss.ss_family == AF_INET6 ? AF_INET6 : AF_INET;
}

/* Resolve host:port in `family` into *out. A nil or empty host is the
 * wildcard address (for bind). */
static void w_udp_resolve(int family, WValue host, WValue port, int passive,
                          struct sockaddr_storage *out, socklen_t *out_len) {
    int64_t p = w_as_int(port);
    if (p < 0 || p > 65535) w_raise(w_string("udp: port out of range"));
    char port_str[8];
    snprintf(port_str, sizeof port_str, "%d", (int)p);

    const char *name = (host == W_NIL) ? NULL : w_rt_as_str(host);
    if (name && name[0] == '\0') name = NULL;

    struct addrinfo hints, *result = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = family;
    hints.ai_socktype = SOCK_DGRAM;
    if (passive) hints.ai_flags = AI_PASSIVE;
    int err = getaddrinfo(name, port_str, &hints, &result);
    if (err != 0 || !result) {
        char msg[300];
        snprintf(msg, sizeof msg, "udp: cannot resolve %s (%s)", name ? name : "*", gai_strerror(err));
        w_raise(w_string(msg));
    }
    memcpy(out, result->ai_addr, result->ai_addrlen);
    *out_len = result->ai_addrlen;
    freeaddrinfo(result);
}

/* Bytes of a String or ByteArray datagram, by length (NULs included). */
static void w_udp_payload(WValue data, char sso[6], const char **ptr, size_t *len) {
    if (w_is_bytes(data)) {
        WArray *a = w_as_array(data);
        *ptr = (const char *)a->slots + a->start;
        *len = (size_t)a->size;
        return;
    }
    if (!w_is_stringy(data) && !w_is_rope(data))
        w_raise(w_string("udp: send expects a String or ByteArray"));
    w_str_data(data, sso, ptr, len);
}

#define W_UDP_BUFFER_BYTES (256 * 1024)

static void w_udp_grow_buffer(int fd, int option) {
    int size = 0;
    socklen_t len = sizeof(size);
    if (getsockopt(fd, SOL_SOCKET, option, &size, &len) == 0 && size >= W_UDP_BUFFER_BYTES) return;
    size = W_UDP_BUFFER_BYTES;
    setsockopt(fd, SOL_SOCKET, option, &size, sizeof(size));
}

/* family: 4 or 6. Answers the new non-blocking fd. */
WValue w_udp_open(WValue family_val) {
    w_sandbox_gate("udp_socket", "");
    int64_t f = w_as_int(family_val);
    if (f != 4 && f != 6) w_raise(w_string("udp: family must be :ipv4 or :ipv6"));
    int fd = socket(f == 6 ? AF_INET6 : AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) w_udp_raise("socket");
    if (w_rt_fd_set_nonblocking(fd) < 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        w_udp_raise("nonblocking");
    }
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    /* Room for full 64 KiB datagrams and a burst of them. macOS sizes a UDP
     * send buffer at 9216 bytes, so a larger datagram fails with EMSGSIZE
     * until it is raised; never shrink a larger default (Linux). */
    w_udp_grow_buffer(fd, SO_SNDBUF);
    w_udp_grow_buffer(fd, SO_RCVBUF);
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    return w_box_int(fd);
}

WValue w_udp_bind(WValue fd_val, WValue host, WValue port) {
    int fd = w_udp_fd(fd_val);
    struct sockaddr_storage ss;
    socklen_t len;
    w_udp_resolve(w_udp_family(fd), host, port, 1, &ss, &len);
    if (bind(fd, (struct sockaddr *)&ss, len) < 0) w_udp_raise("bind");
    return W_NIL;
}

WValue w_udp_connect(WValue fd_val, WValue host, WValue port) {
    int fd = w_udp_fd(fd_val);
    struct sockaddr_storage ss;
    socklen_t len;
    w_udp_resolve(w_udp_family(fd), host, port, 0, &ss, &len);
    /* A UDP connect only records the peer; it never waits on the network. */
    while (connect(fd, (struct sockaddr *)&ss, len) < 0) {
        if (errno != EINTR) w_udp_raise("connect");
    }
    return W_NIL;
}

/* One datagram to `to` (NULL: the connected peer). Answers the byte count. */
static WValue w_udp_send_impl(int fd, WValue data, const struct sockaddr *to, socklen_t to_len) {
    char sso[6];
    const char *ptr;
    size_t len;
    w_udp_payload(data, sso, &ptr, &len);
    while (1) {
        ssize_t n = to ? sendto(fd, ptr, len, 0, to, to_len) : send(fd, ptr, len, 0);
        if (n >= 0) return w_box_int(n);
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS) {
            w_socket_park(fd, W_EVENT_WRITE);
            continue;
        }
        if (errno == ECONNREFUSED) w_raise(w_string("udp: send failed (connection refused)"));
        w_udp_raise("send");
    }
}

WValue w_udp_send(WValue fd_val, WValue data) {
    return w_udp_send_impl(w_udp_fd(fd_val), data, NULL, 0);
}

WValue w_udp_send_to(WValue fd_val, WValue data, WValue host, WValue port) {
    int fd = w_udp_fd(fd_val);
    struct sockaddr_storage ss;
    socklen_t len;
    w_udp_resolve(w_udp_family(fd), host, port, 0, &ss, &len);
    return w_udp_send_impl(fd, data, (struct sockaddr *)&ss, len);
}

static WValue w_udp_host_of(const struct sockaddr_storage *ss) {
    char buf[INET6_ADDRSTRLEN];
    const void *addr = ss->ss_family == AF_INET6
        ? (const void *)&((const struct sockaddr_in6 *)ss)->sin6_addr
        : (const void *)&((const struct sockaddr_in *)ss)->sin_addr;
    if (!inet_ntop(ss->ss_family, addr, buf, sizeof buf)) return W_NIL;
    return w_string(buf);
}

static int w_udp_port_of(const struct sockaddr_storage *ss) {
    return ntohs(ss->ss_family == AF_INET6 ? ((const struct sockaddr_in6 *)ss)->sin6_port
                                           : ((const struct sockaddr_in *)ss)->sin_port);
}

/* Receive one datagram of at most `max` bytes (a longer one is truncated,
 * as recv(2) does). timeout_ms > 0 bounds the wait; it answers nil when that
 * expires. as_bytes selects a ByteArray result over a String. With `from`,
 * the sender's address is stored there. */
static WValue w_udp_recv_impl(WValue fd_val, WValue max_val, WValue timeout_val, WValue as_bytes_val,
                              struct sockaddr_storage *from) {
    int fd = w_udp_fd(fd_val);
    int64_t max = w_as_int(max_val);
    if (max <= 0) max = 65536;
    if ((uint64_t)max > W_STRING_LEN_MASK) w_raise(w_string("udp: recv size exceeds the string length limit"));
    int64_t timeout_ms = timeout_val == W_NIL ? 0 : w_as_int(timeout_val);
    int as_bytes = as_bytes_val != W_NIL && as_bytes_val != W_FALSE;
    int64_t deadline_ticks = timeout_ms > 0 ? w_rt_deadline_ticks_after_ms(timeout_ms) : 0;

    /* A String result is built in place, as Socket#read builds its own. */
    WString *ws = NULL;
    char *buf;
    if (as_bytes) {
        buf = malloc((size_t)max);
    } else {
        ws = malloc(sizeof(WString) + (size_t)max + 1);
        buf = ws ? ws->data : NULL;
    }
    if (!buf) w_rt_die("udp: out of memory");

    while (1) {
        socklen_t from_len = sizeof(*from);
        ssize_t n = from ? recvfrom(fd, buf, (size_t)max, 0, (struct sockaddr *)from, &from_len)
                         : recv(fd, buf, (size_t)max, 0);
        if (n >= 0) {
            if (as_bytes) {
                WValue out = w_bytes_from_data((const uint8_t *)buf, n);
                free(buf);
                return out;
            }
            return w_rt_socket_read_string(ws, (size_t)n);
        }
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (!w_socket_park_until(fd, W_EVENT_READ, deadline_ticks) &&
                deadline_ticks > 0 && __w_clock_ticks_raw() >= deadline_ticks) {
                free(as_bytes ? (void *)buf : (void *)ws);
                return W_NIL;
            }
            continue;
        }
        int saved = errno;
        free(as_bytes ? (void *)buf : (void *)ws);
        errno = saved;
        /* An ICMP port-unreachable for an earlier send to the connected
         * peer surfaces here, as it does from Ruby's UDPSocket#recv. */
        if (saved == ECONNREFUSED) w_raise(w_string("udp: recv failed (connection refused)"));
        w_udp_raise("recv");
    }
}

WValue w_udp_recv(WValue fd_val, WValue max_val, WValue timeout_val, WValue as_bytes_val) {
    return w_udp_recv_impl(fd_val, max_val, timeout_val, as_bytes_val, NULL);
}

/* [data, host, port], or nil when the timeout expires. */
WValue w_udp_recv_from(WValue fd_val, WValue max_val, WValue timeout_val, WValue as_bytes_val) {
    struct sockaddr_storage from;
    memset(&from, 0, sizeof(from));
    WValue data = w_udp_recv_impl(fd_val, max_val, timeout_val, as_bytes_val, &from);
    if (data == W_NIL) return W_NIL;
    WValue out = w_array_new(65, 3);
    out = w_array_push(out, data);
    out = w_array_push(out, w_udp_host_of(&from));
    out = w_array_push(out, w_box_int(w_udp_port_of(&from)));
    return out;
}

WValue w_udp_local_port(WValue fd_val) {
    int fd = w_udp_fd(fd_val);
    struct sockaddr_storage ss;
    socklen_t len = sizeof(ss);
    memset(&ss, 0, sizeof(ss));
    if (getsockname(fd, (struct sockaddr *)&ss, &len) < 0) w_udp_raise("getsockname");
    return w_box_int(w_udp_port_of(&ss));
}

WValue w_udp_close(WValue fd_val) {
    int64_t fd = w_as_int(fd_val);
    if (fd >= 0) close((int)fd);
    return W_NIL;
}

/* ---- the system resolver (core/dns.w: Dns.lookup) ----
 *
 * w_dns_lookup(host, timeout_ms) answers [v4 addresses, v6 addresses, ttl seconds]
 * (addresses as strings), [[], [], ttl] for a name with no address, or nil when the
 * resolver could not be asked (no answer in time, daemon unavailable). It blocks the
 * calling thread, so callers resolve from worker threads.
 *
 * macOS: DNS-SD (DNSServiceGetAddrInfo) over ONE connection to mDNSResponder kept open
 * for the life of the process (kDNSServiceFlagsShareConnection), so every lookup takes
 * the system's path — /etc/hosts, VPN and split-DNS scoped resolvers, search domains —
 * and reports record TTLs. Concurrent lookups from several threads share the connection:
 * whichever thread is waiting reads replies for all of them (under dns_m) and wakes the
 * others. Elsewhere: getaddrinfo (TTL unknown: 0). wasm: unavailable. */

#if defined(__APPLE__)
#include <dns_sd.h>
#include <poll.h>
#include <pthread.h>
#include <time.h>

typedef struct WDnsQuery {
    char v4[16][INET_ADDRSTRLEN];
    char v6[16][INET6_ADDRSTRLEN];
    int n4, n6;
    int done4, done6;     /* family answered (address or no such record) */
    int failed;           /* error other than "no such record" */
    uint32_t ttl;
    int64_t t_first4;     /* ms when the first A answer arrived */
} WDnsQuery;

static pthread_mutex_t w_dns_m = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t w_dns_cv = PTHREAD_COND_INITIALIZER;
static DNSServiceRef w_dns_conn = NULL;
static int w_dns_reading = 0;
static uint64_t w_dns_generation = 0;   /* bumps when the shared connection is replaced */

static int64_t w_dns_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void DNSSD_API w_dns_reply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t ifindex,
                                  DNSServiceErrorType err, const char *hostname,
                                  const struct sockaddr *addr, uint32_t ttl, void *ctx) {
    (void)ref; (void)flags; (void)ifindex; (void)hostname;
    WDnsQuery *q = (WDnsQuery *)ctx;
    int fam = addr ? addr->sa_family : 0;
    if (err == kDNSServiceErr_NoError && addr) {
        if (fam == AF_INET) {
            if (q->n4 < 16 && (flags & kDNSServiceFlagsAdd)) {
                inet_ntop(AF_INET, &((const struct sockaddr_in *)addr)->sin_addr, q->v4[q->n4], INET_ADDRSTRLEN);
                q->n4++;
            }
            if (!q->done4) q->t_first4 = w_dns_now_ms();
            q->done4 = 1;
        } else if (fam == AF_INET6) {
            if (q->n6 < 16 && (flags & kDNSServiceFlagsAdd)) {
                inet_ntop(AF_INET6, &((const struct sockaddr_in6 *)addr)->sin6_addr, q->v6[q->n6], INET6_ADDRSTRLEN);
                q->n6++;
            }
            q->done6 = 1;
        }
        if (ttl > 0 && (q->ttl == 0 || ttl < q->ttl)) q->ttl = ttl;
    } else if (err == kDNSServiceErr_NoSuchRecord) {
        if (fam == AF_INET6) q->done6 = 1;
        else q->done4 = 1;
    } else {
        q->failed = 1;
    }
}

static int w_dns_query_done(WDnsQuery *q) {
    if (q->failed) return 1;
    if (q->done4 && q->done6) return 1;
    /* an IPv4 answer and no AAAA yet: give the AAAA 30 ms, then go with what we have */
    if (q->done4 && q->n4 > 0 && w_dns_now_ms() - q->t_first4 > 30) return 1;
    return 0;
}

WValue w_dns_lookup(WValue host_val, WValue timeout_val) {
    const char *host = w_rt_as_str(host_val);
    int64_t timeout = w_is_int(timeout_val) ? w_as_int(timeout_val) : 5000;
    WDnsQuery *q = calloc(1, sizeof(WDnsQuery));
    if (!q) return W_NIL;
    int64_t deadline = w_dns_now_ms() + timeout;
    pthread_mutex_lock(&w_dns_m);
    if (!w_dns_conn && DNSServiceCreateConnection(&w_dns_conn) != kDNSServiceErr_NoError) {
        w_dns_conn = NULL;
        pthread_mutex_unlock(&w_dns_m);
        free(q);
        return W_NIL;
    }
    uint64_t gen = w_dns_generation;
    DNSServiceRef sub = w_dns_conn;
    DNSServiceErrorType err = DNSServiceGetAddrInfo(&sub,
        kDNSServiceFlagsShareConnection | kDNSServiceFlagsReturnIntermediates | kDNSServiceFlagsTimeout,
        0, kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6, host, w_dns_reply, q);
    if (err != kDNSServiceErr_NoError) {
        if (err == kDNSServiceErr_ServiceNotRunning || err == kDNSServiceErr_Invalid) {
            DNSServiceRefDeallocate(w_dns_conn);
            w_dns_conn = NULL;
            w_dns_generation++;
        }
        pthread_mutex_unlock(&w_dns_m);
        free(q);
        return W_NIL;
    }
    int timed_out = 0;
    while (!w_dns_query_done(q)) {
        if (gen != w_dns_generation) { q->failed = 1; sub = NULL; break; }
        int64_t left = deadline - w_dns_now_ms();
        if (left <= 0) { timed_out = 1; break; }
        if (!w_dns_reading) {
            /* read replies for everyone; others wait on the condition */
            w_dns_reading = 1;
            int fd = DNSServiceRefSockFD(w_dns_conn);
            pthread_mutex_unlock(&w_dns_m);
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ready = poll(&pfd, 1, left < 20 ? (int)left : 20);
            pthread_mutex_lock(&w_dns_m);
            if (ready > 0 && w_dns_conn) {
                if (DNSServiceProcessResult(w_dns_conn) != kDNSServiceErr_NoError) {
                    /* the daemon went away: every query on the old connection fails */
                    DNSServiceRefDeallocate(w_dns_conn);
                    w_dns_conn = NULL;
                    w_dns_generation++;
                }
            }
            w_dns_reading = 0;
            pthread_cond_broadcast(&w_dns_cv);
        } else {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_nsec += 20 * 1000000L;
            if (ts.tv_nsec >= 1000000000L) { ts.tv_sec += 1; ts.tv_nsec -= 1000000000L; }
            pthread_cond_timedwait(&w_dns_cv, &w_dns_m, &ts);
        }
    }
    if (sub && gen == w_dns_generation) DNSServiceRefDeallocate(sub);
    pthread_mutex_unlock(&w_dns_m);
    if (timed_out && q->n4 == 0 && q->n6 == 0) { free(q); return W_NIL; }
    if (q->failed && q->n4 == 0 && q->n6 == 0) { free(q); return W_NIL; }
    WValue v4 = w_array_new(65, q->n4 > 0 ? q->n4 : 1);
    for (int i = 0; i < q->n4; i++) v4 = w_array_push(v4, w_string(q->v4[i]));
    WValue v6 = w_array_new(65, q->n6 > 0 ? q->n6 : 1);
    for (int i = 0; i < q->n6; i++) v6 = w_array_push(v6, w_string(q->v6[i]));
    WValue out = w_array_new(65, 3);
    out = w_array_push(out, v4);
    out = w_array_push(out, v6);
    out = w_array_push(out, w_box_int((int64_t)q->ttl));
    free(q);
    return out;
}

WValue w_dns_available(void) { return W_TRUE; }

#elif !defined(__wasi__)

WValue w_dns_lookup(WValue host_val, WValue timeout_val) {
    (void)timeout_val;
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int err = getaddrinfo(w_rt_as_str(host_val), NULL, &hints, &res);
    if (err == EAI_NONAME
#ifdef EAI_NODATA
        || err == EAI_NODATA
#endif
        ) {
        WValue out = w_array_new(65, 3);
        out = w_array_push(out, w_array_new(65, 1));
        out = w_array_push(out, w_array_new(65, 1));
        out = w_array_push(out, w_box_int(0));
        return out;
    }
    if (err != 0) return W_NIL;
    WValue v4 = w_array_new(65, 4);
    WValue v6 = w_array_new(65, 4);
    char buf[INET6_ADDRSTRLEN];
    for (struct addrinfo *a = res; a; a = a->ai_next) {
        if (a->ai_family == AF_INET) {
            inet_ntop(AF_INET, &((struct sockaddr_in *)a->ai_addr)->sin_addr, buf, sizeof buf);
            v4 = w_array_push(v4, w_string(buf));
        } else if (a->ai_family == AF_INET6) {
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)a->ai_addr)->sin6_addr, buf, sizeof buf);
            v6 = w_array_push(v6, w_string(buf));
        }
    }
    freeaddrinfo(res);
    WValue out = w_array_new(65, 3);
    out = w_array_push(out, v4);
    out = w_array_push(out, v6);
    out = w_array_push(out, w_box_int(0));
    return out;
}

WValue w_dns_available(void) { return W_TRUE; }

#else

WValue w_dns_lookup(WValue host_val, WValue timeout_val) { (void)host_val; (void)timeout_val; return W_NIL; }
WValue w_dns_available(void) { return W_FALSE; }

#endif
