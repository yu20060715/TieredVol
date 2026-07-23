#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "tiered_sched.h"
#include "tiered_io_uring.h"

volatile sig_atomic_t g_shutdown_requested = 0;

/* Forward declarations */
static int flush_submit_io(TV_SCHED *sched, uint64_t logical, uint8_t *data, uint64_t data_len, int buf_idx);

TV_SCHED *tv_sched_init(TV_DISK *disks, int ndisks, TV_METADATA *meta) {
    if (!disks || ndisks <= 0 || !meta) return NULL;
    if (meta->segment_count == 0) return NULL;

    TV_SCHED *sched = calloc(1, sizeof(TV_SCHED));
    if (!sched) return NULL;

    sched->disks = disks;
    sched->ndisks = ndisks;
    sched->meta = meta;
    sched->stripe_size = meta->segments[0].stripe_size;

    if (tv_uring_init(&sched->ring, TV_URING_QUEUE_DEPTH) < 0) {
        free(sched);
        return NULL;
    }

    for (int i = 0; i < TV_BUF_COUNT; i++) {
        sched->sbuf[i].data = aligned_alloc(TV_ALLOC_ALIGNMENT, (size_t)sched->stripe_size);
        if (!sched->sbuf[i].data) {
            for (int j = 0; j < i; j++) free(sched->sbuf[j].data);
            tv_uring_destroy(&sched->ring);
            free(sched);
            return NULL;
        }
        sched->sbuf[i].in_flight = 0;
        sched->sbuf[i].cqes_pending = 0;
    }

    {
        struct iovec iovecs[TV_BUF_COUNT];
        for (int i = 0; i < TV_BUF_COUNT; i++) {
            iovecs[i].iov_base = sched->sbuf[i].data;
            iovecs[i].iov_len  = sched->stripe_size;
        }
        if (tv_uring_register_buffers(&sched->ring, iovecs, TV_BUF_COUNT) < 0) {
            fprintf(stderr, "tv_sched_init: register_buffers failed, falling back to unregistered\n");
            sched->buffers_registered = 0;
        } else {
            sched->buffers_registered = 1;
        }
    }

    sched->sbuf_head = 0;
    sched->sbuf_used = 0;
    sched->sbuf_logical = 0;
    sched->inflight = 0;

    return sched;
}

/* Reap completed CQEs using user_data to identify the correct buffer.
 * Returns 0 on success, TV_ERR if any CQE reported an I/O error. */
static int reap_completed(TV_SCHED *sched) {
    int errors = 0;
    struct io_uring_cqe *cqe;
    while (sched->inflight > 0) {
        int ret = io_uring_peek_cqe(&sched->ring, &cqe);
        if (ret < 0 || !cqe) break;
        if (cqe->res < 0) {
            fprintf(stderr, "tv_sched: I/O error res=%d\n", cqe->res);
            errors++;
        }
        int buf_idx = (int)(intptr_t)io_uring_cqe_get_data(cqe);
        io_uring_cqe_seen(&sched->ring, cqe);
        if (buf_idx >= 0 && buf_idx < TV_BUF_COUNT && sched->sbuf[buf_idx].in_flight) {
            sched->sbuf[buf_idx].cqes_pending--;
            if (sched->sbuf[buf_idx].cqes_pending <= 0) {
                sched->sbuf[buf_idx].in_flight = 0;
                sched->inflight--;
            }
        }
    }
    return errors > 0 ? TV_ERR : 0;
}

