#!/usr/bin/env bash
set -euo pipefail

report=../diagnostics/build-report.txt
apk_tool=staging_dir/host/bin/apk
apk_files=()

for package in kmod-amneziawg amneziawg-tools luci-proto-amneziawg; do
    mapfile -t found < <(find bin -type f -name "$package-*.apk")
    if (( ${#found[@]} != 1 )); then
        printf 'Expected one APK for %s, found %d\n' "$package" "${#found[@]}" | tee -a "$report"
        exit 1
    fi
    apk_files+=("${found[0]}")
    "$apk_tool" adbdump --allow-untrusted "${found[0]}" > "../diagnostics/$package.apk-metadata.txt"
    printf 'Built package: %s\n' "${found[0]##*/}" >> "$report"
done

dependency=$(awk '$1 == "-" && $2 ~ /^kernel=/ {print $2}' ../diagnostics/kmod-amneziawg.apk-metadata.txt)
printf 'Kernel dependency in module APK: %s\n' "$dependency" | tee -a "$report"
if [[ "$dependency" != "kernel=$EXPECTED_KERNEL" ]]; then
    echo 'The module APK does not require the exact firmware kernel version.' | tee -a "$report"
    exit 1
fi

echo 'The kernel package dependency matches. Router runtime and GL.iNet integration are unverified. EXPERIMENTAL.' >> "$report"
mkdir -p ../artifacts
cp "${apk_files[@]}" "$report" ../artifacts/
cd ../artifacts
sha256sum -- *.apk > SHA256SUMS
