#!/usr/bin/env bash
# Verify that an Image is built against the scheduler/KMI contract observed in
# the stock PJZ110_16.0.5.703(CN01) boot image.  A successful common-kernel
# build is not enough: stock vendor_dlkm modules are compiled against OnePlus'
# HMBIRD scheduler and its private data layout.

set -euo pipefail

config="${1:-out/.config}"
attestation="${2:-device-compatibility.attestation}"

if [[ ! -f "$config" ]]; then
  echo "PJZ110 compatibility: missing generated config: $config" >&2
  exit 2
fi

failed=0

require_enabled() {
  local symbol="$1"
  if ! grep -qx "${symbol}=y" "$config"; then
    echo "PJZ110 compatibility: required ${symbol}=y is missing" >&2
    failed=1
  fi
}

require_disabled() {
  local symbol="$1"
  if grep -qx "${symbol}=y" "$config"; then
    echo "PJZ110 compatibility: ${symbol}=y conflicts with the stock kernel" >&2
    failed=1
  fi
}

require_line() {
  local line="$1"
  if ! grep -qxF "$line" "$config"; then
    echo "PJZ110 compatibility: required config line is missing: $line" >&2
    failed=1
  fi
}

require_enabled CONFIG_HMBIRD_SCHED
require_enabled CONFIG_RCU_NOCB_CPU
require_enabled CONFIG_MODVERSIONS
require_enabled CONFIG_TRIM_UNUSED_KSYMS
require_disabled CONFIG_SLIM_SCHED
require_disabled CONFIG_SCHED_CLASS_EXT
require_disabled CONFIG_EXT_GROUP_SCHED
require_disabled CONFIG_RCU_NOCB_CPU_DEFAULT_ALL
require_line 'CONFIG_UNUSED_KSYMS_WHITELIST="abi_symbollist.raw"'

if ! grep -Rqs --include='Kconfig*' 'config HMBIRD_SCHED' kernel; then
  echo "PJZ110 compatibility: HMBIRD Kconfig/source is absent from this tree" >&2
  failed=1
fi

if ! grep -Rqs --include='*.c' --include='*.h' 'enqueue_task_hmbird' kernel; then
  echo "PJZ110 compatibility: HMBIRD scheduler implementation is absent" >&2
  failed=1
fi

if (( failed != 0 )); then
  rm -f "$attestation"
  cat >&2 <<'EOF'
PJZ110 compatibility: FAILED.
This Image must remain a non-flashable research artifact.  Do not package it
with AnyKernel3 or replace the stock boot kernel with it.
EOF
  exit 1
fi

config_sha256="$(sha256sum "$config" | awk '{print $1}')"
cat > "$attestation" <<EOF
device=PJZ110
stock_build=PJZ110_16.0.5.703(CN01)
scheduler=HMBIRD
config_sha256=$config_sha256
verified_by=scripts/luna-verify-pjz110-compatibility.sh
EOF

echo "PJZ110 compatibility: PASSED ($attestation)"
