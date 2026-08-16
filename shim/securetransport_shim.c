/*
 * SecureTransport → OpenSSL 3.5 Shim for Mac OS X Tiger
 *
 * Replaces Apple's Secure Transport SSL/TLS implementation with
 * OpenSSL 3.5.6 LTS, giving TLS 1.2/1.3 support to Safari, Mail,
 * and all applications using the SecureTransport API.
 *
 * This file is built only through scripts/tiger/91-build-security-shim.sh.
 * The resulting wrapper is activated by the opt-in security-shim package;
 * DYLD_INSERT_LIBRARIES is not a supported installation method.
 *
 * Part of the modern-tiger-ppc project.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

#include <CoreServices/../Frameworks/CarbonCore.framework/Headers/MacTypes.h>
#include <CoreFoundation/CoreFoundation.h>

/* Mac error codes (from MacErrors.h) */
#ifndef paramErr
#define paramErr    -50
#endif
#ifndef memFullErr
#define memFullErr  -108
#endif
#ifndef noErr
#define noErr       0
#endif

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/bio.h>

/* Security.framework types for SecCertificateCreateFromData */
typedef struct {
    uint32_t Length;
    uint8_t  *Data;
} CSSM_DATA;

#define CSSM_CERT_X_509v3       0x03
#define CSSM_CERT_ENCODING_DER  0x03

typedef void *SecCertificateRef;

/* Dynamically resolved Security.framework function */
typedef OSStatus (*SecCertificateCreateFromData_t)(
    const CSSM_DATA *data, uint32_t type, uint32_t encoding,
    SecCertificateRef *certificate);

static SecCertificateCreateFromData_t real_SecCertificateCreateFromData = NULL;

/* For SSLSetTrustedRoots: extract DER from SecCertificateRef */
typedef OSStatus (*SecCertificateGetData_t)(SecCertificateRef cert, CSSM_DATA *data);
static SecCertificateGetData_t real_SecCertificateGetData = NULL;

/* ================================================================
 * Secure Transport types (from SecureTransport.h)
 * We redefine them here to avoid including the system header,
 * which would conflict with our function definitions.
 * ================================================================ */

typedef struct ShimSSLContext *SSLContextRef;
typedef const void *SSLConnectionRef;

typedef enum {
    kSSLProtocolUnknown = 0,
    kSSLProtocol2 = 1,
    kSSLProtocol3 = 2,
    kSSLProtocol3Only = 3,
    kTLSProtocol1 = 4,
    kTLSProtocol1Only = 5,
    kSSLProtocolAll = 6,
    kTLSProtocol11 = 7,
    kTLSProtocol12 = 8,
    kDTLSProtocol1 = 9,
    kTLSProtocol13 = 10,
    kDTLSProtocol12 = 11
} SSLProtocol;

typedef enum {
    kSSLIdle,
    kSSLHandshake,
    kSSLConnected,
    kSSLClosed,
    kSSLAborted
} SSLSessionState;

typedef enum {
    kSSLClientCertNone,
    kSSLClientCertRequested,
    kSSLClientCertSent,
    kSSLClientCertRejected
} SSLClientCertificateState;

typedef enum {
    kNeverAuthenticate,
    kAlwaysAuthenticate,
    kTryAuthenticate
} SSLAuthenticate;

typedef UInt32 SSLCipherSuite;

typedef OSStatus (*SSLReadFunc)(SSLConnectionRef connection,
                                void *data, size_t *dataLength);
typedef OSStatus (*SSLWriteFunc)(SSLConnectionRef connection,
                                 const void *data, size_t *dataLength);

/* Secure Transport error codes */
enum {
    errSSLProtocol          = -9800,
    errSSLNegotiation       = -9801,
    errSSLFatalAlert        = -9802,
    errSSLWouldBlock        = -9803,
    errSSLSessionNotFound   = -9804,
    errSSLClosedGraceful    = -9805,
    errSSLClosedAbort       = -9806,
    errSSLXCertChainInvalid = -9807,
    errSSLBadCert           = -9808,
    errSSLCrypto            = -9809,
    errSSLInternal          = -9810,
    errSSLUnknownRootCert   = -9812,
    errSSLNoRootCert        = -9813,
    errSSLCertExpired       = -9814,
    errSSLCertNotYetValid   = -9815,
    errSSLClosedNoNotify    = -9816,
    errSSLBufferOverflow    = -9817,
    errSSLBadCipherSuite    = -9818,
    errSSLHostNameMismatch  = -9843,
    errSSLConnectionRefused = -9844
};

/* ================================================================
 * Our internal SSL context structure
 * Replaces Apple's opaque SSLContext
 * ================================================================ */

#define SHIM_MAGIC 0x5348494D /* "SHIM" */

/* forward */
static void ensure_bio_setup(struct ShimSSLContext *ctx);

struct ShimSSLContext {
    uint32_t            magic;
    Boolean             isServer;
    SSLSessionState     state;
    SSLConnectionRef    connection;
    SSLReadFunc         readFunc;
    SSLWriteFunc        writeFunc;

    /* OpenSSL objects */
    SSL_CTX             *ssl_ctx;
    SSL                 *ssl;
    BIO                 *bio;

    /* Settings */
    char                *peerDomainName;
    size_t              peerDomainNameLen;
    Boolean             enableCertVerify;
    Boolean             allowsExpiredCerts;
    Boolean             allowsAnyRoot;
    Boolean             allowsExpiredRoots;

