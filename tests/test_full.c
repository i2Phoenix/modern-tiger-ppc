#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

#include <CoreServices/CoreServices.h>
typedef struct SSLContext *SSLContextRef;
typedef void* SecCertificateRef;
typedef struct { unsigned int Length; unsigned char *Data; } CSSM_DATA;

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr,"usage: %s <dylib>\n", argv[0]); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW|RTLD_LOCAL);
    if (!h) { fprintf(stderr,"dlopen: %s\n", dlerror()); return 1; }

    printf("\n=== 1. Non-SSL forwarding (AuthorizationCreate) ===\n");
    typedef void* AuthRef;
    OSStatus (*AuthorizationCreate)(void*,void*,unsigned,AuthRef*) = dlsym(h,"AuthorizationCreate");
    OSStatus (*AuthorizationFree)(AuthRef,unsigned) = dlsym(h,"AuthorizationFree");
    AuthRef ar=NULL;
    OSStatus s = AuthorizationCreate(NULL,NULL,0,&ar);
    printf("AuthorizationCreate: %d auth=%p %s\n", (int)s, ar, s==0?"OK":"FAIL");
    if (ar) AuthorizationFree(ar, 0);

    printf("\n=== 2. Keychain forwarding (SecKeychainCopyDefault) ===\n");
    OSStatus (*SecKeychainCopyDefault)(void**) = dlsym(h,"SecKeychainCopyDefault");
    void *kc = NULL;
    s = SecKeychainCopyDefault(&kc);
    printf("SecKeychainCopyDefault: %d kc=%p %s\n", (int)s, kc, s==0?"OK":"FAIL");
    if (kc) CFRelease(kc);

    printf("\n=== 3. 4 previously-missing SSL functions ===\n");
    OSStatus (*SSLNewContext)(unsigned char, SSLContextRef*) = dlsym(h,"SSLNewContext");
    OSStatus (*SSLDisposeContext)(SSLContextRef) = dlsym(h,"SSLDisposeContext");
    OSStatus (*SSLGetEncryptionCertificate)(SSLContextRef, CFArrayRef*) = dlsym(h,"SSLGetEncryptionCertificate");
    OSStatus (*SSLInternalSetMasterSecretFunction)(SSLContextRef, void*, const void*) = dlsym(h,"SSLInternalSetMasterSecretFunction");
    OSStatus (*SSLInternalSetSessionTicket)(SSLContextRef, const void*, size_t) = dlsym(h,"SSLInternalSetSessionTicket");
    OSStatus (*SSLInternal_PRF)(SSLContextRef, const void*, size_t, const void*, size_t, const void*, size_t, void*, size_t) = dlsym(h,"SSLInternal_PRF");

    printf("sym SSLGetEncryptionCertificate      = %p\n", (void*)SSLGetEncryptionCertificate);
    printf("sym SSLInternalSetMasterSecretFunction = %p\n", (void*)SSLInternalSetMasterSecretFunction);
    printf("sym SSLInternalSetSessionTicket      = %p\n", (void*)SSLInternalSetSessionTicket);
    printf("sym SSLInternal_PRF                  = %p\n", (void*)SSLInternal_PRF);

    SSLContextRef ctx=NULL;
    SSLNewContext(0, &ctx);
    CFArrayRef ec=NULL;
    s = SSLGetEncryptionCertificate(ctx, &ec);
    printf("SSLGetEncryptionCertificate: %d ec=%p %s\n", (int)s, ec, s==0?"OK":"FAIL");
    s = SSLInternalSetMasterSecretFunction(ctx, NULL, NULL);
    printf("SSLInternalSetMasterSecretFunction: %d %s\n", (int)s, s==0?"OK":"FAIL");
    unsigned char tkt[16] = {1,2,3,4};
    s = SSLInternalSetSessionTicket(ctx, tkt, sizeof tkt);
    printf("SSLInternalSetSessionTicket: %d %s\n", (int)s, s==0?"OK":"FAIL");
    unsigned char out[32];
    s = SSLInternal_PRF(ctx, "secret",6, "label",5, "seed",4, out, sizeof out);
    int is_zero=1; for(unsigned int i=0;i<sizeof out;i++) if(out[i]) {is_zero=0;break;}
    printf("SSLInternal_PRF: %d zero-output=%d %s\n", (int)s, is_zero, (s==0&&is_zero)?"OK":"FAIL");
    SSLDisposeContext(ctx);

    printf("\n=== 4. SSLSetTrustedRoots with empty array (should not crash) ===\n");
    SSLNewContext(0, &ctx);
    OSStatus (*SSLSetTrustedRoots)(SSLContextRef, CFArrayRef, unsigned char) = dlsym(h,"SSLSetTrustedRoots");
    CFArrayRef empty = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    s = SSLSetTrustedRoots(ctx, empty, 1 /*replace*/);
    printf("SSLSetTrustedRoots(empty,replace=1): %d %s\n", (int)s, s==0?"OK":"FAIL");
    CFRelease(empty);
    SSLDisposeContext(ctx);

    dlclose(h);
    printf("\n=== done ===\n");
    return 0;
}
