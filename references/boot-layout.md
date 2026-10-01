# Alias-free bcachefs 開機架構

狀態：2026-10-01 已在 Linux 7.0.0-30-generic、多裝置 bcachefs root 上
通過預設開機、Docker/exporter、initramfs hook 測試與 restricted Codex
session 驗收。這是經驗證的自訂 initramfs-tools 架構，不是所有發行版預設。

## mount 語意與生命週期

| 階段 | 動作 | 開機後狀態 |
| --- | --- | --- |
| local-premount `zz-bcachefs-multidev-root` | 等所有成員裝置；將整個 FS 掛於 initramfs `/run/bcachefs-top` | 暫存 top mount |
| root handoff | 設 ROOT 指向 `top/@root`、ROOTFLAGS 為 `-o bind`，由 initramfs-tools bind 至 `/root` | `/` 來自 `@root` |
| local-bottom `zz-bcachefs-bind-subvols` | `mount --make-rprivate /`；bind `@home` 到 `/root/home`、`@docker` 到 `/root/var/lib/docker` | 子卷掛載仍在 |
| local-bottom 完成前 | `umount /run/bcachefs-top`，失敗則停止成功路徑 | top alias 不帶進 switch_root |

bind 仍持有底層 superblock；卸 top mount 不會卸掉已建立的子卷 bind。
多裝置 FS 只在頂層掛載時指定成員集合，不需把各子卷當獨立裝置。
不可對正在使用的 root 做遞迴 umount。

此架構的 root 參數示意：

```text
root=bcachefs-root rootfstype=bcachefs bcachefs_members=<member-a>:<member-b> bcachefs_subvol=@root rootwait ro panic=5
```

`bcachefs_members`、`bcachefs_subvol` 由自訂 hook 解析，不是 kernel 原生
mount 選項。舊 hook 可將 `rootflags=subvol=` 作相容輸入；新配置不要使用
`subvol=` 假裝 btrfs 式原生子卷掛載。升級 kernel 後重新核對契約，不宣稱
bcachefs 未來永遠不可能新增原生支援。

## fstab 與 initramfs 的分工

永久 fstab 保留 root FS、獨立 `/boot`、`/boot/efi` 的實際 UUID；不保留
top alias，也不保留來源是 top alias 的 `/home`、Docker bind 列。
**先確認 initramfs 已接管兩個 bind，才移除那些 fstab 列。** root fstab
不得把 `subvol=` 當 kernel 選項；保留當地主機的其他必要項目。

local-bottom 必須驗 ROOTFSTYPE、rootmnt、top mount、子卷與非 symlink
target 目錄，拒絕仍引用 top alias 的 fstab。成員等待需有界；mount／bind／
umount 失敗不得假稱成功。失敗處置須配合已驗證的回退開機入口。

正常 runtime 沒有 `/mnt/bcachefs-top` 或 `/run/bcachefs-top`。需管理 subvolume
時可在明確授權下短暫掛 top-level，再卸除；期間可能影響 bubblewrap。
不要在同一維護窗內啟動依賴 alias-free 拓撲的新 sandbox；須先驗 alias 已卸。

## 安全部署：one-shot，成功後才固化

1. 備份現行 fstab、initrd、GRUB 設定與預設入口；記錄 hash、kernel release、成員裝置、subvolume 與 rollback 操作。保留已知可開機舊 initrd 和獨立入口，不覆寫唯一回退檔。
2. 建立新的 trial initrd，加入所需 hook、ORDER 與必要 userspace/module；解包核對內容和 provenance。不只把 hook 放到主機 `/etc` 就假稱 initrd 已更新。`zz-bcachefs-verify` 是 post-update 驗證入口，不是 mount 實作；移植時須提供其 verifier。
3. 以拋棄式多裝置 VM 驗成功、缺子卷／bind 失敗、Emergency/rescue 與重開回退；不得格式化主機裝置。配置 one-shot GRUB entry，舊入口仍為正常 fallback；trial fstab 只限本次開機。
4. 明確武裝一次，再重開。`panic=5` 只控制 panic 後重開，不保證 mount failure 或 systemd Emergency mode 自動 panic。針對 initramfs 失敗與 systemd Emergency/rescue 各配置可驗證的有界回退；kernel hang／韌體失敗仍需硬體 watchdog、遠端 console 或現場人員，不保證純軟體覆蓋。
5. 核對 boot ID、cmdline、root/home/Docker 的 mount root、alias 缺席、Docker/exporter、sandbox startup、持久 log 與 rollback。失敗保留證據，不固化；無可觀測回退時等待可現場救援的維護窗。
6. trial 通過才安裝永久 local-bottom hook、更新正式 initrd/fstab/GRUB；再以沒有 trial flag 的預設入口重開驗收。只有第二次驗收通過才宣稱永久部署成功。

永久部署至少保留：舊 initrd、fstab 備份、可選舊入口及人工 rollback 說明。
`use-bcachefs grub-canary-check` 核對 default 未誤指一次性影像；每次 kernel／
initramfs／GRUB 更新後重跑。發布包不攜帶私人 UUID、裝置 serial、boot ID。

## 取證與 sandbox 錯誤分流

```bash
findmnt -no TARGET,FSTYPE,FSROOT --target /
findmnt -no TARGET,FSTYPE,FSROOT --target /home
findmnt -no TARGET,FSTYPE,FSROOT --target /var/lib/docker
findmnt /mnt/bcachefs-top
findmnt /run/bcachefs-top
systemctl is-active docker bcachefs-exporter
use-bcachefs grub-canary-check
```

服務名稱依安裝調整；`bcachefs-exporter` 不等於 prometheus-node-exporter。
alias 查無掛載才是預期結果。用 serial console、持久 boot journal 或回退入口
可讀的獨立 log 留失敗證據；root 尚未 mount 時不能依賴其上的檔案 log。

- `unsupported host mount ... bcachefs-top`：核對 runtime top aliases 或 nested mount，不以停用 sandbox 解決永久配置。
- `app-server socket directory must be a user-owned directory with mode 0700`：另查 socket 目錄 owner/mode 與 namespace 可見性，不等同 mount alias 問題；不要盲目 chmod runtime socket。
- 驗證 sandbox deny 用可拋棄合成 fixture。實際 denied secret 路徑不得為測試而讀取或升權；單次 `true` probe 失敗須記失敗，不當作其他 gate 的成功證據。
