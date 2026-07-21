#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/loop.h>

#include "../src/tiered_sched.h"

static int tests_run = 0;
static int tests_passed = 0;

static void check(int cond, const char *name) {
    tests_run++;
    if (cond) {
        tests_passed++;
        printf("  PASS  %s\n", name);
    } else {
        printf("  FAIL  %s\n", name);
    }
}

static void print_summary(void) {
    printf("\n=== Results: %d/%d passed ===\n", tests_passed, tests_run);
}

static void test_init_destroy_cycle(const TV_METADATA *meta) {
    printf("\n[TEST] tv_sched_init / tv_sched_destroy cycle\n");
    TV_SCHED *sched = tv_sched_init(meta);
    check(sched != NULL, "init succeeded");
    if (sched) {
        check(sched->stripe_size == meta->segments[0].stripe_size,
              "stripe_size matches");
        check((int)sched->ndisks == (int)meta->disk_count, "ndisks matches");
        check(sched->inflight == 0, "inflight starts at 0");
        tv_sched_destroy(sched);
        check(1, "destroy completed without crash");
    }
}

static void test_write_read_verify(const TV_METADATA *meta, const char *devpath) {
    (void)devpath;
    printf("\n[TEST] write/read/verify data integrity\n");
    TV_SCHED *sched = tv_sched_init(meta);
    check(sched != NULL, "init succeeded");
    if (!sched) return;

    uint64_t len = 4096;
    uint8_t *wbuf, *rbuf;
    check(posix_memalign((void **)&wbuf, 4096, len) == 0, "write buf alloc");
    check(posix_memalign((void **)&rbuf, 4096, len) == 0, "read buf alloc");
    if (!wbuf || !rbuf) {
        free(wbuf); free(rbuf);
        tv_sched_destroy(sched);
        return;
    }

    for (uint64_t i = 0; i < len; i++) wbuf[i] = (uint8_t)(i & 0xFF);
    memset(rbuf, 0, len);

    int ret = tv_write(sched, wbuf, 0, len);
    check(ret == 0, "write returned 0");
    if (ret != 0) { free(wbuf); free(rbuf); tv_sched_destroy(sched); return; }

    ret = tv_flush(sched);
    check(ret == 0, "flush returned 0");
    if (ret != 0) { free(wbuf); free(rbuf); tv_sched_destroy(sched); return; }

    ret = tv_read(sched, rbuf, 0, len);
    check(ret == 0, "read returned 0");

    check(memcmp(wbuf, rbuf, len) == 0, "readback data matches written data");

    free(wbuf);
    free(rbuf);
    tv_sched_destroy(sched);
}

static TV_METADATA make_2disk_meta(void) {
    TV_METADATA meta;
    memset(&meta, 0, sizeof(meta));
    meta.version = 1;
    meta.chunk_size = TV_CHUNK_SIZE;
    meta.segment_count = 1;
    meta.disk_count = 2;
    strcpy(meta.disk_names[0], "test_disk_0");
    strcpy(meta.disk_names[1], "test_disk_1");
    meta.segments[0].logical_begin = 0;
    meta.segments[0].logical_end = 4ULL * 1024 * 1024;
    meta.segments[0].disk_count = 2;
    meta.segments[0].weight[0] = 2;
    meta.segments[0].weight[1] = 1;
    meta.segments[0].disk_index[0] = 0;
    meta.segments[0].disk_index[1] = 1;
    meta.segments[0].stripe_size = 3 * TV_CHUNK_SIZE;
    return meta;
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    TV_METADATA meta = make_2disk_meta();
    test_init_destroy_cycle(&meta);
    test_write_read_verify(&meta, NULL);

    print_summary();
    return (tests_passed == tests_run) ? 0 : 1;
}
