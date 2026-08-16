#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * Translate the small set of modern Darwin linker options emitted by current
 * build systems into the spelling understood by Tiger cctools-622.9~2.
 * Unsupported rpath pairs are dropped deliberately; Tiger dyld has no rpath.
 */
int main(int argc, char **argv) {
    char **out;
    int i;
    int n = 0;

    out = calloc((size_t)argc + 1, sizeof(*out));
    if (out == NULL) {
        perror("calloc");
        return 70;
    }

    out[n++] = "/usr/bin/ld";
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-install_name") == 0) {
            out[n++] = "-dylib_install_name";
        } else if (strcmp(argv[i], "-compatibility_version") == 0) {
            out[n++] = "-dylib_compatibility_version";
        } else if (strcmp(argv[i], "-current_version") == 0) {
            out[n++] = "-dylib_current_version";
        } else if (strcmp(argv[i], "-rpath") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "tiger-ld: -rpath requires an argument\n");
                free(out);
                return 64;
            }
            i++;
        } else {
            out[n++] = argv[i];
        }
    }
    out[n] = NULL;

    execv(out[0], out);
    fprintf(stderr, "tiger-ld: execv(%s): %s\n", out[0], strerror(errno));
    free(out);
    return 71;
}

