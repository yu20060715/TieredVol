# Benchmark Results — B85 Platform

## System
- CPU: Intel i5-4570
- RAM: DDR3 1600MHz
- NVMe: P3 Plus 1T (PCIe 2.0x4)
- SATA: WD Blue NAND 250G + MX500 500G
- OS: Lubuntu, Linux 6.x

## Integration Test
| Test Suite | Result |
|------------|--------|
| test_common | 34/34 PASS |
| test_mapper | 10/10 PASS |
| test_partition | 19/19 PASS |
| test_metadata | 11/11 PASS |
| test_sched | 22/22 PASS |
| test_integrity | 11/11 PASS |
| **Total** | **107/107 PASS** |

## Throughput Results (512 MB, n=5)

| 場景 | Run1 | Run2 | Run3 | Run4 | Run5 | Mean | StdDev |
|------|------|------|------|------|------|------|--------|
| 2-disk write | 1485.7 | 1490.9 | 2139.0* | 1484.3 | 1477.8 | 1615.5 | 264.3 |
| 2-disk read | 1181.4 | 1216.1 | 1421.9* | 1071.1 | 993.6 | 1176.8 | 144.8 |
| 3-disk write | 1659.5 | 1859.8 | 1852.5 | 1808.0 | 1764.2 | 1788.8 | 73.6 |
| 3-disk read | 1346.3 | 1327.2 | 1228.3 | 1274.5 | 1228.0 | 1280.9 | 50.9 |

\* Run 3 for 2-disk tests shows anomalous high value (likely SLC cache burst)

## Large Transfer Results (3-disk, 1 run)

| 場景 | Size | Throughput |
|------|------|-----------|
| 3-disk write | 5 GB | 1285.6 MB/s |
| 3-disk write | 10 GB | 1228.6 MB/s |
| 3-disk read | 5 GB | 1240.5 MB/s |
| 3-disk read | 10 GB | 1318.0 MB/s |

## LVM Control (sdb+sdc, stripe=1M, mean of 3 runs)

| 場景 | Run1 | Run2 | Run3 | Mean |
|------|------|------|------|------|
| LVM write | 415 | 390 | 390 | 398.3 MB/s |
| LVM read | 440 | 426 | 430 | 432.0 MB/s |

## Analysis

### Scheduler vs LVM Comparison (sdb + sdc only)

Since the TieredVol scheduler was tested with nvme0n1 + sdb + sdc, and LVM was tested with sdb + sdc only, a direct comparison involves different disk sets:

- **TieredVol 3-disk write (NVMe + 2x SATA)**: ~1789 MB/s
- **LVM 2-disk write (2x SATA only)**: ~398 MB/s
- **TieredVol 3-disk read (NVMe + 2x SATA)**: ~1281 MB/s
- **LVM 2-disk read (2x SATA only)**: ~432 MB/s

Note: TieredVol includes NVMe with PCIe 2.0x4 (~1000 MB/s) while LVM only uses the two SATA disks (~450 MB/s each). The weighted striping allows heterogeneous disks to be combined effectively.

### Observations
- Weighted striping achieves **~94%** of theoretical sum (1788.8 / 1900 ≈ 0.94)
- Write performance scales well with additional disks
- Read shows lower efficiency due to NVMe read speed being limited by PCIe 2.0x4 bottleneck
- "CQEs stuck (lost), recovering" messages indicate occasional io_uring completion queue timeouts, data integrity is maintained via retry
