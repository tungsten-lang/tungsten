/*
 * tls.c — TLS wrapper using OpenSSL
 *
 * Provides TLS 1.3 for Tungsten sockets with:
 * - Non-blocking handshake (goroutine parking on WANT_READ/WANT_WRITE)
 * - ALPN server-side selection for HTTP/2 negotiation
 * - TLS client mode with SNI and system CA verification
 * - RSA key generation, JWK export, signing, CSR generation (for ACME)
 * - Auto-detection in socket read/write (via WSocket.ssl field)
 *
 * Build with: -lssl -lcrypto (or `pkg-config --libs openssl`)
 * On macOS: brew install openssl@3
 */

#ifdef TUNGSTEN_TLS

#include "runtime.h"
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/bn.h>
#include <openssl/pem.h>
#include <openssl/sha.h>
#include <errno.h>
#include <fcntl.h>

/* GC removed — using malloc/calloc directly */

/* Forward declarations for goroutine parking */
extern __thread WGoroutine *g_current;

/* Global SSL contexts — server and client */
static SSL_CTX *g_ssl_ctx = NULL;
static SSL_CTX *g_ssl_client_ctx = NULL;

/* Cert/key path storage for HTTP/3 (separate SSL context needs same certs) */
static const char *g_cert_path = NULL;
static const char *g_key_path = NULL;

/* ALPN server-side selection callback */
static int alpn_select_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen,
                          const unsigned char *in, unsigned int inlen, void *arg) {
    (void)ssl; (void)arg;
    /* Prefer h2 over http/1.1 */
    static const unsigned char h2[] = "\x02h2";
    static const unsigned char h11[] = "\x08http/1.1";

    /* Walk client's ALPN list */
    const unsigned char *p = in;
    const unsigned char *end = in + inlen;
    int has_h2 = 0, has_h11 = 0;
    while (p < end) {
        unsigned char len = *p++;
        if (p + len > end) break;
        if (len == 2 && memcmp(p, "h2", 2) == 0) has_h2 = 1;
        if (len == 8 && memcmp(p, "http/1.1", 8) == 0) has_h11 = 1;
        p += len;
    }

    if (has_h2) {
        *out = h2 + 1;
        *outlen = 2;
        return SSL_TLSEXT_ERR_OK;
    }
    if (has_h11) {
        *out = h11 + 1;
        *outlen = 8;
        return SSL_TLSEXT_ERR_OK;
    }
    return SSL_TLSEXT_ERR_NOACK;
}

WValue w_tls_init(void) {
    if (g_ssl_ctx) return W_TRUE;

    /* OpenSSL 1.1.0+ auto-initializes, but be explicit */
    OPENSSL_init_ssl(OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, NULL);

    g_ssl_ctx = SSL_CTX_new(TLS_server_method());
    if (!g_ssl_ctx) {
        w_raise(w_string("TLS: failed to create SSL context"));
    }

    /* Require TLS 1.3 minimum */
    SSL_CTX_set_min_proto_version(g_ssl_ctx, TLS1_3_VERSION);

    /* Prefer AES-GCM — fastest with kTLS (kernel crypto uses AES-NI / ARMv8 CE).
     * Benchmarked on Intel DO server with kTLS:
     *   AES-128-GCM: 260k req/s | ChaCha20: 221k (18% slower)
     * Despite ChaCha20 being faster in userspace OpenSSL benchmarks (779 vs 626 MB/s),
     * the kernel's AES-GCM implementation is more optimized for kTLS record processing.
     * Server cipher preference enforced via SSL_OP_CIPHER_SERVER_PREFERENCE. */
    SSL_CTX_set_ciphersuites(g_ssl_ctx,
        "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256");

    unsigned long opts = SSL_OP_CIPHER_SERVER_PREFERENCE;
#ifdef SSL_OP_ENABLE_KTLS
    /* kTLS: after TLS handshake, offload encryption/decryption to the kernel.
     * OpenSSL 3.0+ with Linux 4.13+. When active, SSL_read/SSL_write route
     * through kernel TLS, enabling io_uring RECV/SEND on encrypted sockets.
     * Requires: AES-GCM cipher (already preferred above), tls kernel module. */
    opts |= SSL_OP_ENABLE_KTLS;
#endif
    SSL_CTX_set_options(g_ssl_ctx, opts);

    /* Keep SSL buffers allocated between requests — avoids malloc/free per
     * write on keep-alive connections. Trades ~32KB per idle connection for
     * eliminating ~70 malloc samples per profile (~2.5% of active CPU). */

    /* ALPN server-side selection callback */
    SSL_CTX_set_alpn_select_cb(g_ssl_ctx, alpn_select_cb, NULL);

    return W_TRUE;
}

