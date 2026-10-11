# Configuring lattice

lattice is one flake. Each host is a flake output, and everything it runs is declared
in the modules it imports.

## Where things live

| Path | What it holds |
| --- | --- |
| `hosts/<host>/` | Per-host config and its generated `hardware-configuration.nix` |
| `modules/nixos/` | The distro: the core, branding, theme, artwork, Plymouth, display, storage and backups, the firewall, Bitwarden, the iPhone, Stream Deck, Home Assistant, weather, web apps, the shell and dev tools. `default.nix` imports all of it |
| `modules/nixos/hardware/` | Apple Silicon: Asahi and its kernel, video decode, trackpad, suspend, power, charge limit, and the carried display and USB-C patches |
| `modules/personal/` | The author's own setup on top: account, sops secrets, AirPlay, the mouse, Thunderbird, books, house and homelab. Only `hosts/mac` imports it |
| `modules/nixos/desktop/` | The desktop by surface: session, apps, the launcher, theming, bar, menus, notifications, lock, screenshot, greeter, radio, pomodoro, the guides and the cheatsheet, plus the patches they carry |
| `modules/nixos/profiles/` | `laptop` and `graphical`; `graphical` is the desktop modules and the hardware ones they need |
| `modules/nixos/cli.nix` | The `lattice` command; each module registers its scripts in `lattice.cli.commands` |
| `secrets/` | [sops](https://github.com/getsops/sops)-encrypted secrets |
| `scripts/` | What `lattice rebuild`, `update`, `cache` and `secrets password` run, the backup password, the CI build and the installer VM |
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
lattice.theme.flavor = "mocha";   # what boot, the greeter and the console are drawn in
lattice.theme.accent = "mauve";   # the default accent: any palette entry
```

`lattice.theme` holds the palette, the flavours and the accent, and generated theme kits
feed every app that can take one. Each generated file defines `accent` and `accentAlt`
aliases. A theme switch rewrites the kit files in `~/.cache/lattice`, so a module with a
program of its own to theme adds a file to every kit with `lattice.theme.extraKitFiles`,
and that program follows the switch too.

> [!TIP]
> Use `accent` and `accentAlt` rather than literal hex. An undefined colour makes GTK
> render transparent, with no error to tell you why.

## Desktop configs and your dotfiles

Hyprland, the terminal, tmux, the bar, rofi, mako, the on-screen display and the other
desktop programs run on configs lattice ships in `modules/nixos/desktop/configs/`,
installed under `/etc`. A file of your own in `~/.config` takes over from lattice's for
that program. The bar's modules are declared in Nix, each next to the script that feeds
it, as `lattice.bar.modules` (see `desktop/waybar.nix`). Everything reads its colours
from the generated theme files.

Hyprland's config runs two more files at the end, so you can add to it without replacing
it:

- `/etc/xdg/hypr/lattice.lua`, the host's: monitor rules from `lattice.display.monitors`,
  plus any Lua in `lattice.hyprland.extraConfig`, such as an external monitor's
  workspaces or a mouse's device block.
- `~/.config/hypr/local.lua`, your own, run last.

The keybinding cheatsheet takes extra rows the same way: `lattice.keys.extras` for the
host, `~/.config/lattice/keys.tsv` for you.

zsh comes set up from `/etc/zshrc`: a starship prompt, completion, fzf, zoxide,
autosuggestions and syntax highlighting, all in the theme's colours, and a notification
when a command that took 5 seconds or more finishes. Your `~/.zshrc` runs after it, for
aliases and the like, and can test `$LATTICE_SHELL` if it is shared with another OS. A
`~/.config/starship.toml` of your own replaces the prompt's layout and keeps the theme's
colours. Neovim, git and the other tools are installed but not configured. The author's
own configs live in [a separate dotfiles repo](https://github.com/TWinston-66/.dotfiles). `lattice doctor`
expects anything that runs at login (shell rc files, `~/.config/hypr/local.lua`) to be a
symlink into a git repo, so a change you didn't make shows up as uncommitted there.

## Adding a command

A module that ships a script registers it in `lattice.cli.commands`, next to the script.
The `lattice` router, its help and its zsh completion are built from that registry.
