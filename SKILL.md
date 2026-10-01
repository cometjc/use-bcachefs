---
name: use-bcachefs
description: Use when integrating bcachefs with Linux boot, multi-device root subvolumes, initramfs/GRUB rollback, bubblewrap mount checks, plocate or swap.
---

# bcachefs 系統整合

提供 bcachefs 特有的相容性與唯讀檢查；不自動安裝 kernel、改 fstab、武裝
重開或改磁碟。主機寫入與重開須另獲授權。範例須依當地主機調整。

## 依問題選入口

| 問題 | 入口 |
| --- | --- |
| 多裝置 root、子卷 bind、Codex/bubblewrap 拒絕 top alias | [最新開機架構與可回退部署](references/boot-layout.md) |
| 新 kernel/module/userspace/initramfs 是否一致 | `use-bcachefs dkms-port-check --help`；[版本與 provenance](references/dkms-porting.md) |
| GRUB 預設誤指一次性 canary/bootstrap initrd | `use-bcachefs grub-canary-check --help`；[漂移診斷](references/grub-canary-drift.md) |
| locate 結果空白 | 下節 plocate |
| bcachefs swapfile 回 Invalid argument | 下節 swap |

目前驗證的架構是 initramfs **先 bind 子卷，再卸 top alias**，非原生
`subvol=` mount；`bcachefs_subvol` 是自訂 hook 參數。不要僅刪 fstab 的 bind
列、永久停用 sandbox，或把 `panic=5` 當作所有 Emergency mode 的保證。

## plocate / updatedb

症狀：已知檔案查無結果，plocate DB 近乎只有 header，更新服務卻 exit 0。
bcachefs 子卷可能有相同 `st_dev`；無對應支援的 updatedb 會把它們當 bind
mount，於 `PRUNE_BIND_MOUNTS="yes"` 時跳過。

先核對 `/etc/updatedb.conf`、DB 大小與 `stat` 的 device ID，再於獲授權後
改 `PRUNE_BIND_MOUNTS="no"`，執行 `updatedb` 並用已知檔案驗證。
僅當 top-level 管理掛載存在時，加入相應 `PRUNEPATHS` 避免重複索引；
alias-free 正常開機不需要恢復 `/mnt/bcachefs-top` 或 `/run/bcachefs-top`。
Ubuntu 24.04 plocate 1.1.19 的歷史結果不可推定為所有新版本行為。

## swap

2026-05 驗證環境中，bcachefs 上的 swapfile 回 `swapon: Invalid argument`；
不要套用 btrfs 的 `chattr +C`／offset 做法，亦不要斷言未來所有版本均不支援。
先查目標 kernel 的實際支援；不支援時採 zram 或獨立 swap partition。
已有 systemd-zram-generator 時用 `/etc/systemd/zram-generator.conf`，不要另建
重複 service。RAM 大小、壓縮演算法與容量由主機負載決定，不寫死 60G。

## 安裝與驗證

安裝方式見 [README.md](README.md)。兩個公開命令皆唯讀；不帶參數時以
各自 `--help` 查契約。變更後跑 `tests/` 的 fixture selfchecks；不得讓測試
格式化真實裝置或寫入 `/proc`、`/sys`、`/dev`。
