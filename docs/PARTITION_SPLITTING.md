# Weighted Striping Scheduler — 按碟速度比例分配 I/O

本文檔說明 TieredVol 的進階效能優化策略：**Weighted Striping Scheduler**。根據每顆碟的實際讀寫速度，以加權比例分配 I/O，讓快碟不被慢碟拖累。

---

## 問題：統一 Stripe Size 的瓶頸

標準 LVM striping / md RAID0 使用**統一的 stripe size**（chunk size），每顆碟在每個 cycle 拿到**相同大小的資料塊**。

### 範例：NVMe 2000 MB/s + SATA 500 MB/s

```
stripe size = 64KB

cycle 1:
  NVMe 寫 64KB → 0.032ms（完成，等待中...）
  SATA 寫 64KB → 0.128ms（進行中...）
                 ↑ 0.128ms 後 SATA 完成
                 ↑ NVMe 已空等 0.096ms

cycle 2:
  同上...
```

每個 cycle，NVMe 寫完 64KB 只要 0.032ms，但要等 SATA 0.128ms。**NVMe 每個 cycle 空等 75% 的時間。**

### 效能估算

| 碟 | 理論速度 | 每 cycle 寫入 | 每 cycle 時間 | 實際利用率 |
|----|---------|-------------|-------------|-----------|
| NVMe | 2000 MB/s | 64KB | 0.128ms | 25% |
| SATA | 500 MB/s | 64KB | 0.128ms | 100% |
| **合計** | 2500 MB/s | 128KB | 0.128ms | **~1000 MB/s** |

**`2000 + 500 = 2500`，但實際只有 ~1000 MB/s。** 快碟被慢碟嚴重拖累。

---

## 為什麼 Partition Splitting + LVM 不可行？

一個常見的誤解是：把 NVMe 切成 4 個 partition，讓 LVM 看到 5 個 PV（4 NVMe + 1 SATA），用 `lvcreate -i 5 -I 64k` 就能實現 4:1:1。

**這是不成立的。** 原因：

### 1. Linux Block Layer 會合併 BIO

對 kernel 而言，`/dev/nvme0n1p1` ~ `/dev/nvme0n1p4` 只是同一個 block device 的四個 partition。當 LVM 同時對四個 partition 下 I/O 請求時，block layer 的 I/O scheduler **完全可能把四個 64KB BIO 合併成一個 256KB Write**，送一次到底層。

結果：NVMe 拿到的不是「4 個平行的 64KB」，而是「1 個 256KB」。**I/O 沒有被分散到多個 queue。**

### 2. Multi-Queue ≠ 四倍頻寬

NVMe 的 64 個 queue 意味著可以同時 outstanding 很多 request，但不代表每個 queue 都有獨立頻寬。所有 queue 共享同一個 PCIe x4 通道：

```
PCIe x4 Gen3 = 3940 MB/s（理論上限）
PCIe x4 Gen4 = 7880 MB/s（理論上限）

所有 queue 加起來，總頻寬仍然是 PCIe 的上限。
不是 2000 × 4 = 8000 MB/s。
```

### 3. 沒有核心層級的保證

LVM md RAID0 的 striping 是**固定大小、round-robin**，沒有「加權 striping（weighted striping）」的概念。你無法指定「NVMe 拿 4 個 chunk，SATA 拿 1 個 chunk」。

**結論：Partition Splitting 是一個看似合理但缺乏可靠理論和核心保證的做法。**

---

## 正確解法：Weighted Striping Scheduler

如果 TieredVol 自己控制 I/O 排程，就能真正實現 4:1:1 加權 striping。

### 架構

```
Application
     ↓
TieredVol Scheduler
     ↓
io_uring / AIO
     ↓
NVMe ← 256KB
SATA1 ← 64KB
SATA2 ← 64KB
```

TieredVol 不是 RAID，而是一個 **I/O Scheduler**。它決定每個 disk 拿多少資料，然後直接對底層裝置發送 I/O。

