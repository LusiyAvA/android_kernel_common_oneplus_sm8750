#!/bin/bash
# Luna integration script for this OnePlus 13 (SM8750, sun) common kernel.
#
# Integrates, with pinned upstream commits:
#   - ReSukiSU v4.2.0-rc3 (Baka-SU/BakaSU) as
#     drivers/kernelsu -> ../KernelSU/kernel, SUSFS inline-hook mode
#   - SUSFS v2.3.0 kernel side (simonpunk/susfs4ksu, gki-android15-6.6)
#   - CVE-2026-43499 rtmutex fix (patches/cve-2026-43499-rtmutex-6.6.patch)
#   - defconfig: CONFIG_KSU / CONFIG_KSU_SUSFS* / CONFIG_KALLSYMS_ALL
#     (the latter is the KPatch-Next requirement; CONFIG_DEBUG_INFO_BTF=y
#     is already in the stock gki_defconfig)
#   - KernelSU driver version display: v<tag>-<version code>-<build date>-luna
#   - Kernel release stays in stock GKI style: scripts/setlocalversion is
#     patched to strip the "-dirty" marker (the build tree carries the
#     not-yet-committed integration), no LOCALVERSION branding is added.
#
# KPatch-Next itself is applied to the built Image by the workflow
# (kptools + kpimg), it is not a source-level integration.
#
# The script is idempotent: pins live in scripts/luna-root-stack.env and an
# exact-version marker prevents an older integration from being mistaken for
# the requested root stack.
set -euo pipefail
cd "$(dirname "$0")/.."

STACK_ENV="scripts/luna-root-stack.env"
# shellcheck disable=SC1090
source "$STACK_ENV"
: "${BAKASU_TAG:?}" "${BAKASU_COMMIT:?}" "${BAKASU_COMMIT_COUNT:?}" "${BAKASU_VERSION_CODE:?}"
: "${SUSFS_BRANCH:?}" "${SUSFS_VERSION:?}" "${SUSFS_COMMIT:?}"
: "${KPATCH_NEXT_VERSION:?}"
[ "$((30000 + BAKASU_COMMIT_COUNT + 700))" -eq "$BAKASU_VERSION_CODE" ] || {
    echo "[luna] ReSukiSU version-code pin does not match its commit count" >&2
    exit 1
}

BAKASU_TARBALL="https://codeload.github.com/Baka-SU/BakaSU/tar.gz/${BAKASU_COMMIT}"
SUSFS_TARBALL="https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/archive.tar.gz?sha=${SUSFS_COMMIT}"
INTEGRATION_MARKER="scripts/luna-root-stack.applied"

if [ -e KernelSU/kernel/Kconfig ] \
   && grep -qxF "ReSukiSU=${BAKASU_TAG}@${BAKASU_COMMIT}" "$INTEGRATION_MARKER" 2>/dev/null \
   && grep -qxF "SUSFS=${SUSFS_VERSION}@${SUSFS_COMMIT}" "$INTEGRATION_MARKER" 2>/dev/null \
   && grep -qxF "KPatch-Next=${KPATCH_NEXT_VERSION}" "$INTEGRATION_MARKER" 2>/dev/null \
   && grep -qxF "KSU_TAG_NAME    := ${BAKASU_TAG}" KernelSU/kernel/Kbuild \
   && grep -qxF "KSU_LOCAL_VERSION := ${BAKASU_COMMIT_COUNT}" KernelSU/kernel/Kbuild \
   && grep -q 'KERNEL_PATCH_KPN' KernelSU/uapi/supercall.h \
   && grep -q 'do_get_kernel_patch_implement' KernelSU/kernel/supercall/dispatch.c \
   && grep -q "SUSFS_VERSION \"${SUSFS_VERSION}\"" include/linux/susfs.h \
   && ! grep -q '^extern bool __ksu_is_allow_uid_for_current(uid_t uid);$' fs/exec.c; then
    echo "[luna] Root stack already integrated exactly (${BAKASU_TAG} + SUSFS ${SUSFS_VERSION} + KP-N ${KPATCH_NEXT_VERSION})."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[luna] Fetching ReSukiSU ${BAKASU_TAG} @ ${BAKASU_COMMIT}"
