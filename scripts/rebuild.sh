#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
export NIX_CONFIG="experimental-features = nix-command flakes"
enter_dev_shell scripts/rebuild.sh "$@"

host="${1:-$(hostname)}"
host="${host#lattice-}"

key=/etc/ssh/ssh_host_ed25519_key
if [[ ! -f "$key" ]]; then
    sudo ssh-keygen -q -t ed25519 -N "" -f "$key"
fi
require_recipient "$host" "$(cat "$key.pub")"

nixos-rebuild switch --flake ".#$host" --sudo

# The hypr configs this flake generates -- /etc/xdg/hypr/lattice.lua and the hyprpaper,
# hypridle and hyprlock confs beside it -- are /etc symlinks whose target moves on every
# switch. Hyprland's autoreload watches the path, not the store path behind it, so a running
# session keeps the config it started with until it is told to reread.
#
# Guarded on the signature rather than on `command -v hyprctl`: the variable is set only
# inside a Hyprland session, so a switch from a TTY or over SSH skips this instead of
# failing an otherwise good rebuild on a socket that is not there.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null
fi
