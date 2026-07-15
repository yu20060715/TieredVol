# TieredVol — 分層儲存卷管理器

Linux 分層儲存解決方案。將多顆硬碟合併成高效能條紋化磁碟區（striped volume），支援 dm-linear 分割 + LVM striped + RAM Cache 即時調優。

```
Disk A ──dm-linear──┐
Disk B ──dm-linear──┤── LVM VG ── striped LV ── filesystem ── mount
Disk C ──dm-linear──┘
```

## 功能

| 功能 | 說明 |
|------|------|
| 硬碟偵測 | 自動列出所有硬碟型號、傳輸介面、容量，標記系統碟 |
| 自動測速 | 啟動時背景自動跑 benchmark，不阻塞 UI |
| 建立 Volume | 互動式 3 步驟精靈：選碟 → 設定容量 → 命名掛載 |
| RAM Cache | 即時調整 `vm.dirty_ratio`，128MB 步進 |
| Volume 管理 | 一鍵建立/查看狀態/刪除 striped LVM volume |

## 系統需求

- Linux（已測試 Ubuntu 24.04, kernel 6.14）
- `lvm2` `dmsetup` `libncurses-dev` `gcc` `make`
- Root 權限（sudo）

### 安裝依賴

```bash
# Debian / Ubuntu
sudo apt install lvm2 libncurses-dev gcc make

# Fedora / RHEL
sudo dnf install lvm2 ncurses-devel gcc make

# Arch
sudo pacman -S lvm2 ncurses gcc make
```

## 快速開始

```bash
git clone https://github.com/yu20060715/TieredVol.git
cd TieredVol
make
sudo ./tiered_ui
```

### 安裝到系統

```bash
sudo make install
sudo tiered_ui
```

## CLI 使用

```bash
# 列出所有硬碟
sudo tiered_setup --list

# 測速（3 顆硬碟）
sudo tiered_setup --bench --disks sdb,sdc,nvme0n1

# 建立 striped volume（2 顆碟，各取 300G + 200G）
sudo tiered_setup --create --name fastpool --disks sdb:300,sdc:200 --fs ext4 --mount /mnt/fast

# 查看狀態
sudo tiered_setup --status

# 刪除 volume
sudo tiered_setup --destroy --name fastpool
```

## TUI 介面

```bash
sudo tiered_ui
```

```
┌─ Main Menu ─────────────────────┐
│   > Disk List                   │
│     Benchmark                   │
│     Create Volume               │
│     Volume Status               │
│     RAM Cache                   │
│     Destroy Volume              │
│     Exit                        │
└─────────────────────────────────┘
```

### 快速鍵

| 畫面 | 按鍵 | 動作 |
|------|------|------|
| 主選單 | ↑↓ Enter Q/ESC | 選擇/確認/離開 |
| Disk List | Q/ESC | 返回 |
| Benchmark | Q/ESC | 返回（測速繼續背景跑）|
| Create Phase 0 | Space Enter | 選碟 / 下一步 |
| Create Phase 1 | ←→ | 調整 carve 容量 |
| RAM Cache | ←→ ↑↓ Enter | 調整 / 選擇 Apply/Reset |
| Destroy | Y | 確認刪除 |

## RAM Cache 調優

透過調整 kernel 的 `vm.dirty_ratio` 將部分 RAM 用作寫入快取：

- **← →**：調整借用量（128MB 步進）
- **↑ ↓**：選擇 Apply / Reset / Back
- **Apply**：套用新設定
- **Reset**：恢復原始值

例：16GB RAM 借用 2GB → dirty_ratio 從 20% 提升到 33%。

## 專案結構

```
TieredVol/
├── Makefile              # 建置系統
├── README.md             # 說明文件
├── .gitignore
├── src/
│   ├── tiered_setup.c    # CLI 後端（~726 行）
│   └── tiered_ui.c       # ncurses TUI 前端（~1140 行）
```

## 注意事項

- **系統碟無法使用** — dm-linear 在已掛載的根分区上會回傳 EBUSY
- 選擇的硬碟資料會被**完全清除**
- 需要 root 權限執行所有操作

## License

MIT