curl -sL -o "$WORK/bakasu.tar.gz" "$BAKASU_TARBALL"
tar xzf "$WORK/bakasu.tar.gz" -C "$WORK"
BAKASU_SRC="$WORK/BakaSU-${BAKASU_COMMIT}"

echo "[luna] Fetching susfs4ksu ${SUSFS_BRANCH} @ ${SUSFS_COMMIT}"
curl -sL -o "$WORK/susfs.tar.gz" "$SUSFS_TARBALL"
tar xzf "$WORK/susfs.tar.gz" -C "$WORK"
SUSFS_SRC="$(find "$WORK" -maxdepth 1 -type d -name 'susfs4ksu-*' | head -n1)"

# --- 1. Vendor the KernelSU driver (ReSukiSU RC) ---
mkdir -p KernelSU
rm -rf KernelSU/kernel KernelSU/uapi
cp -a "$BAKASU_SRC/kernel" KernelSU/kernel
cp -a "$BAKASU_SRC/uapi" KernelSU/uapi
cp -a "$BAKASU_SRC/LICENSE" KernelSU/LICENSE
rm -f KernelSU/kernel/.gitignore
if [ -L drivers/kernelsu ]; then
    ln -sfn ../KernelSU/kernel drivers/kernelsu
elif [ -f drivers/kernelsu ] && grep -qxF '../KernelSU/kernel' drivers/kernelsu; then
    # Git for Windows with core.symlinks=false materializes the tracked
    # symlink as a text file. Keep it; Linux CI checks it out as a symlink.
    :
else
    rm -rf drivers/kernelsu
    ln -s ../KernelSU/kernel drivers/kernelsu
fi
grep -q "kernelsu" drivers/Makefile || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
grep -q 'source "drivers/kernelsu/Kconfig"' drivers/Kconfig || \
    sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig

# --- 2. Kbuild pins for the vendored (non-git) layout + %BUILD_DATE% ---
export BAKASU_COMMIT_COUNT BAKASU_TAG
python3 - << 'PY'
import os
import pathlib
p = pathlib.Path("KernelSU/kernel/Kbuild")
s = p.read_text()
# A vendored copy has no ReSukiSU .git of its own; the unshallow fetch and
# the rev-list count would otherwise run against the kernel repo.
old_fetch = "$(shell cd $(KSU_SRC); [ -f ../.git/shallow ] && $(GIT_BIN) fetch --unshallow)"
assert old_fetch in s, "Kbuild unshallow line not found"
s = s.replace(old_fetch, "# luna: vendored copy, skip git fetch --unshallow")
old_count = "KSU_LOCAL_VERSION := $(shell cd $(KSU_SRC); $(GIT_BIN) rev-list --count HEAD)"
assert old_count in s, "Kbuild rev-list line not found"
s = s.replace(
    old_count,
    "# luna: pinned ReSukiSU RC commit count (vendored layout)\n"
    f"KSU_LOCAL_VERSION := {os.environ['BAKASU_COMMIT_COUNT']}",
)
# The vendored copy lives inside the kernel repo, so accept the kernel
# repo's .git (two levels up) in the "is a git checkout" check, and pin
# the tag name (git describe would otherwise see kernel repo tags).
old_check = "test -e $(KSU_SRC)/../.git"
assert old_check in s, "Kbuild git-exists check not found"
s = s.replace(old_check, "test -e $(KSU_SRC)/../.git -o -e $(KSU_SRC)/../../.git")
lines = s.splitlines()
for i, ln in enumerate(lines):
    if ln.startswith("KSU_TAG_NAME"):
        lines[i] = f"KSU_TAG_NAME    := {os.environ['BAKASU_TAG']}"
        break
