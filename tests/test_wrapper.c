#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

typedef struct SSLContext *SSLContextRef;
typedef int OSStatus;

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <dylib-path>\n", argv[0]); return 2; }
    const char *path = argv[1];

    printf("=== Loading %s ===\n", path);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    printf("dlopen OK, handle=%p\n", h);

    /* --- SSL path: should hit our shim --- */
    OSStatus (*SSLNewContext)(int isServer, SSLContextRef *ctx) = dlsym(h, "SSLNewContext");
    OSStatus (*SSLDisposeContext)(SSLContextRef ctx) = dlsym(h, "SSLDisposeContext");
    OSStatus (*SSLSetProtocolVersionEnabled)(SSLContextRef, int, int) = dlsym(h, "SSLSetProtocolVersionEnabled");
    printf("SSLNewContext sym: %p\n", (void*)SSLNewContext);
    printf("SSLDisposeContext sym: %p\n", (void*)SSLDisposeContext);

    SSLContextRef ctx = NULL;
    OSStatus s = SSLNewContext(0, &ctx);
    printf("SSLNewContext returned %d, ctx=%p\n", (int)s, (void*)ctx);
    if (ctx) {
        s = SSLSetProtocolVersionEnabled(ctx, 4 /*kTLSProtocol12*/, 1);
        printf("SSLSetProtocolVersionEnabled returned %d\n", (int)s);
        s = SSLDisposeContext(ctx);
        printf("SSLDisposeContext returned %d\n", (int)s);
    }

    /* --- non-SSL path: should forward to Security.orig --- */
    typedef void *AuthorizationRef;
    OSStatus (*AuthorizationCreate)(void *rights, void *env, unsigned flags, AuthorizationRef *auth) = dlsym(h, "AuthorizationCreate");
    OSStatus (*AuthorizationFree)(AuthorizationRef auth, unsigned flags) = dlsym(h, "AuthorizationFree");
    printf("AuthorizationCreate sym: %p\n", (void*)AuthorizationCreate);

    AuthorizationRef auth = NULL;
    if (AuthorizationCreate) {
        s = AuthorizationCreate(NULL, NULL, 0 /*kAuthorizationFlagDefaults*/, &auth);
        printf("AuthorizationCreate returned %d, auth=%p\n", (int)s, auth);
        if (auth && AuthorizationFree) {
            s = AuthorizationFree(auth, 0);
            printf("AuthorizationFree returned %d\n", (int)s);
        }
    } else {
        printf("AuthorizationCreate NOT FOUND in wrapper\n");
    }

    /* --- keychain symbol sanity --- */
    void *SecKeychainCopyDefault = dlsym(h, "SecKeychainCopyDefault");
    printf("SecKeychainCopyDefault sym: %p\n", SecKeychainCopyDefault);

    dlclose(h);
    printf("=== done ===\n");
    return 0;
}
