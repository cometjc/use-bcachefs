#!/usr/bin/env bash
set -eu

usage() {
    cat <<'EOF'
usage: use-bcachefs grub-canary-check [--config FILE] [--grub-cfg FILE]

Read-only check for stale bcachefs manual-GRUB canary/bootstrap state.
Detects the root cause of a known incident: a one-shot canary or bootstrap
section left in the manual-GRUB config after the one-shot alternate boot was
consumed, which silently rebinds the permanent default boot entry
(bcachefs-root-default) to a stale alternate initrd on the next re-render.

Checks performed:
  1. config: if MANUAL_GRUB_CANARY_* or MANUAL_GRUB_BOOTSTRAP_* variables
     are present, their referenced initrd file must exist under /boot;
     a variable set with no matching file is stale config drift.
  2. rendered grub.cfg: the bcachefs-root-default entry's initrd line must
     not reference a *.bcachefs-module-canary or *.bcachefs-bootstrap
     image. That combination means the permanent default entry is bound to
     a one-shot alternate image instead of the plain kernel initramfs.

This does not modify config, GRUB, or disks; it also does not require the
canary/bootstrap state machine in bcachefs-module-local.sh to be in any
particular state, since a fully-consumed one-shot round can still leave
config drift behind even after the state directory is otherwise clean.

optional arguments:
  --config FILE    manual-GRUB config file
                    (default: /etc/default/bcachefs-manual-grub)
  --grub-cfg FILE  rendered grub.cfg to inspect
                    (default: /boot/grub/grub.cfg)

exit status:
  0 no stale canary/bootstrap config or drifted default entry found
  1 stale config or drifted default entry found
  2 invalid usage or required input missing
EOF
}

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

config_file=/etc/default/bcachefs-manual-grub
grub_cfg=/boot/grub/grub.cfg

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            config_file=$2
            shift 2
            ;;
        --grub-cfg)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            grub_cfg=$2
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

[ -f "$config_file" ] || die "config not found: $config_file"
[ -f "$grub_cfg" ] || die "grub.cfg not found: $grub_cfg"

boot_dir=$(dirname -- "$grub_cfg")
boot_dir=$(dirname -- "$boot_dir")

read_config_var() {
    local var=$1
    awk -F= -v var="$var" '
        $0 ~ "^"var"=" {
            value = substr($0, length(var) + 2)
            gsub(/^["'"'"']|["'"'"']$/, "", value)
            print value
            exit
        }
    ' "$config_file"
}

stale_found=0

check_prefixed_initrd_var() {
    local prefix=$1 var value
    var="MANUAL_GRUB_${prefix}_INITRD"
    value=$(read_config_var "$var")
    [ -n "$value" ] || return 0
    local resolved="$boot_dir/${value#/}"
    if [ ! -f "$resolved" ]; then
        printf 'FAIL: stale config: %s=%s but %s is missing\n' \
            "$var" "$value" "$resolved" >&2
        stale_found=1
    fi
}

check_prefixed_initrd_var CANARY
check_prefixed_initrd_var BOOTSTRAP

default_entry_block=$(awk '
    /\$menuentry_id_option[[:space:]]+.bcachefs-root-default.[[:space:]]*\{/ { in_block = 1 }
    in_block { print }
    in_block && /^\}/ { exit }
' "$grub_cfg")
[ -n "$default_entry_block" ] || die "bcachefs-root-default entry not found in $grub_cfg"

default_initrd=$(printf '%s\n' "$default_entry_block" |
    awk '/^[[:space:]]*initrd[[:space:]]/ { print $2; exit }')
[ -n "$default_initrd" ] || die "bcachefs-root-default entry has no initrd line"

case "$default_initrd" in
    *.bcachefs-module-canary)
        printf 'FAIL: bcachefs-root-default permanently bound to canary initrd: %s\n' \
            "$default_initrd" >&2
        stale_found=1
        ;;
    *.bcachefs-bootstrap)
        printf 'FAIL: bcachefs-root-default permanently bound to bootstrap initrd: %s\n' \
            "$default_initrd" >&2
        stale_found=1
        ;;
esac

[ "$stale_found" -eq 0 ] || exit 1

printf 'PASS: no stale canary/bootstrap config; bcachefs-root-default initrd=%s\n' \
    "$default_initrd"
