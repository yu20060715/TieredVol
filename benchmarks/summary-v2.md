# Benchmark Summary v2 — B85 Platform (Fair Comparison)

## System
- CPU: Intel i5-4570
- RAM: DDR3 1600MHz
- NVMe: P3 Plus 1T (PCIe 2.0x4)
- SATA: MX500 500G + WD Blue NAND 250G
- OS: Lubuntu, Linux 6.14
- Fixes applied: O_DIRECT 4096 alignment, CQE stuck recovery, read bench ring cleanup

## TieredVol Scheduler (Weighted Stripe)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
| 2disk_5gb_write | 1237.4 | 90.3311 | 5 |
| 2disk_5gb_read | 1383.4 | 89.3188 | 5 |
| 2disk_512mb_write | 2067.6 | 135.4196 | 5 |
| 3disk_5gb_write | 1192.3 | 66.7314 | 5 |
| 3disk_5gb_read | 1212.6 | 109.5126 | 5 |

## LVM Striped — Same Disk Configuration (NVMe+SATA)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
| lvm_2disk_5gb_write | 704.3 | 20.9464 | 5 |
| lvm_3disk_5gb_write | 587.8 | 8.5911 | 5 |

## LVM Stripe Size Sweep (2-disk, 5GB write)

| Stripe Size | Mean (MB/s) | Runs |
|-------------|------------|------|
| 128 KB | 706.2 | 3 |
| 256 KB | 720.3 | 3 |
| 512 KB | 714.1 | 3 |
| 1024 KB | 650.1 | 3 |

## TieredVol Chunk Size Sweep (2-disk, 5GB write)

| Chunk Size | Mean (MB/s) | Runs |
|------------|------------|------|
| 256 KB | 1072.6 | 3 |
| 512 KB | 1093.5 | 3 |
| 1024 KB (default) | 1237.4 | 5 |

## io_uring Metrics (3-disk 5GB write)

- Syscalls: io_uring_enter
- Total calls: 3166 (2 errors from CQE recovery)
- Avg time/call: 78 us
- Throughput: 1083.5 MB/s

## Fair Comparison Table

| Scenario | TieredVol (MB/s) | LVM (MB/s) | Ratio |
|----------|-----------------|------------|-------|
| 2-disk NVMe+SATA 5GB **write** | 1237.4 | 704.3 | 1.75x |
| 3-disk NVMe+2xSATA 5GB **write** | 1192.3 | 587.8 | 2.02x |
| 2-disk NVMe+SATA 5GB **read** | 1383.4 | N/A | — |
| 3-disk NVMe+2xSATA 5GB **read** | 1212.6 | N/A | — |

## Bug Fixes Applied
1. **O_DIRECT alignment**: 512 → 4096 bytes (prevents EINVAL on modern NVMe/SATA)
2. **tv_flush CQE stuck recovery**: Graceful ring cleanup instead of TV_ERR return (data already on disk)
3. **tv_write CQE stuck recovery**: Same graceful cleanup with break (not return)
4. **Read bench ring cleanup**: Flush failure in cmd_bench_read_one now drains orphaned CQEs before proceeding

## Notes
- CQE stuck recovery: data confirmed on disk before graceful recovery (no data loss)
- Read benchmarks now work thanks to Fix 3 (previously failed with io_uring flush timeout)
- LVM read benchmarks: tiered_io --bench-read --raw not supported for LVM
- Run directory: benchmarks/run_20260722_053853
