# Configuring lattice

lattice is one flake. Each host is a flake output, and everything it runs is declared
in the modules it imports.

## Where things live

| Path | What it holds |
| --- | --- |
| `hosts/<host>/` | Per-host config and its generated `hardware-configuration.nix` |
| `modules/nixos/` | The distro: the core, branding, theme, artwork, Plymouth, display, Stream Deck, Home Assistant, web apps, dotfiles. `default.nix` imports all of it |
| `modules/nixos/hardware/` | Apple Silicon: Asahi, video decode, the carried DRM patch, trackpad, suspend, power, charge limit |
| `modules/personal/` | The author's own setup on top: account, sops secrets, house and homelab. Only `hosts/mac` imports it |
| `modules/nixos/desktop/` | The desktop by surface: session, apps, theming, bar, menus, notifications, lock, screenshot, greeter, plus the patches they carry |
| `modules/nixos/profiles/` | `laptop` and `graphical`; `graphical` is the desktop modules and the hardware ones they need |
| `modules/nixos/cli.nix` | The `lattice` command; each module registers its scripts in `lattice.cli.commands` |
| `secrets/` | [sops](https://github.com/getsops/sops)-encrypted secrets |
| `scripts/` | What `lattice rebuild`, `update` and `secrets password` run |
| `assets/lattice-art.py` | Draws the wallpapers, the splash, its widgets and the Stream Deck keys |
| `docs/` | These guides |

## Hosts and profiles

| Host | Hardware | Notes |
| --- | --- | --- |
| `macbook` | Any M1/M2 MacBook | The distro alone, with a password set by `passwd` |
| `mac` | The author's MacBook Pro | `macbook` plus `modules/personal` |

Each host imports `modules/nixos`, adds its `hardware-configuration.nix`, firmware hash and
panel geometry, and names its user. Optional features are switched on per host:
`lattice.homeassistant.enable`, `lattice.streamdeck.enable`, `lattice.weather.*`,
`services.tailscale.enable`. To add a host, see [Installing lattice](install.md#installing).

## The theme

```nix
lattice.theme.accent = "mauve";   # the default accent: any palette entry
```

`lattice.theme` holds the palette, the flavours and the accent, and generated theme kits
feed every app that can take one. Each generated file defines `accent` and `accentAlt`
aliases.

> [!TIP]
> Use `accent` and `accentAlt` rather than literal hex. An undefined colour makes GTK
> render transparent, with no error to tell you why.

## Your dotfiles

User-level configs (Hyprland, waybar, rofi, Neovim, tmux…) live in
[a separate dotfiles repo](https://github.com/TWinston-66/.dotfiles) and read their
colours from the generated theme files. Tweaking a bar or a menu needs no rebuild.

## Adding a command

A module that ships a script registers it in `lattice.cli.commands`, next to the script.
The `lattice` router, its help and its zsh completion are built from that registry.
