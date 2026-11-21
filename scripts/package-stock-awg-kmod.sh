#!/usr/bin/env bash
set -euo pipefail

report=../diagnostics/build-report.txt
firmware=mt3000-op-4.11.0-op25_beta2-1205-1116-1794798505.bin
firmware_sha=7a2913787e880e001c29b7c3b012c56058a70bc23a03c530952a520c577f6421
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

curl --fail --silent --show-error --location --retry 3 --output "$work/$firmware" \
    "https://fw.gl-inet.com/firmware/mt3000-open/testing/$firmware"
printf '%s  %s\n' "$firmware_sha" "$work/$firmware" | sha256sum --check
tar -xOf "$work/$firmware" sysupgrade-glinet_gl-mt3000/root > "$work/firmware.squashfs"
rootfs=$work/firmware.squashfs
[[ "$(unsquashfs -cat "$rootfs" etc/glversion)" == 4.11.0-op25 ]]
[[ "$(unsquashfs -cat "$rootfs" etc/version.build)" == 1205 ]]
[[ "$(unsquashfs -cat "$rootfs" etc/apk/arch)" == aarch64_cortex-a53 ]]

unsquashfs -cat "$rootfs" lib/apk/db/installed > "$work/installed"
dependencies=$(python3 - "$work/installed" "$EXPECTED_KERNEL" "$STOCK_AWG_KMOD" <<'PY'
import sys
from pathlib import Path

installed = {}
for record in Path(sys.argv[1]).read_text().split("\n\n"):
    fields = dict(line.split(":", 1) for line in record.splitlines() if ":" in line)
    if "P" in fields:
        installed[fields["P"]] = fields
module = installed["kmod-amneziawg"]
if installed["kernel"]["V"] != sys.argv[2] or module["V"] != sys.argv[3]:
    raise SystemExit("The image does not contain the expected kernel and AWG package.")
dependencies = module["D"].split()
if f"kernel={sys.argv[2]}" not in dependencies:
    raise SystemExit("The stock module does not declare the expected kernel dependency.")
print(" ".join(dependencies))
PY
)

linux_version=${EXPECTED_KERNEL%%~*}
module=lib/modules/$linux_version/amneziawg.ko
manifest=lib/apk/packages/kmod-amneziawg.list
for member in "$module" "$manifest"; do
    mkdir -p "$work/package/${member%/*}"
    unsquashfs -cat "$rootfs" "$member" > "$work/package/$member"
    test -s "$work/package/$member"
done
chmod 0644 "$work/package/$module" "$work/package/$manifest"
mkdir -p bin/stock-kmod
fakeroot staging_dir/host/bin/apk mkpkg \
    --info name:kmod-amneziawg \
    --info "version:$STOCK_AWG_KMOD" \
    --info arch:aarch64_cortex-a53 \
    --info "description:GL.iNet stock AmneziaWG kernel module from OP25 build 1205" \
    --info license:GPL-2.0-only \
    --info url:https://amnezia.org/ \
    --info "depends:$dependencies" \
    --info provides:kmod-amneziawg-any \
    --files "$work/package" \
    --output "bin/stock-kmod/kmod-amneziawg-$STOCK_AWG_KMOD.apk"

{
    printf 'Stock kernel module source image: %s\n' "$firmware"
    printf 'Firmware SHA256: %s\n' "$firmware_sha"
    printf 'Stock module SHA256: %s\n' "$(sha256sum "$work/package/$module" | cut -d ' ' -f 1)"
    printf 'Stock module package version: %s\n' "$STOCK_AWG_KMOD"
    printf 'The stock module binary is copied byte for byte. It was compiled by GL.iNet.\n'
} >> "$report"
