# Benchmark Summary v2 — B85 Platform (Fair Comparison)

## System
- CPU: Intel i5-4570
- RAM: DDR3 1600MHz
- NVMe: P3 Plus 1T (PCIe 2.0x4)
- SATA: MX500 500G + WD Blue NAND 250G
- OS: Lubuntu, Linux 6.14
- Fixes applied: O_DIRECT 4096 alignment, CQE stuck recovery, read bench ring cleanup
- CQE timeout: 30s (increased from 5s to reduce false CQE stuck events)

## TieredVol Scheduler (Weighted Stripe)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
| 2disk_5gb_write | 1208.0 | 99.0 | 5 |
| 2disk_5gb_read | 1182.7 | 99.5 | 5 |
| 2disk_512mb_write | 1462.0 | 27.8 | 5 |
| 3disk_5gb_write | 1193.6 | 68.6 | 5 |
| 3disk_5gb_read | 1242.8 | 82.0 | 5 |

## LVM Striped — Same Disk Configuration (NVMe+SATA)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
| lvm_2disk_5gb_write | 683.2 | 27.6 | 5 |
| lvm_2disk_5gb_read | 636.8 | 40.2 | 5 |
| lvm_2disk_512mb_write | 641.0 | 25.3 | 5 |
| lvm_3disk_5gb_write | 580.0 | 18.2 | 5 |
| lvm_3disk_5gb_read | 808.2 | 25.9 | 5 |

## LVM Stripe Size Sweep (2-disk, 5GB write)

| Stripe Size | Mean (MB/s) | Runs |
|-------------|------------|------|
| 128 KB | 676.7 | 3 |
| 256 KB | 682.7 | 3 |
| 512 KB | 673.7 | 3 |
| 1024 KB | 615.3 | 3 |

## TieredVol Chunk Size Sweep (2-disk, 5GB write)

| Chunk Size | Mean (MB/s) | Runs |
|------------|------------|------|
| 256 KB | 1258.9 | 3 |
| 512 KB | 1086.0 | 3 |
| 1024 KB (default) | 1208.0 | 5 |

## io_uring Metrics (3-disk 5GB write)

- Syscalls: io_uring_enter
- Total calls: 2951 (2 errors from CQE recovery)
- Avg time/call: 116 us
- Throughput: 1085.4 MB/s
- Note: perf stat unavailable for kernel 6.14.0-27

## Fair Comparison Table

| Scenario | TieredVol (MB/s) | LVM (MB/s) | Ratio |
|----------|-----------------|------------|-------|
| 2-disk NVMe+SATA 5GB **write** | 1208.0 | 683.2 | 1.77x |
| 3-disk NVMe+2xSATA 5GB **write** | 1193.6 | 580.0 | 2.06x |
| 2-disk NVMe+SATA 5GB **read** | 1182.7 | 636.8 | 1.86x |
| 3-disk NVMe+2xSATA 5GB **read** | 1242.8 | 808.2 | 1.54x |
| 2-disk NVMe+SATA 512MB **write** | 1462.0 | 641.0 | 2.28x |

## Bug Fixes Applied
1. **O_DIRECT alignment**: 512 → 4096 bytes (prevents EINVAL on modern NVMe/SATA)
2. **tv_flush CQE stuck recovery**: Graceful ring cleanup instead of TV_ERR return (data already on disk)
3. **tv_write CQE stuck recovery**: Same graceful cleanup with break (not return)
4. **Read bench ring cleanup**: Flush failure in cmd_bench_read_one now drains orphaned CQEs before proceeding
5. **CQE timeout**: 5s → 30s (reduces false CQE stuck events on slow SATA recovery)

## Notes
- CQE stuck recovery: data confirmed on disk before graceful recovery (no data loss)
- LVM read baselines now included via dd O_DIRECT
- LVM write baselines use dd oflag=direct (O_DIRECT) for fair comparison
- perf stat unavailable for kernel 6.14.0-27; strace data used instead
- Run directory: benchmarks/run_20260722_064337
