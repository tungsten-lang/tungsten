/*
 * tls_stub.c — stubs used when the OpenSSL TLS backend is not compiled in.
 */

#include "runtime.h"
#include <errno.h>

static WValue tls_not_compiled(void) {
    w_raise(w_string("TLS: not compiled in (build with TLS=1 and OpenSSL installed)"));
    return W_NIL;
}

WValue w_tls_init(void) { return tls_not_compiled(); }

WValue w_tls_load_cert(const char *cert_path, const char *key_path) {
    (void)cert_path;
    (void)key_path;
    return tls_not_compiled();
}

WValue w_tls_wrap(WValue sock) {
    (void)sock;
    return tls_not_compiled();
}

WValue w_tls_client_wrap(WValue sock, const char *hostname) {
    (void)sock;
    (void)hostname;
    return tls_not_compiled();
}

int w_tls_server_configured(void) { return 0; }

const char *w_tls_get_cert_path(void) { return NULL; }
const char *w_tls_get_key_path(void) { return NULL; }

ssize_t w_tls_read(WSocket *s, char *buf, size_t len) {
    (void)s;
    (void)buf;
    (void)len;
    errno = ENOSYS;
    return -1;
}

ssize_t w_tls_write(WSocket *s, const char *buf, size_t len) {
    (void)s;
    (void)buf;
    (void)len;
    errno = ENOSYS;
    return -1;
}

WValue w_crypto_generate_rsa_key(int64_t bits) {
    (void)bits;
    return tls_not_compiled();
}

WValue w_crypto_rsa_public_jwk(WValue key) {
    (void)key;
    return tls_not_compiled();
}

WValue w_crypto_rsa_sign_sha256(WValue key, WValue data) {
    (void)key;
    (void)data;
    return tls_not_compiled();
}

WValue w_crypto_rsa_thumbprint(WValue key) {
    (void)key;
    return tls_not_compiled();
}

WValue w_crypto_generate_csr(WValue key, WValue domains) {
    (void)key;
    (void)domains;
    return tls_not_compiled();
}
