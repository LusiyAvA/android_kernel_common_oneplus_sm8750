# BakaSU RC, SUSFS testing, and KPatch-Next integration

This branch adds the current BakaSU release candidate, SUSFS testing branch,
and a reproducible KPatch-Next post-link step to the OnePlus 13 Android 16
kernel while keeping the original `xkse4_dodge_defconfig` feature set intact.

## Fixed revisions

- Kernel baseline: `75c2486ddccdde89a560d72ed334d92e7563ec8d`
- BakaSU submodule: `v4.2.0-rc3` at
  `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`
- SUSFS: v2.3.0 testing snapshot at
  `64e1690ab3b0d067e7f2c37da03da8c04a26d438` on the
  `gki-android15-6.6-dev` branch of `simonpunk/susfs4ksu`
- KPatch-Next: `0.13.5-2`; its Linux tools are downloaded after the kernel
  link and accepted only when both pinned SHA-256 checks pass
- AnyKernel3: `020dfeccf9d7e962a48400fc94d3e451df92eead`

## Integration mode

- BakaSU is tracked as the `KernelSU` Git submodule.
- `drivers/kernelsu` links to `../KernelSU/kernel`.
- SUSFS uses BakaSU's `SUSFS Inline Hook` mode.
- SUSFS v2.3.0 testing kernel sources and the 6.6 hooks are integrated directly into
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

The device configuration also retains HMBIRD scheduling, BTF,
`CONFIG_KALLSYMS_ALL`, thin LTO, CFI, and the existing per-CPU RCU offload
support. It deliberately does not enable `CONFIG_RCU_NOCB_CPU_DEFAULT_ALL`.

The device local version is `-4k`. It intentionally contains no `optimized`,
`xkse4`, `custom`, `ReSukiSU`, or `SUSFS` marker.

## Build

Initialize the submodule before configuring or building the plain Image:

```sh
git submodule update --init --recursive
make O=out ARCH=arm64 xkse4_dodge_defconfig
make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 Image
```

The `xkse4 OnePlus 13 root-stack build` workflow performs the same device
configuration with the pinned AOSP clang r510928, verifies the root-stack and
HMBIRD/BTF contracts, links the arm64 Image, applies KPatch-Next, and emits
both Plain and KPN AnyKernel3 zips. The exact pins and checksums live in
`scripts/xkse4-root-stack.env`.

Build and packaging success prove source/tool compatibility only. Runtime boot
and display compatibility still require testing on the OnePlus 13; the
workflow does not flash a device or publish a GitHub Release automatically.
