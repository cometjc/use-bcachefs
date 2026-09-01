# bcachefs DKMS 移植檢查

## 邊界

`use-bcachefs dkms-port-check` 僅作唯讀前置查核，不編譯、不安裝、不更新
initramfs，亦不改動實機磁碟或 GRUB。

## 查核項

- source tree 版本：讀取 `VERSION`、`version`、`Cargo.toml` 或 `Makefile`。
- kernel module 版本：由 `modinfo` 讀取 `version`。
- module `vermagic`：首欄須等於目標 kernel release。
- userspace 版本：先執行 `--version`，失敗則執行 `version`，須與 source tree 相同。
- initramfs：須含同名 `*.ko` 或常見壓縮形式。

版本任一不合即失敗；勿以「可載入」或「已編出」代替相容性證明。

## 用法

```bash
use-bcachefs dkms-port-check \
  --source-dir /path/to/bcachefs-tools \
  --kernel-release 7.0.0-30-generic \
  --module /path/to/bcachefs.ko \
  --userspace /path/to/bcachefs \
  --initramfs /boot/initrd.img-7.0.0-30-generic
```

成功僅表示五項靜態條件一致；後續安裝、模組載入與開機驗證仍由系統
維運流程負責。
