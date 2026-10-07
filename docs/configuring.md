# Configuring lattice

lattice is one flake. Each host is a flake output, and everything it runs is declared
in the modules it imports.

## Where things live

| Path | What it holds |
| --- | --- |
| `hosts/<host>/` | Per-host config and its generated `hardware-configuration.nix` |
| `modules/nixos/` | The core, branding, theme, artwork, Plymouth, display, Stream Deck, Home Assistant, web apps, dotfiles |
| `modules/nixos/desktop/` | The desktop by surface: session, apps, theming, bar, menus, notifications, lock, screenshot, greeter, plus the patches they carry |
| `modules/nixos/profiles/` | `laptop`, `graphical` and `server`; `graphical` is the desktop modules and the hardware ones they need |
| `modules/nixos/cli.nix` | The `lattice` command; each module registers its scripts in `lattice.cli.commands` |
| `secrets/` | [sops](https://github.com/getsops/sops)-encrypted secrets |
| `scripts/` | What `lattice rebuild`, `deploy`, `update` and `secrets password` run |
| `assets/lattice-art.py` | Draws the wallpapers, the splash, its widgets and the Stream Deck keys |
| `docs/` | These guides |

## Hosts and profiles

| Host | Hardware | Notes |
| --- | --- | --- |
| `dell` | Dell laptop | Hibernation tuned for a day of classes, Thunderbolt via bolt |
| `mac` | MacBook | Asahi kernel next to macOS, aarch64 Widevine, carried DRM patch, VA-API video decode, hourly snapper snapshots of `/home` |

Each host imports a small core (`base.nix`) and layers on the `laptop`, `graphical` and
`server` profiles plus whichever feature modules it needs. To add one, see
[Installing lattice](install.md#adding-a-host).

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
