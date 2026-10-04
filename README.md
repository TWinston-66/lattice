<p align="center">
  <img src=".github/assets/banner.svg" alt="lattice" width="100%">
</p>

<p align="center">
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-unstable-89B4FA?style=flat-square&labelColor=313244&logo=nixos&logoColor=CDD6F4" alt="NixOS unstable"></a>
  <a href="https://hyprland.org"><img src="https://img.shields.io/badge/Hyprland-Wayland-94E2D5?style=flat-square&labelColor=313244" alt="Hyprland"></a>
  <a href="https://asahilinux.org"><img src="https://img.shields.io/badge/runs%20on-x86__64%20%C2%B7%20Apple%20Silicon-F5C2E7?style=flat-square&labelColor=313244" alt="x86_64 and Apple Silicon"></a>
  <a href="https://github.com/Mic92/sops-nix"><img src="https://img.shields.io/badge/secrets-sops--nix-B4BEFE?style=flat-square&labelColor=313244" alt="sops-nix"></a>
  <a href="https://github.com/TWinston-66/lattice/commits/main"><img src="https://img.shields.io/github/last-commit/TWinston-66/lattice?style=flat-square&color=A6E3A1&labelColor=313244" alt="Last commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-CBA6F7?style=flat-square&labelColor=313244" alt="MIT license"></a>
</p>

<p align="center">
  <b>A complete, themed Wayland desktop, declared in one NixOS flake.</b><br>
  From the boot splash to the lock screen, every surface is built from the same palette and the same mark,
  on Intel laptops and Apple Silicon Macs alike.
</p>

<p align="center">
  <img src=".github/assets/screenshots/desktop.png" alt="The lattice desktop: waybar over the generated lattice wallpaper" width="100%">
</p>

## Why lattice

- **One design, end to end.** Plymouth, the greeter, the console, the bar, menus,
  notifications, the lock screen, GTK and Qt apps, the terminal, Neovim, even the
  Stream Deck: all drawn from one palette and one geometric mark.
- **Switch themes live.** Seven dark flavours, fourteen accents and a matching wallpaper
  for each. Change them from the bar, and they apply without a rebuild or a logout.
- **Built for laptops.** Battery-aware refresh rates, charge limiting, measured
  suspend drain, smart hibernation, captive-portal sign-in and a guard against
  failed suspends.
- **Runs on Apple Silicon.** A first-class MacBook host on the Asahi kernel, with
  Widevine DRM, tuned trackpad and keyboard, and display fixes carried as patches.
- **Reproducible and recoverable.** Every host is a flake output. Secrets live in
  sops, deploys go over Tailscale, and the system refuses to switch to a host
  that couldn't log anyone in.

## A tour

<table>
  <tr>
    <td width="50%"><img src=".github/assets/screenshots/terminals.png" alt="Ghostty, tmux, fastfetch and Neovim"></td>
    <td width="50%"><img src=".github/assets/screenshots/launcher.png" alt="The rofi app launcher"></td>
  </tr>
  <tr>
    <td><b>Terminal-first.</b> Ghostty, tmux, Neovim with DAP debugging, starship, fzf,
    bat, delta, lazygit and btop, all following the live theme.</td>
    <td><b>One launcher for everything.</b> rofi for apps, web apps, clipboard
    history, a libqalculate calculator, Wi-Fi, audio devices and more.</td>
  </tr>
  <tr>
    <td><img src=".github/assets/screenshots/theme-menu.png" alt="The theme picker"></td>
    <td><img src=".github/assets/screenshots/keys.png" alt="The SUPER + / keybinding cheatsheet"></td>
  </tr>
  <tr>
    <td><b>Pick a theme from the bar.</b> Catppuccin Mocha, Macchiato and Frappé,
    Tokyo Night and Storm, Rosé Pine and Moon, and Gruvbox Material.</td>
    <td><b>Every shortcut, one keypress away.</b> <kbd>SUPER</kbd> + <kbd>/</kbd> lists
    each Hyprland, tmux and Neovim binding, read live from where it's defined.</td>
  </tr>
</table>

### The bar is the control panel