WValue w_tls_load_cert(const char *cert_path, const char *key_path) {
    if (!g_ssl_ctx) {
        w_tls_init();
    }

    if (SSL_CTX_use_certificate_chain_file(g_ssl_ctx, cert_path) != 1) {
        w_raise(w_string("TLS: failed to load certificate"));
    }

    if (SSL_CTX_use_PrivateKey_file(g_ssl_ctx, key_path, SSL_FILETYPE_PEM) != 1) {
        w_raise(w_string("TLS: failed to load private key"));
    }

    if (SSL_CTX_check_private_key(g_ssl_ctx) != 1) {
        w_raise(w_string("TLS: certificate and private key do not match"));
    }

    /* Store paths for HTTP/3's separate SSL context */
    g_cert_path = cert_path;
    g_key_path = key_path;

    return W_TRUE;
}

/* Query: is the TLS server context configured? */
int w_tls_server_configured(void) {
    return g_ssl_ctx != NULL ? 1 : 0;
}

const char *w_tls_get_cert_path(void) { return g_cert_path; }
const char *w_tls_get_key_path(void)  { return g_key_path; }

/* Helper: park goroutine during non-blocking SSL handshake */
static void tls_park_for_ssl_error(int fd, int ssl_err) {
    extern void w_socket_park(int fd, int events);
    if (ssl_err == SSL_ERROR_WANT_READ) {
        w_socket_park(fd, W_EVENT_READ);
    } else if (ssl_err == SSL_ERROR_WANT_WRITE) {
        w_socket_park(fd, W_EVENT_WRITE);
    }
}

WValue w_tls_wrap(WValue sock) {
    if (!g_ssl_ctx) {
        w_raise(w_string("TLS: context not initialized (call w_tls_init first)"));
    }

    WSocket *s = (WSocket *)w_as_ptr(sock);
    if (!w_is_socket(sock) || !s) {
        w_raise(w_string("TLS: expected a socket"));
    }

    SSL *ssl = SSL_new(g_ssl_ctx);
    if (!ssl) {
        w_raise(w_string("TLS: failed to create SSL object"));
    }

    SSL_set_fd(ssl, s->fd);

    /* Non-blocking handshake with goroutine parking */
    while (1) {
        int ret = SSL_accept(ssl);
        if (ret == 1) break;  /* handshake complete */

        int err = SSL_get_error(ssl, ret);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            tls_park_for_ssl_error(s->fd, err);
            continue;
        }

        /* Fatal error */
        SSL_free(ssl);
        w_raise(w_string("TLS: handshake failed"));
    }

    s->ssl = ssl;

    /* Check if kTLS was installed by OpenSSL (SSL_OP_ENABLE_KTLS).
     * When active, the kernel handles TLS encryption — we can use plain
     * read()/write() instead of SSL_read()/SSL_write(). */
#ifdef SSL_OP_ENABLE_KTLS
    if (BIO_get_ktls_send(SSL_get_wbio(ssl)) &&
        BIO_get_ktls_recv(SSL_get_rbio(ssl))) {
        s->ktls = 1;
    }
#endif

    return sock;
}

/*
 * TLS-aware read/write — called from w_socket_read/w_socket_write
 * when socket has ssl != NULL.
 */

ssize_t w_tls_read(WSocket *s, char *buf, size_t len) {
    SSL *ssl = (SSL *)s->ssl;
    while (1) {
        int n = SSL_read(ssl, buf, (int)len);
        if (n > 0) return n;

        int err = SSL_get_error(ssl, n);
        if (err == SSL_ERROR_ZERO_RETURN) return 0;  /* clean shutdown */
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            tls_park_for_ssl_error(s->fd, err);
            continue;
        }
        return -1;  /* error */
    }
}

ssize_t w_tls_write(WSocket *s, const char *buf, size_t len) {
    SSL *ssl = (SSL *)s->ssl;
    while (1) {
        int n = SSL_write(ssl, buf, (int)len);
        if (n > 0) return n;

        int err = SSL_get_error(ssl, n);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            tls_park_for_ssl_error(s->fd, err);
            continue;
        }
        return -1;  /* error */
    }
}

