# AmneziaWG Packages for offical GL.iNET MT-3000 router firmware

Official op24 GL.iNET firmware could be downloaded [here](https://dl.gl-inet.com/router/mt3000/open)

Installation instructions (in Russian) coud be found [here](https://github.com/openwrt-xiaomi/awg-openwrt/wiki/AmneziaWG-installing#%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-amneziawg-%D0%BD%D0%B0-openwrt-%D1%83%D1%81%D1%82%D1%80%D0%BE%D0%B9%D1%81%D1%82%D0%B2%D0%B5)

NOTE: in case you need to pass all traffic through AWG interface, check "Route Allowed IPs" checkbox in the Peer settings (this is absent in instruction above)

# Usage

You will have to configure Amnezia using LUCI web interface, but once configured and installed, you can continue using full power on GL.iNET interface (including VPN settings). In case your AWG interface is ON and no VPN configured in GL's UI all traffic is going through AWG, once you turn your Wireguard connection ON (in GL UI) all traffic will go through Wireguard connection (no matter about AWG status), so basically it will work like independed VPN connection with lower priority than GL.iNET's VPN.

## Experimental AWG 3.1 packages for GL-MT3000 OP25

This workflow targets GL.iNet's `4.11.0-op25` firmware on the Beryl AX (GL-MT3000). The defaults come from OP25 beta2 build `1205`, which reports `r33311-981c978eff` for `mediatek/filogic`. Its installed kernel package is `6.12.112~9469a6c8c449c47e503c05678ea1559d-r1`. Other firmware builds require their own source revision, configuration, and kernel package version. [GL.iNet OP25 beta2 firmware](https://forum.gl-inet.com/t/op25-firmware-for-flint-2-beryl-ax-is-out/69771/313)

### Build in GitHub Actions

1. Check the installed firmware and APK versions over SSH. These commands leave router state alone.

   ```sh
   cat /etc/glversion /etc/version.build /etc/openwrt_release
   uname -r
   awk '/^P:kernel$/ { getline; sub(/^V:/, ""); print; exit }' /lib/apk/db/installed
   apk info -v kmod-amneziawg amneziawg-tools
   ```

2. In the fork's **Actions** tab, open **Build experimental AWG 3.1 APKs for GL-MT3000 OP25** and select **Run workflow**. Use the default `stock-kernel` mode for beta2 build `1205`. This compiles the tools and LuCI against the pinned 25.12.6 SDK and packages the byte-for-byte AWG 3.1 module from GL.iNet's beta2 image. The tools APK requires that exact stock module version. Select `rebuild-kernel` to test a source build with the full firmware source commit and installed kernel APK version.
3. A successful run uploads `awg31-mt3000-op25-experimental` with three APKs, `build-report.txt`, and `SHA256SUMS`. A failing run uploads `awg31-mt3000-op25-diagnostics`. The report records the source and feed revisions, the configuration hash, and, when available, the generated APK's exact kernel dependency.

The source rebuild uses GL.iNet's build configuration with the public OpenWrt 25.12.6 feed revisions. It produced kernel config hash `45663ba8165ccd977d7acb36d8719a1d` for beta2, so the workflow stopped before compiling a replacement module. The public OpenWrt 25.12.6 SDK also has a different kernel ABI. The stock mode uses its toolchain only for the new userspace packages and verifies the kernel package dependency on GL.iNet's binary. [Source build diagnostics](https://github.com/l1cache/amnezia-glinet-mt3000/actions/runs/44946358919) · [Public kernel ABI](https://downloads.openwrt.org/releases/25.12.6/targets/mediatek/filogic/kmods/) · [GL.iNet build configuration discussion](https://forum.gl-inet.com/t/4-6-6-op24-source-vermagic/50529/51)

### Evaluate and install the APKs manually

1. Check the build report against the installed firmware and verify `sha256sum -c SHA256SUMS` from the unpacked artifact. Back up the router configuration and have the original firmware and package versions available for recovery. Enable LuCI from GL.iNet's **System → Advanced Settings** page if it is missing. [GL.iNet LuCI guide](https://docs.gl-inet.com/router/en/4/interface_guide/advanced_settings/)
2. Copy the APKs into a dedicated directory such as `/tmp/awg31` on the router. Build `1205` already has the stock kernel module, so with the default artifact you can leave it installed and simulate adding only the tools and LuCI. The bundle also contains an unsigned APK of the same stock module if you need to reinstall it for this exact firmware build.

   ```sh
   cd /tmp/awg31
   apk add --simulate --allow-untrusted ./amneziawg-tools-*.apk ./luci-proto-amneziawg-*.apk
   ```

3. Review the simulation. If it proposes unexpected removals or replacements, or reports an ABI or dependency conflict, stop there. When the transaction contains the intended changes and you are ready to test, repeat it without `--simulate`. The `--allow-untrusted` option authorizes the local experimental files you verified.
4. In LuCI, go to **Network → Interfaces**, add an **AmneziaWG** interface and import the AWG 3.1 profile. Verify a handshake and transfer with the intended peer, then check that normal routing and any GL.iNet VPN features you use still work.

Build `1205` already ships AWG 3.1 tools and a kernel module. The community tools APK also replaces GL.iNet's `/lib/netifd/proto/amneziawg.sh`. That enables LuCI to pass the newer settings, but it may affect GL.iNet's VPN Manager or GoodPAS. A matching APK kernel dependency is one check. Loading the module and testing the tunnel and GL.iNet integration are separate runtime checks. [AWG 3.1 package recipes](https://github.com/2Grey/awg-openwrt/tree/86f89bce58e01cd0793b944bf8a998124fcc172f)

For a newly compiled module, ask GL.iNet for the exact firmware's kernel SDK or source and patch set, feed revisions, generated Linux `.config`, and `Module.symvers`. The stock package version identifies commit `4569c4c`, whose source includes Header Protection, RandomTrailers, and DisableCookies. A tunnel test on the router is still needed. [Stock module source revision](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/4569c4c67f3a57414969260cafbbd04694fbaae0)
