#!/bin/bash
# Luna integration script for this OnePlus 13 (SM8750, sun) common kernel.
#
# Integrates, with pinned upstream commits:
#   - SukiSU-Ultra "builtin" branch (KernelSU driver with built-in SUSFS
#     inline hooks and SukiSU KPM) as drivers/kernelsu -> ../KernelSU/kernel
#   - SUSFS v2.3.0 kernel side (simonpunk/susfs4ksu, gki-android15-6.6)
#   - defconfig: CONFIG_KSU / CONFIG_KPM / CONFIG_SUKISU_KPM / CONFIG_KSU_SUSFS*
#     (CONFIG_DEBUG_INFO_BTF=y is already in the stock gki_defconfig)
#   - KernelSU driver version display: v<tag>-<version code>-<build date>-luna
#   - No LOCALVERSION branding: kernel release stays in stock GKI style.
#
# The script is idempotent: on an already integrated tree it exits 0.
set -euo pipefail
cd "$(dirname "$0")/.."

SUKISU_COMMIT="70fa0e092a2c81060823f8ae526eac14fdda2930"
SUKISU_TARBALL="https://codeload.github.com/SukiSU-Ultra/SukiSU-Ultra/tar.gz/${SUKISU_COMMIT}"
SUSFS_COMMIT="a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a"
SUSFS_TARBALL="https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/archive.tar.gz?sha=${SUSFS_COMMIT}"

if [ -e drivers/kernelsu/Kconfig ] && grep -q 'SUSFS_VERSION "v2.3.0"' include/linux/susfs.h 2>/dev/null; then
    echo "[luna] Already integrated (SukiSU-Ultra + SUSFS v2.3.0). Skipping."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[luna] Fetching SukiSU-Ultra builtin @ ${SUKISU_COMMIT}"
curl -sL -o "$WORK/sukisu.tar.gz" "$SUKISU_TARBALL"
tar xzf "$WORK/sukisu.tar.gz" -C "$WORK"
SUKISU_SRC="$WORK/SukiSU-Ultra-${SUKISU_COMMIT}"

echo "[luna] Fetching susfs4ksu gki-android15-6.6 @ ${SUSFS_COMMIT}"
curl -sL -o "$WORK/susfs.tar.gz" "$SUSFS_TARBALL"
tar xzf "$WORK/susfs.tar.gz" -C "$WORK"
SUSFS_SRC="$(find "$WORK" -maxdepth 1 -type d -name 'susfs4ksu-*' | head -n1)"

# --- 1. Vendor the KernelSU driver (SukiSU-Ultra builtin) ---
mkdir -p KernelSU
cp -a "$SUKISU_SRC/kernel" KernelSU/kernel
cp -a "$SUKISU_SRC/LICENSE" KernelSU/LICENSE
ln -s ./kernel/include/uapi KernelSU/uapi
rm -f KernelSU/kernel/.gitignore
ln -s ../KernelSU/kernel drivers/kernelsu
grep -q "kernelsu" drivers/Makefile || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
grep -q 'source "drivers/kernelsu/Kconfig"' drivers/Kconfig || \
    sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig

# --- 2. Add CONFIG_SUKISU_KPM alias (selects the real CONFIG_KPM) ---
python3 - << 'PY'
import pathlib
p = pathlib.Path("KernelSU/kernel/Kconfig")
s = p.read_text()
anchor = 'menu "KernelSU - SUSFS"'
alias = '''config SUKISU_KPM
    bool "Enable SukiSU KPM (SUKISU_KPM)"
    depends on KSU && 64BIT
    select KPM
    default n
    help
      Alias switch for the SukiSU KPM feature: enabling SUKISU_KPM
      selects KPM. Kept so defconfigs can use CONFIG_SUKISU_KPM=y.

'''
assert anchor in s, "Kconfig anchor not found"
if "config SUKISU_KPM" not in s:
    s = s.replace(anchor, alias + anchor, 1)
    p.write_text(s)
print("[luna] Kconfig: CONFIG_SUKISU_KPM alias present")
PY

# --- 3. Driver version display: v<tag>-<code>-<build date>-luna ---
python3 - << 'PY'
import pathlib
p = pathlib.Path("KernelSU/kernel/Makefile")
s = p.read_text()
old = 'KSU_VERSION_FULL := $(if $(call git_short_sha),v$(VERSION_TAG)-$(call git_short_sha)@$(call git_branch),v$(VERSION_TAG)-$(REPO_NAME)-unknown@unknown)'
new = 'BUILD_DATE := $(shell date -u +%Y%m%d)\nKSU_VERSION_FULL := v$(VERSION_TAG)-$(KSU_VERSION)-$(BUILD_DATE)-luna'
assert old in s, "Makefile version line not found"
if "BUILD_DATE" not in s:
    s = s.replace(old, new, 1)
    p.write_text(s)
print("[luna] Makefile: version display = v<tag>-<code>-<date>-luna")
PY

# --- 4. SUSFS v2.3.0 kernel side ---
cp "$SUSFS_SRC/kernel_patches/fs/susfs.c" fs/
cp "$SUSFS_SRC/kernel_patches/include/linux/susfs.h" include/linux/
cp "$SUSFS_SRC/kernel_patches/include/linux/susfs_def.h" include/linux/
patch -p1 < "$SUSFS_SRC/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
grep -q 'SUSFS_VERSION "v2.3.0"' include/linux/susfs.h
echo "[luna] SUSFS v2.3.0 kernel side applied"

# --- 5. defconfig ---
if ! grep -q "^CONFIG_KSU=y" arch/arm64/configs/gki_defconfig; then
cat >> arch/arm64/configs/gki_defconfig << 'EOF'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIG_SUKISU_KPM=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
fi
grep -q "^CONFIG_DEBUG_INFO_BTF=y" arch/arm64/configs/gki_defconfig && \
    echo "[luna] defconfig: CONFIG_DEBUG_INFO_BTF=y (stock) confirmed"
echo "[luna] Integration done."