int tv_write(TV_SCHED *sched, const void *buf, uint64_t len) {
    if (!sched || !buf || len == 0) return TV_ERR;

    const uint8_t *src = (const uint8_t *)buf;
    uint64_t pos = 0;

    while (pos < len) {
        if (g_shutdown_requested) return TV_ERR;
        uint64_t space = sched->stripe_size - sched->sbuf_used;

        if (space == 0) {
            int head = sched->sbuf_head;
            TV_STRIPE_BUF *cur = &sched->sbuf[head];
            int nsub = flush_submit_io(sched, sched->sbuf_logical, cur->data, sched->sbuf_used, head);
            if (nsub < 0) return TV_ERR;
            if (nsub == 0) {
                /* No I/O submitted (empty segment), skip this buffer */
                sched->sbuf_head = (sched->sbuf_head + 1) % TV_BUF_COUNT;
                sched->sbuf_logical += sched->stripe_size;
                sched->sbuf_used = 0;
                space = sched->stripe_size;
                continue;
            }
            cur->in_flight = 1;
            cur->cqes_pending = nsub;
            sched->inflight++;

            sched->sbuf_head = (sched->sbuf_head + 1) % TV_BUF_COUNT;
            sched->sbuf_logical += sched->stripe_size;
            sched->sbuf_used = 0;
            space = sched->stripe_size;

            /* All buffers occupied — wait for one to fully complete */
            if (sched->inflight >= TV_BUF_COUNT) {
                while (sched->inflight >= TV_BUF_COUNT) {
                    if (g_shutdown_requested) return TV_ERR;
                    if (reap_completed(sched) < 0) return TV_ERR;
                    if (sched->inflight >= TV_BUF_COUNT) {
                        struct io_uring_cqe *cqe = NULL;
                        struct __kernel_timespec ts = { .tv_sec = TV_CQE_TIMEOUT_SEC, .tv_nsec = 0 };
                        int r = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &ts);
                        if (r == -ETIME) {
                            int inflight_before = sched->inflight;
                            reap_completed(sched);
                            if (sched->inflight == 0) break;
                            if (sched->inflight == inflight_before) {
                                fprintf(stderr, "tv_write: %d CQEs slow, retrying (%ds)\n",
                                        sched->inflight, TV_CQE_RETRY_SEC);
                                ts.tv_sec = TV_CQE_RETRY_SEC;
                                int r2 = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &ts);
                                if (r2 == -ETIME) {
                                    reap_completed(sched);
                                    if (sched->inflight == 0) break;
                                    if (sched->inflight == inflight_before) {
                                        fprintf(stderr, "tv_write: %d CQEs stuck, draining...\n",
                                                sched->inflight);
                                        /* Wait up to 30s for kernel to finish DMA */
                                        int drain_wait = 0;
                                        while (sched->inflight > 0 && drain_wait < 30) {
                                            struct __kernel_timespec wait_ts = { .tv_sec = 1, .tv_nsec = 0 };
                                            int r3 = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &wait_ts);
                                            if (r3 == 0 && cqe) {
                                                int bi = (int)(intptr_t)io_uring_cqe_get_data(cqe);
                                                io_uring_cqe_seen(&sched->ring, cqe);
                                                if (bi >= 0 && bi < TV_BUF_COUNT && sched->sbuf[bi].in_flight) {
                                                    sched->sbuf[bi].cqes_pending--;
                                                    if (sched->sbuf[bi].cqes_pending <= 0) {
                                                        sched->sbuf[bi].in_flight = 0;
                                                        sched->inflight--;
                                                    }
                                                }
                                                drain_wait = 0;
                                            } else {
                                                drain_wait++;
                                            }
                                        }
                                        if (sched->inflight > 0)
                                            fprintf(stderr, "tv_write: WARNING: %d CQEs still in flight after drain\n",
                                                    sched->inflight);
                                        /* Now safe to reset */
                                        for (int i = 0; i < TV_BUF_COUNT; i++) {
                                            sched->sbuf[i].in_flight = 0;
                                            sched->sbuf[i].cqes_pending = 0;
                                        }
                                        sched->inflight = 0;
                                        break;
                                    }
                                    continue;
                                }
                                if (r2 == -EINTR) {
                                    if (g_shutdown_requested) return TV_ERR;
                                    continue;
                                }
                                if (r2 < 0) {
                                    fprintf(stderr, "tv_write: wait_cqe failed: %s\n", strerror(-r2));
                                    return TV_ERR;
                                }
                                goto w_process;
                            }
                            continue;
                        }
                        if (r == -EINTR) {
                            if (g_shutdown_requested) return TV_ERR;
                            continue;
                        }
                        if (r < 0) {
                            fprintf(stderr, "tv_write: wait_cqe failed: %s\n", strerror(-r));
                            return TV_ERR;
                        }
w_process:
                        {
                        int buf_idx = (int)(intptr_t)io_uring_cqe_get_data(cqe);
                        if (cqe->res < 0)
                            fprintf(stderr, "tv_write: I/O error res=%d\n", cqe->res);
                        io_uring_cqe_seen(&sched->ring, cqe);
                        if (buf_idx >= 0 && buf_idx < TV_BUF_COUNT && sched->sbuf[buf_idx].in_flight) {
                            sched->sbuf[buf_idx].cqes_pending--;
                            if (sched->sbuf[buf_idx].cqes_pending <= 0) {
                                sched->sbuf[buf_idx].in_flight = 0;
                                sched->inflight--;
                            }
                        }
                        }
                    }
                }
            }
        }

        uint64_t chunk = (len - pos < space) ? (len - pos) : space;
        TV_STRIPE_BUF *cur = &sched->sbuf[sched->sbuf_head];
        memcpy(cur->data + sched->sbuf_used, src + pos, (size_t)chunk);
        sched->sbuf_used += chunk;
        pos += chunk;
    }

    return 0;
}

