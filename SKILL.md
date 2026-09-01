---
name: use-bcachefs
description: Reference for bcachefs-specific system configuration pitfalls — plocate/updatedb/locate setup, DKMS port checks, PRUNEFS, PRUNE_BIND_MOUNTS, subvolume mount behaviour, and swapfile limitation (use zram instead).
---

# bcachefs 系統整合注意事項

## 指令總覽

```bash
use-bcachefs dkms-port-check --help
```

唯讀核對新版 kernel 之 source、module、userspace、vermagic 與 initramfs；
不編譯、不安裝、不改磁碟或 GRUB。詳見 `references/dkms-porting.md`。

## 安裝 skill command

於 primary worktree 執行：

```bash
writing-skill-scripts install scripts/uv-tools-expose.json
use-bcachefs --help
use-bcachefs dkms-port-check --help
```

## plocate / updatedb / locate 在 bcachefs 上的正確設定

### 症狀

- `locate <已知檔案>` 查無結果
- `/var/lib/plocate/plocate.db` 只有 ~969 bytes（空 header）
- `plocate-updatedb.service` CPU time 只有數十毫秒（正常應數秒至數十秒）
- `systemctl status plocate-updatedb.service` 顯示 exit 0，無錯誤

### 根因

bcachefs 子卷（`/@root`、`/@home`、`/@docker` 等）均來自同一底層裝置，
所有子卷的 `st_dev` **相同**。

當 `/etc/updatedb.conf` 設定 `PRUNE_BIND_MOUNTS="yes"` 時，
plocate 以 same-source-device 邏輯誤判所有 bcachefs 子卷為 bind mount，
整批跳過，導致 DB 幾乎為空。

### 診斷指令

```bash
# 確認 st_dev 是否一致（bcachefs 子卷預期相同）
python3 -c "
import os
for p in ['/', '/home', '/boot']:
    s = os.stat(p)
    print(f'{p}: st_dev=0x{s.st_dev:X}')
"

# 確認設定
grep PRUNE_BIND_MOUNTS /etc/updatedb.conf

# 確認 DB 大小（正常應 > 10MB）
ls -lh /var/lib/plocate/plocate.db
```

### 修復

```bash
# 1. 關閉 bind mount pruning
sudo sed -i 's/^PRUNE_BIND_MOUNTS="yes"/PRUNE_BIND_MOUNTS="no"/' /etc/updatedb.conf

# 2. 若有掛載 bcachefs 頂層（/mnt/bcachefs-top 等），加入 PRUNEPATHS 避免重複路徑
#    （修改 /etc/updatedb.conf 的 PRUNEPATHS 行，手動加入路徑）

# 3. 重建索引並驗證
sudo updatedb
locate /etc/passwd   # 應有多筆輸出
```

### PRUNEPATHS 建議

若系統有 `/mnt/bcachefs-top`、`/run/bcachefs-top` 等直接掛載 bcachefs 頂層的路徑，
`locate` 會出現重複結果（例如 `/home/foo` 與 `/mnt/bcachefs-top/@home/foo`）。
建議加入 `PRUNEPATHS`：

```
PRUNEPATHS="/tmp /var/spool /media ... /mnt/bcachefs-top /run/bcachefs-top"
```

### Ubuntu 套件狀態

- `plocate 1.1.19-2ubuntu2`（Ubuntu 24.04）：編譯時未帶入 bcachefs ioctl 支援
  （`strings /usr/sbin/updatedb.plocate | grep -i bcachefs` 無輸出）
- 無 bcachefs ioctl 支援時，plocate 應降回 opendir/readdir traversal
- `PRUNE_BIND_MOUNTS="no"` 後，traversal 可正常運作
- `mlocate` 在 Ubuntu 22.04+ 已從套件庫移除

### 參考 ops 記錄

`ops/resolved/2026-05-13-updatedb-bcachefs-locate-empty.md`

---

## bcachefs 不支援 swapfile（swapon Invalid argument）

### 症狀

```
swapon /swapfile
swapon: /swapfile: swapon failed: Invalid argument
```

`dmesg` 無更多說明；`/swapfile` 已建立且大小正確。

### 根因

bcachefs 截至 2026-05 不支援以 `swapon` 啟用放置在其上的 swapfile。
核心拒絕操作並回 `EINVAL`；此限制與 btrfs 需要 `chattr +C` 不同，
即使設定正確的 offset/uuid 仍無效。

### 解法：zram swap

不依賴磁碟路徑，直接在記憶體裡建立壓縮 swap 裝置：

```bash
# 建立 60G zram swap（可依記憶體大小調整）
sudo modprobe zram
echo zstd | sudo tee /sys/block/zram0/comp_algorithm
echo 60G  | sudo tee /sys/block/zram0/disksize
sudo mkswap /dev/zram0
sudo swapon -p 100 /dev/zram0

# 驗證
swapon --show
# 預期: /dev/zram0  60G  prio 100
```

**持久化**（開機自動啟用）：

```bash
# /usr/local/sbin/example-zram-swap
#!/bin/bash
set -e
modprobe zram
echo zstd > /sys/block/zram0/comp_algorithm
echo 60G  > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0
```

```ini
# /etc/systemd/system/example-zram-swap.service
[Unit]
Description=zram swap (bcachefs workaround)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/example-zram-swap
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now example-zram-swap.service
```

### 規則

- bcachefs 上放 swapfile 永遠失敗，不必排查 offset 或 uuid；直接改 zram。
- zram 預設壓縮為 `lzo-rle`；`zstd` 效率更佳，可設定後再 mkswap。
- 若系統有 `systemd-zram-generator`（Ubuntu 24.04 預設安裝），可改用 `/etc/systemd/zram-generator.conf` 統一管理；手工 service 可視情況移除。

### 參考 ops 記錄

`ops/archive/plan-2026-05-boot-repair-iso-rebuild/README.md`（2026-05-16 執行紀錄 §本機 swap 補救）