    /* Client cert state */
    SSLClientCertificateState clientCertState;
    CFArrayRef              clientCertRefs;
};

/* CA bundle path */
static const char *CA_BUNDLE = "/usr/local/ssl/certs/cacert.pem";

/* Debug logging */
#ifdef SHIM_DEBUG
#define SHIM_LOG(fmt, ...) fprintf(stderr, "[ST-shim] " fmt "\n", ##__VA_ARGS__)
#else
#define SHIM_LOG(fmt, ...)
#endif

/* ================================================================
 * Custom BIO: bridges OpenSSL I/O to app's SSLReadFunc/SSLWriteFunc
 * ================================================================ */

static int bio_shim_write(BIO *bio, const char *buf, int len) {
    struct ShimSSLContext *ctx = (struct ShimSSLContext *)BIO_get_data(bio);
    if (!ctx || !ctx->writeFunc || !ctx->connection) return -1;

    size_t written = (size_t)len;
    OSStatus status = ctx->writeFunc(ctx->connection, buf, &written);

    if (status == errSSLWouldBlock) {
        BIO_set_retry_write(bio);
        return (int)written > 0 ? (int)written : -1;
    }
    if (status != noErr) return -1;

    BIO_clear_retry_flags(bio);
    return (int)written;
}

static int bio_shim_read(BIO *bio, char *buf, int len) {
    struct ShimSSLContext *ctx = (struct ShimSSLContext *)BIO_get_data(bio);
    if (!ctx || !ctx->readFunc || !ctx->connection) return -1;

    size_t readLen = (size_t)len;
    OSStatus status = ctx->readFunc(ctx->connection, buf, &readLen);

    if (status == errSSLWouldBlock) {
        BIO_set_retry_read(bio);
        return (int)readLen > 0 ? (int)readLen : -1;
    }
    if (status == errSSLClosedGraceful || status == errSSLClosedNoNotify) {
        return 0; /* EOF */
    }
    if (status != noErr) return -1;

    BIO_clear_retry_flags(bio);
    return (int)readLen;
}

static int bio_shim_puts(BIO *bio, const char *str) {
    return bio_shim_write(bio, str, (int)strlen(str));
}

static long bio_shim_ctrl(BIO *bio, int cmd, long num, void *ptr) {
    (void)bio; (void)num; (void)ptr;
    switch (cmd) {
        case BIO_CTRL_FLUSH:
            return 1;
        case BIO_CTRL_PUSH:
        case BIO_CTRL_POP:
            return 0;
        default:
            return 0;
    }
}

static int bio_shim_create(BIO *bio) {
    BIO_set_init(bio, 1);
    return 1;
}

static int bio_shim_destroy(BIO *bio) {
    if (!bio) return 0;
    BIO_set_data(bio, NULL);
    BIO_set_init(bio, 0);
    return 1;
}

static BIO_METHOD *shim_bio_method = NULL;

/*
 * Custom verify callback: honors allowsExpiredCerts / allowsExpiredRoots / allowsAnyRoot
 * flags stored in the per-SSL ShimSSLContext. Called by OpenSSL for each cert
 * during chain verification.
 */
