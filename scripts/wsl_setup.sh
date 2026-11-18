#!/bin/bash
# Takes a fresh Ubuntu WSL2 distribution to a SeaBee build.
#
# - installs the packages needed to build SeaBee and its vendored libraries
# - installs Rust with rustup if cargo is missing
# - mounts securityfs and the BPF filesystem if they are missing
# - builds SeaBee with 'make all'
# - prints the .wslconfig line needed to enable BPF LSM
# - runs scripts/check_env.sh
#
# It does not install Docker, Poetry, or the documentation tools. Use
# 'make update' for the full development environment.
set -e

TOP_DIR=$(dirname "$(dirname "$(realpath "$0" || true)")")

SUDO="sudo"
if [ "$EUID" -eq 0 ]; then
  SUDO=""
fi

if ! grep -q "^ID=ubuntu" /etc/os-release; then
  printf "This script only supports Ubuntu\n"
  exit 1
fi

printf "Installing packages needed to build SeaBee\n"
$SUDO apt-get update
$SUDO apt-get install --no-install-recommends -y \
  ca-certificates curl git \
  clang make gcc pkg-config \
  autoconf automake autopoint bison flex gawk perl
# bpftool is only used by the tests, and is not packaged for every release
if apt-cache show bpftool &>/dev/null; then
  $SUDO apt-get install --no-install-recommends -y bpftool
else
  printf "bpftool is not packaged for this release, skipping\n"
fi

if ! command -v cargo &>/dev/null && [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  printf "Rustup not detected. Installing...\n"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
export PATH="$HOME/.cargo/bin:$PATH"
rustup component add rustfmt clippy

# containers cannot mount these, and do not need them to build
if [ ! -f /.dockerenv ]; then
  if ! grep -q " /sys/kernel/security securityfs " /proc/mounts; then
    $SUDO mount -t securityfs none /sys/kernel/security
  fi
  if ! grep -q " /sys/fs/bpf bpf " /proc/mounts; then
    $SUDO mount -t bpf bpf /sys/fs/bpf
  fi
fi

make -C "$TOP_DIR" all

if [ -r /sys/kernel/security/lsm ] && ! $SUDO grep -qw bpf /sys/kernel/security/lsm; then
  printf "\nBPF LSM is not active. Add this to %%UserProfile%%\\.wslconfig on Windows,\n"
  printf "then run 'wsl --shutdown' and run this script again:\n\n"
  printf "[wsl2]\nkernelCommandLine = lsm=%s,bpf\n\n" "$($SUDO cat /sys/kernel/security/lsm)"
fi

"$TOP_DIR"/scripts/check_env.sh
