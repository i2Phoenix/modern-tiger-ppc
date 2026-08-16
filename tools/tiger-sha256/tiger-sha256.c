#include <CommonCrypto/CommonDigest.h>

#include <stdio.h>

static int hash_file(const char *path)
{
    unsigned char buffer[32768];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX context;
    FILE *input;
    size_t count;
    unsigned int index;

    input = fopen(path, "rb");
    if (input == NULL) {
        perror(path);
        return 1;
    }

    if (!CC_SHA256_Init(&context)) {
        fprintf(stderr, "CC_SHA256_Init failed for %s\n", path);
        fclose(input);
        return 1;
    }

    while ((count = fread(buffer, 1, sizeof(buffer), input)) != 0) {
        if (!CC_SHA256_Update(&context, buffer, (CC_LONG)count)) {
            fprintf(stderr, "CC_SHA256_Update failed for %s\n", path);
            fclose(input);
            return 1;
        }
    }
    if (ferror(input)) {
        perror(path);
        fclose(input);
        return 1;
    }
    fclose(input);

    if (!CC_SHA256_Final(digest, &context)) {
        fprintf(stderr, "CC_SHA256_Final failed for %s\n", path);
        return 1;
    }

    for (index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index)
        printf("%02x", (unsigned int)digest[index]);
    printf("  %s\n", path);
    return 0;
}

int main(int argc, char **argv)
{
    int argument;
    int failed = 0;

    if (argc < 2) {
        fprintf(stderr, "usage: %s <file> [file ...]\n", argv[0]);
        return 2;
    }

    for (argument = 1; argument < argc; ++argument) {
        if (hash_file(argv[argument]) != 0)
            failed = 1;
    }
    return failed;
}