/* ---- ALPN protocol query (Phase 8b) ---- */

WValue w_socket_alpn_protocol(WValue sock) {
    WSocket *s = (WSocket *)w_as_ptr(sock);
    if (!w_is_socket(sock) || !s) return W_NIL;

    if (s->ssl) {
        const unsigned char *proto = NULL;
        unsigned int proto_len = 0;
        SSL_get0_alpn_selected((SSL *)s->ssl, &proto, &proto_len);
        if (proto && proto_len > 0) {
            char *str = malloc(proto_len + 1);
            memcpy(str, proto, proto_len);
            str[proto_len] = '\0';
            WValue result = w_string(str);
            free(str);
            return result;
        }
    }
    return W_NIL;
}

/* ---- TLS client wrap (Phase 8b) ---- */

static void ensure_client_ctx(void) {
    if (g_ssl_client_ctx) return;

    g_ssl_client_ctx = SSL_CTX_new(TLS_client_method());
    if (!g_ssl_client_ctx) {
        w_raise(w_string("TLS: failed to create client SSL context"));
    }

    /* Use TLS 1.2+ for client (some servers don't support 1.3) */
    SSL_CTX_set_min_proto_version(g_ssl_client_ctx, TLS1_2_VERSION);

    /* Load system CA certificates for verification */
    SSL_CTX_set_default_verify_paths(g_ssl_client_ctx);
    SSL_CTX_set_verify(g_ssl_client_ctx, SSL_VERIFY_PEER, NULL);

    /* ALPN: advertise h2 and http/1.1 */
    static const unsigned char alpn[] = "\x02h2\x08http/1.1";
    SSL_CTX_set_alpn_protos(g_ssl_client_ctx, alpn, sizeof(alpn) - 1);
}

WValue w_tls_client_wrap(WValue sock, const char *hostname) {
    ensure_client_ctx();

    WSocket *s = (WSocket *)w_as_ptr(sock);
    if (!w_is_socket(sock) || !s) {
        w_raise(w_string("TLS: expected a socket"));
    }

    SSL *ssl = SSL_new(g_ssl_client_ctx);
    if (!ssl) {
        w_raise(w_string("TLS: failed to create client SSL object"));
    }

    SSL_set_fd(ssl, s->fd);

    /* Set SNI hostname */
    SSL_set_tlsext_host_name(ssl, hostname);

    /* Also set hostname for certificate verification */
    SSL_set1_host(ssl, hostname);

    /* Non-blocking handshake with goroutine parking */
    while (1) {
        int ret = SSL_connect(ssl);
        if (ret == 1) break;  /* handshake complete */

        int err = SSL_get_error(ssl, ret);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            tls_park_for_ssl_error(s->fd, err);
            continue;
        }

        SSL_free(ssl);
        w_raise(w_string("TLS: client handshake failed"));
    }

    s->ssl = ssl;
    return sock;
}

/* ---- RSA Crypto for ACME JWS signing (Phase 8b) ---- */

/* RSA key handle stored as opaque pointer storage. Phase 6i.1 folded the
 * old WBytes struct into WArray<u8>; we now stash the EVP_PKEY* in an
 * 8-byte ByteArray (WArray with ebits=8, size = sizeof(EVP_PKEY *)). */

WValue w_crypto_generate_rsa_key(int64_t bits) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    if (!ctx) w_raise(w_string("Crypto: failed to create RSA context"));

    if (EVP_PKEY_keygen_init(ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, (int)bits) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        w_raise(w_string("Crypto: failed to init RSA keygen"));
    }

    EVP_PKEY *pkey = NULL;
    if (EVP_PKEY_keygen(ctx, &pkey) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        w_raise(w_string("Crypto: RSA key generation failed"));
    }
    EVP_PKEY_CTX_free(ctx);

    WValue kb = w_bytes_new(sizeof(EVP_PKEY *));
    WArray *kba = (WArray *)w_as_ptr(kb);
    memcpy(kba->slots, &pkey, sizeof(EVP_PKEY *));
    return kb;
}

static EVP_PKEY *extract_pkey(WValue key) {
    WArray *kba = (WArray *)w_as_ptr(key);
    if (!kba || kba->size != (int32_t)sizeof(EVP_PKEY *)) {
        w_raise(w_string("Crypto: invalid key handle"));
    }
    EVP_PKEY *pkey;
    memcpy(&pkey, kba->slots, sizeof(EVP_PKEY *));
    return pkey;
}

