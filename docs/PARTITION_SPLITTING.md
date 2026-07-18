# Partition Splitting — 按碟速度比例分配 Stripe

本文檔說明 TieredVol 的進階 stripe 優化策略：**Partition Splitting**，根據每顆碟的實際讀寫速度，自動分配不同的 stripe slot 數量，讓快碟不被慢碟拖累。

---

## 問題：統一 Stripe Size 的瓶頸

標準 LVM striping 使用**統一的 stripe size**（chunk size），每顆碟在每個 cycle 拿到**相同大小的資料塊**。

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

## 解決方案：Partition Splitting

核心概念：**讓快碟在每個 cycle 拿到更多資料**，使其與慢碟同時完成。

### 數學推導

```
NVMe 速度 = 2000 MB/s
SATA 速度 = 500 MB/s

比例 = 2000 / 500 = 4 : 1

→ NVMe 每 cycle 拿 4 個 stripe slot = 4 × 64KB = 256KB
→ SATA 每 cycle 拿 1 個 stripe slot = 1 × 64KB = 64KB

時間驗證：
  NVMe: 256KB / 2000 MB/s = 0.128ms
  SATA:  64KB / 500 MB/s  = 0.128ms
  兩顆同時完成 → 沒有等待
```

**`2000 + 500 = 2500 MB/s`，實際可達 ~2300+ MB/s。**

### 如何實現：Partition Splitting

將速度快的碟切成多個 partition，每個 partition 作為獨立的 PV：

```
NVMe 1TB → 切成 4 個 partition（各 250GB）
SATA 500GB → 1 個 partition

PV: NVMe_p1, NVMe_p2, NVMe_p3, NVMe_p4, SATA
lvcreate -i 5 -I 64k -n my_lv my_vg
```

每個 PV 拿到的 stripe 都是 64KB：
```
cycle 1:
  NVMe_p1: 64KB ─┐
  NVMe_p2: 64KB ─┤ NVMe 控制器同時處理
  NVMe_p3: 64KB ─┤ → 共 256KB，0.128ms
  NVMe_p4: 64KB ─┘
  SATA:    64KB    → 0.128ms
  兩組同時完成 → 沒有等待
```

### 效能對比

| 方法 | NVMe 每 cycle | SATA 每 cycle | 等待時間 | 預估速度 |
|------|-------------|-------------|---------|---------|
| 標準 striping | 64KB | 64KB | NVMe 等 0.096ms | ~1000 MB/s |
| Partition splitting | 256KB | 64KB | ≈ 0 | ~2300 MB/s |

---

## NVMe Multi-Queue 的支援

你可能會問：「NVMe 的 4 個 partition 在同一顆物理碟上，真的可以同時寫入嗎？」

答案是：**可以。**

NVMe SSD 使用 **multi-queue 架構**（通常 64-128 個佇列），與 SATA 的單佇列完全不同：

```
SATA (AHCI):
  Host → [1 個命令佇列] → [1 個磁碟控制器] → 媒體
  → 同一時間只能處理 1 個 I/O request

NVMe:
  Host → [Queue 0] → ┐
         [Queue 1] → ├→ [NVMe 控制器] → 媒體
         [Queue 2] → │    (多通道平行處理)
         [Queue N] → ┘
  → 可同時處理多個 I/O request
```

每個 partition 的 I/O 會分配到不同的 NVMe queue，控制器**真正平行處理**。這不是模擬的平行，而是硬體層級的平行。

### 限制

- 效果取決於 NVMe 控制器的佇列深度和內部通道數
- HDD **不適用**（只有一個磁頭，無法平行）
- 同一顆 NVMe 上的 partition 數量不宜超過控制器的實際佇列數（通常 4-8 個就夠了）

---

## TieredVol 自動化

TieredVol 可以根據 benchmark 測速結果，自動計算最優的 partition 分配：

### 計算邏輯

```
1. 取得每顆碟的速度（MB/s）
2. 找出最慢碟作為基準
3. 計算每顆碟的比例：ratio = disk_speed / slowest_speed
4. 取整數（四捨五入，最少 1）
5. 快碟切成 ratio 個 partition
6. lvcreate -i total_partitions -I stripesize
```

### 範例

```
碟 A: NVMe 2000 MB/s → ratio = 2000/500 = 4 → 切 4 個 partition
碟 B: SATA 500 MB/s  → ratio = 500/500 = 1 → 不切
碟 C: SATA 1000 MB/s → ratio = 1000/500 = 2 → 切 2 個 partition

PV 數量 = 4 + 1 + 2 = 7
lvcreate -i 7 -I 64k
```

### 刪除 volume 時

刪除 volume 時需要自動清除為 partition splitting 建立的 partition：

```bash
# 刪除 LVM
lvremove -f my_vg/my_lv
vgremove my_vg
pvremove /dev/nvme0n1p1 /dev/nvme0n1p2 ...

# 還原 partition table
sgdisk --delete /dev/nvme0n1
# 或用 sgdisk 恢復原本的 partition layout
```

---

## 實作難度

| 項目 | 難度 | 說明 |
|------|------|------|
| 速度比例計算 | 簡單 | 數學運算 |
| Partition 切割 | 中等 | 用 `sgdisk` 或 `parted` 動態切割 |
| lvcreate 參數調整 | 簡單 | 改 `-i` 參數 |
| 刪除時清除 partition | 中等 | 需要備份/還原 partition table |
| 錯誤處理 | 中等 | 切 partition 失敗要回滾 |

---

## 參考

- LVM striped: `lvcreate -i <num> -I <chunk_size>`
- dm-stripe: `dmsetup create ... striped <num_devs> <chunk_size>`
- NVMe multi-queue: Linux kernel `drivers/nvme/host/`
- Partition tool: `sgdisk` (GPT) / `parted` / `fdisk` (MBR)
