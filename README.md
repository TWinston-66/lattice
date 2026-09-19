<p align="center">
  <img src=".github/assets/banner.svg" alt="lattice" width="100%">
</p>

<p align="center">
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-unstable-89B4FA?style=flat-square&labelColor=313244&logo=nixos&logoColor=CDD6F4" alt="NixOS unstable"></a>
  <a href="https://github.com/Mic92/sops-nix"><img src="https://img.shields.io/badge/secrets-sops--nix-B4BEFE?style=flat-square&labelColor=313244" alt="sops-nix"></a>
  <a href="https://github.com/TWinston-66/lattice/commits/main"><img src="https://img.shields.io/github/last-commit/TWinston-66/lattice?style=flat-square&color=A6E3A1&labelColor=313244" alt="Last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-CBA6F7?style=flat-square&labelColor=313244" alt="MIT license"></a>
</p>

My NixOS machines, as one flake. Every host gets a small core, and everything
else is layered on through modules and profiles.

## Layout

| Path | What it holds |
| --- | --- |
| `hosts/<host>/` | Per-host config and its generated `hardware-configuration.nix` |
| `modules/nixos/` | The core (`base.nix`), branding, theme, artwork, Plymouth, SSH, firewall, dotfiles |
| `modules/nixos/profiles/` | `laptop`, `graphical` and `server` |
| `secrets/` | [sops](https://github.com/getsops/sops)-encrypted secrets |
| `scripts/` | Deploy, rebuild and password helpers |
| `assets/lattice-art.py` | Draws the wallpaper, the splash's mark and its widgets |

## Usage

```sh
scripts/deploy.sh [host] [addr]          # build and switch a host over SSH
scripts/rebuild.sh [host]                # build and switch this machine
scripts/set-password.sh [user]           # set a login password
nix develop -c sops secrets/common.yaml  # edit secrets
```

`deploy.sh` evaluates locally and builds on the target, reaching it by MagicDNS
name; pass an address for a host not on the tailnet yet. Both switch scripts
refuse a host that can't decrypt its secrets, since it would boot with every
account locked. Secrets decrypt with an admin age key at
`~/.config/sops/age/keys.txt` or with each host's SSH host key.

## Theming

`lattice.theme` holds the palette and one accent, so re-accenting the whole
desktop is a one-line change:

```nix
lattice.theme.accent = "mauve";   # any palette entry
```

It reaches the console, Plymouth, tuigreet, hyprlock, the GTK/icon/cursor
themes, the generated wallpaper, and the palettes under `/etc/xdg` that waybar,
rofi, mako and swayosd import from [my dotfiles](https://github.com/TWinston-66/.dotfiles)
by absolute path — so tweaking a bar or menu needs no rebuild. Each generated
file defines `accent` and `accentAlt` aliases; prefer them over literal hex,
since an undefined colour makes GTK render transparent with no error.

## Artwork

`assets/lattice-art.py` draws the lattice — the same triangular grid as the
logo — in whatever palette it is handed:

```sh
lattice-art wallpaper --density 1.4 > wallpaper.svg   # live palette
lattice-art mark --phase 0.3                          # one frame of the splash
```

The graphical profile builds three wallpapers; `lattice-wallpaper [next|prev|list|<index>]`
switches between them. Boot is silent — splash straight through to the greeter,
with `journalctl -b` keeping everything.

## Adding a host

1. Install NixOS with a `winston` user (plus OpenSSH and the deploy key if it's remote).
2. Copy `hardware-configuration.nix` into `hosts/<host>/`, add a `default.nix`
   importing `base.nix` and the modules you want, and register the host in
   `flake.nix` — and in `scripts/deploy.sh` if it's remote.
3. Add the host's age key to `.sops.yaml`, then re-encrypt from an admin machine
   with `nix develop -c sops updatekeys secrets/common.yaml`:
   - Remote: `ssh-keyscan -t ed25519 <ip> | nix develop -c ssh-to-age`
   - Local: run `scripts/rebuild.sh <host>` on the host; it prints the key.
4. Switch it with `scripts/deploy.sh <host>`, or `scripts/rebuild.sh <host>` on the host.

### Apple Silicon

`hosts/mac` runs the Asahi kernel from [nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon)
next to macOS. It is installed with a minimal config first: the installer can
only copy its own kernel, and the host can't decrypt secrets until its key is a
recipient. Its [install guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md)
has the details; in short:

1. In macOS, run `curl https://alx.sh | sh`. Resize (`r`) to leave 500GB free, then
   install (`f`) **UEFI environment only**, named `lattice`, and finish the
   permissive-security steps it prints in recovery.
2. `dd` the latest [release ISO](https://github.com/nix-community/nixos-apple-silicon/releases)
   to a USB stick and boot it. Keep the stick: it is this host's recovery stick.
3. Create a partition in the free space only. Damaging the GPT, the first or last
   partition, or the APFS containers can leave the Mac unbootable.

   ```sh
   sgdisk /dev/nvme0n1 -n 0:0 -s    # then sgdisk -p for its number
   mkfs.btrfs -L lattice /dev/nvme0n1pN
   mount /dev/disk/by-label/lattice /mnt
   btrfs subvolume create /mnt/home && btrfs subvolume create /mnt/nix
   mount -o subvol=home /dev/disk/by-label/lattice /mnt/home
   mount -o subvol=nix /dev/disk/by-label/lattice /mnt/nix
   mkdir /mnt/boot
   mount /dev/disk/by-partuuid/$(cat /proc/device-tree/chosen/asahi,efi-system-partition) /mnt/boot
   nixos-generate-config --root /mnt
   ```

   Edit `configuration.nix` as the guide says, plus `networking.hostName = "lattice-mac"`,
   NetworkManager, git, and a `winston` user with an `initialPassword`, then `nixos-install`.
4. On NixOS, clone lattice to `~/Documents/Projects/lattice` and copy
   `/etc/nixos/hardware-configuration.nix` over `hosts/mac/`'s. `scripts/rebuild.sh mac`
   stops at the recipient check and prints the host's age key.
5. Back in macOS, add the key and run `updatekeys` (step 3 above), and push.
6. Back on NixOS, pull, pin the firmware hash (see the comment in `hosts/mac/default.nix`)
   and run `scripts/rebuild.sh mac`. The first switch builds the kernel.

## Recovery

Root is locked and passwords only come from sops, so a host that can't decrypt
its secrets locks you out entirely. Keep a NixOS USB stick around.

1. Boot the stick, `cryptsetup open` the LUKS devices, and mount under `/mnt`.
2. From an admin machine, either add the host's key
   (`/mnt/etc/ssh/ssh_host_ed25519_key.pub`) and run `updatekeys`, or set a new
   password with `scripts/set-password.sh`.
3. Reinstall from a checkout with the fix:

   ```sh
   sudo nixos-install --root /mnt --flake .#<host> --no-root-passwd \
     --option experimental-features 'nix-command flakes'
   ```

## License

[MIT](LICENSE)