static int shim_verify_cb(int preverify_ok, X509_STORE_CTX *store_ctx) {
    if (preverify_ok) return 1;

    SSL *ssl = X509_STORE_CTX_get_ex_data(
        store_ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
    if (!ssl) return 0;

    struct ShimSSLContext *ctx = (struct ShimSSLContext *)SSL_get_app_data(ssl);
    if (!ctx || ctx->magic != SHIM_MAGIC) return 0;

    int err = X509_STORE_CTX_get_error(store_ctx);
    int depth = X509_STORE_CTX_get_error_depth(store_ctx);

    switch (err) {
    case X509_V_ERR_CERT_HAS_EXPIRED:
    case X509_V_ERR_CRL_HAS_EXPIRED:
        if (ctx->allowsExpiredCerts) {
            SHIM_LOG("verify_cb: allowing expired cert (depth=%d)", depth);
            return 1;
        }
        break;
    case X509_V_ERR_CERT_NOT_YET_VALID:
    case X509_V_ERR_CRL_NOT_YET_VALID:
        if (ctx->allowsExpiredCerts) {
            SHIM_LOG("verify_cb: allowing not-yet-valid cert (depth=%d)", depth);
            return 1;
        }
        break;
    case X509_V_ERR_ERROR_IN_CERT_NOT_BEFORE_FIELD:
    case X509_V_ERR_ERROR_IN_CERT_NOT_AFTER_FIELD:
        if (ctx->allowsExpiredRoots && depth > 0) {
            SHIM_LOG("verify_cb: allowing expired-root cert (depth=%d)", depth);
            return 1;
        }
        break;
    case X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT:
    case X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN:
    case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT:
    case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY:
    case X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE:
        if (ctx->allowsAnyRoot) {
            SHIM_LOG("verify_cb: allowing any-root cert (err=%d depth=%d)",
                     err, depth);
            return 1;
        }
        break;
    default:
        break;
    }
    SHIM_LOG("verify_cb: REJECTED err=%d depth=%d", err, depth);
    return 0;
}

static BIO_METHOD *get_shim_bio_method(void) {
    if (!shim_bio_method) {
        shim_bio_method = BIO_meth_new(BIO_TYPE_SOURCE_SINK, "securetransport_shim");
        BIO_meth_set_write(shim_bio_method, bio_shim_write);
        BIO_meth_set_read(shim_bio_method, bio_shim_read);
        BIO_meth_set_puts(shim_bio_method, bio_shim_puts);
        BIO_meth_set_ctrl(shim_bio_method, bio_shim_ctrl);
        BIO_meth_set_create(shim_bio_method, bio_shim_create);
        BIO_meth_set_destroy(shim_bio_method, bio_shim_destroy);
    }
    return shim_bio_method;
}

/* ================================================================
 * Helper: convert OpenSSL errors to Secure Transport OSStatus
 * ================================================================ */

static OSStatus ossl_error_to_osstatus(SSL *ssl, int ret) {
    int err = SSL_get_error(ssl, ret);
    switch (err) {
        case SSL_ERROR_NONE:          return noErr;
        case SSL_ERROR_WANT_READ:     return errSSLWouldBlock;
        case SSL_ERROR_WANT_WRITE:    return errSSLWouldBlock;
        case SSL_ERROR_ZERO_RETURN:   return errSSLClosedGraceful;
        case SSL_ERROR_SYSCALL:       return errSSLClosedAbort;
        case SSL_ERROR_SSL: {
            unsigned long e = ERR_peek_error();
            int reason = ERR_GET_REASON(e);
            (void)reason;
            /* Check for specific cert errors */
            long verify = SSL_get_verify_result(ssl);
            if (verify == X509_V_ERR_CERT_HAS_EXPIRED)
                return errSSLCertExpired;
            if (verify == X509_V_ERR_CERT_NOT_YET_VALID)
                return errSSLCertNotYetValid;
            if (verify == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY)
                return errSSLUnknownRootCert;
            if (verify == X509_V_ERR_HOSTNAME_MISMATCH)
                return errSSLHostNameMismatch;
            return errSSLCrypto;
        }
        default:
            return errSSLInternal;
    }
}

/* ================================================================
 * Secure Transport API implementation
 * ================================================================ */

OSStatus SSLNewContext(Boolean isServer, SSLContextRef *contextPtr) {
    SHIM_LOG("SSLNewContext(isServer=%d)", isServer);

    if (!contextPtr) return paramErr;

    struct ShimSSLContext *ctx = calloc(1, sizeof(struct ShimSSLContext));
    if (!ctx) return memFullErr;

    ctx->magic = SHIM_MAGIC;
    ctx->isServer = isServer;
    ctx->state = kSSLIdle;
    ctx->enableCertVerify = true;
    ctx->allowsExpiredCerts = false;
    ctx->allowsAnyRoot = false;
    ctx->allowsExpiredRoots = false;
    ctx->clientCertState = kSSLClientCertNone;

    /* Create OpenSSL context */
    const SSL_METHOD *method = isServer ? TLS_server_method() : TLS_client_method();
    ctx->ssl_ctx = SSL_CTX_new(method);
    if (!ctx->ssl_ctx) {
        SHIM_LOG("SSL_CTX_new failed");
        free(ctx);
        return errSSLInternal;
    }

    /* Set minimum TLS 1.2 (no old protocols) */
    SSL_CTX_set_min_proto_version(ctx->ssl_ctx, TLS1_2_VERSION);

    /* Load CA certificates */
    if (SSL_CTX_load_verify_locations(ctx->ssl_ctx, CA_BUNDLE, NULL) != 1) {
        SHIM_LOG("Warning: failed to load CA bundle from %s", CA_BUNDLE);
    }

    /* Create SSL object */
    ctx->ssl = SSL_new(ctx->ssl_ctx);
    if (!ctx->ssl) {
        SSL_CTX_free(ctx->ssl_ctx);
        free(ctx);
        return errSSLInternal;
    }

    /* Wire ShimSSLContext to SSL so verify_cb can find it */
    SSL_set_app_data(ctx->ssl, ctx);
    SSL_set_verify(ctx->ssl, SSL_VERIFY_PEER, shim_verify_cb);

    *contextPtr = ctx;
    return noErr;
}

OSStatus SSLDisposeContext(SSLContextRef context) {
    SHIM_LOG("SSLDisposeContext(%p)", context);

    if (!context || context->magic != SHIM_MAGIC) return paramErr;

    if (context->ssl) SSL_free(context->ssl); /* also frees BIO */
    if (context->ssl_ctx) SSL_CTX_free(context->ssl_ctx);
    if (context->peerDomainName) free(context->peerDomainName);
    if (context->clientCertRefs) CFRelease(context->clientCertRefs);

    context->magic = 0;
    free(context);
    return noErr;
}

OSStatus SSLGetSessionState(SSLContextRef context, SSLSessionState *state) {
    if (!context || !state || context->magic != SHIM_MAGIC) return paramErr;
    *state = context->state;
    return noErr;
}

OSStatus SSLSetIOFuncs(SSLContextRef context,
                       SSLReadFunc readFunc, SSLWriteFunc writeFunc) {
    SHIM_LOG("SSLSetIOFuncs(%p)", context);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (context->state != kSSLIdle) return paramErr;

    context->readFunc = readFunc;
    context->writeFunc = writeFunc;
    ensure_bio_setup(context);
    return noErr;
}

/* Helper: ensure BIO is set up when both IO funcs and connection are ready */
static void ensure_bio_setup(struct ShimSSLContext *ctx) {
    if (ctx->bio) return; /* already done */
    if (!ctx->readFunc || !ctx->writeFunc || !ctx->connection) return;

    BIO *bio = BIO_new(get_shim_bio_method());
    BIO_set_data(bio, ctx);
    SSL_set_bio(ctx->ssl, bio, bio);
    ctx->bio = bio;
    SHIM_LOG("BIO setup complete for %p", ctx);
}

OSStatus SSLSetConnection(SSLContextRef context, SSLConnectionRef connection) {
    SHIM_LOG("SSLSetConnection(%p, %p)", context, connection);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;

    context->connection = connection;
    ensure_bio_setup(context);

    return noErr;
}

OSStatus SSLGetConnection(SSLContextRef context, SSLConnectionRef *connection) {
    if (!context || !connection || context->magic != SHIM_MAGIC) return paramErr;
    *connection = context->connection;
    return noErr;
}

OSStatus SSLSetPeerDomainName(SSLContextRef context,
                              const char *peerName, size_t peerNameLen) {
    SHIM_LOG("SSLSetPeerDomainName(%p, %.*s)", context, (int)peerNameLen, peerName);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (!peerName && peerNameLen != 0) return paramErr;

    if (context->peerDomainName) free(context->peerDomainName);

    context->peerDomainName = malloc(peerNameLen + 1);
    if (!context->peerDomainName) return memFullErr;

    memcpy(context->peerDomainName, peerName, peerNameLen);
    context->peerDomainName[peerNameLen] = '\0';
    context->peerDomainNameLen = peerNameLen;

    /* Set SNI for OpenSSL */
    SSL_set_tlsext_host_name(context->ssl, context->peerDomainName);

    /* Set hostname verification */
    if (context->enableCertVerify) {
        SSL_set1_host(context->ssl, context->peerDomainName);
    }

    return noErr;
}

OSStatus SSLGetPeerDomainNameLength(SSLContextRef context, size_t *peerNameLen) {
    if (!context || !peerNameLen || context->magic != SHIM_MAGIC) return paramErr;
    *peerNameLen = context->peerDomainNameLen;
    return noErr;
}

OSStatus SSLGetPeerDomainName(SSLContextRef context,
                              char *peerName, size_t *peerNameLen) {
    if (!context || !peerName || !peerNameLen || context->magic != SHIM_MAGIC)
        return paramErr;
    size_t len = context->peerDomainNameLen;
    if (*peerNameLen < len) return errSSLBufferOverflow;
    memcpy(peerName, context->peerDomainName, len);
    *peerNameLen = len;
    return noErr;
}

OSStatus SSLSetProtocolVersionEnabled(SSLContextRef context,
                                      SSLProtocol protocol, Boolean enable) {
    SHIM_LOG("SSLSetProtocolVersionEnabled(%p, %d, %d)", context, protocol, enable);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)protocol;
    (void)enable;
    /* We always use TLS 1.2+ regardless of what the app requests */
    return noErr;
}

