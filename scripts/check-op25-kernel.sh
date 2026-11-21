#!/usr/bin/env bash
set -euo pipefail

report=../diagnostics/build-report.txt
expected_hash=${EXPECTED_KERNEL#*~}
expected_hash=${expected_hash%-r*}

case "${1:-}" in
    preflight)
        config=../diagnostics/kernel.config.set
        # Mirror Kernel/Configure/Default at the pinned 6.12 OpenWrt source.
        # The completed kernel build checks the actual emitted .vermagic again.
        kernel_configs=(target/linux/generic/config-6.12)
        for target in mediatek mediatek/filogic; do
            if [[ -f "target/linux/$target/config-6.12" ]]; then
                kernel_configs+=("target/linux/$target/config-6.12")
            elif [[ -f "target/linux/$target/config-default" ]]; then
                kernel_configs+=("target/linux/$target/config-default")
            fi
        done
        merge=()
        for ((index = 1; index < ${#kernel_configs[@]}; index++)); do
            merge+=(+)
        done
        ./scripts/kconfig.pl "${merge[@]}" "${kernel_configs[@]}" > "$config.target"
        awk '/^(#[[:space:]]+)?CONFIG_KERNEL/{sub("CONFIG_KERNEL_","CONFIG_");print}' .config >> "$config.target"
        printf '%s\n' '# CONFIG_KALLSYMS_EXTRA_PASS is not set' '# CONFIG_KALLSYMS_ALL is not set' \
            'CONFIG_KALLSYMS_UNCOMPRESSED=y' >> "$config.target"
        ./scripts/package-metadata.pl kconfig tmp/.packageinfo .config 6.12 > "$config.override"
        ./scripts/kconfig.pl 'm+' '+' "$config.target" /dev/null "$config.override" |
            grep -v INITRAMFS > "$config"
        printf '%s\n' 'CONFIG_INITRAMFS_SOURCE=""' '# CONFIG_INITRAMFS_FORCE is not set' \
            '# CONFIG_INITRAMFS_PRESERVE_MTIME is not set' >> "$config"
        hash=$(grep '=[ym]' "$config" | LC_ALL=C sort | md5sum | cut -d ' ' -f 1)
        version=$(awk '$1 == "LINUX_VERSION-6.12" {print "6.12" $3}' target/linux/generic/kernel-6.12)
        printf 'Preflight Linux version: %s\nPreflight kernel config hash: %s\n' "$version" "$hash" | tee -a "$report"
        if [[ "$version" != "${EXPECTED_KERNEL%%~*}" ]]; then
            echo 'OpenWrt source selects a different Linux version from the requested firmware.' | tee -a "$report"
            exit 1
        fi
        ;;
    compiled)
        shopt -s nullglob
        files=(build_dir/target-*/linux-mediatek_filogic/linux-*/.vermagic)
        if (( ${#files[@]} != 1 )); then
            printf 'Expected one generated .vermagic, found %s\n' "${#files[@]}" | tee -a "$report"
            exit 1
        fi
        hash=$(tr -d '\r\n' < "${files[0]}")
        printf 'Compiled kernel config hash: %s\n' "$hash" | tee -a "$report"
        ;;
    *)
        echo 'Usage: check-op25-kernel.sh preflight|compiled' >&2
        exit 2
        ;;
esac

if [[ "$hash" != "$expected_hash" ]]; then
    printf 'Kernel config ABI mismatch. Firmware expects %s, this source and configuration produce %s.\n' \
        "$expected_hash" "$hash" | tee -a "$report"
    exit 1
fi
