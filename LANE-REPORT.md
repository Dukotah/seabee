# LANE 8 report: seabee

## 1. Upstream contribution rules (CONTRIBUTING.md)

- Search existing issues first; opening a dialogue (issue) before implementing is strongly recommended.
- Smallest reasonable change; no refactors, renames, or find-and-replace sweeps without authorization.
- No third-party library bumps unless a critical security fix (open an issue instead).
- Squash to one commit whose message **starts with the issue number**.
- One independent patch per PR; be ready for review questions. A committer (`awandke`) merges.

## 2. Branches

| Branch | Base | Bound for | Commit |
|---|---|---|---|
| `docs/wsl2` | upstream/main | upstream PR | `71c2ab1` Add WSL2 (Ubuntu) steps to the system requirements |
| `fix/43-seabeectl-add-update-apply` | upstream/main | upstream PR (#43) | `9838e38` 43 split seabeectl update into add, update, and apply |
| `lane/wsl-devcontainer` | `docs/wsl2` | fork only | `make check-env`, `scripts/check_env.sh`, `scripts/wsl_setup.sh`, this report |

### A: `docs/wsl2`
Adds a "WSL2 (Ubuntu)" section to `docs/docs/requirements.md`, above "Other Distributions" (which asks
for exactly this). It covers: the WSL2 kernel has `CONFIG_BPF_LSM=y` and BTF, but `bpf` is not an
active LSM; without systemd WSL2 mounts neither securityfs nor bpffs (SeaBee reads
`/sys/kernel/security/lsm` at startup and pins under `/sys/fs/bpf`); the `.wslconfig`
`kernelCommandLine = lsm=...,bpf` step; and limitations (no `linux-headers` for the WSL kernel, so the
test kmods and `make test` fail; `make run`/`enable`/policy tests need `systemd=true`).

**OWNER MUST VERIFY AFTER RESTART:** the `.wslconfig` + `wsl --shutdown` step was NOT run (other lanes
share this WSL VM). The doc carries an HTML comment saying so; delete it before opening the PR once
`sudo cat /sys/kernel/security/lsm` shows `bpf`. Steps:

1. In `%UserProfile%\.wslconfig` under the existing `[wsl2]` add
   `kernelCommandLine = lsm=capability,landlock,yama,safesetid,selinux,ima,bpf`
2. `wsl --shutdown` (PowerShell), reopen Ubuntu.
3. `sudo mount -t securityfs none /sys/kernel/security; sudo mount -t bpf bpf /sys/fs/bpf; sudo cat /sys/kernel/security/lsm`
4. `make check-env` (branch C) should flip "BPF LSM active" to GO; then `sudo target/debug/seabee -s allow`.
   If `bpf` does not appear, the doc's kernelCommandLine claim is wrong and must be fixed before upstreaming.

### B: `fix/43-seabeectl-add-update-apply`
Implements the maintainer's own proposal in #43:
- `seabeectl add` adds, errors if the policy name exists.
- `seabeectl update` updates, errors if the name does not exist.
- `seabeectl apply` = old add-or-update behaviour.

`SocketCommand` gains `Add`/`Apply`; the daemon routes all three through `handle_policy_command` with a
small pure `check_policy_action()` that has 6 unit tests. Integration tests: initial loads use `add`,
updates use `update`, the signed unverified-suite block uses `apply`, `protect_tool` uses `apply`
(keeps old tolerant behaviour), and two new negative tests (`no_update_missing_policy`,
`no_add_existing_policy`). Docs (`seabeectl.md`, `tutorial.md`, `policy_tutorial.md`, autocast demo)
use `add` where a policy is first loaded.
Known gap: tutorial screenshots (`seabeectl-update-help.png`, `update-verify-fail.png`) and
`crypto.md`'s diagram alt text still show `update`; flagged in the PR body for the maintainers.
This is a deliberate breaking change for anyone scripting `seabeectl update` to add policies.

### C: `lane/wsl-devcontainer` (fork only)
- `make check-env` -> `scripts/check_env.sh`: GO/NO-GO/WARN table (kernel >= 5.14, CONFIG_BPF_LSM, BTF,
  securityfs, BPF LSM active, bpffs, sudo, clang, bpftool, cargo; WARN for kernel headers and systemd).
  Non-zero exit on any NO-GO.
- `make wsl-setup` -> `scripts/wsl_setup.sh`: apt build deps, rustup if missing, mounts, `make all`,
  prints the `.wslconfig` line built from the current LSM list, then runs check_env.

## 3. Evidence (WSL Ubuntu 26.04, kernel 6.18.33.1-microsoft-standard-WSL2, cargo 1.100.0)

Environment (no restart):
```
$ zcat /proc/config.gz | grep -E 'BPF_LSM|CONFIG_LSM='
CONFIG_BPF_LSM=y
CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,apparmor,tomoyo"
$ cat /proc/cmdline        # no lsm= argument
initrd=\initrd.img WSL_ROOT_INIT=1 panic=-1 nr_cpus=6 ... console=hvc0 debug ...
$ ls /sys/kernel/btf/vmlinux  -> present
$ sudo mount -t securityfs none /sys/kernel/security && sudo cat /sys/kernel/security/lsm
capability,landlock,yama,safesetid,selinux,ima
$ sudo mount -t bpf bpf /sys/fs/bpf     # rc=0
$ ps -p 1 -o comm=   -> init(Ubuntu)   (no systemd)
$ make -C tests/kmod_example test
make: *** /lib/modules/6.18.33.1-microsoft-standard-WSL2/build: No such file or directory.  Stop.
$ apt-cache search linux-headers | grep -ci wsl  -> 0
```

Build of upstream/main in a clone on ext4 (`~/seabee-wsl`), after `apt-get install autopoint bison flex`:
```
$ make all
warning: unused dependency `strum` / `tempfile` / `tracing-journald`   (pre-existing, cargo 1.100 lint)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 4m 26s
-rwxr-xr-x ... target/debug/seabee
-rwxr-xr-x ... target/debug/seabeectl
$ sudo ./target/debug/seabee -s allow
Error: BPF LSM is not enabled!
Try adding "bpf" to "lsm=" on the kernel command line.
```
(eBPF objects are compiled by `bpf/build.rs` during `cargo build`; that succeeded.)

Docs: `mkdocs build` (uv, mkdocs 1.6 + material 9 per pyproject) -> `Documentation built in 17.80 seconds`,
exit 0, page has `id="wsl2-ubuntu"`.

Branch B:
```
$ cargo test -p seabee
test policy::runtime_update::tests::test_add_existing_policy_fails ... ok
test policy::runtime_update::tests::test_add_new_policy ... ok
test policy::runtime_update::tests::test_apply_existing_policy ... ok
test policy::runtime_update::tests::test_apply_new_policy ... ok
test policy::runtime_update::tests::test_update_existing_policy ... ok
test policy::runtime_update::tests::test_update_new_policy_fails ... ok
test result: ok. 14 passed; 0 failed
$ cargo build -p tests            -> Finished (integration test crate compiles)
$ cargo fmt -- --check            -> exit 0
$ cargo clippy --all-targets --all-features --no-deps
  identical warning set to upstream/main (all pre-existing; the 2 in runtime_update.rs are
  upstream lines 318/422, shifted to 334/438). No new warnings.
$ sudo ./target/debug/seabeectl --help
  add               Add a new policy from a path
  update            Update an existing policy from a path
  apply             Add or update a policy from a path
```
NOT run: the root/BPF-LSM integration and policy suites (`make test`) -- they need BPF LSM active,
systemd, and kernel headers, none available here. The new integration tests are compiled, not executed.

Branch C (cheap verification only, after the machine-wide memory stall):
```
$ make check-env
GO     kernel >= 5.14           6.18.33.1-microsoft-standard-WSL2
GO     CONFIG_BPF_LSM           CONFIG_BPF_LSM=y
GO     BTF                      /sys/kernel/btf/vmlinux
GO     securityfs mounted       /sys/kernel/security
NO-GO  BPF LSM active           capability,landlock,yama,safesetid,selinux,ima
GO     bpffs mounted            /sys/fs/bpf
GO     sudo / clang 21.1.8 / bpftool / cargo 1.100.0
WARN   kernel headers           missing, test kernel modules will not build
WARN   systemd                  not running, daemon targets and policy tests need it
make: *** [Makefile] Error 2      (non-zero because of the NO-GO, as intended)
$ bash -n scripts/*.sh -> OK;  shellcheck scripts/check_env.sh scripts/wsl_setup.sh -> clean
```
**`wsl_setup.sh` zero-to-build was NOT verified end to end.** A docker `ubuntu:24.04` run was started
but was killed during the image pull by the machine-wide memory stall and not re-run (coordinator
constraint). Each of its steps was run by hand on this distro (apt packages, mounts, `make all`), but
not as one script on a fresh install.

## 4. Competing work check

- `gh search issues/prs WSL` on NationalSecurityAgency/seabee: none.
- #43: no comments, no linked PR. Open PRs touching the same files (merge-conflict risk, not
  duplicates): #63 (add-key overwrite, runtime_update.rs), #66 (socket retry, runtime_update.rs +
  seabeectl_lib.rs), #76 (keygen, seabeectl_lib.rs + seabeectl.md), #78 (multi-label,
  runtime_update.rs + tests/src/policy/shared.rs + verified_policy.rs), #79 (show-config,
  seabeectl_lib.rs + seabeectl.md + verified_policy.rs). Most are from theyottaboy's 15-PR burst.