OSStatus SSLGetProtocolVersionEnabled(SSLContextRef context,
                                      SSLProtocol protocol, Boolean *enable) {
    if (!context || !enable || context->magic != SHIM_MAGIC) return paramErr;
    /* Report TLS1 and "all" as enabled */
    *enable = (protocol == kTLSProtocol1 || protocol == kSSLProtocolAll);
    return noErr;
}

OSStatus SSLSetProtocolVersion(SSLContextRef context, SSLProtocol version) {
    SHIM_LOG("SSLSetProtocolVersion(%p, %d)", context, version);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)version;
    return noErr; /* Ignored — always TLS 1.2+ */
}

OSStatus SSLGetProtocolVersion(SSLContextRef context, SSLProtocol *protocol) {
    if (!context || !protocol || context->magic != SHIM_MAGIC) return paramErr;
    *protocol = kTLSProtocol1;
    return noErr;
}

OSStatus SSLGetNegotiatedProtocolVersion(SSLContextRef context,
                                         SSLProtocol *protocol) {
    if (!context || !protocol || context->magic != SHIM_MAGIC) return paramErr;
    if (context->state != kSSLConnected || !context->ssl) {
        *protocol = kSSLProtocolUnknown;
        return noErr;
    }
    int v = SSL_version(context->ssl);
    switch (v) {
        case TLS1_VERSION:   *protocol = kTLSProtocol1;  break;
        case TLS1_1_VERSION: *protocol = kTLSProtocol11; break;
        case TLS1_2_VERSION: *protocol = kTLSProtocol12; break;
        case TLS1_3_VERSION: *protocol = kTLSProtocol13; break;
        case SSL3_VERSION:   *protocol = kSSLProtocol3;  break;
        default:             *protocol = kSSLProtocolUnknown; break;
    }
    return noErr;
}

OSStatus SSLSetEnableCertVerify(SSLContextRef context, Boolean enableVerify) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    context->enableCertVerify = enableVerify;
    /* Keep our callback installed either way so flags stay honored.
     * enableVerify=false -> SSL_VERIFY_NONE (callback not invoked, always pass).
     * enableVerify=true  -> SSL_VERIFY_PEER (callback consulted). */
    SSL_set_verify(context->ssl,
                   enableVerify ? SSL_VERIFY_PEER : SSL_VERIFY_NONE,
                   shim_verify_cb);
    return noErr;
}

OSStatus SSLGetEnableCertVerify(SSLContextRef context, Boolean *enableVerify) {
    if (!context || !enableVerify || context->magic != SHIM_MAGIC) return paramErr;
    *enableVerify = context->enableCertVerify;
    return noErr;
}

