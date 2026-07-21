# TieredVol — B85 測試 Agent

> 在 B85 Lubuntu 上的 TieredVol 目錄啟動 opencode，把 prompt 貼進去
> 完成後把測試數據放回 TieredVol 目錄，然後 git push

---

## 碟配置

- nvme0n1: P3 Plus 1T (NVMe, PCIe 2.0x4, ~1000 MB/s)
- sda: S4610 960G (系統碟，勿動)
- sdb: WD Blue NAND 250G (SATA)
- sdc: MX500 500G (SATA)

---

## Prompt — 完整貼入 opencode

```
幫我在 B85 上跑完整的 code 測試，包含 integration test 和 benchmark。
測試完成後把所有結果寫入 BENCHMARK-RESULTS.md 存在 TieredVol 根目錄。

碟配置：
- nvme0n1: P3 Plus 1T (NVMe, ~1000 MB/s)
- sda: S4610 960G (系統碟，勿動)
- sdb: WD Blue NAND 250G (SATA)
- sdc: MX500 500G (SATA)

=== 第一部分：Integration Test ===

sudo make clean && sudo make test-full

逐個回報 PASS/FAIL 狀態，如果有 FAIL 附上錯誤訊息。

=== 第二部分：Benchmark ===

1. 先確認環境：
   sudo tiered_setup --info
   sudo dmsetup ls | grep tiered
   如果有舊 volume 先移除：sudo tiered_setup --remove --name <name>

2. 跑以下 4 個主場景，每個 5 次，每次之間 sleep 10：

   場景 A: 2-disk write
     sudo tiered_setup --create --disks nvme0n1,sdb --name bench_a
     sudo tiered_io bench --target /dev/tiered/bench_a --size 512M --type write
     記錄 throughput
     sudo tiered_setup --remove --name bench_a
     sleep 10

   場景 B: 2-disk read
     （create → 填入 512M 資料 → remove → 重建 → bench read）
     sudo tiered_setup --create --disks nvme0n1,sdb --name bench_b_fill
     sudo tiered_io write --target /dev/tiered/bench_b_fill --size 512M
     sudo tiered_setup --remove --name bench_b_fill
     sudo tiered_setup --create --disks nvme0n1,sdb --name bench_b
     sudo tiered_io bench --target /dev/tiered/bench_b --size 512M --type read
     記錄 throughput
     sudo tiered_setup --remove --name bench_b
     sleep 10

   場景 C: 3-disk write
     sudo tiered_setup --create --disks nvme0n1,sdb,sdc --name bench_c
     sudo tiered_io bench --target /dev/tiered/bench_c --size 512M --type write
     記錄 throughput
     sudo tiered_setup --remove --name bench_c
     sleep 10

   場景 D: 3-disk read
     （create → 填入 512M 資料 → remove → 重建 → bench read）
     sudo tiered_setup --create --disks nvme0n1,sdb,sdc --name bench_d_fill
     sudo tiered_io write --target /dev/tiered/bench_d_fill --size 512M
     sudo tiered_setup --remove --name bench_d_fill
     sudo tiered_setup --create --disks nvme0n1,sdb,sdc --name bench_d
     sudo tiered_io bench --target /dev/tiered/bench_d --size 512M --type read
     記錄 throughput
     sudo tiered_setup --remove --name bench_d
     sleep 10

3. 補充測試（各跑 1 次）：
   - 3-disk write 5GB
   - 3-disk write 10GB
   - 3-disk read 5GB
   - 3-disk read 10GB
   流程同上，--size 改為 5G 或 10G

4. LVM control 組（sdb + sdc，stripe=1M）：
   sudo pvcreate /dev/sdb /dev/sdc
   sudo vgcreate bench_vg /dev/sdb /dev/sdc
   sudo lvcreate -l 100%FREE -i 2 -I 1M -n bench_lv bench_vg
   sudo mkfs.ext4 /dev/bench_vg/bench_lv
   sudo mkdir -p /mnt/bench
   sudo mount /dev/bench_vg/bench_lv /mnt/bench
   用 dd 或 fio 跑 write/read 512M，跑 3 次取平均
   卸載後清理：sudo umount /mnt/bench && sudo lvremove -f bench_vg/bench_lv && sudo vgremove -f bench_vg && sudo pvremove -f /dev/sdb /dev/sdc

5. 全部完成後，把結果寫入 BENCHMARK-RESULTS.md：

# Benchmark Results — B85 Platform

## System
- CPU: Intel i5-4570
- RAM: DDR3 1600MHz
- NVMe: P3 Plus 1T (PCIe 2.0x4)
- SATA: WD Blue NAND 250G + MX500 500G
- OS: Lubuntu, Linux 6.x

## Integration Test
（逐項列出 PASS/FAIL）

## Throughput Results (512 MB, mean ± stddev, n=5)

| 場景 | Run1 | Run2 | Run3 | Run4 | Run5 | Mean | StdDev |
|------|------|------|------|------|------|------|--------|
| 2-disk write | | | | | | | |
| 2-disk read | | | | | | | |
| 3-disk write | | | | | | | |
| 3-disk read | | | | | | | |

## Large Transfer Results (3-disk, 1 run)

| 場景 | Size | Throughput |
|------|------|-----------|
| 3-disk write | 5 GB | |
| 3-disk write | 10 GB | |
| 3-disk read | 5 GB | |
| 3-disk read | 10 GB | |

## LVM Control (sdb+sdc, stripe=1M, mean of 3 runs)

| 場景 | Throughput |
|------|-----------|
| LVM write | |
| LVM read | |

6. 最後執行：
   git add BENCHMARK-RESULTS.md
   git commit -m "bench: B85 benchmark results (5 runs, mean ± stddev)"
   git push

完成後回報 "DONE: benchmark data pushed to TieredVol"。
```

---

## 注意事項

- 每次 create 之前跑 `sudo dmsetup ls | grep tiered` 確認無殘留 volume
- 如果某次 run 失敗（如 timeout），重跑一次而不是跳過
- sda 是系統碟，**絕對不要**對 sda 做任何操作
- LVM 組只用 sdb + sdc，不跨 NVMe（LVM 不適合跨異質碟）
- read 場景需要先填資料（write 一次），因為碟上要有可讀的資料
- 全部做完後 git push，讓 Windows 那邊 pull 拿到數據
