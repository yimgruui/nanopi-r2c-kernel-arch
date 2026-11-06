# NanoPi R2C kernel

**Unofficial / community-maintained** Linux kernel packages for the
**FriendlyElec NanoPi R2C** (Rockchip RK3328, 1 GB DDR4) on Arch Linux ARM.

The package tracks the Arch Linux ARM `linux-aarch64` version and config
baseline, then applies a small NanoPi R2C router profile on top:

* PPPoE WAN (PPPoE is the primary WAN mode on this box),
* the eBPF stack, including BTF type information,
* ksmbd, the in-kernel SMB3 server,
* the Motorcomm YT8521S WAN PHY and the RTL8153 USB3 LAN port.

**GitHub repository:** [`yimgruui/nanopi-r2c-kernel-arch`](https://github.com/yimgruui/nanopi-r2c-kernel-arch)

**Related project:** [`yimgruui/nanopi-r2c-arch`](https://github.com/yimgruui/nanopi-r2c-arch)
builds the SD-card images (mainline TPL/SPL + TF-A + U-Boot), and its
`minimal-kernel` image variant installs exactly this package.

**Disclaimer:** Packages are provided as-is, without warranty of fitness or
successful operation on your hardware. Builds follow rolling Arch Linux ARM and
upstream kernel updates; behavior may change between releases.

## AI disclosure

Much of this repository was written with AI assistance and refined through
iterative review, builds, and hardware testing.

## Package

| Term | Value |
|------|-------|
| Pacman package | `linux-nanopi-r2c-minimal` |
| Kernel release suffix | `-nanopi-r2c-minimal` (e.g. `7.3.1-2-nanopi-r2c-minimal`) |
| Pacman repo | `[nanopi-r2c-kernel-arch]` |
| Repository signing key | `D43FCE3212FD6ED05AAD4685FB554996DC1276E8` |

The package installs `/boot/Image`, the single R2C DTB at
`/boot/dtbs/rockchip/rk3328-nanopi-r2c.dtb`, a mkinitcpio preset/config, and
modules under `/usr/lib/modules/<kernel-release>/`. A pacman hook regenerates
the zstd initramfs; other initramfs compression formats are intentionally
unsupported.

It conflicts with `linux-aarch64`, so pacman asks for confirmation when
replacing the stock kernel. The R2C image `boot.scr` expects exactly these
paths (`Image`, `initramfs-linux.img`,
`dtbs/rockchip/rk3328-nanopi-r2c.dtb`).

## R2C vs R2S

Same SoC, same device-tree include, one real difference that matters for the
kernel config:

| | NanoPi R2S | NanoPi R2C |
|---|---|---|
| WAN PHY | Realtek RTL8211E | **Motorcomm YT8521S** (`CONFIG_MOTORCOMM_PHY`) |
| DTB | `rk3328-nanopi-r2s.dtb` | `rk3328-nanopi-r2c.dtb` |
| LAN | RTL8153 on USB3 | RTL8153 on USB3 (same) |

The R2C DTB inherits `rk3328-nanopi-r2.dtsi`, so the LED labels and the
`&rtl8153` node are shared with the R2S (compare the `nanopi-r2s:*` LED names in
`/sys/class/leds`).

## Install From Repo

Add the pacman repo (the same snippet ships as
[packaging/nanopi-r2c.repo](packaging/nanopi-r2c.repo)):

```ini
[nanopi-r2c-kernel-arch]
Server = https://yimgruui.github.io/nanopi-r2c-kernel-arch/aarch64
SigLevel = Required
```

Import and locally trust the repository signing key, then install. The
`lsign-key` step makes pacman trust packages signed by this key, so only run it
after verifying the public key source or fingerprint.

```bash
curl -fsSLO https://yimgruui.github.io/nanopi-r2c-kernel-arch/aarch64/nanopi-r2c-kernel-arch.pub
gpg --show-keys --with-colons nanopi-r2c-kernel-arch.pub | awk -F: '/^fpr:/ {print $10; exit}'
# must print D43FCE3212FD6ED05AAD4685FB554996DC1276E8
sudo pacman-key --add nanopi-r2c-kernel-arch.pub
sudo pacman-key --lsign-key D43FCE3212FD6ED05AAD4685FB554996DC1276E8
sudo pacman -Syu linux-nanopi-r2c-minimal
```

Release assets, the pacman database, and `SHA256SUMS` are published on both
GitHub Releases and GitHub Pages.

## Verify A Download

Every release ships the package signature (`*.pkg.tar.zst.sig`), the repository
public key, the merged kernel config, and `SHA256SUMS`. Check both layers before
installing a hand-downloaded package:

```bash
gh release download --repo yimgruui/nanopi-r2c-kernel-arch \
  --pattern '*.pkg.tar.zst*' --pattern '*.pub' --pattern 'SHA256SUMS' --pattern 'config.merged'
sha256sum -c SHA256SUMS
gpg --import nanopi-r2c-kernel-arch.pub
gpg --verify linux-nanopi-r2c-minimal-*.pkg.tar.zst.sig linux-nanopi-r2c-minimal-*.pkg.tar.zst
# gpg: Good signature from "nanopi-r2c-kernel-arch"
```

`config.merged` is the exact resolved `.config` the package was built from, so
`diff <(zcat /proc/config.gz | sort) <(sort config.merged)` is a quick way to
confirm what a booted router is actually running.

## Versioning And Rebuilds

The package version follows ALARM `linux-aarch64` (`pkgver`-`pkgrel`), and the
kernel release is `<pkgver>-<pkgrel>-nanopi-r2c-minimal`.

When the profile in this repository changes but ALARM has not moved, the package
must be republished with a higher `pkgrel`; otherwise pacman sees the same
version and never upgrades. Trigger such a rebuild manually:

```bash
gh workflow run build-kernel.yml --repo yimgruui/nanopi-r2c-kernel-arch \
  --ref main -f pkgver=<same-as-ALARM> -f pkgrel=<previous+1>
```

The workflow rewrites `pkgver`/`pkgrel`/`_srcname` from those inputs, so the
resulting tag, package, and Pages entry all carry the new `pkgrel`.

## Build Locally

Install the Arch build dependencies. `pahole` is required because the profile
enables `CONFIG_DEBUG_INFO_BTF`:

```bash
sudo pacman -S --needed base-devel coreutils kmod mkinitcpio \
  aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils \
  bc dtc git python curl xz openssl libelf pahole
```

Build the package:

```bash
./scripts/build-package.sh
```

The package, resolved ALARM config, and merged config are written under
`build/`.

Useful environment variables:

| Variable | Default |
|----------|---------|
| `MAKEFLAGS` | `-j$(nproc)` |
| `CROSS_COMPILE` | `aarch64-linux-gnu-` |
| `ARCH` | `arm64` |
| `MAKEPKG_SYNCDEPS` | `0`; set `1` to run `makepkg -s` (needs root) |
| `SKIP_ALARM_FETCH` | `0`; set `1` only for cached CI/local rebuilds |
| `PACMAN_KEY_PATH`, `PACMAN_KEY_ID` | unset; set both to sign packages and the repo |
| `PUBLISH_REPO` | `0`; set `1` to run `scripts/publish-repo.sh` after the build |

Note that `CONFIG_DEBUG_INFO_BTF` implies `CONFIG_DEBUG_INFO`, so a from-scratch
build is noticeably slower and needs a few GB of free space for the build tree.

## Test A Local Package

Copy the built package to the NanoPi R2C, then install it:

```bash
sudo pacman -U linux-nanopi-r2c-minimal-*.pkg.tar.zst
sudo reboot
```

`mkinitcpio` may warn that no modules were added to the image. That is normal
for plain SD/eMMC/USB root filesystems because the R2C boot path is built in.
For encrypted root, add the required dm-crypt hooks/modules before rebooting.

After boot:

```bash
uname -r                 # ...-nanopi-r2c-minimal
ip link                  # WAN (end0/eth0) + LAN (eth1/enp...) present
cat /proc/config.gz | zgrep -E 'CONFIG_(MOTORCOMM_PHY|PPPOE|SMB_SERVER|DEBUG_INFO_BTF)'
```

Serial console: `ttyS2` at `1500000` baud.

## Config Strategy

Builds start from the current ALARM `linux-aarch64` config and apply two
disjoint fragments:

| File | Purpose |
|------|---------|
| [config/fragment.r2c](config/fragment.r2c) | R2C board and router features to keep |
| [config/fragment.prune](config/fragment.prune) | Subsystems not needed for this headless router target |

`fragment.r2c` is applied last and owns everything the profile needs: the
RK3328 boot path (RK I2C PMIC/regulators, Rockchip MMC/eMMC, USB2/USB3 host,
onboard GMAC, internal USB3 RTL8153, Motorcomm WAN PHY), nftables/iptables
compatibility, broad VPN/tunnel/ipset support, WireGuard, IPv6, PPPoE, ksmbd,
AES-based dm-crypt/LUKS, optional zram swap, Cubic/BBR, Landlock, the eBPF stack
with BTF, 32-bit userspace compatibility, ext4/overlayfs/exfat/FUSE,
thermal/cpufreq, GPIO LEDs, and the reset button.

`fragment.prune` is applied first and only disables: desktop/media/wireless/
virtualization support, SATA/AHCI, USB gadget mode, non-R2C SoC and device
drivers, legacy filesystems, partition parsers, crypto/netfilter helpers, niche
routing and virtual networking, optional storage layers, and debug/test code.
The two files never list the same symbol, so a prune entry that does not stick
is a real error rather than silent drift.

The internal RTL8153 driver is built as a module so it loads after the root
filesystem is available and can read `rtl_nic/rtl8153b-2.fw` from
`linux-firmware-realtek`. A built-in driver works for networking, but misses
that firmware unless the firmware is added to the initramfs or built into the
kernel.

`scripts/merge-config.sh` fails if a requested config symbol is not honored
after `olddefconfig`, for `=y`/`=m` **and** for `=n`; `scripts/verify-r2c-config.sh`
checks the R2C-critical options (including PPPoE, BTF/eBPF, and ksmbd) before
compile.

## Layout

```
nanopi-r2c-kernel-arch/
├── config/                 # kernel config fragments (fragment.prune, fragment.r2c)
├── packaging/              # PKGBUILD, mkinitcpio preset/config, DTS+r8152 patches
├── scripts/                # fetch / merge / verify / build / publish
├── LICENSES/
└── .github/workflows/
```

## CI

- `build-kernel.yml` builds and signs kernel packages and publishes GitHub Releases.
- `check-kernel.yml` polls ALARM twice a day and triggers a build when a new
  `linux-aarch64` version has no release yet.
- Default-branch builds also deploy the pacman repository through a GitHub Pages artifact.
- Branch builds publish a prerelease and workflow artifact for validation without deploying GitHub Pages.
- If the latest default-branch build failed, the poll fails loudly and pauses
  automatic builds instead of retrying forever. Fix the failure, then run
  `build-kernel.yml` manually (or the poll with `force_build`) to resume.
- The poll also deletes older `build-kernel.yml` runs, keeping the three most
  recent completed ones; deleting a run frees its cached sources and package
  artifacts, so the repository does not grow without bound.

GitHub Pages must use the GitHub Actions source, and the `github-pages`
environment must allow the default branch. The signing key is provided as the
`NANOPI_R2C_KERNEL_PACMAN_KEY` repository secret (base64 of the exported secret
key).

## Troubleshooting

**No WAN link / link flaps.** Check that the YT8521S PHY is bound:

```bash
dmesg | grep -iE 'yt8521|motorcomm|eth'
ethtool <wan-iface> | grep -E 'Speed|Link detected'
# the PHY driver must be built in, not a module
zcat /proc/config.gz | grep CONFIG_MOTORCOMM_PHY   # =y
```

**LAN port missing.** The RTL8153 is a USB3 device behind `dwc3`; it appears a
few seconds after boot, once `r8152` is loaded:

```bash
lsmod | grep r8152
dmesg | grep -iE 'r8152|rtl8153|firmware'
```

If the firmware line reports a missing `rtl_nic/rtl8153b-2.fw`, install
`linux-firmware-realtek` (a package optdepend).

**ksmbd does not start.** The server is a module plus userspace tooling:

```bash
modprobe ksmbd
pacman -S ksmbd-tools
systemctl enable --now ksmbd
zcat /proc/config.gz | grep CONFIG_SMB_SERVER       # =m
```

**PPPoE does not come up.** `pppd` needs the module and the kernel ppp unit:

```bash
modprobe pppoe
zcat /proc/config.gz | grep -E 'CONFIG_(PPP|PPPOE)=' # =m
```

**Kernel replaces the stock one but does not boot.** Confirm the image builder
or your own `boot.scr` points at `/boot/Image` and
`/boot/dtbs/rockchip/rk3328-nanopi-r2c.dtb`; the package does not install the R2S
DTB or `Image.gz`.

**A rebuild is not offered by pacman.** Same `pkgver`-`pkgrel` as the installed
package means no upgrade; see [Versioning And Rebuilds](#versioning-and-rebuilds).

## License

Kernel and driver patches: GPL-2.0-only. Devicetree patch and packaging
scripts: GPL-2.0-or-later. License texts are included in `LICENSES/`.

Release assets include the standard makepkg source package
`linux-nanopi-r2c-minimal-<pkgver>-<pkgrel>.src.tar.gz`. The GitHub Pages
pacman directory includes `SOURCE_INFO.txt`, `config.merged`, and a link to that
package.
