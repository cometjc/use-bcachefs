# 手動 GRUB canary/bootstrap 設定殘留導致預設開機項目漂移

## 症狀

- `sudo reboot`（未武裝 `next_entry` one-shot）後，`saved_entry` 指向的
  `bcachefs-root-default` 沒有進入預期的最新 kernel/stock initramfs，
  而是掛載了一個數月前建立的一次性 canary 或 bootstrap initrd。
- 開機 log 出現 `Version downgrade required`、
  `junk at end accounting key, deleting`；`bcachefs show-super` 回報的
  `Version:` 欄位比先前確認過的版本低（例如已知在跑 1.39，這次卻顯示
  1.28）。
- `/usr/sbin/bcachefs version` 顯示的是 in-tree stock 版本，而非先前
  `bcachefs-module-local.sh install` 裝好的版本。

## 根因

這套系統把 `update-grub`（`/usr/sbin/update-grub`）以 `dpkg-divert`
改指向自訂的 `update-grub-manual-bcachefs` wrapper；該 wrapper 讀取
`/etc/default/bcachefs-manual-grub`，交給
`render_manual_grub_cfg.py` 渲染整份 `/boot/grub/grub.cfg`。

`bcachefs-module-local.sh stage-canary` 與
`tools/bcachefs-module-package/bcachefs-bootstrap.sh` 都會在這份設定檔寫入
`MANUAL_GRUB_CANARY_*`／`MANUAL_GRUB_BOOTSTRAP_*` 變數，讓 renderer 多產生一個
one-shot GRUB entry。**這些變數只影響「多產生一個 entry」，不影響
`bcachefs-root-default` 本身**——但 renderer 的
`discover_versions()` 永遠把 `bcachefs-root-default` 綁到
`/boot` 目錄下**目前實際存在的最新 kernel/initrd 對**。

如果 canary/bootstrap 用完後，`remove-canary` 或等效清理沒有執行（例如
canary 生命週期外的 `/boot` 檔案被手動增刪，導致
`bcachefs-module-local.sh remove-canary` 之後因 `canary grub config drift`
拒絕自動清除），這些變數會**在設定檔裡長期殘留**。只要之後任何原因
（例如安裝新版 module 觸發 `update-initramfs`，或維護時手動重跑
`update-grub-manual-bcachefs`）造成 grub.cfg 被**重新渲染**，殘留的
`MANUAL_GRUB_CANARY_INITRD`／`MANUAL_GRUB_BOOTSTRAP_INITRD` 就会又被
renderer 讀到，重新產生對應 entry；若當時 `/boot` 目錄裡「最新版本」剛好
就是這個殘留 initrd 所屬的 kernel release，`bcachefs-root-default`
就會被連帶指向這個舊 one-shot 影像，而不是預期的正常 initramfs。

`saved_entry` 一旦被 GRUB 寫回 `bcachefs-root-default`（沒有
`next_entry` one-shot 保護的正常重開），就會直接載入這個舊 canary/
bootstrap initrd。若該 initrd 內含的 module 版本比磁碟上 superblock 記錄
的版本舊，舊版 driver 會對不認識的新格式 metadata 做「安全但有損」的
處理（丟棄、降級 superblock 版本），即使沒有 fsck 報錯或 panic。

## 為何容易被忽略

- 這個殘留設定平時完全無害：只要每次重開機都靠
  `grub-reboot`／`next_entry` one-shot 導向正確 entry，
  `bcachefs-root-default` 的實際內容從未被真正走到。
- 只有在「一次沒有武裝 one-shot 的普通重開」，或「one-shot 目標選錯／被
  消耗後自然退回」時，才會真正踩到這個綁定，因此可能間隔數月才觸發。
- `bcachefs-module-local.sh remove-canary` 本身有 `canary grub config
  drift` fail-closed 保護，但這只防止「用錯誤的 before/after 快照覆寫掉
  之後的合法變更」，不會主動提醒「這個殘留其實已經開始影響
  `bcachefs-root-default`」。

## 診斷

```bash
use-bcachefs grub-canary-check
```

`FAIL` 訊息會分別指出：設定檔殘留但檔案已不存在的 canary/bootstrap 變數；
或渲染後 `bcachefs-root-default` 目前正綁定到 canary/bootstrap 影像。

## 修復

1. 若 canary/bootstrap 生命週期仍在管理中（`arm-canary` 尚未 disarm、
   `remove-canary` 沒有 drift），優先用
   `bcachefs-module-local.sh remove-canary --kernel-release KREL` 走正式
   流程。
2. 若 `remove-canary` 因 config drift 拒絕（例如之後又合法追加了
   `MANUAL_GRUB_BOOTSTRAP_*`），先手動比對
   `/var/lib/bcachefs-module-local/canary/KREL/grub-config.before`／
   `.after` 與目前設定檔的差異，確認差異只包含合法的後續追加，備份目前
   設定檔後手動移除 canary 那幾行，保留合法追加的部分。
3. 執行 `update-grub-manual-bcachefs`（或等效 wrapper）重新渲染
   `grub.cfg`，並用 `use-bcachefs grub-canary-check`、
   `grub-script-check /boot/grub/grub.cfg` 確認乾淨。
4. 清除已無 entry 引用的舊 one-shot initrd 檔案與對應的
   `/var/lib/bcachefs-module-local/canary/KREL` 狀態目錄，避免占用
   `/boot` 空間。

## 規則

- 每次完成 canary／bootstrap 一次性驗證流程後，必須確認
  `/etc/default/bcachefs-manual-grub` 已清除對應變數，而不能只靠
  `next_entry` one-shot 被消耗來判斷「已經沒事了」。
- 任何觸發 `update-grub`／grub.cfg 重新渲染的操作（安裝新 module、手動
  維護、kernel 套件更新）之後，都應該用 `use-bcachefs grub-canary-check`
  核對 `bcachefs-root-default` 沒有意外綁定到 one-shot 影像。
