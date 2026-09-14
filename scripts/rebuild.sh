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

exec nixos-rebuild switch --flake ".#$host" --sudo
