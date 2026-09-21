/* wasm32-wasi compat: no resolver. getaddrinfo always fails with EAI_FAIL. */
#ifndef TUNGSTEN_WASI_NETDB_H
#define TUNGSTEN_WASI_NETDB_H
#include <sys/socket.h>
#include <netinet/in.h>
struct addrinfo {
    int ai_flags, ai_family, ai_socktype, ai_protocol;
    socklen_t ai_addrlen;
    struct sockaddr *ai_addr;
    char *ai_canonname;
    struct addrinfo *ai_next;
};
#define AI_PASSIVE 1
#define AI_CANONNAME 2
#define AI_NUMERICHOST 4
#define AI_NUMERICSERV 0x400
#define AI_ADDRCONFIG 0x20
#define EAI_FAIL (-4)
#define EAI_NONAME (-2)
#define NI_MAXHOST 255
#define NI_MAXSERV 32
#define NI_NUMERICHOST 1
#define NI_NUMERICSERV 2
int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
const char *gai_strerror(int errcode);
int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen,
                char *serv, socklen_t servlen, int flags);
#endif