### Step 1：Benchmark 取得速度

```
NVMe  = 2000 MB/s
SATA1 = 500 MB/s
SATA2 = 500 MB/s
```

### Step 2：計算 Weight

以最慢碟為基準，計算比例：

```
ratio = disk_speed / slowest_speed

NVMe  = 2000 / 500 = 4
SATA1 = 500 / 500  = 1
SATA2 = 500 / 500  = 1

weight = [4, 1, 1]
```

### Step 3：決定 Chunk Size

固定 chunk size（例如 64KB），每輪共寫：

```
total_chunks = 4 + 1 + 1 = 6
stripe_size  = 6 × 64KB = 384KB per cycle
```

每輪的分配：
```
NVMe:   4 × 64KB = 256KB
SATA1:  1 × 64KB = 64KB
SATA2:  1 × 64KB = 64KB
─────────────────────────
合計:             384KB
```

時間驗證：
```
NVMe:  256KB / 2000 MB/s ≈ 0.128ms
SATA1: 64KB / 500 MB/s   ≈ 0.128ms
SATA2: 64KB / 500 MB/s   ≈ 0.128ms
三者同時完成 → 沒有等待
```

### Step 4：Dispatch I/O

使用 io_uring 同時送出，不等第一個完成：

```
io_uring_submit:
  SQE[0]: write(NVMe,  256KB, offset=N)
  SQE[1]: write(SATA1, 64KB,  offset=M)
  SQE[2]: write(SATA2, 64KB,  offset=P)
```

Kernel 同時發出三個 I/O。

### Step 5：等全部完成

等 CQE（Completion Queue Entry）：

```
NVMe  Done
SATA1 Done
SATA2 Done
```

全部完成 → 開始下一輪 Stripe2。

---

## Offset 計算（核心）

任何 logical offset 都能快速定位到正確的碟和碟內 offset。

### 計算公式

```
stripe_size = sum(weight) × chunk_size = 6 × 64KB = 384KB

stripe_no    = logical_offset / stripe_size
offset_in    = logical_offset % stripe_size
disk_index   = offset_in / chunk_size   （但要注意 weight 累加）
disk_offset  = stripe_no × disk_weight × chunk_size + (offset_in % disk_weight × chunk_size)
```

### 具體範例

```
chunk_size = 64KB
weight = [4, 1, 1]
stripe_size = 384KB

Logical Offset = 1MB = 1024KB

stripe_no = 1024 / 384 = 2
offset_in = 1024 % 384 = 256

Disk 分佈（stripe 內的 offset）：
  0 ~ 255KB  → NVMe    (weight=4, 範圍 0~255)
  256 ~ 319KB → SATA1  (weight=1, 範圍 256~319)
  320 ~ 383KB → SATA2  (weight=1, 範圍 320~383)

offset_in = 256 → 落在 SATA1 範圍
disk_offset = 2 × 1 × 64KB + (256 - 256) = 128KB
```

因此：Logical 1MB → SATA1 的 offset 128KB。

### 查表加速

程式不需要每次算數學，可以用預計算的 prefix sum table：

```
disk_boundary[0] = 0          (NVMe start)
disk_boundary[1] = 4 × 64 = 256   (SATA1 start)
disk_boundary[2] = 5 × 64 = 320   (SATA2 start)
disk_boundary[3] = 6 × 64 = 384   (stripe end)
```

binary search 即可快速定位。

---

## Metadata

只需要保存：

```
chunk_size:  64KB
weight:      [4, 1, 1]
disk_list:   [nvme0n1, sda, sdb]
```

即可由公式計算所有映射，**不需要記錄每個 block 的位置**。

---

## Partial Stripe 處理

應用程式不一定寫 384KB 的整數倍。例如寫 100KB、10KB、70KB。

### 方案 A：Buffer（推薦）

TieredVol 內部維護一個 buffer：