- #70/#71 (theyottaboy) change tests/Makefile for missing kernel headers; if merged, the WSL doc's
  "`make test` will fail" line should be softened.
- #3 (audit output tests) was not picked: its harness needs root + active BPF LSM, unrunnable here.

## 5. Draft upstream text

### A: issue (open first; then set the commit subject to "<N> add WSL2 (Ubuntu) steps to requirements")

Title: Document running SeaBee on WSL2 (Ubuntu)

> The requirements page asks for steps from other environments. I have SeaBee building on WSL2
> (Ubuntu 26.04, kernel 6.18.33.1-microsoft-standard-WSL2) and found a few WSL-specific steps:
>
> - The WSL2 kernel has `CONFIG_BPF_LSM=y` and BTF, but `bpf` is not in the active LSM list
>   (`capability,landlock,yama,safesetid,selinux,ima`). It can be added from Windows with
>   `kernelCommandLine = lsm=...,bpf` in `%UserProfile%\.wslconfig` and `wsl --shutdown`.
> - Without systemd, WSL2 does not mount securityfs or the BPF filesystem, so `seabee` cannot read
>   `/sys/kernel/security/lsm` or pin programs until they are mounted by hand.
> - There is no `linux-headers` package for the WSL2 kernel, so the test kernel modules and
>   `make test` do not build.
>
> I'd like to add a short "WSL2 (Ubuntu)" section to `docs/docs/requirements.md` with these steps,
> marked as tested-but-unsupported. Happy to open a PR if that's welcome.