OSStatus SSLSetAllowsExpiredCerts(SSLContextRef context, Boolean allows) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    context->allowsExpiredCerts = allows;
    return noErr;
}

OSStatus SSLGetAllowsExpiredCerts(SSLContextRef context, Boolean *allows) {
    if (!context || !allows || context->magic != SHIM_MAGIC) return paramErr;
    *allows = context->allowsExpiredCerts;
    return noErr;
}

OSStatus SSLSetAllowsExpiredRoots(SSLContextRef context, Boolean allows) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    context->allowsExpiredRoots = allows;
    return noErr;
}

OSStatus SSLGetAllowsExpiredRoots(SSLContextRef context, Boolean *allows) {
    if (!context || !allows || context->magic != SHIM_MAGIC) return paramErr;
    *allows = context->allowsExpiredRoots;
    return noErr;
}

OSStatus SSLSetAllowsAnyRoot(SSLContextRef context, Boolean anyRoot) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    context->allowsAnyRoot = anyRoot;
    /* Keep SSL_VERIFY_PEER + callback; the callback accepts any-root errors
     * when the flag is on, instead of disabling verification entirely. */
    return noErr;
}

OSStatus SSLGetAllowsAnyRoot(SSLContextRef context, Boolean *anyRoot) {
    if (!context || !anyRoot || context->magic != SHIM_MAGIC) return paramErr;
    *anyRoot = context->allowsAnyRoot;
    return noErr;
}

OSStatus SSLSetCertificate(SSLContextRef context, CFArrayRef certRefs) {
    SHIM_LOG("SSLSetCertificate(%p)", context);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    /* Store client certificate refs (retain) */
    if (context->clientCertRefs) CFRelease(context->clientCertRefs);
    context->clientCertRefs = certRefs ? (CFArrayRef)CFRetain(certRefs) : NULL;
    return noErr;
}

OSStatus SSLGetCertificate(SSLContextRef context, CFArrayRef *certRefs) {
    SHIM_LOG("SSLGetCertificate(%p)", context);
    if (!context || !certRefs || context->magic != SHIM_MAGIC) return paramErr;
    /* Return client certificate (not retained — caller does NOT release) */
    *certRefs = context->clientCertRefs;
    return noErr;
}

OSStatus SSLSetEncryptionCertificate(SSLContextRef context, CFArrayRef certRefs) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)certRefs;
    return noErr; /* Server-side only, stub */
}

OSStatus SSLSetTrustedRoots(SSLContextRef context,
                            CFArrayRef trustedRoots, Boolean replaceExisting) {
    SHIM_LOG("SSLSetTrustedRoots(%p, replace=%d, count=%ld)",
             context, replaceExisting,
             trustedRoots ? CFArrayGetCount(trustedRoots) : 0L);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (!context->ssl_ctx) return errSSLInternal;

    if (!real_SecCertificateGetData) {
        real_SecCertificateGetData = (SecCertificateGetData_t)
            dlsym(RTLD_DEFAULT, "SecCertificateGetData");
    }
    if (!real_SecCertificateGetData) {
        SHIM_LOG("SecCertificateGetData not resolvable; keeping CA bundle");
        return noErr;
    }

    X509_STORE *store;
    if (replaceExisting) {
        /* Fresh store with no defaults */
        store = X509_STORE_new();
        if (!store) return memFullErr;
        SSL_CTX_set_cert_store(context->ssl_ctx, store);
    } else {
        store = SSL_CTX_get_cert_store(context->ssl_ctx);
        if (!store) return errSSLInternal;
    }

    if (!trustedRoots) return noErr;

    CFIndex n = CFArrayGetCount(trustedRoots);
    int added = 0;
    for (CFIndex i = 0; i < n; i++) {
        SecCertificateRef secCert =
            (SecCertificateRef)CFArrayGetValueAtIndex(trustedRoots, i);
        if (!secCert) continue;

        CSSM_DATA der;
        memset(&der, 0, sizeof der);
        OSStatus st = real_SecCertificateGetData(secCert, &der);
        if (st != noErr || !der.Data || der.Length == 0) {
            SHIM_LOG("trustedRoots[%ld]: SecCertificateGetData failed (%d)",
                     i, (int)st);
            continue;
        }

        const unsigned char *p = der.Data;
        X509 *x = d2i_X509(NULL, &p, (long)der.Length);
        if (!x) {
            SHIM_LOG("trustedRoots[%ld]: d2i_X509 failed", i);
            continue;
        }
        if (X509_STORE_add_cert(store, x) == 1) {
            added++;
        } else {
            /* dup or other — not fatal */
            unsigned long e = ERR_peek_error();
            (void)e;
            SHIM_LOG("trustedRoots[%ld]: X509_STORE_add_cert skipped (err=0x%lx)",
                     i, e);
            ERR_clear_error();
        }
        X509_free(x);
    }
    SHIM_LOG("SSLSetTrustedRoots: added %d/%ld certs", added, (long)n);
    return noErr;
}

OSStatus SSLGetTrustedRoots(SSLContextRef context, CFArrayRef *trustedRoots) {
    if (!context || !trustedRoots || context->magic != SHIM_MAGIC) return paramErr;
    *trustedRoots = CFArrayCreate(NULL, NULL, 0, NULL);
    return noErr;
}