```
寫入 100KB → buffer 收下
寫入 70KB  → buffer 累積 170KB
寫入 214KB → buffer 累積 384KB → dispatch 整個 stripe
```

- 優點：永遠 dispatch 完整 stripe，offset 計算簡單
- 缺點：增加延遲（要等 buffer 滿），需要額外記憶體

### 方案 B：Partial Stripe

允許不完整的 stripe，但 metadata 需要記錄：

```
stripe_no | disk | offset | length
2         | NVMe | 0      | 100KB
```

- 優點：低延遲，不需要 buffer
- 缺點：metadata 複雜，讀取時需要拼接

### 建議

TieredVol 先實作 **方案 A（Buffer）**，簡單可靠。未來可擴充方案 B。

---

## 讀取流程

與寫入相同：

```
io_uring_submit:
  SQE[0]: read(NVMe,  256KB, offset=N)
  SQE[1]: read(SATA1, 64KB,  offset=M)
  SQE[2]: read(SATA2, 64KB,  offset=P)
```

等全部完成 → 依 offset 組回 buffer。

---

## 效能對比

| 方法 | NVMe 每 cycle | SATA 每 cycle | 等待時間 | 預估速度 |
|------|-------------|-------------|---------|---------|
| 標準 LVM striping | 64KB | 64KB | NVMe 等 0.096ms | ~1000 MB/s |
| Partition splitting（不可靠） | 256KB | 64KB | 有風險 | 不確定 |
| **Weighted Striping Scheduler** | **256KB** | **64KB** | **≈ 0** | **~2500 MB/s** |

---

## 實作架構

```
TieredVol/
├── scheduler/
│   ├── weighted_io.c      # I/O scheduler 核心
│   ├── offset_map.c       # Logical → Physical offset 映射
│   ├── stripe_buffer.c    # Partial stripe buffer
│   └── io_uring_dispatch.c # io_uring 送出/回收
├── tiered_setup.c         # CLI（加入 --scheduler 模式）
└── tiered_ui.c            # TUI（加入 scheduler 狀態顯示）
```

### API 概念

```c
// 初始化 scheduler
tiered_sched_t *sched = tiered_sched_init(disks, ndisks, chunk_size);

// 寫入（自動 buffer + dispatch）
tiered_sched_write(sched, data, length);

// 讀取
tiered_sched_read(sched, buf, length, offset);

// 清理
tiered_sched_destroy(sched);
```

---

## 為什麼 LVM/md RAID 做不到？

LVM 和 md RAID0 的 striping 是**固定大小、round-robin**：

```
LVM: chunk → D1, chunk → D2, chunk → D3, chunk → D1...
md:  chunk → D1, chunk → D2, chunk → D3, chunk → D1...
```

它們沒有「加權 striping（weighted striping）」的概念，無法指定「NVMe 拿 4 個 chunk，SATA 拿 1 個 chunk」。

要實現真正的加權 striping，需要：
1. 自己控制 I/O dispatch（不依賴 LVM/md）
2. 使用 async I/O（io_uring / AIO）同時送出多個 request
3. 自己管理 offset 映射和 metadata

**TieredVol 作為 I/O Scheduler，正好可以做到這些。**

---

## 實作難度

| 項目 | 難度 | 說明 |
|------|------|------|
| Weight 計算 | 簡單 | 數學運算 |
| Offset 映射 | 簡單 | prefix sum + binary search |
| io_uring dispatch | 中等 | 需要 liburing 或直接 syscall |
| Stripe buffer | 中等 | Ring buffer + flush 機制 |
| Partial stripe | 中等 | 方案 A 簡單，方案 B 複雜 |
| 錯誤處理 | 中等 | I/O 失敗要 retry 或 rollback |

---

## 參考

- io_uring: `io_uring_setup`, `io_uring_enter`, liburing
- Linux block layer: `drivers/block/`
- NVMe multi-queue: `drivers/nvme/host/`
- Weighted striping 概念: 本文件原創（TieredVol project）
