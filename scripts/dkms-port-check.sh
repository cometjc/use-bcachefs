#!/usr/bin/env bash
set -eu

usage() {
    cat <<'EOF'
usage: use-bcachefs dkms-port-check --source-dir DIR --kernel-release RELEASE
       --module FILE --userspace FILE --initramfs FILE

Read-only DKMS port preflight. Checks source, kernel module, userspace, and
initramfs versions without compiling, installing, updating initramfs, or
changing disks or GRUB.

required arguments:
  --source-dir DIR       bcachefs-tools source tree
  --kernel-release NAME  target kernel release, such as 7.0.0-30-generic
  --module FILE          built bcachefs kernel module
  --userspace FILE       bcachefs userspace executable
  --initramfs FILE       target initramfs image

exit status:
  0 all checks passed
  1 a supplied artifact or compatibility check failed
  2 invalid usage or missing required tool
EOF
}

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

source_dir=
kernel_release=
module_file=
userspace=
initramfs=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source-dir)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            source_dir=$2
            shift 2
            ;;
        --kernel-release)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            kernel_release=$2
            shift 2
            ;;
        --module)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            module_file=$2
            shift 2
            ;;
        --userspace)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            userspace=$2
            shift 2
            ;;
        --initramfs)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            initramfs=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$source_dir" ] || [ -z "$kernel_release" ] || [ -z "$module_file" ] ||
    [ -z "$userspace" ] || [ -z "$initramfs" ]; then
    usage >&2
    exit 2
fi

case "$kernel_release" in
    ''|*[!A-Za-z0-9._+-]*) die "invalid kernel release: $kernel_release" ;;
esac
[ -d "$source_dir" ] || die "source directory not found: $source_dir"
[ -f "$module_file" ] || die "module not found: $module_file"
[ -x "$userspace" ] || die "userspace executable not found: $userspace"
[ -f "$initramfs" ] || die "initramfs not found: $initramfs"
command -v modinfo >/dev/null 2>&1 || {
    printf 'FAIL: required tool not found: modinfo\n' >&2
    exit 2
}
command -v lsinitramfs >/dev/null 2>&1 || {
    printf 'FAIL: required tool not found: lsinitramfs\n' >&2
    exit 2
}

read_version_file() {
    local file=$1 value
    [ -f "$file" ] || return 1
    value=$(awk 'NF { print $1; exit }' "$file")
    case "$value" in
        ''|*[!0-9A-Za-z._+-]*) return 1 ;;
        *) printf '%s\n' "$value" ;;
    esac
}

source_version=
for candidate in "$source_dir/VERSION" "$source_dir/version"; do
    if source_version=$(read_version_file "$candidate"); then
        break
    fi
    source_version=
done
if [ -z "$source_version" ] && [ -f "$source_dir/Cargo.toml" ]; then
    source_version=$(awk -F '"' '
        /^[[:space:]]*version[[:space:]]*=/ { print $2; exit }
    ' "$source_dir/Cargo.toml")
fi
if [ -z "$source_version" ] && [ -f "$source_dir/Makefile" ]; then
    source_version=$(awk '
        /^[[:space:]]*VERSION[[:space:]]*[:?+]?=/ {
            value=$0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            print value
            exit
        }
    ' "$source_dir/Makefile")
fi
[ -n "$source_version" ] || die "source version not found in VERSION, version, Cargo.toml, or Makefile"
source_version=${source_version#v}

module_version=$(modinfo -F version "$module_file" 2>/dev/null || true)
module_vermagic=$(modinfo -F vermagic "$module_file" 2>/dev/null || true)
[ -n "$module_version" ] || die "module version unavailable: $module_file"
[ -n "$module_vermagic" ] || die "module vermagic unavailable: $module_file"
module_version=${module_version#v}
module_kernel=${module_vermagic%% *}
[ "$module_kernel" = "$kernel_release" ] ||
    die "module vermagic kernel mismatch: expected $kernel_release, got $module_kernel"

userspace_output=$("$userspace" --version 2>&1 || "$userspace" version 2>&1) ||
    die "userspace version command failed: $userspace"
userspace_version=$(printf '%s\n' "$userspace_output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
[ -n "$userspace_version" ] || die "userspace version not found: $userspace"
userspace_version=${userspace_version#v}

[ "$source_version" = "$module_version" ] ||
    die "source/module version mismatch: $source_version != $module_version"
[ "$source_version" = "$userspace_version" ] ||
    die "source/userspace version mismatch: $source_version != $userspace_version"

module_base=$(basename "$module_file")
module_name=${module_base%%.ko*}
case "$module_name" in
    ''|*[!A-Za-z0-9_-]*) die "invalid module filename: $module_base" ;;
esac
initramfs_listing=$(lsinitramfs -l "$initramfs" 2>/dev/null) ||
    die "cannot inspect initramfs: $initramfs"
printf '%s\n' "$initramfs_listing" |
    grep -Eq "(^|/)${module_name}\.ko(\.(xz|zst|gz|lz4|lzma))?$" ||
    die "module absent from initramfs: $module_name"

printf 'PASS: source=%s module=%s userspace=%s kernel=%s initramfs=%s\n' \
    "$source_version" "$module_version" "$userspace_version" "$kernel_release" "$module_name"
