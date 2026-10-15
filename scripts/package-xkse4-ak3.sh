#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <image-directory> <output-directory> <kernelrelease>" >&2
    exit 2
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
image_dir="$(CDPATH= cd -- "$1" && pwd)"
output_dir="$2"
kernelrelease="$3"

# shellcheck source=xkse4-root-stack.env
. "$script_dir/xkse4-root-stack.env"

test -s "$image_dir/Image"
mkdir -p "$output_dir"
output_dir="$(CDPATH= cd -- "$output_dir" && pwd)"

work_root="${AK3_WORK_ROOT:-$repo_root/.build-ak3}"
rm -rf "$work_root"
mkdir -p "$work_root"

git -C "$work_root" init ak3-src
git -C "$work_root/ak3-src" remote add origin https://github.com/osm0sis/AnyKernel3.git
git -C "$work_root/ak3-src" fetch --depth 1 origin "$ANYKERNEL3_COMMIT"
git -C "$work_root/ak3-src" checkout --detach "$ANYKERNEL3_COMMIT"
rm -rf "$work_root/ak3-src/.git"

make_zip() {
    local variant="$1"
    local image_source="$2"
    local stack_suffix="$3"
    local package_dir="$work_root/pkg-$variant"
    local zip_name="xkse4-OP13-${kernelrelease}-${variant}-AK3.zip"

    mkdir -p "$package_dir"
    cp -a "$work_root/ak3-src/." "$package_dir/"
    cp "$image_source" "$package_dir/Image"

    cat > "$package_dir/anykernel.sh" <<EOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

properties() { '
kernel.string=xkse4 ${kernelrelease} (BakaSU ${BAKASU_TAG} + SUSFS ${SUSFS_VERSION}${stack_suffix}) for OnePlus 13
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=OP5D0DL1
device.name2=sun
device.name3=PJZ110
device.name4=CPH2649
device.name5=CPH2653
supported.versions=
supported.patchlevels=
'; }

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh

split_boot;
flash_boot;
EOF

    (
        cd "$package_dir"
        zip -qr9 "$output_dir/$zip_name" . -x '*.git*'
    )
    test -s "$output_dir/$zip_name"
}

make_zip Plain "$image_dir/Image" ''
if [ -s "$image_dir/Image.kpn" ]; then
    make_zip KPN "$image_dir/Image.kpn" " + KPatch-Next ${KPATCH_NEXT_VERSION}"
fi

(
    cd "$output_dir"
    sha256sum xkse4-OP13-*-AK3.zip > SHA256SUMS
    sha256sum -c SHA256SUMS
)
