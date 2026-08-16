#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <Security/SecureTransport.h>

static OSStatus socket_read(SSLConnectionRef connection, void *data,
    size_t *length)
{
    int fd = (int)(long)connection;
    ssize_t received;

    do {
        received = read(fd, data, *length);
    } while (received < 0 && errno == EINTR);

    if (received < 0) {
        *length = 0;
        return (errno == EAGAIN || errno == EWOULDBLOCK) ? -9803 : -1;
    }
    if (received == 0) {
        *length = 0;
        return -9805;
    }

    *length = (size_t)received;
    return 0;
}

static OSStatus socket_write(SSLConnectionRef connection, const void *data,
    size_t *length)
{
    int fd = (int)(long)connection;
    ssize_t sent;

    do {
        sent = write(fd, data, *length);
    } while (sent < 0 && errno == EINTR);

    if (sent < 0) {
        *length = 0;
        return (errno == EAGAIN || errno == EWOULDBLOCK) ? -9803 : -1;
    }

    *length = (size_t)sent;
    return 0;
}

int main(int argc, char **argv)
{
    const char *host = argc > 1 ? argv[1] : "example.com";
    struct addrinfo hints;
    struct addrinfo *address = NULL;
    SSLContextRef context = NULL;
    OSStatus status;
    int fd = -1;
    int tries = 0;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    if (getaddrinfo(host, "443", &hints, &address) != 0) {
        fprintf(stderr, "getaddrinfo failed for %s\n", host);
        return 2;
    }

    fd = socket(address->ai_family, address->ai_socktype,
        address->ai_protocol);
    if (fd < 0 || connect(fd, address->ai_addr, address->ai_addrlen) != 0) {
        perror("connect");
        freeaddrinfo(address);
        if (fd >= 0)
            close(fd);
        return 3;
    }
    freeaddrinfo(address);

    status = SSLNewContext(0, &context);
    if (status == 0)
        status = SSLSetIOFuncs(context, socket_read, socket_write);
    if (status == 0)
        status = SSLSetConnection(context, (SSLConnectionRef)(long)fd);
    if (status == 0)
        status = SSLSetPeerDomainName(context, host, strlen(host));

    while (status == 0) {
        status = SSLHandshake(context);
        if (status != -9803)
            break;
        if (++tries > 200)
            break;
        status = 0;
    }

    printf("SSLHandshake: %d\n", (int)status);
    if (status == 0) {
        char request[512];
        char response[1024];
        char *newline;
        size_t sent = 0;
        size_t received = 0;
        int request_length;

        request_length = snprintf(request, sizeof(request),
            "GET / HTTP/1.0\r\nHost: %s\r\n\r\n", host);
        status = SSLWrite(context, request, (size_t)request_length, &sent);
        if (status == 0)
            status = SSLRead(context, response, sizeof(response) - 1,
                &received);

        if (received > 0) {
            response[received] = '\0';
            newline = strchr(response, '\n');
            if (newline != NULL)
                *newline = '\0';
            printf("RESP: %s\n", response);
        }
    }

    if (context != NULL) {
        SSLClose(context);
        SSLDisposeContext(context);
    }
    close(fd);
    return status == 0 ? 0 : 10;
}