<table>
  <tr>
    <td width="50%"><img src=".github/assets/screenshots/performance.png" alt="Power-profile tooltip with live CPU, frequency and power graphs"></td>
    <td width="50%"><img src=".github/assets/screenshots/wifi.png" alt="Wi-Fi picker"></td>
  </tr>
  <tr>
    <td><b>Performance at a glance.</b> Hover the power-profile pill for two minutes of
    CPU load, P- and E-core clocks and package power, plus battery, fans and heat.
    Click it to cycle profiles.</td>
    <td><b>Wi-Fi without a tray applet.</b> Join, rescan, disconnect or switch the
    radio off from a rofi menu, and get a notification when the link changes.</td>
  </tr>
  <tr>
    <td><img src=".github/assets/screenshots/audio.png" alt="Audio output picker"></td>
    <td><img src=".github/assets/screenshots/calculator.png" alt="rofi calculator converting units"></td>
  </tr>
  <tr>
    <td><b>Audio devices in one click.</b> Switching outputs or inputs moves whatever
    is already playing along with them.</td>
    <td><b>A real calculator in the launcher.</b> libqalculate handles units, conversions
    and algebra, and copies the result to the clipboard.</td>
  </tr>
</table>

### Lock and leave

<table>
  <tr>
    <td width="50%"><img src=".github/assets/screenshots/lock-screen.png" alt="hyprlock lock screen"></td>
    <td width="50%"><img src=".github/assets/screenshots/power-menu.png" alt="wlogout power menu"></td>
  </tr>
  <tr>
    <td><b>hyprlock</b>, laid out around the wallpaper's mark. Its colours follow the
    live theme, and it shares the password box with the boot splash.</td>
    <td><b>The power menu</b>: lock, suspend, log out, reboot or shut down, sized to fit
    every attached screen. Hosts that hibernate get a sixth button.</td>
  </tr>
</table>

<p align="center">
  <img src=".github/assets/screenshots/wallpapers.png" alt="Generated wallpapers across flavours and accents" width="100%">
  <br><sub>The wallpapers aren't downloaded. <code>lattice-art</code> draws them at build time, one per accent in each flavour, sized for each screen.</sub>
</p>

## Features

### Desktop

- **Hyprland** under UWSM, with **waybar** as a row of pills: workspaces, weather from
  Open-Meteo (no API key), a calendar clock, Tailscale, Wi-Fi, audio, brightness, battery,
  a power-profile pill with sparkline history, caps-lock and do-not-disturb indicators.
- **Clickable pills that open menus.** Wi-Fi picker, output and input device switchers,
  wallpaper and theme pickers, Tailscale status, keep-awake and a wlogout power menu.
- **Notifications** through mako, with do-not-disturb, a browsable history, and alerts for
  battery levels, network changes, finished Taildrop transfers, and any systemd unit that
  fails, in the session or system-wide.
- **Screenshots** with HyprQuickFrame's overlay, satty for annotation, and a patched-in
  **OCR** toggle that copies the text in a selection.
- **hyprlock** and **hypridle** for the lock screen, **hyprsunset** for a warm shift at night,
  and **swayosd** for on-screen volume and brightness.
- **Web apps** as chromeless Firefox Taskbar Tabs (Claude, Gemini, Apple Music, YouTube,
  Apple TV, iCloud Reminders and Calendar), sharing your existing logins and Firefox Sync.

### Theming

- `lattice.theme` holds the palette, the flavours and the accent. Generated theme kits feed
  GTK (adw-gtk3), Qt, Papirus folder icons, rofi, mako, waybar, hyprlock, Ghostty, tmux,
  Neovim, Thunderbird and a dozen CLI tools.
- **`lattice-theme`** switches the flavour at run time. Every app that can reload, does:
  GTK3 apps restyle in place, Ghostty and Neovim reload, and the wallpaper and Stream Deck follow.
- **`lattice-wallpaper`** cycles through the generated pool, or right-click the bar to pick one.
- Boot is silent: a **Plymouth** splash that pulses the lattice mark, straight into a themed
  **tuigreet** greeter, sized per screen under cage and foot.

### Hardware

- **Stream Deck**: three pages (desktop, media and home), with key art drawn by the same
  generator as the wallpaper, a Home Assistant page for lights, the fan and scenes, and keys that
  follow the theme.
- **Logitech MX Master** through Solaar: DPI held across reconnects, and buttons mapped to
  volume, the launcher and continuous workspace scrolling.
- **NuPhy keyboard** configuration over WebHID, with a scoped udev rule.
- **iPhone** file transfer over Taildrop, with a notification when files arrive.