OSStatus SSLSetPeerID(SSLContextRef context,
                      const void *peerID, size_t peerIDLen) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)peerID;
    (void)peerIDLen;
    /* Session resumption — OpenSSL handles this internally */
    return noErr;
}

OSStatus SSLGetPeerID(SSLContextRef context,
                      const void **peerID, size_t *peerIDLen) {
    if (!context || !peerID || !peerIDLen || context->magic != SHIM_MAGIC)
        return paramErr;
    *peerID = NULL;
    *peerIDLen = 0;
    return noErr;
}

OSStatus SSLGetPeerCertificates(SSLContextRef context, CFArrayRef *certs) {
    SHIM_LOG("SSLGetPeerCertificates(%p)", context);
    if (!context || !certs || context->magic != SHIM_MAGIC) return paramErr;

    /* Resolve SecCertificateCreateFromData from Security.framework */
    if (!real_SecCertificateCreateFromData) {
        real_SecCertificateCreateFromData =
            (SecCertificateCreateFromData_t)dlsym(RTLD_DEFAULT,
                                                   "SecCertificateCreateFromData");
        if (!real_SecCertificateCreateFromData) {
            SHIM_LOG("Cannot find SecCertificateCreateFromData");
            *certs = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
            return noErr;
        }
    }

    /* Get peer certificate chain from OpenSSL */
    STACK_OF(X509) *chain = SSL_get_peer_cert_chain(context->ssl);
    X509 *peer_cert = SSL_get1_peer_certificate(context->ssl);

    int chain_len = chain ? sk_X509_num(chain) : 0;
    int total = (peer_cert && chain_len == 0) ? 1 : chain_len;

    SHIM_LOG("Peer cert chain: %d certificates", total);

    if (total == 0) {
        if (peer_cert) X509_free(peer_cert);
        *certs = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
        return noErr;
    }

    /* Convert each X509 to SecCertificateRef */
    CFMutableArrayRef certArray = CFArrayCreateMutable(NULL, total,
                                                       &kCFTypeArrayCallBacks);

    for (int i = 0; i < total; i++) {
        X509 *x509;
        if (chain) {
            x509 = sk_X509_value(chain, i);
        } else {
            x509 = peer_cert;
        }

        /* Convert X509 to DER */
        unsigned char *der = NULL;
        int derLen = i2d_X509(x509, &der);
        if (derLen <= 0 || !der) {
            SHIM_LOG("i2d_X509 failed for cert %d", i);
            continue;
        }

        /* Create SecCertificateRef from DER data */
        CSSM_DATA cssmData;
        cssmData.Length = (uint32_t)derLen;
        cssmData.Data = der;

        SecCertificateRef secCert = NULL;
        OSStatus st = real_SecCertificateCreateFromData(&cssmData,
                          CSSM_CERT_X_509v3, CSSM_CERT_ENCODING_DER, &secCert);

        OPENSSL_free(der);

        if (st == noErr && secCert) {
            CFArrayAppendValue(certArray, secCert);
            CFRelease(secCert);
            SHIM_LOG("Cert %d: converted to SecCertificateRef", i);
        } else {
            SHIM_LOG("Cert %d: SecCertificateCreateFromData failed (%d)", i, (int)st);
        }
    }

    if (peer_cert) X509_free(peer_cert);

    *certs = certArray;
    SHIM_LOG("Returning %ld certificates", CFArrayGetCount(certArray));
    return noErr;
}

OSStatus SSLGetClientCertificateState(SSLContextRef context,
                                      SSLClientCertificateState *clientState) {
    if (!context || !clientState || context->magic != SHIM_MAGIC) return paramErr;
    *clientState = context->clientCertState;
    return noErr;
}

OSStatus SSLSetClientSideAuthenticate(SSLContextRef context, SSLAuthenticate auth) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)auth;
    return noErr; /* Stub */
}

OSStatus SSLAddDistinguishedName(SSLContextRef context,
                                 const void *derDN, size_t derDNLen) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)derDN;
    (void)derDNLen;
    return noErr; /* Stub */
}

OSStatus SSLSetSessionCacheTimeout(SSLContextRef context, uint32_t timeout) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    SSL_CTX_set_timeout(context->ssl_ctx, timeout);
    return noErr;
}

/* Cipher suite mapping */
OSStatus SSLGetNumberSupportedCiphers(SSLContextRef context, size_t *numCiphers) {
    if (!context || !numCiphers || context->magic != SHIM_MAGIC) return paramErr;
    STACK_OF(SSL_CIPHER) *ciphers = SSL_get_ciphers(context->ssl);
    *numCiphers = ciphers ? (size_t)sk_SSL_CIPHER_num(ciphers) : 0;
    return noErr;
}

OSStatus SSLGetSupportedCiphers(SSLContextRef context,
                                SSLCipherSuite *ciphers, size_t *numCiphers) {
    if (!context || !ciphers || !numCiphers || context->magic != SHIM_MAGIC)
        return paramErr;
    STACK_OF(SSL_CIPHER) *stack = SSL_get_ciphers(context->ssl);
    size_t count = stack ? (size_t)sk_SSL_CIPHER_num(stack) : 0;
    if (*numCiphers < count) return errSSLBufferOverflow;
    for (size_t i = 0; i < count; i++) {
        const SSL_CIPHER *c = sk_SSL_CIPHER_value(stack, i);
        ciphers[i] = (SSLCipherSuite)SSL_CIPHER_get_protocol_id(c);
    }
    *numCiphers = count;
    return noErr;
}

