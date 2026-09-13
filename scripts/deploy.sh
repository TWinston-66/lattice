#!/usr/bin/env bash
# Build and switch a NixOS host from this flake over SSH.
#
# Usage: scripts/deploy.sh [host] [ip]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

host="${1:-dell}"

case "$host" in
dell) hostname="lattice-dell" default_ip="10.0.10.148" ;;
*)
    echo "unknown host: $host" >&2
    exit 1
    ;;
esac

ip="${2:-$default_ip}"
target="winston@$ip"

# Pin the host key to the host name, not the IP, so an IP change can't
# silently point a deploy at a different machine.
export NIX_SSHOPTS="-o HostKeyAlias=$hostname"

nix_pkg="$(dirname "$(dirname "$(readlink -f "$(command -v nix)")")")"
nixos_rebuild="$(nix build --no-link --print-out-paths --impure \
    --argstr lockFile "$PWD/flake.lock" \
    --argstr nix "$nix_pkg" \
    --expr '{ lockFile, nix }:
      let
        lock = (builtins.fromJSON (builtins.readFile lockFile)).nodes.nixpkgs.locked;
        pkgs = import (builtins.fetchTree lock) { };
      in
      pkgs.nixos-rebuild-ng.override { nix = builtins.storePath nix; }')"

exec "$nixos_rebuild/bin/nixos-rebuild" switch --no-reexec \
    --flake ".#$host" \
    --target-host "$target" \
    --build-host "$target" \
    --sudo --ask-sudo-password