### Laptops

- A 50/20/10/5% battery ladder that shows time remaining. On the Mac, an 80% charge cap
  and a panel that drops to 60 Hz when unplugged.
- Suspend drain logged per sleep, hibernate-after-delay on the Dell, and a suspend guard
  for sleeps that never wake.
- Captive-portal detection that opens the sign-in page for you.
- Keyboard-backlight control on both hosts, including the Mac that has no key for it.

### Development

- **`fhs`**, a bubblewrap shell with a populated `/usr`, for the `./configure`s and
  course toolchains that expect a normal Linux. **nix-ld** covers prebuilt binaries.
- `nh` for readable rebuild diffs and garbage collection, `nix-index` and comma
  (`, cowsay`) for running anything in nixpkgs without installing it.
- Docker and virtualization on both hosts.

### Security

- Root is locked, and passwords come only from **sops-nix**, decrypted with each host's SSH key.
- A declared firewall with SSH reachable **only over Tailscale**.
- **Bitwarden** with browser unlock through polkit.

## Hosts

| Host | Hardware | Notes |
| --- | --- | --- |
| `dell` | Dell laptop | Hibernation tuned for a day of classes, Thunderbolt via bolt |
| `mac` | MacBook | Asahi kernel next to macOS, aarch64 Widevine, carried DRM patch |

Each host imports a small core (`base.nix`) and layers on the `laptop`, `graphical`
and `server` profiles plus feature modules.

## Layout

| Path | What it holds |
| --- | --- |
| `hosts/<host>/` | Per-host config and its generated `hardware-configuration.nix` |
| `modules/nixos/` | The core, branding, theme, artwork, Plymouth, display, Stream Deck, Home Assistant, web apps, dotfiles |
| `modules/nixos/desktop/` | The desktop by surface: session, apps, theming, bar, menus, notifications, lock, screenshot, greeter, plus the patches they carry |
| `modules/nixos/profiles/` | `laptop`, `graphical` and `server`; `graphical` is the desktop modules and the hardware ones they need |
| `secrets/` | [sops](https://github.com/getsops/sops)-encrypted secrets |
| `scripts/` | Deploy, rebuild, update and password helpers |
| `assets/lattice-art.py` | Draws the wallpapers, the splash, its widgets and the Stream Deck keys |

User-level configs (Hyprland, waybar, rofi, Neovim, tmux…) live in
[my dotfiles](https://github.com/TWinston-66/.dotfiles) and read their colours from the
generated theme files, so tweaking a bar or menu needs no rebuild.

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

### Theming

```nix
lattice.theme.accent = "mauve";   # the default accent, any palette entry
```

```sh
lattice-theme                     # pick a flavour
lattice-wallpaper [next|prev|random|list|current|<slot>]
lattice-art wallpaper --density 1.4 > wallpaper.svg
```

Each generated file defines `accent` and `accentAlt` aliases; prefer them over literal
hex, since an undefined colour makes GTK render transparent with no error.

<details>
<summary><b>Adding a host</b></summary>

1. Install NixOS with a `winston` user (plus OpenSSH and the deploy key if it's remote).
2. Copy `hardware-configuration.nix` into `hosts/<host>/`, add a `default.nix`
   importing `base.nix` and the modules you want, and register the host in
   `flake.nix`, and in `scripts/deploy.sh` if it's remote.
3. Add the host's age key to `.sops.yaml`, then re-encrypt from an admin machine
   with `nix develop -c sops updatekeys secrets/common.yaml`:
   - Remote: `ssh-keyscan -t ed25519 <ip> | nix develop -c ssh-to-age`
   - Local: run `scripts/rebuild.sh <host>` on the host; it prints the key.
4. Switch it with `scripts/deploy.sh <host>`, or `scripts/rebuild.sh <host>` on the host.

</details>

<details>
<summary><b>Installing on Apple Silicon</b></summary>

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
5. Back in macOS, add the key and run `updatekeys` (step 3 of *Adding a host*), and push.
6. Back on NixOS, pull, pin the firmware hash (see the comment in `hosts/mac/default.nix`)
   and run `scripts/rebuild.sh mac`. The first switch builds the kernel.

</details>

<details>
<summary><b>Recovery</b></summary>

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

</details>

## License

[MIT](LICENSE)
