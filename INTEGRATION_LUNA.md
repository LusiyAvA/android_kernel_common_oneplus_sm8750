# Luna integration notes

## PJZ110 compatibility status: source-built Image is not flashable

The stock `PJZ110_16.0.5.703(CN01)` boot Image was extracted and compared
against the Image produced by this repository.  The stock kernel enables
`CONFIG_HMBIRD_SCHED=y` and contains OnePlus' HMBIRD scheduler implementation
(`enqueue_task_hmbird`, `pick_next_task_hmbird`, and related code).  This
public common-kernel tree has no HMBIRD implementation; it enables
`CONFIG_SLIM_SCHED=y` / sched_ext instead.  The stock vendor modules remain on
the device and were built around the stock scheduler/private ABI.

Replacing only the boot Image therefore mixes incompatible scheduler and
vendor-module contracts.  On the tested device this produced blocked Qualcomm
performance threads, repeated display commit failures, severe flicker, and a
green screen.  Disabling the duplicate in-tree Game Opt implementation did not
fix those symptoms, confirming that Game Opt was a separate collision rather
than the display root cause.

`scripts/luna-verify-pjz110-compatibility.sh` now enforces the observed stock
scheduler/KMI conditions.  CI stops before a normal build when they are not
met.  An explicitly requested research build may still compile a plain Image,
but receives no compatibility attestation, is not patched with KPatch-Next,
and cannot pass the AK3 release workflow.  A flashable source-built kernel
requires the matching HMBIRD implementation and complete device/vendor kernel
sources.  Until those are available, the safe root experiment is patching the
exact stock Image with KPatch-Next while leaving its kernel code intact.

This branch starts from the stock OnePlus 13 common kernel
(`oneplus/sm8750_b_16.0.0_oneplus_13`, Linux 6.6.118,
PJZ110_16.0.9.401(CN01) / android15-6.6-2026-01_r22). The build
workflow first merges the latest Google ACK security release
(see below), then applies the pinned changes listed after it.
Source-level changes are applied by `scripts/luna-integrate.sh`
(idempotent); the merge and the integration are pushed back to
this branch only after a successful build.

## Base update: ACK android15-6.6-2026-07_r11

- The workflow merges the ACK tag
  `android15-6.6-2026-07_r11`
  (`cc1e318bd6fc5a65a436cd6d3f2d7a8fca25271b`) from
  `android.googlesource.com/kernel/common` — the newest Google
  GKI security release for android15-6.6 (the 2026-10 quarterly
  release was not tagged yet). This brings in all Android
  Security Bulletin kernel fixes published after the stock
  2026-01_r22 base, including the official CVE-2026-43499 fix.
- KMI generation is unchanged: `KMI_GENERATION=8` in both the
  stock base and this tag, the pinned toolchain remains clang
  r510928, and the final generic ABI definition matches the ACK
  tag. These are the required static compatibility conditions;
  device boot testing is still required before calling vendor
  module compatibility proven. The kernel sublevel moves forward
  with the LTS branch, as expected for a security-base update.

## KernelSU driver: ReSukiSU v4.2.0-rc3

- Source: `Baka-SU/BakaSU` (the repository that now carries the
  former ReSukiSU release line),
  release tag `v4.2.0-rc3`, commit
  `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`. This is the
  newest published release candidate as of 2026-10-13; unreleased
  `main` commits are intentionally not branded as the RC.
- Vendored under `KernelSU/` (its `kernel/` + `uapi/` +
  `LICENSE`), exposed as the `drivers/kernelsu` symlink, wired
  into `drivers/Makefile` and `drivers/Kconfig` (the upstream
  `setup.sh` layout).
- `KernelSU/kernel/Kbuild` carries three small "luna" patches for
  the vendored (non-git) layout: the version commit count is
  pinned to the ReSukiSU RC count at the pinned commit (4471, so
  the version code is 35171 exactly as with a real clone), the
  tag name is pinned to `v4.2.0-rc3`, and a
  `%BUILD_DATE%` placeholder is added (see version display
  below).
- SUSFS support is built into this driver (its Kconfig provides
  the `KSU_SUSFS` inline-hook choice and all `KSU_SUSFS_*`
  sub-options); the susfs4ksu `10_enable_susfs_for_ksu.patch`
  (written for upstream KernelSU) must NOT be applied on top.
- Note on KPM: this driver intentionally has no compiled-in
  KPM. Its `MANAGE_KPM` ioctls are deprecated upstream; KPM is
  provided by KPatch-Next instead (see below), which this driver
  detects at runtime (`GET_KERNEL_PATCH_IMPLEMENT` -> KPN).
- Reproducible pins for ReSukiSU, SUSFS, and KPatch-Next are
  centralized in `scripts/luna-root-stack.env`; CI also checks the
  downloaded KP-N tools against their upstream SHA-256 digests.

## SUSFS v2.3.0 (latest stable)

- Source: `simonpunk/susfs4ksu` (GitLab), branch
  `gki-android15-6.6`, commit
  `bd7d199ac87808001127e8a6d076832e2938cf0d`
  (`SUSFS_VERSION "v2.3.0"`, latest stable branch head checked on
  2026-10-13). This snapshot removes the obsolete exec hook
  declaration while retaining the v2.3.0 kernel ABI.
- Applied: `kernel_patches/50_add_susfs_in_gki-android15-6.6.patch`
  plus `fs/susfs.c`, `include/linux/susfs.h`,
  `include/linux/susfs_def.h`. The patch applies cleanly to this
  tree (verified by dry-run before first integration).

## CVE-2026-43499 fix