### A: PR

Title: `<N> add WSL2 (Ubuntu) steps to the system requirements`

> Closes #N.
>
> Adds a "WSL2 (Ubuntu)" section to the system requirements, as invited under "Other Distributions":
> how to check the WSL2 kernel for BPF LSM support, mount securityfs and the BPF filesystem, enable
> `bpf` through `.wslconfig`, and the known limitations (no kernel headers for the test modules,
> systemd needed for the daemon targets).
>
> Tested on Ubuntu 26.04 / WSL kernel 6.18.33.1: `make all` builds, `mkdocs build` renders the page,
> and after enabling `bpf` in the LSM list `seabee` starts past the BPF LSM check.
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

(Owner: only keep the last sentence if the restart check in section 2 passed.)

### B: comment on #43 (post first, wait for a nod)

> I'd like to pick this up if it's still wanted. Plan, following the semantics in the issue:
> `add` errors if the policy name exists, `update` errors if it doesn't, and `apply` keeps today's
> add-or-update behaviour. The existence check would be a small pure function with unit tests, the
> integration tests would use `add`/`update`/`apply` as appropriate (plus two negative tests), and the
> docs/tutorial would use `add` for first loads. Since this changes what `seabeectl update` does for
> new policies, is that breaking change OK, and do you want the tutorial screenshots left for your
> team to regenerate?

### B: PR

Title: `43 split seabeectl update into add, update, and apply`

> Closes #43.
>
> - `seabeectl add` adds a new policy and errors if a policy with the same name exists
> - `seabeectl update` updates an existing policy and errors if none exists
> - `seabeectl apply` adds or updates (the previous `update` behaviour)
>
> The daemon routes all three through one handler; the existence rule is `check_policy_action()`,
> covered by unit tests. Integration tests use `add` for initial loads, `update` for updates, `apply`
> where the old behaviour was relied on, and add `no_update_missing_policy` and
> `no_add_existing_policy`. Docs and the autocast demo use `add` for first loads.
>
> Not updated: the tutorial screenshots `seabeectl-update-help.png` / `update-verify-fail.png` and the
> `create-policy.png` diagram still show `update`.
>
> Testing: `cargo test -p seabee` (14 passed), `cargo fmt --check`, `cargo clippy` (no new warnings),
> `cargo build -p tests`. I could not run the root integration/policy suites locally (no BPF LSM
> host); CI or a reviewer run would be appreciated.
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 6. Land probability and next steps

- **A: Med-High.** The docs explicitly invite other-environment steps and the change is docs-only;
  the risk is the unverified `.wslconfig` step. Owner: do the restart check in section 2, remove the
  HTML comment, open the issue, rename the commit to start with the issue number, open the PR.
- **B: Med.** It implements the maintainer's own proposal, but it is a breaking CLI change, the
  integration suites were not executed here, and five open PRs touch the same files. Owner: post the
  #43 comment, wait for agreement, rebase on whatever lands first, open the PR.
- **C: fork only.** `check-env` verified; `wsl-setup` needs one fresh-distro run before it is advertised.

Note: commits use the `Co-Authored-By: Claude Fable 5.1` trailer required by LANE-RULES; the work was
actually done by Claude Opus 5.5. Change the trailer before upstreaming if accuracy matters.
