# Luna integration notes

This branch is the stock OnePlus 13 common kernel
(`oneplus/sm8750_b_16.0.0_oneplus_13`, Linux 6.6.118,
PJZ110_16.0.9.401(CN01) / android15-6.6-2026-01_r22) plus the
following pinned changes. Everything is applied by
`scripts/luna-integrate.sh` (idempotent) and built by
`.github/workflows/luna-build.yml`; the integration is committed
back to this branch only after a successful build.

## KernelSU driver: SukiSU-Ultra (builtin)

- Source: `SukiSU-Ultra/SukiSU-Ultra`, branch `builtin`,
  commit `70fa0e092a2c81060823f8ae526eac14fdda2930`
- Vendored under `KernelSU/` (its `kernel/` + `LICENSE`, with the
  `uapi` symlink kept), exposed as `drivers/kernelsu` symlink,
  wired into `drivers/Makefile` and `drivers/Kconfig`
  (the upstream `setup.sh` layout).
- The older `ReSukiSU/ReSukiSU` line was renamed to
  `Baka-SU/BakaSU` and no longer ships KPM in the kernel driver,
  which is why the SukiSU-Ultra builtin line is used here.
- SUSFS support is built into this driver (SUSFS inline hooks);
  the susfs4ksu `10_enable_susfs_for_ksu.patch` (written for
  upstream KernelSU) must NOT be applied on top.

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

## Configuration (arch/arm64/configs/gki_defconfig)

- `CONFIG_KSU=y`
- KPM: `CONFIG_KPM=y`, and `CONFIG_SUKISU_KPM=y` — the latter is
  an alias symbol added to `KernelSU/kernel/Kconfig` that
  `select`s `KPM`, so both lines are real in the final `.config`
  (upstream only defines `CONFIG_KPM`). KPM also selects
  `KALLSYMS` / `KALLSYMS_ALL`.
- `CONFIG_KSU_SUSFS=y` with all `CONFIG_KSU_SUSFS_*`
  sub-features enabled.
- BTF: `CONFIG_DEBUG_INFO_BTF=y` was already in the stock
  gki_defconfig; the workflow verifies the `.BTF` section exists
  in the built `vmlinux` (pahole comes from the `dwarves`
  package; the compiler is the tree-pinned AOSP clang r510928).

## Version display and kernel name

- KernelSU driver version shown in the manager is generated in
  `KernelSU/kernel/Makefile` as
  `v<tag>-<version code>-<build date YYYYMMDD>-luna`
  (build date is taken at compile time; `luna` is the
  production-line identifier).
- No LOCALVERSION branding was added: the kernel release string
  stays in stock GKI style (`CONFIG_LOCALVERSION="-4k"` as in the
  stock defconfig) and builds run on a clean committed tree, so
  no `-dirty` suffix appears.
