#!/bin/bash
# Prints a go/no-go table of what SeaBee needs from this machine.
# Exit status is non-zero if anything needed to build or run SeaBee is missing.
# Kernel headers are only needed for the test kernel modules, so they only warn.

MIN_KERNEL=5.14
FAILED=0

# https://unix.stackexchange.com/a/567537
# shellcheck disable=SC2329 # invoked indirectly through check
version_greater_equal() {
  printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}

row() {
  # row <GO|NO-GO|WARN> <check> <detail>
  printf "%-6s %-24s %s\n" "$1" "$2" "$3"
  if [ "$1" = "NO-GO" ]; then
    FAILED=1
  fi
}

check() {
  # check <check> <detail> <test command...>
  local name=$1 detail=$2
  shift 2
  if "$@" &>/dev/null; then
    row GO "$name" "$detail"
  else
    row NO-GO "$name" "$detail"
  fi
}

kernel_config() {
  if [ -r /proc/config.gz ]; then
    zcat /proc/config.gz
  elif [ -r "/boot/config-$(uname -r)" ]; then
    cat "/boot/config-$(uname -r)"
  fi
}

KERNEL=$(uname -r)
KERNEL_VERSION=$(echo "$KERNEL" | cut -d- -f1)
LSM_FILE=/sys/kernel/security/lsm

printf "%-6s %-24s %s\n" "STATUS" "CHECK" "DETAIL"

check "kernel >= $MIN_KERNEL" "$KERNEL" version_greater_equal "$KERNEL_VERSION" "$MIN_KERNEL"
BPF_LSM_CONFIG=$(kernel_config | grep '^CONFIG_BPF_LSM=')
check "CONFIG_BPF_LSM" "${BPF_LSM_CONFIG:-not set or kernel config not found}" test "$BPF_LSM_CONFIG" = "CONFIG_BPF_LSM=y"
check "BTF" "/sys/kernel/btf/vmlinux" test -r /sys/kernel/btf/vmlinux

if ! grep -q " /sys/kernel/security securityfs " /proc/mounts; then
  row NO-GO "securityfs mounted" "sudo mount -t securityfs none /sys/kernel/security"
  row NO-GO "BPF LSM active" "cannot read $LSM_FILE"
else
  row GO "securityfs mounted" "/sys/kernel/security"
  LSM_LIST=$(sudo cat "$LSM_FILE" 2>/dev/null)
  check "BPF LSM active" "${LSM_LIST:-cannot read $LSM_FILE}" grep -qw bpf <<<"$LSM_LIST"
fi

if grep -q " /sys/fs/bpf bpf " /proc/mounts; then
  row GO "bpffs mounted" "/sys/fs/bpf"
else
  row NO-GO "bpffs mounted" "sudo mount -t bpf bpf /sys/fs/bpf"
fi

check "sudo" "$(command -v sudo || echo 'not found')" sudo -n true
check "clang" "$(clang --version 2>/dev/null | head -n1 || echo 'not found')" command -v clang
check "bpftool" "$(command -v bpftool || echo 'not found')" bpftool version
check "cargo" "$(cargo --version 2>/dev/null || echo 'not found, see make update')" command -v cargo

if [ -d "/lib/modules/$KERNEL/build" ]; then
  row GO "kernel headers" "/lib/modules/$KERNEL/build"
else
  row WARN "kernel headers" "missing, test kernel modules will not build"
fi

if [ -d /run/systemd/system ]; then
  row GO "systemd" "running"
else
  row WARN "systemd" "not running, daemon targets and policy tests need it"
fi

exit $FAILED
