#ifndef SETUP_BENCH_H
#define SETUP_BENCH_H

#include <stdio.h>
#include <stddef.h>
#include <signal.h>

typedef struct {
    char disk[32];
    char model[128];
    char tran[16];
    long long size_gb;
    double speed_write;
    double speed_read;
    long long carve_gb;
    int is_root;
    int is_mounted;
} disk_t;

typedef void (*bench_interrupt_fn)(void *ctx);

int safe_execvp(const char *path, char *const argv[]);
int run_quiet(const char *path, char *const argv[]);
int run_sudo_argv(char *const argv[]);
int run_sudo_quiet(char *const argv[]);

int cmd_bench(int argc, char *argv[]);
int run_parallel_bench(disk_t *disks, int ndisks, int warmup,
                       bench_interrupt_fn on_interrupt, void *interrupt_ctx);
int cmp_speed(const void *a, const void *b);

#endif
