/* SPDX-License-Identifier: MIT */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#include <fft_dma_uapi.h>

#define FFT_DMA_BYTES 4096u
#define MAX_ITERATIONS 1000000ul

static uint64_t monotonic_ns(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + ts.tv_nsec;
}

static int compare_u64(const void *left, const void *right)
{
    uint64_t a = *(const uint64_t *)left;
    uint64_t b = *(const uint64_t *)right;

    return (a > b) - (a < b);
}

static int parse_iterations(int argc, char *argv[], unsigned long *iterations)
{
    char *end;
    unsigned long value;

    if (argc != 3 || strcmp(argv[1], "--iterations"))
        return -1;
    errno = 0;
    value = strtoul(argv[2], &end, 10);
    if (errno || *end || !value || value > MAX_ITERATIONS)
        return -1;
    *iterations = value;
    return 0;
}

int main(int argc, char *argv[])
{
    uint64_t *latencies;
    uint64_t start_ns;
    uint64_t elapsed_ns;
    uint64_t total_latency_ns = 0;
    uint64_t transferred = 0;
    unsigned long iterations = 1000;
    unsigned long completed = 0;
    unsigned long failed = 0;
    unsigned long timeouts = 0;
    unsigned long dma_errors = 0;
    unsigned long validation_errors = 0;
    unsigned long i;
    int fd;

    if (argc != 1 && parse_iterations(argc, argv, &iterations)) {
        fprintf(stderr, "Usage: %s [--iterations <1..1000000>]\n", argv[0]);
        return 64;
    }

    latencies = calloc(iterations, sizeof(*latencies));
    if (!latencies) {
        perror("calloc latency samples");
        return 70;
    }

    fd = open("/dev/fft_dma0", O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "open /dev/fft_dma0 failed: %s\n", strerror(errno));
        free(latencies);
        return 10;
    }

    start_ns = monotonic_ns();
    if (!start_ns) {
        perror("clock_gettime");
        close(fd);
        free(latencies);
        return 70;
    }

    for (i = 0; i < iterations; ++i) {
        struct fft_dma_result result = { };
        uint64_t begin_ns = monotonic_ns();
        uint64_t end_ns;

        if (!begin_ns || ioctl(fd, FFT_DMA_IOCTL_RUN, &result) < 0) {
            ++failed;
            if (errno == ETIMEDOUT)
                ++timeouts;
            else if (errno == EIO)
                ++dma_errors;
            else
                ++validation_errors;
            continue;
        }
        end_ns = monotonic_ns();
        if (!end_ns || result.dma_status != FFT_DMA_STATUS_COMPLETE ||
            result.bytes_received != FFT_DMA_BYTES || result.peak_bin != 1u) {
            ++failed;
            ++validation_errors;
            continue;
        }

        latencies[completed] = end_ns - begin_ns;
        total_latency_ns += latencies[completed];
        ++completed;
        transferred += result.bytes_received;
    }
    elapsed_ns = monotonic_ns() - start_ns;
    close(fd);

    if (completed) {
        size_t p50 = (completed - 1) / 2;
        size_t p95 = (completed * 95 + 99) / 100 - 1;

        qsort(latencies, completed, sizeof(*latencies), compare_u64);
        printf("DMAENGINE_BENCH iterations=%lu ok=%lu failed=%lu timeouts=%lu "
               "dma_errors=%lu validation_errors=%lu bytes=%" PRIu64 " "
               "elapsed_us=%" PRIu64 " min_us=%.3f avg_us=%.3f p50_us=%.3f "
               "p95_us=%.3f max_us=%.3f throughput_mib_s=%.3f\n",
               iterations, completed, failed, timeouts, dma_errors,
               validation_errors, transferred, elapsed_ns / 1000,
               (double)latencies[0] / 1000.0,
               (double)total_latency_ns / completed / 1000.0,
               (double)latencies[p50] / 1000.0,
               (double)latencies[p95] / 1000.0,
               (double)latencies[completed - 1] / 1000.0,
               elapsed_ns ? (double)transferred * 1000000000.0 /
                            elapsed_ns / (1024.0 * 1024.0) : 0.0);
    } else {
        printf("DMAENGINE_BENCH iterations=%lu ok=0 failed=%lu timeouts=%lu "
               "dma_errors=%lu validation_errors=%lu bytes=0 elapsed_us=%" PRIu64
               " min_us=0.000 avg_us=0.000 p50_us=0.000 p95_us=0.000 "
               "max_us=0.000 throughput_mib_s=0.000\n",
               iterations, failed, timeouts, dma_errors, validation_errors,
               elapsed_ns / 1000);
    }

    free(latencies);
    return failed ? 2 : 0;
}
