# SeaBee System Requirements

SeaBee only works on Linux.

SeaBee needs root or 'sudo' or run.

We specifically run tests to ensure support on the following distributions:

* Fedora 41, 42, 43
* RHEL/Rocky 9
* Ubuntu 22.04, 24.04

However, in theory, SeaBee should work on any Linux kernel 5.14+ since we do not rely on any features added after 5.14.

## Fedora 41, 42, 43

Should work out of the box

## RHEL/Rocky 9

Should work out of the box

## Ubuntu 22.04, 24.04

As of Ubuntu 24.04, Ubuntu has the kernel config option `CONFIG_BPF_LSM`, but it does not enable BPF LSM by default.
We must enable it in order for this code to work.

```bash
# get current LSM list
sudo cat /sys/kernel/security/lsm
# edit new GRUB config stub
sudo vim /etc/default/grub.d/99-bpf-lsm.cfg
# add a line with ",bpf" at the end with the current LSM list preceding, something like
# GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} lsm=lockdown,capability,landlock,yama,apparmor,bpf"
#
# update GRUB config
sudo update-grub
# reboot and check LSM list again
sudo reboot
sudo cat /sys/kernel/security/lsm
# If you see 'bpf' in the list, then you are good to go!
```

## WSL2 (Ubuntu)

WSL2 is not one of the environments we test on, but SeaBee can be compiled there.
This was tried with Ubuntu 26.04 on the WSL2 kernel `6.18.33.1-microsoft-standard-WSL2`.

The WSL2 kernel is built with `CONFIG_BPF_LSM` and BTF, but `bpf` is not in its default LSM list.
Without systemd, WSL2 also does not mount securityfs or the BPF filesystem,
so SeaBee cannot check the LSM list or pin its programs until they are mounted.

```bash
# check that the kernel supports BPF LSM
zcat /proc/config.gz | grep -E 'CONFIG_BPF_LSM|CONFIG_LSM='
ls /sys/kernel/btf/vmlinux
# mount securityfs and the BPF filesystem if they are missing
sudo mount -t securityfs none /sys/kernel/security
sudo mount -t bpf bpf /sys/fs/bpf
# get current LSM list
sudo cat /sys/kernel/security/lsm
```

<!-- owner must verify after restart: the kernelCommandLine step below has not been run yet;
remove this comment once `wsl --shutdown` has been done and 'bpf' shows in the LSM list -->
The kernel command line for WSL2 is set from Windows in `%UserProfile%\.wslconfig`.
Add a `kernelCommandLine` with ",bpf" at the end of the current LSM list, something like

```ini
[wsl2]
kernelCommandLine = lsm=capability,landlock,yama,safesetid,selinux,ima,bpf
```

Then run `wsl --shutdown` from Windows, reopen WSL, mount securityfs again,
and check the LSM list. If you see 'bpf' in the list, then you are good to go!
This step restarts every running WSL distribution.

### Limitations

- There is no `linux-headers` package for the WSL2 kernel, so the test kernel modules in
  `tests/kmod_example` and `tests/kmod_test` do not build and `make test` will fail.
- `make run`, `make enable`, and the policy tests use systemd services,
  which need `systemd=true` under `[boot]` in `/etc/wsl.conf`.

## Other Distributions

If you have tested SeaBee on another distribution/environment, and have instructions for how you did it,
please create a PR so we can add those steps to our documentation and benefit anyone who wants to use SeaBee!
