#!/usr/bin/env bash
# Links the author's own configs (zsh, Neovim, git and the rest) from this folder into
# $HOME with Stow. Each top-level folder is one Stow package laid out like $HOME. Anything
# Stow would replace is moved to ~/.dotfiles-backup/<date>/ first. Safe to re-run.
#
# These were the NixOS half of TWinston-66/.dotfiles until that repo went macOS-only;
# lattice-install runs this for the personal setup, against the new home.

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
packages=(git zsh zed ssh tealdeer sesh starship nvim bat btop lazygit pi solaar)

for cmd in stow git; do
    command -v "$cmd" >/dev/null || {
        echo "link.sh: $cmd is missing; lattice installs it, so rebuild first" >&2
        exit 1
    }
done

backup="$HOME/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"
for pkg in "${packages[@]}"; do
    while IFS= read -r file; do
        rel="${file#"$dir/$pkg/"}"
        # A folder on the way may itself be a link (~/.config/nvim into an old dotfiles
        # repo), and moving a file through it would move that repo's own file. The link is
        # what is in the way, so it is what gets moved.
        prefix=""
        IFS=/ read -ra parts <<<"$rel"
        for part in "${parts[@]}"; do
            prefix="${prefix:+$prefix/}$part"
            [[ -L $HOME/$prefix ]] && break
        done
        rel="$prefix"
        target="$HOME/$rel"
        [[ -e $target || -L $target ]] || continue
        case "$(realpath "$target" 2>/dev/null || true)" in
            "$dir"/*) continue ;;
        esac
        echo "backing up ~/$rel"
        mkdir -p "$backup/$(dirname "$rel")"
        mv "$target" "$backup/$rel"
    done < <(find "$dir/$pkg" \( -type f -o -type l \))
done

# Made first so Stow links the files inside rather than folding the whole directory into
# the repo, which would put machine-local state (auth.json, sessions/) in git. ~/.config
# and ~/.local likewise, so an empty home doesn't get them linked wholesale.
mkdir -p -m 700 "$HOME/.ssh"
mkdir -p "$HOME/.pi/agent" "$HOME/.config/solaar" "$HOME/.local/share" "$HOME/.local/state"

stow --dir="$dir" --target="$HOME" --restow "${packages[@]}"

# Solaar rewrites a cookie in its config.yaml on every start. The file stays tracked for
# its settings, but out of `git status`; to commit a change on purpose, run
# `git update-index --no-skip-worktree home/solaar/.config/solaar/config.yaml` first.
git -C "$dir" update-index --skip-worktree solaar/.config/solaar/config.yaml 2>/dev/null || true

echo "configs linked"
