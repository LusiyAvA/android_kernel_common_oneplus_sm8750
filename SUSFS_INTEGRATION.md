# ReSukiSU and SUSFS integration

This branch adds ReSukiSU and SUSFS to the OnePlus 13 Android 16 kernel while
keeping the original `xkse4_dodge_defconfig` feature set intact.

## Fixed revisions

- Kernel baseline: `75c2486ddccdde89a560d72ed334d92e7563ec8d`
- ReSukiSU submodule: `ca62a37fc328e6cb836ea6d77b7eab0c073104a6`
- SUSFS: v2.2.0, sourced from
  `e7b28525f69ca5864bed7db51f77663f5adfe218` on the
  `gki-android15-6.6` branch of `simonpunk/susfs4ksu`

## Integration mode

- ReSukiSU is tracked as the `KernelSU` Git submodule.
- `drivers/kernelsu` links to `../KernelSU/kernel`.
- SUSFS uses ReSukiSU's `SUSFS Inline Hook` mode.
- SUSFS v2.2.0 kernel sources and the 6.6 hooks are integrated directly into
  the kernel tree.
- The `fs/proc/task_mmu.c` hunk is merged around the existing OnePlus
  `vma_data_pages()` implementation rather than replacing that implementation.

## Configuration

Both `gki_defconfig` and `xkse4_dodge_defconfig` enable:

```text
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
```

The SUSFS feature defaults enable SUS_PATH, SUS_MOUNT, SUS_KSTAT,
SPOOF_UNAME, SPOOF_CMDLINE_OR_BOOTCONFIG, OPEN_REDIRECT, SUS_MAP, log control,
and KSU/SUSFS symbol filtering.

The device local version is `-4k`. It intentionally contains no `optimized`,
`xkse4`, `custom`, `ReSukiSU`, or `SUSFS` marker.

## Build

Initialize the submodule before configuring or building:

```sh
git submodule update --init --recursive
make O=out ARCH=arm64 xkse4_dodge_defconfig
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 Image
```

The integration was checked with the device defconfig, all seven ReSukiSU
inline hooks, SUSFS v2.2.0 detection, SELinux compatibility hooks, BTF, and a
complete arm64 `Image` link. Runtime boot compatibility still requires testing
on a OnePlus 13.
