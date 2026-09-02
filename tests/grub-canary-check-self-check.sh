#!/usr/bin/env bash
set -eu

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir=$(mktemp -d)
trap 'find "$tmpdir" -mindepth 1 -delete; rmdir "$tmpdir"' EXIT

mkdir -p "$tmpdir/boot/grub"

write_config() {
    cat >"$tmpdir/config" <<EOF
MANUAL_GRUB_BOOT_UUID='deadbeef'
MANUAL_GRUB_ROOT_MEMBERS='/dev/sda:/dev/nvme0n1p3'
MANUAL_GRUB_ROOT_SUBVOL='@root'
MANUAL_GRUB_DISTRO='Linux Mint 22.1 Cinnamon'
$1
EOF
}

write_grub_cfg() {
    local default_initrd=$1
    cat >"$tmpdir/boot/grub/grub.cfg" <<EOF
menuentry 'Linux Mint 22.1 Cinnamon (bcachefs root)' \$menuentry_id_option 'bcachefs-root-default' {
    insmod ext2
    linux /vmlinuz-6.17.0-40-generic root=bcachefs-root rootfstype=bcachefs
    initrd $default_initrd
}
EOF
}

# 1) clean state: no canary/bootstrap vars, default entry uses plain initrd -> PASS
write_config ''
write_grub_cfg '/initrd.img-6.17.0-40-generic'
"$root/scripts/grub-canary-check.sh" \
    --config "$tmpdir/config" --grub-cfg "$tmpdir/boot/grub/grub.cfg"

# 2) config references a canary initrd that does not exist under /boot -> FAIL
write_config 'MANUAL_GRUB_CANARY_INITRD=/initrd.img-6.17.0-40-generic.bcachefs-module-canary'
if "$root/scripts/grub-canary-check.sh" \
    --config "$tmpdir/config" --grub-cfg "$tmpdir/boot/grub/grub.cfg"; then
    printf 'self-check: missing canary initrd unexpectedly passed\n' >&2
    exit 1
fi

# 3) reproduces the actual incident: bcachefs-root-default entry permanently
#    bound to a *.bcachefs-module-canary initrd -> FAIL
write_config ''
write_grub_cfg '/initrd.img-6.17.0-40-generic.bcachefs-module-canary'
if "$root/scripts/grub-canary-check.sh" \
    --config "$tmpdir/config" --grub-cfg "$tmpdir/boot/grub/grub.cfg"; then
    printf 'self-check: canary-bound default entry unexpectedly passed\n' >&2
    exit 1
fi

# 4) bcachefs-root-default entry permanently bound to a bootstrap initrd -> FAIL
write_grub_cfg '/initrd.img-7.0.0-30-generic.bcachefs-bootstrap'
if "$root/scripts/grub-canary-check.sh" \
    --config "$tmpdir/config" --grub-cfg "$tmpdir/boot/grub/grub.cfg"; then
    printf 'self-check: bootstrap-bound default entry unexpectedly passed\n' >&2
    exit 1
fi

# 5) config references a bootstrap initrd that does exist -> PASS
: >"$tmpdir/boot/initrd.img-7.0.0-30-generic.bcachefs-bootstrap"
write_config 'MANUAL_GRUB_BOOTSTRAP_INITRD=/initrd.img-7.0.0-30-generic.bcachefs-bootstrap'
write_grub_cfg '/initrd.img-6.17.0-40-generic'
"$root/scripts/grub-canary-check.sh" \
    --config "$tmpdir/config" --grub-cfg "$tmpdir/boot/grub/grub.cfg"

"$root/scripts/grub-canary-check.sh" --help >/dev/null
printf 'self-check: PASS\n'