static int flush_submit_io(TV_SCHED *sched, uint64_t logical, uint8_t *data, uint64_t data_len, int buf_idx) {
    TV_SEGMENT *seg = NULL;
    for (int i = 0; i < (int)sched->meta->segment_count; i++) {
        if (logical >= sched->meta->segments[i].logical_begin &&
            logical <  sched->meta->segments[i].logical_end) {
            seg = &sched->meta->segments[i];
            break;
        }
    }
    if (!seg) {
        fprintf(stderr, "tv_flush: logical offset %lu not in any segment\n",
                (unsigned long)logical);
        return TV_ERR;
    }
    if (seg->disk_count == 0) {
        fprintf(stderr, "tv_flush: no disks in segment, skipping\n");
        return 0;
    }

    uint64_t stripe_no = (logical - seg->logical_begin) / seg->stripe_size;
    uint64_t buf_pos = 0;
    uint64_t remaining = data_len;
    int submitted = 0;
    void *ud = (void *)(intptr_t)buf_idx;

    for (int i = 0; i < (int)seg->disk_count && remaining > 0; i++) {
        uint64_t disk_bytes = (uint64_t)seg->weight[i] * TV_CHUNK_SIZE;
        if (disk_bytes == 0) continue;
        if (seg->disk_index[i] >= (uint32_t)sched->ndisks) {
            fprintf(stderr, "tv_flush: invalid disk index %u\n", seg->disk_index[i]);
            return TV_ERR;
        }
        uint64_t write_bytes = (disk_bytes < remaining) ? disk_bytes : remaining;
        uint64_t disk_off = stripe_no * disk_bytes;
        int fd = sched->disks[seg->disk_index[i]].fd;

        if (sched->buffers_registered) {
            if (tv_uring_write_fixed(&sched->ring, fd, data + buf_pos,
                               (size_t)write_bytes, (off_t)disk_off, buf_idx, ud) < 0) {
                fprintf(stderr, "tv_flush: SQE allocation failed for disk %u\n",
                        seg->disk_index[i]);
                return TV_ERR;
            }
        } else {
            if (tv_uring_write(&sched->ring, fd, data + buf_pos,
                               (size_t)write_bytes, (off_t)disk_off, ud) < 0) {
                fprintf(stderr, "tv_flush: SQE allocation failed for disk %u\n",
                        seg->disk_index[i]);
                return TV_ERR;
            }
        }
        buf_pos += write_bytes;
        remaining -= write_bytes;
        submitted++;
    }

    if (submitted == 0 && data_len > 0) {
        fprintf(stderr, "tv_flush: all weights=0, data would be lost\n");
        return TV_ERR;
    }

    if (tv_uring_submit(&sched->ring) < 0) {
        fprintf(stderr, "tv_flush: submit failed\n");
        return TV_ERR;
    }
    return submitted;
}