- `patches/cve-2026-43499-rtmutex-6.6.patch` (backport used by
  the cctv18 OnePlus SM8750 builder for this kernel family):
  `remove_waiter()` in `kernel/locking/rtmutex.c` used
  `current` where the waiter's task was required (proxy-lock
  path, `waiter->task != current`), and
  `rt_mutex_start_proxy_lock()` in `rtmutex_api.c` called it
  for any non-zero return instead of only on error. The stock
  2026-01 base did not contain the fix. After the ACK
  2026-07_r11 merge above, the official fix is already in the
  tree and the integrate script detects it (marker:
  `waiter_task` / "never enqueued") and skips this patch; the
  patch is kept as a safeguard for building from the unmerged
  stock base.

## KPatch-Next (KP-N) 0.13.5-2

- Applied to the built kernel image by the workflow, not at
  source level (same method as the cctv18 SM8750 builder):
  `kptools-linux -p -i Image -k kpimg-linux -o Image.kpn`,
  using the pinned `KernelSU-Next/KPatch-Next` release
  **0.13.5-2** (2026-01-20).
- Build artifacts contain both the plain `Image` and the
  KP-N-patched `Image.kpn`.
- KPatch-Next requires `CONFIG_KALLSYMS=y` +
  `CONFIG_KALLSYMS_ALL=y`; the latter is enabled in the
  defconfig for this purpose.

## Configuration (arch/arm64/configs/gki_defconfig)

- `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y` with all
  `CONFIG_KSU_SUSFS_*` sub-features enabled.
- `CONFIG_TMPFS_XATTR=y`, `CONFIG_TMPFS_POSIX_ACL=y`
  (module/mount ecosystem support, as in OnePlus builders).
- `CONFIG_KALLSYMS_ALL=y` (KPatch-Next requirement).
- `CONFIG_OPLUS_GAME_OPT` remains available as an optional in-tree Linux
  6.6 compatibility layer, but it is deliberately disabled for OnePlus 13.
  The stock vendor ramdisk loads `oplus_bsp_game_opt`, which owns
  `/proc/game_opt`; enabling both implementations prevents the vendor module
  from initializing. OnePlus 13 therefore retains the complete vendor Game
  Opt interface instead of the two-entry compatibility subset.
- `CONFIG_RCU_NOCB_CPU_DEFAULT_ALL` is disabled, matching the extracted
  PJZ110 stock configuration.  The earlier all-CPU offload experiment is not
  retained because it adds scheduler/latency risk while device compatibility
  is unresolved.
- BTF: `CONFIG_DEBUG_INFO_BTF=y` was already in the stock
  gki_defconfig; the workflow verifies the `.BTF` section exists
  in the built `vmlinux` (pahole comes from the `dwarves`
  package; the compiler is the tree-pinned AOSP clang r510928).

## Version display and kernel name

- KernelSU driver version shown in the manager is generated
  from `CONFIG_KSU_FULL_NAME_FORMAT` as
  `%TAG_NAME%-%KSU_VERSION%-%BUILD_DATE%-luna`, e.g.
  `v4.2.0-rc3-35171-20261013-luna` (build date is taken at compile
  time; `luna` is the production-line identifier).
- No LOCALVERSION branding was added: the kernel release string
  stays in stock GKI style (`CONFIG_LOCALVERSION="-4k"` as in the
  stock defconfig). `scripts/setlocalversion` is patched to
  strip the `-dirty` marker, because the build tree carries the
  not-yet-committed integration while compiling.

## How the ACK security merge works (run #4 onwards)

Run #3 tried a plain `git merge` of the ACK tag and failed with
~162 conflicts: this tree's git history is a OnePlus re-import and
shares no usable merge base with ACK, so git compared against an
ancient base. Content-wise the base of this tree is exactly ACK
`android15-6.6-2026-01_r22`, so the workflow now merges at content
level with `scripts/luna-ack-merge.py` (base = ACK 2026-01_r22
tree, theirs = ACK 2026-07_r11 tree): files changed on only one
side are taken from that side; files changed on both sides go
through `git merge-file`. A successful merge writes
`scripts/luna-ack-2026-07-r11.applied`; later builds detect this
tracked marker and skip replaying the merge over SUSFS-modified files.

Measured for 2026-01_r22 -> 2026-07_r11: 2750 files take the ACK
version, 26 added, 109 deleted, 74 Oplus-only files kept, 19 files
merge cleanly. The remaining 7 both-changed files are pre-resolved
by hand in `patches/ack-merge-resolved/`:

- `android/abi_gki_aarch64_sunxi` - ACK symbol additions win
  (Oplus only added a blank line).
- `fs/erofs/zdata.c` - keep both: ACK's
  `trace_android_vh_erofs_iostat_submit` call and the Oplus
  empty-bio WARN debug block.
- `include/linux/pgsize_migration.h` - ACK file verbatim (Oplus
  had only reordered an include that ACK keeps).
- `kernel/fork.c`, `kernel/sched/core.c`, `kernel/sched/sched.h` -
  keep the Oplus sched_ext (scx) integration and vendor hooks.
  `kernel/sched/core.c.patch` explicitly preserves the stock
  `android_vh_chk_task` hook in the non-SCX fast path; dropping it
  would bypass OnePlus's registered task-selection extension.
- `include/linux/sched.h` - real KABI collision in task_struct:
  Oplus (CONFIG_SLIM_SCHED=y) uses slot 2 for the sched_ext entity
  pointer, ACK uses slot 2 for its new `user_dumpable` field
  (accessed unconditionally from kernel/exit.c and
  kernel/ptrace.c). Resolution: SLIM branch keeps scx at slot 2
  and puts `user_dumpable` at slot 4; the non-SLIM branch takes
  ACK's slot 2 layout. Slots 1-8 appear exactly once per branch,
  so task_struct layout positions are unchanged.