else:
    raise AssertionError("Kbuild KSU_TAG_NAME line not found")
s = "\n".join(lines) + "\n"
old_subst = "KSU_VERSION_FULL := $(subst %KSU_VERSION%,$(KSU_VERSION),$(KSU_VERSION_FULL))"
assert old_subst in s, "Kbuild version subst line not found"
s = s.replace(old_subst, old_subst + "\nKSU_VERSION_FULL := $(subst %BUILD_DATE%,$(shell date -u +%Y%m%d),$(KSU_VERSION_FULL))")
p.write_text(s)
print("[luna] Kbuild: version pins + %BUILD_DATE% placeholder")
PY

# --- 3. Strip "-dirty" from the kernel release (stock-style name) ---
sed -i 's/ -dirty//g' scripts/setlocalversion
grep -qF 'res=$(echo "$res" | sed '\''s/-dirty//g'\'')' scripts/setlocalversion || \
    sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' scripts/setlocalversion

# --- 4. SUSFS kernel side ---
cp "$SUSFS_SRC/kernel_patches/fs/susfs.c" fs/
cp "$SUSFS_SRC/kernel_patches/include/linux/susfs.h" include/linux/
cp "$SUSFS_SRC/kernel_patches/include/linux/susfs_def.h" include/linux/
SUSFS_PATCH="$SUSFS_SRC/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
# The latest stable patch removed this unused declaration.  Remove it when
# upgrading a tree integrated with the previous v2.3.0 stable snapshot.
sed -i '/^extern bool __ksu_is_allow_uid_for_current(uid_t uid);$/d' fs/exec.c
if patch --dry-run -p1 < "$SUSFS_PATCH" >/dev/null 2>&1; then
    patch -p1 < "$SUSFS_PATCH"
elif patch --dry-run -R -p1 < "$SUSFS_PATCH" >/dev/null 2>&1; then
    echo "[luna] SUSFS kernel patch already applied"
else
    echo "[luna] SUSFS patch is neither applicable nor already applied" >&2
    exit 1
fi
grep -q "SUSFS_VERSION \"${SUSFS_VERSION}\"" include/linux/susfs.h
echo "[luna] SUSFS ${SUSFS_VERSION} kernel side applied"

# --- 5. CVE-2026-43499 rtmutex fix ---
if ! grep -q "never enqueued" kernel/locking/rtmutex.c; then
    patch -p1 < patches/cve-2026-43499-rtmutex-6.6.patch
fi
grep -q "never enqueued" kernel/locking/rtmutex.c
echo "[luna] CVE-2026-43499 rtmutex fix applied"

# --- 6. defconfig ---
if ! grep -q "^CONFIG_KSU=y" arch/arm64/configs/gki_defconfig; then
cat >> arch/arm64/configs/gki_defconfig << 'EOF'
CONFIG_KSU=y
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
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-%KSU_VERSION%-%BUILD_DATE%-luna"
EOF
fi
grep -qxF 'CONFIG_KALLSYMS_ALL=y' arch/arm64/configs/gki_defconfig || \
    printf '%s\n' 'CONFIG_KALLSYMS_ALL=y' >> arch/arm64/configs/gki_defconfig
grep -q "^CONFIG_DEBUG_INFO_BTF=y" arch/arm64/configs/gki_defconfig && \
    echo "[luna] defconfig: CONFIG_DEBUG_INFO_BTF=y (stock) confirmed"
printf '%s\n' \
    "ReSukiSU=${BAKASU_TAG}@${BAKASU_COMMIT}" \
    "SUSFS=${SUSFS_VERSION}@${SUSFS_COMMIT}" \
    "KPatch-Next=${KPATCH_NEXT_VERSION}" > "$INTEGRATION_MARKER"
echo "[luna] Integration done."