/* Explicit flush: submit current buffer if non-empty, then wait for ALL in-flight */
int tv_flush(TV_SCHED *sched) {
    if (!sched) return TV_ERR;

    /* Submit current buffer if it has data */
    if (sched->sbuf_used > 0) {
        int head = sched->sbuf_head;
        TV_STRIPE_BUF *cur = &sched->sbuf[head];
        int nsub = flush_submit_io(sched, sched->sbuf_logical, cur->data, sched->sbuf_used, head);
        if (nsub < 0) return TV_ERR;
        if (nsub == 0) {
            /* No I/O submitted (empty segment), skip this buffer */
            sched->sbuf_head = (sched->sbuf_head + 1) % TV_BUF_COUNT;
            sched->sbuf_logical += sched->stripe_size;
            sched->sbuf_used = 0;
        } else {
            cur->in_flight = 1;
            cur->cqes_pending = nsub;
            sched->inflight++;
            sched->sbuf_head = (sched->sbuf_head + 1) % TV_BUF_COUNT;
            sched->sbuf_logical += sched->stripe_size;
            sched->sbuf_used = 0;
        }
    }

    /* Wait for ALL in-flight I/Os */
    while (sched->inflight > 0) {
        if (g_shutdown_requested) return TV_ERR;
        /* Drain any already-completed CQEs before blocking wait */
        reap_completed(sched);
        if (sched->inflight == 0) break;
        struct io_uring_cqe *cqe = NULL;
        struct __kernel_timespec ts = { .tv_sec = TV_CQE_TIMEOUT_SEC, .tv_nsec = 0 };
        int ret = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &ts);
        if (ret == -ETIME) {
            int inflight_before = sched->inflight;
            reap_completed(sched);
            if (sched->inflight == 0) break;
            if (sched->inflight == inflight_before) {
                fprintf(stderr, "tv_flush: %d CQEs slow, retrying (%ds)\n",
                        sched->inflight, TV_CQE_RETRY_SEC);
                ts.tv_sec = TV_CQE_RETRY_SEC;
                int r2 = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &ts);
                if (r2 == -ETIME) {
                    reap_completed(sched);
                    if (sched->inflight == 0) break;
                    if (sched->inflight == inflight_before) {
                        fprintf(stderr, "tv_flush: %d CQEs stuck, draining...\n",
                                sched->inflight);
                        io_uring_submit(&sched->ring);
                        /* Wait up to 30s for kernel to finish DMA */
                        int drain_wait = 0;
                        while (sched->inflight > 0 && drain_wait < 30) {
                            struct __kernel_timespec wait_ts = { .tv_sec = 1, .tv_nsec = 0 };
                            struct io_uring_cqe *tmp;
                            int r3 = io_uring_wait_cqe_timeout(&sched->ring, &tmp, &wait_ts);
                            if (r3 == 0 && tmp) {
                                int bi = (int)(intptr_t)io_uring_cqe_get_data(tmp);
                                io_uring_cqe_seen(&sched->ring, tmp);
                                if (bi >= 0 && bi < TV_BUF_COUNT && sched->sbuf[bi].in_flight) {
                                    sched->sbuf[bi].cqes_pending--;
                                    if (sched->sbuf[bi].cqes_pending <= 0) {
                                        sched->sbuf[bi].in_flight = 0;
                                        sched->inflight--;
                                    }
                                }
                                drain_wait = 0;
                            } else {
                                drain_wait++;
                            }
                        }
                        if (sched->inflight > 0)
                            fprintf(stderr, "tv_flush: WARNING: %d CQEs still in flight after drain\n",
                                    sched->inflight);
                        /* Now safe to reset */
                        for (int i = 0; i < TV_BUF_COUNT; i++) {
                            sched->sbuf[i].in_flight = 0;
                            sched->sbuf[i].cqes_pending = 0;
                        }
                        sched->inflight = 0;
                        break;
                    }
                    continue;
                }
                if (r2 == -EINTR) {
                    if (g_shutdown_requested) return TV_ERR;
                    continue;
                }
                if (r2 < 0) {
                    fprintf(stderr, "tv_flush: wait_cqe failed: %s\n", strerror(-r2));
                    return TV_ERR;
                }
                goto process_cqe;
            }
            continue;
        }
        if (ret == -EINTR) {
            if (g_shutdown_requested) return TV_ERR;
            continue;
        }
        if (ret < 0) {
            fprintf(stderr, "tv_flush: wait_cqe failed: %s\n", strerror(-ret));
            return TV_ERR;
        }
