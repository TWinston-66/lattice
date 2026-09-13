#!/usr/bin/env bash
# Build and switch this machine from a local checkout of the flake. For hosts
# without remote access; the rest can also use deploy.sh.
#
# Usage: scripts/rebuild.sh [host]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

# A fresh stock install doesn't enable flakes yet.
export NIX_CONFIG="experimental-features = nix-command flakes"
use_dev_shell "$PWD/scripts/rebuild.sh" "$@"

host="${1:-$(hostname)}"
host="${host#lattice-}"

# The SSH host key is the host's sops identity, and without sshd nothing else
# creates it.
key=/etc/ssh/ssh_host_ed25519_key
if [[ ! -f "$key" ]]; then
    sudo ssh-keygen -q -t ed25519 -N "" -f "$key"
fi
require_recipient "$host" "$(cat "$key.pub")"

exec nixos-rebuild switch --flake ".#$host" --sudo
