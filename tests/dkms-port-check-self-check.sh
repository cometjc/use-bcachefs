#!/usr/bin/env bash
set -eu

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir=$(mktemp -d)
trap 'find "$tmpdir" -mindepth 1 -delete; rmdir "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/source"
printf '1.39.4\n' >"$tmpdir/source/VERSION"
touch "$tmpdir/bcachefs.ko" "$tmpdir/initramfs.img"
cat >"$tmpdir/bin/modinfo" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    version) printf '1.39.4\n' ;;
    vermagic) printf '7.0.0-30-generic SMP mod_unload\n' ;;
    *) exit 1 ;;
esac
EOF
cat >"$tmpdir/bin/lsinitramfs" <<'EOF'
#!/usr/bin/env bash
printf 'usr/lib/modules/7.0.0-30-generic/updates/bcachefs.ko\n'
EOF
cat >"$tmpdir/userspace" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "version" ]; then
    printf 'bcachefs version: v1.39.4\n'
    exit 0
fi
exit 2
EOF
chmod +x "$tmpdir/bin/modinfo" "$tmpdir/bin/lsinitramfs" "$tmpdir/userspace"

PATH="$tmpdir/bin:$PATH" "$root/scripts/dkms-port-check.sh" \
    --source-dir "$tmpdir/source" \
    --kernel-release 7.0.0-30-generic \
    --module "$tmpdir/bcachefs.ko" \
    --userspace "$tmpdir/userspace" \
    --initramfs "$tmpdir/initramfs.img"

if PATH="$tmpdir/bin:$PATH" "$root/scripts/dkms-port-check.sh" \
    --source-dir "$tmpdir/source" \
    --kernel-release wrong-kernel \
    --module "$tmpdir/bcachefs.ko" \
    --userspace "$tmpdir/userspace" \
    --initramfs "$tmpdir/initramfs.img"; then
    printf 'self-check: mismatch unexpectedly passed\n' >&2
    exit 1
fi

"$root/scripts/dkms-port-check.sh" --help >/dev/null
printf 'self-check: PASS\n'