process_cqe:
        {
        int buf_idx = (int)(intptr_t)io_uring_cqe_get_data(cqe);
        int res = cqe->res;
        io_uring_cqe_seen(&sched->ring, cqe);
        if (res < 0 && res != -ETIME) {
            fprintf(stderr, "tv_flush: I/O error res=%d\n", res);
            /* Still decrement inflight to avoid hang */
            if (buf_idx >= 0 && buf_idx < TV_BUF_COUNT && sched->sbuf[buf_idx].in_flight) {
                sched->sbuf[buf_idx].cqes_pending--;
                if (sched->sbuf[buf_idx].cqes_pending <= 0) {
                    sched->sbuf[buf_idx].in_flight = 0;
                    sched->inflight--;
                }
            }
        } else if (buf_idx >= 0 && buf_idx < TV_BUF_COUNT && sched->sbuf[buf_idx].in_flight) {
            sched->sbuf[buf_idx].cqes_pending--;
            if (sched->sbuf[buf_idx].cqes_pending <= 0) {
                sched->sbuf[buf_idx].in_flight = 0;
                sched->inflight--;
            }
        }
        }
    }

    return 0;
}

int tv_sched_seek(TV_SCHED *sched, uint64_t offset) {
    if (!sched) return TV_ERR;
    if (offset % sched->stripe_size != 0) {
        fprintf(stderr, "tv_sched_seek: offset %lu is not stripe-aligned (%lu)\n",
                (unsigned long)offset, (unsigned long)sched->stripe_size);
        return TV_ERR;
    }
    if (tv_flush(sched) < 0) return TV_ERR;
    sched->sbuf_logical = offset;
    sched->sbuf_used = 0;
    return 0;
}

int tv_read(TV_SCHED *sched, void *buf, uint64_t len, uint64_t offset) {
    if (!sched || !buf || len == 0) return TV_ERR;

    /* Flush any pending writes first */
    if (tv_flush(sched) < 0) return TV_ERR;

    /* Drain any stale read CQEs from prior failed reads */
    {
        struct io_uring_cqe *tmp;
        while (io_uring_peek_cqe(&sched->ring, &tmp) == 0 && tmp) {
            fprintf(stderr, "tv_read: discarding stale CQE res=%d\n", tmp->res);
            io_uring_cqe_seen(&sched->ring, tmp);
        }
    }

    /* Check SQ has enough room for max possible SQEs per stripe */
    {
        int sq_slots = io_uring_sq_space_left(&sched->ring);
        if (sq_slots < sched->ndisks) {
            fprintf(stderr, "tv_read: insufficient SQ slots (%d < %d), submitting first\n",
                    sq_slots, sched->ndisks);
            io_uring_submit(&sched->ring);
        }
    }

    uint8_t *dst = (uint8_t *)buf;
    uint64_t pos = 0;

    while (pos < len) {
        int n_sqes = 0;
        uint64_t acc = 0;

        /* Build SQEs for all disk chunks in the current stripe */
        while (pos < len && acc < sched->stripe_size) {
            TV_MAP map = tv_map_logical(offset + pos, sched->meta);
            if (map.disk < 0 || map.disk >= sched->ndisks) {
                fprintf(stderr, "tv_read: invalid disk index %d\n", map.disk);
                return TV_ERR;
            }
            uint64_t chunk = len - pos;
            if (chunk > map.length) chunk = map.length;
            if (acc + chunk > sched->stripe_size)
                chunk = sched->stripe_size - acc;

            int fd = sched->disks[map.disk].fd;
            if (tv_uring_read(&sched->ring, fd, dst + pos,
                              (size_t)chunk, (off_t)map.offset) < 0) {
                fprintf(stderr, "tv_read: SQE allocation failed after %d SQEs "
                        "(partial stripe orphaned)\n", n_sqes);
                return TV_ERR;
            }
            n_sqes++;
            pos += chunk;
            acc += chunk;
        }

        if (n_sqes == 0) break;

        /* Single submit — all disks in stripe run in parallel */
        if (tv_uring_submit(&sched->ring) < 0) {
            fprintf(stderr, "tv_read: submit failed\n");
            return TV_ERR;
        }

        /* Wait for all completions */
        for (int i = 0; i < n_sqes; i++) {
            int res = tv_uring_wait(&sched->ring);
            if (res < 0) {
                fprintf(stderr, "tv_read: I/O error\n");
                return TV_ERR;
            }
        }
    }

    return 0;
}

