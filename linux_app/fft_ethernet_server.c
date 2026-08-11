/* SPDX-License-Identifier: MIT */
/* Direct Ethernet control endpoint for the FFT DMA kernel driver. */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#include <fft_dma_uapi.h>

#define SERVER_PORT 5000
#define LINE_SIZE 64

static void run_fft(int client)
{
    struct fft_dma_result result = { };
    char response[192];
    int fd = open("/dev/fft_dma0", O_RDWR);

    if (fd < 0) {
        snprintf(response, sizeof(response), "ERROR open errno=%d\n", errno);
    } else if (ioctl(fd, FFT_DMA_IOCTL_RUN, &result) < 0) {
        snprintf(response, sizeof(response), "ERROR ioctl errno=%d\n", errno);
        close(fd);
    } else {
        close(fd);
        snprintf(response, sizeof(response),
                 "RESULT status=0x%08x bytes=%u peak=%u re=%d im=%d mag2=%llu\n",
                 result.dma_status, result.bytes_received, result.peak_bin,
                 result.peak_real, result.peak_imag,
                 (unsigned long long)result.peak_magnitude_squared);
    }
    (void)send(client, response, strlen(response), MSG_NOSIGNAL);
}

int main(void)
{
    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(SERVER_PORT),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    int server = socket(AF_INET, SOCK_STREAM, 0);
    int reuse = 1;

    if (server < 0)
        return 1;
    if (setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) ||
        bind(server, (struct sockaddr *)&address, sizeof(address)) ||
        listen(server, 2)) {
        close(server);
        return 2;
    }

    for (;;) {
        char line[LINE_SIZE] = { };
        int client = accept(server, NULL, NULL);
        ssize_t received;

        if (client < 0)
            continue;
        received = recv(client, line, sizeof(line) - 1, 0);
        if (received > 0 && !strcmp(line, "PING\n"))
            (void)send(client, "PONG\n", 5, MSG_NOSIGNAL);
        else if (received > 0 && !strcmp(line, "RUN\n"))
            run_fft(client);
        else
            (void)send(client, "ERROR command\n", 14, MSG_NOSIGNAL);
        close(client);
    }
}
