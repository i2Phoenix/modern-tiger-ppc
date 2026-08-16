#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr,"usage: %s <dylib> <symlist>\n", argv[0]); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW|RTLD_LOCAL);
    if (!h) { fprintf(stderr,"dlopen: %s\n", dlerror()); return 1; }
    FILE *f = fopen(argv[2], "r");
    if (!f) { perror("fopen"); return 1; }
    char line[256];
    int ok=0, missing=0;
    while (fgets(line, sizeof line, f)) {
        char *nl = line + strlen(line); while (nl>line && (nl[-1]=='\n'||nl[-1]=='\r')) *--nl=0;
        if (!*line) continue;
        const char *sym = line[0]=='_' ? line+1 : line;
        void *p = dlsym(h, sym);
        if (p) { ok++; }
        else   { missing++; printf("MISSING: %s\n", sym); }
    }
    fclose(f); dlclose(h);
    printf("Symbols present: %d, missing: %d\n", ok, missing);
    return missing ? 3 : 0;
}