void tv_sched_destroy(TV_SCHED *sched) {
    if (!sched) return;
    /* 1. Flush any pending data */
    tv_flush(sched);
    /* 2. Wait for all in-flight CQEs to complete (up to 30s each) */
    while (sched->inflight > 0) {
        struct io_uring_cqe *cqe;
        int ret = io_uring_wait_cqe_timeout(&sched->ring, &cqe,
                    &(struct __kernel_timespec){.tv_sec = TV_CQE_TIMEOUT_SEC, .tv_nsec = 0});
        if (ret == 0 && cqe) {
            int buf_idx = (int)(intptr_t)io_uring_cqe_get_data(cqe);
            io_uring_cqe_seen(&sched->ring, cqe);
            if (buf_idx >= 0 && buf_idx < TV_BUF_COUNT && sched->sbuf[buf_idx].in_flight) {
                sched->sbuf[buf_idx].cqes_pending--;
                if (sched->sbuf[buf_idx].cqes_pending <= 0) {
                    sched->sbuf[buf_idx].in_flight = 0;
                    sched->inflight--;
                }
            }
        } else {
            /* Timeout — force drain with blocking wait */
            fprintf(stderr, "tv_sched_destroy: timeout waiting for %d inflight CQEs, "
                    "waiting up to 60s more\n", sched->inflight);
            int extra = 0;
            while (sched->inflight > 0 && extra < 60) {
                struct __kernel_timespec wait_ts = { .tv_sec = 1, .tv_nsec = 0 };
                int r = io_uring_wait_cqe_timeout(&sched->ring, &cqe, &wait_ts);
                if (r == 0 && cqe) {
                    int bi = (int)(intptr_t)io_uring_cqe_get_data(cqe);
                    io_uring_cqe_seen(&sched->ring, cqe);
                    if (bi >= 0 && bi < TV_BUF_COUNT && sched->sbuf[bi].in_flight) {
                        sched->sbuf[bi].cqes_pending--;
                        if (sched->sbuf[bi].cqes_pending <= 0) {
                            sched->sbuf[bi].in_flight = 0;
                            sched->inflight--;
                        }
                    }
                    extra = 0;
                } else {
                    extra++;
                }
            }
            if (sched->inflight > 0) {
                fprintf(stderr, "tv_sched_destroy: WARNING: %d CQEs still in flight, "
                        "proceeding with teardown\n", sched->inflight);
            }
            break;
        }
    }
    /* 3. fsync all disks */
    for (int i = 0; i < sched->ndisks; i++) {
        if (sched->disks[i].fd >= 0)
            fsync(sched->disks[i].fd);
    }
    /* 4. Unregister buffers before freeing */
    if (sched->buffers_registered)
        tv_uring_unregister_buffers(&sched->ring);
    /* 5. Free buffers and ring */
    for (int i = 0; i < TV_BUF_COUNT; i++) {
        free(sched->sbuf[i].data);
    }
    tv_uring_destroy(&sched->ring);
    free(sched);
}