/* Helper: base64url encode binary data to a malloc-allocated string */
static char *b64url_encode_raw(const uint8_t *data, int64_t len) {
    static const char b64url[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    int64_t out_len = ((len + 2) / 3) * 4;
    char *out = malloc(out_len + 1);
    int64_t j = 0;
    for (int64_t i = 0; i < len; i += 3) {
        uint32_t triple = ((uint32_t)data[i]) << 16;
        if (i + 1 < len) triple |= ((uint32_t)data[i + 1]) << 8;
        if (i + 2 < len) triple |= ((uint32_t)data[i + 2]);
        out[j++] = b64url[((triple >> 18) & 0x3F)];
        out[j++] = b64url[((triple >> 12) & 0x3F)];
        if (i + 1 < len) out[j++] = b64url[((triple >> 6) & 0x3F)];
        if (i + 2 < len) out[j++] = b64url[(triple & 0x3F)];
    }
    out[j] = '\0';
    return out;
}

/* Helper: BIGNUM to base64url string */
static char *bn_to_b64url(const BIGNUM *bn) {
    int len = BN_num_bytes(bn);
    uint8_t *buf = malloc(len);
    BN_bn2bin(bn, buf);
    char *result = b64url_encode_raw(buf, len);
    free(buf);
    return result;
}

WValue w_crypto_rsa_public_jwk(WValue key) {
    EVP_PKEY *pkey = extract_pkey(key);

    BIGNUM *n_bn = NULL, *e_bn = NULL;
    EVP_PKEY_get_bn_param(pkey, "n", &n_bn);
    EVP_PKEY_get_bn_param(pkey, "e", &e_bn);

    if (!n_bn || !e_bn) {
        if (n_bn) BN_free(n_bn);
        if (e_bn) BN_free(e_bn);
        w_raise(w_string("Crypto: failed to extract RSA public key components"));
    }

    char *n_b64 = bn_to_b64url(n_bn);
    char *e_b64 = bn_to_b64url(e_bn);
    BN_free(n_bn);
    BN_free(e_bn);

    /* Build JSON */
    size_t json_len = strlen(n_b64) + strlen(e_b64) + 64;
    char *json = malloc(json_len);
    snprintf(json, json_len, "{\"kty\":\"RSA\",\"n\":\"%s\",\"e\":\"%s\"}", n_b64, e_b64);
    WValue result = w_string(json);
    free(json);
    free(n_b64);
    free(e_b64);
    return result;
}

WValue w_crypto_rsa_sign_sha256(WValue key, WValue data) {
    EVP_PKEY *pkey = extract_pkey(key);

    const uint8_t *input;
    size_t input_len;
    if (w_is_bytes(data)) {
        WArray *a = (WArray *)w_as_ptr(data);
        input = (const uint8_t *)a->slots;
        input_len = (size_t)a->size;
    } else {
        char str_buf[6];
        const char *s;
        size_t slen;
        w_str_data(data, str_buf, &s, &slen);
        if (slen == 0 && !w_is_string(data) && !w_is_symbol(data)) {
            w_raise(w_string("Crypto: expected string or bytes"));
            return W_NIL;
        }
        input = (const uint8_t *)s;
        input_len = slen;
    }

    EVP_MD_CTX *md_ctx = EVP_MD_CTX_new();
    if (!md_ctx) w_raise(w_string("Crypto: failed to create digest context"));

    if (EVP_DigestSignInit(md_ctx, NULL, EVP_sha256(), NULL, pkey) <= 0) {
        EVP_MD_CTX_free(md_ctx);
        w_raise(w_string("Crypto: sign init failed"));
    }

    if (EVP_DigestSignUpdate(md_ctx, input, input_len) <= 0) {
        EVP_MD_CTX_free(md_ctx);
        w_raise(w_string("Crypto: sign update failed"));
    }

    size_t sig_len = 0;
    EVP_DigestSignFinal(md_ctx, NULL, &sig_len);
    uint8_t *sig = malloc(sig_len);
    if (EVP_DigestSignFinal(md_ctx, sig, &sig_len) <= 0) {
        EVP_MD_CTX_free(md_ctx);
        free(sig);
        w_raise(w_string("Crypto: signing failed"));
    }
    EVP_MD_CTX_free(md_ctx);

    WValue result = w_bytes_from_data(sig, (int64_t)sig_len);
    free(sig);
    return result;
}

WValue w_crypto_rsa_thumbprint(WValue key) {
    EVP_PKEY *pkey = extract_pkey(key);

    BIGNUM *n_bn = NULL, *e_bn = NULL;
    EVP_PKEY_get_bn_param(pkey, "n", &n_bn);
    EVP_PKEY_get_bn_param(pkey, "e", &e_bn);
    if (!n_bn || !e_bn) {
        if (n_bn) BN_free(n_bn);
        if (e_bn) BN_free(e_bn);
        w_raise(w_string("Crypto: failed to extract RSA params for thumbprint"));
    }

    char *e_b64 = bn_to_b64url(e_bn);
    char *n_b64 = bn_to_b64url(n_bn);
    BN_free(n_bn);
    BN_free(e_bn);

    /* RFC 7638 thumbprint: lexicographic JSON {"e":"...","kty":"RSA","n":"..."} */
    size_t json_len = strlen(e_b64) + strlen(n_b64) + 32;
    char *json = malloc(json_len);
    snprintf(json, json_len, "{\"e\":\"%s\",\"kty\":\"RSA\",\"n\":\"%s\"}", e_b64, n_b64);

    /* SHA-256 hash */
    uint8_t hash[SHA256_DIGEST_LENGTH];
    SHA256((const uint8_t *)json, strlen(json), hash);
    free(json);
    free(e_b64);
    free(n_b64);

    /* base64url encode the hash */
    char *thumb = b64url_encode_raw(hash, SHA256_DIGEST_LENGTH);
    WValue thumb_val = w_string(thumb);
    free(thumb);
    return thumb_val;
}

WValue w_crypto_generate_csr(WValue key, WValue domains) {
    EVP_PKEY *pkey = extract_pkey(key);
    WArray *dom_arr = (WArray *)w_as_ptr(domains);
    if (!dom_arr || dom_arr->length < 1) {
        w_raise(w_string("Crypto: CSR requires at least one domain"));
    }

    X509_REQ *req = X509_REQ_new();
    if (!req) w_raise(w_string("Crypto: failed to create CSR"));

    X509_REQ_set_version(req, 0);

    /* Set subject CN to first domain */
    char cn_buf[6];
    const char *cn;
    size_t cn_len;
    w_str_data(dom_arr->items[0], cn_buf, &cn, &cn_len);

    X509_NAME *subj = X509_REQ_get_subject_name(req);
    X509_NAME_add_entry_by_txt(subj, "CN", MBSTRING_ASC, (const unsigned char *)cn, -1, -1, 0);

    /* Add SAN extension for all domains */
    if (dom_arr->length > 0) {
        STACK_OF(X509_EXTENSION) *exts = sk_X509_EXTENSION_new_null();
        /* Build SAN string: "DNS:a.com,DNS:b.com" */
        size_t san_len = 0;
        for (int64_t i = 0; i < dom_arr->length; i++) {
            char d_buf[6];
            const char *d;
            size_t d_len;
            w_str_data(dom_arr->items[i], d_buf, &d, &d_len);
            san_len += d_len + 5; /* "DNS:" + "," */
        }
        char *san = malloc(san_len + 1);
        san[0] = '\0';
        for (int64_t i = 0; i < dom_arr->length; i++) {
            if (i > 0) strcat(san, ",");
            strcat(san, "DNS:");
            char d_buf2[6];
            const char *d;
            size_t d_len2;
            w_str_data(dom_arr->items[i], d_buf2, &d, &d_len2);
            strcat(san, d);
        }

        X509_EXTENSION *ext = X509V3_EXT_nconf_nid(NULL, NULL, NID_subject_alt_name, san);
        free(san);
        if (ext) {
            sk_X509_EXTENSION_push(exts, ext);
            X509_REQ_add_extensions(req, exts);
            sk_X509_EXTENSION_pop_free(exts, X509_EXTENSION_free);
        }
    }

    X509_REQ_set_pubkey(req, pkey);
    X509_REQ_sign(req, pkey, EVP_sha256());

    /* DER encode */
    int der_len = i2d_X509_REQ(req, NULL);
    if (der_len <= 0) {
        X509_REQ_free(req);
        w_raise(w_string("Crypto: CSR DER encoding failed"));
    }
    uint8_t *der = malloc(der_len);
    uint8_t *p = der;
    i2d_X509_REQ(req, &p);
    X509_REQ_free(req);

    WValue result = w_bytes_from_data(der, (int64_t)der_len);
    free(der);
    return result;
}

#endif /* TUNGSTEN_TLS */
