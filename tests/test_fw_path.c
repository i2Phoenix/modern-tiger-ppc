/* Links directly against Security.framework — uses DYLD_FRAMEWORK_PATH lookup */
#include <stdio.h>
#include <Security/SecureTransport.h>
int main(void) {
    SSLContextRef ctx = NULL;
    OSStatus s = SSLNewContext(0, &ctx);
    printf("[test] SSLNewContext: %d ctx=%p\n", (int)s, ctx);
    SSLProtocol v;
    s = SSLGetProtocolVersion(ctx, &v);
    printf("[test] SSLGetProtocolVersion: %d v=%d\n", (int)s, (int)v);
    SSLDisposeContext(ctx);
    return 0;
}
