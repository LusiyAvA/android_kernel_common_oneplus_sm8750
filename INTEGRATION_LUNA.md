# Luna integration notes

This branch is the stock OnePlus 13 common kernel
(`oneplus/sm8750_b_16.0.0_oneplus_13`, Linux 6.6.118,
PJZ110_16.0.9.401(CN01) / android15-6.6-2026-01_r22) plus the
following pinned changes. Everything is applied by
`scripts/luna-integrate.sh` (idempotent) and built by
`.github/workflows/luna-build.yml`; the integration is committed
back to this branch only after a successful build.

## KernelSU driver: ReSukiSU (BakaSU)

- Source: `Baka-SU/BakaSU` (the renamed ReSukiSU project), branch
  `main`, commit `c9246641b9eee8b9986050e8bf1832f88da880c2`
- Vendored under `KernelSU/` (its `kernel/` + `uapi/` +
  `LICENSE`), exposed as the `drivers/kernelsu` symlink, wired
  into `drivers/Makefile` and `drivers/Kconfig` (the upstream
  `setup.sh` layout).
- `KernelSU/kernel/Kbuild` carries three small "luna" patches for
  the vendored (non-git) layout: the version commit count is
  pinned to the BakaSU main count at the pinned commit (4517, so
  the version code is 35217 exactly as with a real clone), the
  tag name is pinned to `v4.1.0` (latest stable tag), and a
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

## SUSFS v2.3.0 (latest stable)

- Source: `simonpunk/susfs4ksu` (GitLab), branch
  `gki-android15-6.6`, commit
  `a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a` (2026-09-26,
  `SUSFS_VERSION "v2.3.0"`, includes post-release fixes of the
  2.3.0 stable line)
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
  tree did not contain the fix; the patch applies with a small
  offset and is applied by the integrate script.

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
- BTF: `CONFIG_DEBUG_INFO_BTF=y` was already in the stock
  gki_defconfig; the workflow verifies the `.BTF` section exists
  in the built `vmlinux` (pahole comes from the `dwarves`
  package; the compiler is the tree-pinned AOSP clang r510928).

## Version display and kernel name

- KernelSU driver version shown in the manager is generated
  from `CONFIG_KSU_FULL_NAME_FORMAT` as
  `%TAG_NAME%-%KSU_VERSION%-%BUILD_DATE%-luna`, e.g.
  `v4.1.0-35217-20261007-luna` (build date is taken at compile
  time; `luna` is the production-line identifier).
- No LOCALVERSION branding was added: the kernel release string
  stays in stock GKI style (`CONFIG_LOCALVERSION="-4k"` as in the
  stock defconfig). `scripts/setlocalversion` is patched to
  strip the `-dirty` marker, because the build tree carries the
  not-yet-committed integration while compiling.
