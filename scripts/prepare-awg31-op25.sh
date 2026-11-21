#!/usr/bin/env bash
set -euo pipefail

report=../diagnostics/build-report.txt
vendor_config=../meta/configs/mt3000-4.11.0-op25.buildinfo
packages=(amneziawg-tools luci-proto-amneziawg)
if [[ "$BUILD_MODE" == rebuild-kernel ]]; then
    packages+=(kmod-amneziawg)
fi

{
    if [[ "$BUILD_MODE" == rebuild-kernel ]]; then
        printf 'Checked-out OpenWrt commit: %s\n' "$(git rev-parse HEAD)"
        printf 'AWG module source commit: %s\n' "$AWG_MODULE_COMMIT"
    fi
    printf 'AWG recipes commit: %s\n' "$(git -C ../awg rev-parse HEAD)"
    printf 'OpenWrt build config SHA256: %s\n' "$(sha256sum "$vendor_config" | cut -d ' ' -f 1)"
    printf 'AWG tools source commit: %s\n' "$AWG_TOOLS_COMMIT"
} >> "$report"

cp ../meta/configs/mt3000-4.11.0-op25.feeds.conf feeds.conf
./scripts/feeds update -a
printf 'Feed commits:\n' >> "$report"
while read -r _ feed source; do
    revision=$(git -C "feeds/$feed" rev-parse HEAD)
    printf '  %s: %s\n' "$feed" "$revision" >> "$report"
    [[ "$revision" == "${source##*^}" ]]
done < feeds.conf
./scripts/feeds install -a

for package in "${packages[@]}"; do
    test -f "../awg/$package/Makefile"
    mkdir -p "package/awg31/$package"
    cp -a "../awg/$package/." "package/awg31/$package/"
done

module_recipe=package/awg31/kmod-amneziawg/Makefile
tools_recipe=package/awg31/amneziawg-tools/Makefile
grep -Fxq 'PKG_SOURCE_VERSION:=v$(PKG_VERSION)' "$tools_recipe"
grep -qx 'PKG_RELEASE:=1' "$tools_recipe"
sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$AWG_TOOLS_COMMIT/" "$tools_recipe"
# The stock APK is already 3.1.20260812-r1. The replacement also changes the netifd handler.
sed -i 's/^PKG_RELEASE:=1$/PKG_RELEASE:=2/' "$tools_recipe"

if [[ "$BUILD_MODE" == rebuild-kernel ]]; then
    grep -qx 'PKG_SOURCE_VERSION:=v3.1.20261113-02' "$module_recipe"
    sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$AWG_MODULE_COMMIT/" "$module_recipe"
    cp "$vendor_config" .config
else
    # Keep the stock module as an APK dependency without compiling an SDK kmod.
    grep -Eq '^[[:space:]]*\+kmod-amneziawg$' "$tools_recipe"
    sed -i -e '/+!BUSYBOX_CONFIG_FEATURE_IP_LINK:ip/s/ \\$//' \
        -e "s/^[[:space:]]*+kmod-amneziawg$/  EXTRA_DEPENDS:=kmod-amneziawg (=$STOCK_AWG_KMOD)/" "$tools_recipe"
    printf 'CONFIG_PACKAGE_amneziawg-tools=y\n' > .config
fi
printf '\nCONFIG_PACKAGE_luci-proto-amneziawg=m\n' >> .config
make defconfig
cp .config ../diagnostics/normalized.config

grep -qx 'CONFIG_USE_APK=y' .config
if [[ "$BUILD_MODE" == rebuild-kernel ]]; then
    grep -qx 'CONFIG_TARGET_mediatek_filogic_DEVICE_glinet_gl-mt3000=y' .config
    grep -qx 'CONFIG_PACKAGE_kmod-amneziawg=y' .config
fi
grep -qx 'CONFIG_PACKAGE_amneziawg-tools=y' .config
grep -qx 'CONFIG_PACKAGE_luci-proto-amneziawg=m' .config

python3 - "$vendor_config" "$BUILD_MODE" "${packages[@]}" <<'PY' | tee -a "$report"
import re
import sys
from pathlib import Path


def kernel_options(path):
    options = {}
    for line in Path(path).read_text().splitlines():
        match = re.fullmatch(r"(?:(CONFIG_KERNEL_\w+)=(.*)|# (CONFIG_KERNEL_\w+) is not set)", line)
        if match:
            key, value, disabled = match.groups()
            options[key or disabled] = value if key else "n"
    return options


if sys.argv[2] == "rebuild-kernel":
    vendor = kernel_options(sys.argv[1])
    normalized = kernel_options(".config")
    changes = [(key, value, normalized.get(key)) for key, value in vendor.items()
               if normalized.get(key) != value]
    for key, before, after in changes:
        print(f"Kernel option changed during defconfig: {key} ({before} -> {after})")
    if changes:
        raise SystemExit("Vendor kernel options changed during defconfig.")

metadata = Path("tmp/.packageinfo").read_text()
for name in sys.argv[3:]:
    definitions = re.findall(
        rf"^Source-Makefile: ([^\n]+)\n(?:(?!^Source-Makefile:)[\s\S])*?^Package: {re.escape(name)}$",
        metadata,
        re.MULTILINE,
    )
    expected = f"package/awg31/{name}/Makefile"
    if definitions != [expected]:
        raise SystemExit(f"Expected one definition of {name} from {expected}, got {definitions}")
    print(f"Selected recipe: {expected}")
PY
