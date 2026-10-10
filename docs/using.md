# Everyday use

Everything goes through one command. `lattice` alone lists it all,
`lattice <command> --help` explains one, and zsh completes both.

## Keeping the system current

```sh
lattice rebuild [host]              # build this machine from the checkout and switch
lattice rebuild --build             # build only, and list what a switch would change
lattice rebuild --test              # switch until the next reboot
lattice update [input...]           # move flake.lock forward, then offer a rebuild
lattice version                     # what is running, and whether the checkout has moved
```

`--test` is for a change that might break the session: it runs like a normal switch, but
the machine still boots the generation from before, so a reboot undoes it. `lattice
version` says when a trial is running, and a plain `lattice rebuild` keeps it.

> [!NOTE]
> On a host that keeps its password in sops, `lattice rebuild` refuses to switch until the
> host can decrypt its secrets, since it would boot with every account locked. See
> [Recovery](recovery.md) if one ever does.

## Secrets

```sh
lattice secrets password [user]     # set a login password
lattice secrets edit                # open secrets/common.yaml in sops
```

Secrets decrypt with an admin age key at `~/.config/sops/age/keys.txt`, or with each
host's SSH host key.

## Checking on things

```sh
lattice doctor                      # failed units, crashes, drift, persistence, boot errors, backups, disk
lattice backup status               # when this machine last backed up
```

`lattice doctor` is the first thing to run when something feels off. It leaves known boot
noise out, so anything it lists is worth reading.

## Themes and wallpapers

```sh
lattice theme [next|prev|<flavour>]           # or `lattice theme menu`
lattice wallpaper [next|prev|random|<slot>]   # or `lattice wallpaper menu`
lattice art wallpaper --density 1.4 > wallpaper.svg
```

Changes apply live: GTK apps restyle in place, open terminals and Neovim recolour, and the
wallpaper and Stream Deck follow. Clicking the bar does the same, and right-clicking it
picks a wallpaper.

## Finding your way around

- <kbd>SUPER</kbd> + <kbd>/</kbd> searches every Hyprland, tmux and Neovim binding.
- `lattice guide keys` (or <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>/</kbd>) opens the same
  bindings as a page, with practice cards. It's linked from the guides' sidebar too.
- `lattice guide` opens these guides.