OSStatus SSLSetEnabledCiphers(SSLContextRef context,
                              const SSLCipherSuite *ciphers, size_t numCiphers) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)ciphers;
    (void)numCiphers;
    /* Let OpenSSL use its defaults — they're better than Tiger's */
    return noErr;
}

OSStatus SSLGetNumberEnabledCiphers(SSLContextRef context, size_t *numCiphers) {
    return SSLGetNumberSupportedCiphers(context, numCiphers);
}

OSStatus SSLGetEnabledCiphers(SSLContextRef context,
                              SSLCipherSuite *ciphers, size_t *numCiphers) {
    return SSLGetSupportedCiphers(context, ciphers, numCiphers);
}

OSStatus SSLGetNegotiatedCipher(SSLContextRef context, SSLCipherSuite *cipherSuite) {
    if (!context || !cipherSuite || context->magic != SHIM_MAGIC) return paramErr;
    if (context->state != kSSLConnected) return errSSLInternal;
    const SSL_CIPHER *c = SSL_get_current_cipher(context->ssl);
    if (c) {
        *cipherSuite = (SSLCipherSuite)SSL_CIPHER_get_protocol_id(c);
    }
    return noErr;
}

OSStatus SSLGetCipherSizes(SSLContextRef context,
                           size_t *digestSize, size_t *symmetricKeySize,
                           size_t *ivSize) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (digestSize) *digestSize = 32;
    if (symmetricKeySize) *symmetricKeySize = 256;
    if (ivSize) *ivSize = 16;
    return noErr;
}

OSStatus SSLSetDiffieHellmanParams(SSLContextRef context,
                                   const void *dhParams, size_t dhParamsLen) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)dhParams;
    (void)dhParamsLen;
    return noErr; /* OpenSSL handles DH internally */
}

OSStatus SSLGetDiffieHellmanParams(SSLContextRef context,
                                   const void **dhParams, size_t *dhParamsLen) {
    if (!context || !dhParams || !dhParamsLen || context->magic != SHIM_MAGIC)
        return paramErr;
    *dhParams = NULL;
    *dhParamsLen = 0;
    return noErr;
}

OSStatus SSLSetRsaBlinding(SSLContextRef context, Boolean blinding) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    (void)blinding;
    return noErr;
}

OSStatus SSLGetRsaBlinding(SSLContextRef context, Boolean *blinding) {
    if (!context || !blinding || context->magic != SHIM_MAGIC) return paramErr;
    *blinding = true;
    return noErr;
}

OSStatus SSLGetResumableSessionInfo(SSLContextRef context,
                                    Boolean *sessionWasResumed,
                                    void *sessionID, size_t *sessionIDLength) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (sessionWasResumed) *sessionWasResumed = SSL_session_reused(context->ssl);
    if (sessionID && sessionIDLength) *sessionIDLength = 0;
    return noErr;
}

/* SecTrust creation via dlsym */
typedef OSStatus (*SecTrustCreateWithCertificates_t)(CFArrayRef, CFTypeRef, void **);
typedef OSStatus (*SecPolicySearchCreate_t)(uint32_t, const void *, const void *, void **);
typedef OSStatus (*SecPolicySearchCopyNext_t)(void *, void **);
static SecTrustCreateWithCertificates_t real_SecTrustCreate = NULL;

OSStatus SSLGetPeerSecTrust(SSLContextRef context, void **trust) {
    SHIM_LOG("SSLGetPeerSecTrust(%p)", context);
    if (!context || !trust || context->magic != SHIM_MAGIC) return paramErr;

    /* Get certs first */
    CFArrayRef certs = NULL;
    OSStatus st = SSLGetPeerCertificates(context, &certs);
    if (st != noErr || !certs || CFArrayGetCount(certs) == 0) {
        if (certs) CFRelease(certs);
        *trust = NULL;
        return noErr;
    }

    /* Resolve SecTrustCreateWithCertificates */
    if (!real_SecTrustCreate) {
        real_SecTrustCreate = (SecTrustCreateWithCertificates_t)
            dlsym(RTLD_DEFAULT, "SecTrustCreateWithCertificates");
    }

    if (real_SecTrustCreate) {
        st = real_SecTrustCreate(certs, NULL, trust);
        SHIM_LOG("SecTrustCreate: %d, trust=%p", (int)st, *trust);
    } else {
        SHIM_LOG("SecTrustCreateWithCertificates not found");
        *trust = NULL;
    }

    CFRelease(certs);
    return noErr;
}

OSStatus SSLGetBufferedReadSize(SSLContextRef context, size_t *bufSize) {
    if (!context || !bufSize || context->magic != SHIM_MAGIC) return paramErr;
    *bufSize = (size_t)SSL_pending(context->ssl);
    return noErr;
}

/* ================================================================
 * Core I/O: Handshake, Read, Write, Close
 * ================================================================ */

OSStatus SSLHandshake(SSLContextRef context) {
    SHIM_LOG("SSLHandshake(%p)", context);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (!context->ssl || !context->bio) return errSSLInternal;

    context->state = kSSLHandshake;

    int ret;
    if (context->isServer) {
        ret = SSL_accept(context->ssl);
    } else {
        ret = SSL_connect(context->ssl);
    }

    if (ret == 1) {
        context->state = kSSLConnected;
        SHIM_LOG("Handshake complete: %s", SSL_get_version(context->ssl));
        return noErr;
    }

    OSStatus status = ossl_error_to_osstatus(context->ssl, ret);
    if (status == errSSLWouldBlock) {
        return errSSLWouldBlock; /* App should call SSLHandshake again */
    }

    context->state = kSSLAborted;
    SHIM_LOG("Handshake failed: %d (OSStatus %d)", ret, (int)status);
    return status;
}

