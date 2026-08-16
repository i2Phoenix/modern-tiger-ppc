#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>

typedef int OSStatus;
typedef struct SSLContext *SSLContextRef;
typedef const void *SSLConnectionRef;
typedef unsigned char Boolean;

typedef OSStatus (*SSLReadFunc)(SSLConnectionRef, void*, size_t*);
typedef OSStatus (*SSLWriteFunc)(SSLConnectionRef, const void*, size_t*);

#define errSSLWouldBlock -9803
#define errSSLClosedGraceful -9805

static OSStatus my_read(SSLConnectionRef c, void *data, size_t *len) {
    int fd = (int)(long)c;
    size_t want = *len, got = 0;
    while (got < want) {
        ssize_t n = read(fd, (char*)data + got, want - got);
        if (n > 0) { got += n; continue; }
        if (n == 0) { *len = got; return errSSLClosedGraceful; }
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            *len = got;
            return errSSLWouldBlock;
        }
        *len = got;
        return -1;
    }
    *len = got;
    return 0;
}

static OSStatus my_write(SSLConnectionRef c, const void *data, size_t *len) {
    int fd = (int)(long)c;
    size_t want = *len, sent = 0;
    while (sent < want) {
        ssize_t n = write(fd, (const char*)data + sent, want - sent);
        if (n > 0) { sent += n; continue; }
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
            *len = sent;
            return errSSLWouldBlock;
        }
        *len = sent;
        return -1;
    }
    *len = sent;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <dylib> [host] [port]\n", argv[0]);
        return 2;
    }
    const char *dylib = argv[1];
    const char *host  = argc > 2 ? argv[2] : "apple.com";
    const char *port  = argc > 3 ? argv[3] : "443";

    printf("=== Loading %s ===\n", dylib);
    void *h = dlopen(dylib, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }

    OSStatus (*SSLNewContext)(Boolean, SSLContextRef*)                      = dlsym(h,"SSLNewContext");
    OSStatus (*SSLDisposeContext)(SSLContextRef)                            = dlsym(h,"SSLDisposeContext");
    OSStatus (*SSLSetIOFuncs)(SSLContextRef, SSLReadFunc, SSLWriteFunc)     = dlsym(h,"SSLSetIOFuncs");
    OSStatus (*SSLSetConnection)(SSLContextRef, SSLConnectionRef)           = dlsym(h,"SSLSetConnection");
    OSStatus (*SSLSetPeerDomainName)(SSLContextRef, const char*, size_t)    = dlsym(h,"SSLSetPeerDomainName");
    OSStatus (*SSLHandshake)(SSLContextRef)                                 = dlsym(h,"SSLHandshake");
    OSStatus (*SSLRead)(SSLContextRef, void*, size_t, size_t*)              = dlsym(h,"SSLRead");
    OSStatus (*SSLWrite)(SSLContextRef, const void*, size_t, size_t*)       = dlsym(h,"SSLWrite");
    OSStatus (*SSLClose)(SSLContextRef)                                     = dlsym(h,"SSLClose");
    OSStatus (*SSLGetNegotiatedProtocolVersion)(SSLContextRef, int*)        = dlsym(h,"SSLGetNegotiatedProtocolVersion");

    if (!SSLNewContext || !SSLHandshake) { fprintf(stderr,"missing symbols\n"); return 2; }

    /* TCP connect */
    struct addrinfo hints, *res;
    memset(&hints,0,sizeof hints); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    int g = getaddrinfo(host, port, &hints, &res);
    if (g) { fprintf(stderr,"getaddrinfo: %s\n", gai_strerror(g)); return 3; }
    int fd = socket(res->ai_family, res->ai_socktype, 0);
    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0) { perror("connect"); return 4; }
    printf("TCP connected to %s:%s (fd=%d)\n", host, port, fd);
    freeaddrinfo(res);

    /* TLS */
    SSLContextRef ctx = NULL;
    OSStatus s = SSLNewContext(0, &ctx);
    printf("SSLNewContext: %d, ctx=%p\n", (int)s, ctx);

    s = SSLSetIOFuncs(ctx, my_read, my_write);
    printf("SSLSetIOFuncs: %d\n", (int)s);

    s = SSLSetConnection(ctx, (SSLConnectionRef)(long)fd);
    printf("SSLSetConnection: %d\n", (int)s);

    s = SSLSetPeerDomainName(ctx, host, strlen(host));
    printf("SSLSetPeerDomainName(%s): %d\n", host, (int)s);

    int tries = 0;
    do {
        s = SSLHandshake(ctx);
        if (s == errSSLWouldBlock) { tries++; if (tries > 200) { fprintf(stderr,"too many wouldblocks\n"); break; } continue; }
        break;
    } while (1);
    printf("SSLHandshake: %d (tries=%d)\n", (int)s, tries);

    if (s == 0) {
        int ver = -1;
        if (SSLGetNegotiatedProtocolVersion) {
            SSLGetNegotiatedProtocolVersion(ctx, &ver);
            printf("Negotiated protocol version (enum): %d\n", ver);
        }

        /* send HTTP request */
        char req[512];
        int rl = snprintf(req, sizeof req,
            "GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: tiger-test\r\nConnection: close\r\n\r\n", host);
        size_t sent = 0;
        s = SSLWrite(ctx, req, rl, &sent);
        printf("SSLWrite: %d, sent=%zu/%d\n", (int)s, sent, rl);

        /* read response */
        char buf[4096];
        size_t got = 0;
        s = SSLRead(ctx, buf, sizeof buf - 1, &got);
        buf[got < sizeof buf ? got : sizeof buf - 1] = 0;
        printf("SSLRead: %d, got=%zu\n", (int)s, got);
        if (got > 0) {
            /* print just first status line */
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            printf("RESPONSE: %s\n", buf);
        }

        SSLClose(ctx);
    }

    SSLDisposeContext(ctx);
    close(fd);
    dlclose(h);
    printf("=== done ===\n");
    return (s == 0 ? 0 : 10);
}