OSStatus SSLWrite(SSLContextRef context, const void *data,
                  size_t dataLength, size_t *processed) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (context->state != kSSLConnected) return errSSLInternal;
    if (!data || !processed) return paramErr;

    int ret = SSL_write(context->ssl, data, (int)dataLength);
    if (ret > 0) {
        *processed = (size_t)ret;
        return noErr;
    }

    *processed = 0;
    return ossl_error_to_osstatus(context->ssl, ret);
}

OSStatus SSLRead(SSLContextRef context, void *data,
                 size_t dataLength, size_t *processed) {
    if (!context || context->magic != SHIM_MAGIC) return paramErr;
    if (context->state != kSSLConnected) return errSSLInternal;
    if (!data || !processed) return paramErr;

    int ret = SSL_read(context->ssl, data, (int)dataLength);
    if (ret > 0) {
        *processed = (size_t)ret;
        return noErr;
    }

    *processed = 0;
    return ossl_error_to_osstatus(context->ssl, ret);
}

OSStatus SSLClose(SSLContextRef context) {
    SHIM_LOG("SSLClose(%p)", context);
    if (!context || context->magic != SHIM_MAGIC) return paramErr;

    if (context->state == kSSLConnected || context->state == kSSLHandshake) {
        SSL_shutdown(context->ssl);
    }
    context->state = kSSLClosed;
    return noErr;
}

/* ================================================================
 * Internal/undocumented functions (called by some Apple code)
 * ================================================================ */

OSStatus SSLInternalClientRandom(SSLContextRef context,
                                  void *random, size_t *randomLen) {
    if (!context || !random || !randomLen || context->magic != SHIM_MAGIC)
        return paramErr;
    /* Stub — these are used for EAP-TLS keying material */
    memset(random, 0, *randomLen);
    return noErr;
}

OSStatus SSLInternalServerRandom(SSLContextRef context,
                                  void *random, size_t *randomLen) {
    if (!context || !random || !randomLen || context->magic != SHIM_MAGIC)
        return paramErr;
    memset(random, 0, *randomLen);
    return noErr;
}

OSStatus SSLInternalMasterSecret(SSLContextRef context,
                                  void *secret, size_t *secretLen) {
    if (!context || !secret || !secretLen || context->magic != SHIM_MAGIC)
        return paramErr;
    memset(secret, 0, *secretLen);
    return noErr;
}

/* ================================================================
 * Library initialization
 * ================================================================ */


/* ================================================================
 * Missing-from-shim functions present in the original Security.framework
 * (added 2026-04-18 for full API-level coverage before replacement)
 * ================================================================ */

typedef OSStatus (*SSLInternalMasterSecretFunction)(
    SSLContextRef ctx, const void *arg,
    void *secret, size_t *secretLen);

OSStatus SSLGetEncryptionCertificate(SSLContextRef ctx, CFArrayRef *certRefs) {
    SHIM_LOG("SSLGetEncryptionCertificate(%p)", ctx);
    if (!ctx || !certRefs || ctx->magic != SHIM_MAGIC) return paramErr;
    *certRefs = ctx->clientCertRefs;
    return noErr;
}

OSStatus SSLInternalSetMasterSecretFunction(SSLContextRef ctx,
                                            SSLInternalMasterSecretFunction mFunc,
                                            const void *arg) {
    SHIM_LOG("SSLInternalSetMasterSecretFunction(%p) - stubbed", ctx);
    if (!ctx || ctx->magic != SHIM_MAGIC) return paramErr;
    (void)mFunc; (void)arg;
    return noErr;
}

OSStatus SSLInternalSetSessionTicket(SSLContextRef ctx,
                                     const void *ticket, size_t ticketLength) {
    SHIM_LOG("SSLInternalSetSessionTicket(%p, len=%lu) - stubbed",
             ctx, (unsigned long)ticketLength);
    if (!ctx || ctx->magic != SHIM_MAGIC) return paramErr;
    (void)ticket;
    (void)ticketLength;
    return noErr;
}

OSStatus SSLInternal_PRF(SSLContextRef context,
                         const void *secret, size_t secretLen,
                         const void *label, size_t labelLen,
                         const void *seed, size_t seedLen,
                         void *out, size_t outLen) {
    SHIM_LOG("SSLInternal_PRF(%p, outLen=%lu) - stubbed (zero output)",
             context, (unsigned long)outLen);
    if (!context || !out || context->magic != SHIM_MAGIC) return paramErr;
    (void)secret; (void)secretLen; (void)label; (void)labelLen;
    (void)seed; (void)seedLen;
    memset(out, 0, outLen);
    return noErr;
}

__attribute__((constructor))
static void shim_init(void) {
    /* Pre-resolve Security.framework functions */
    real_SecCertificateCreateFromData =
        (SecCertificateCreateFromData_t)dlsym(RTLD_DEFAULT,
                                               "SecCertificateCreateFromData");
    SHIM_LOG("SecureTransport shim loaded — OpenSSL %s", OpenSSL_version(OPENSSL_VERSION));
    SHIM_LOG("SecCertificateCreateFromData: %p", real_SecCertificateCreateFromData);
}
