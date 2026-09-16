#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
enter_dev_shell scripts/deploy.sh "$@"

host="${1:-dell}"
case "$host" in
    dell) ;;
    *) echo "unknown host: $host" >&2; exit 1 ;;
esac
# Hosts answer SSH on the tailnet only, so the default address is the MagicDNS name.
# Pass an address explicitly to reach a host that is not on the tailnet yet.
target="winston@${2:-lattice-$host}"

host_key_alias="HostKeyAlias=lattice-$host"
export NIX_SSHOPTS="-o $host_key_alias"
pubkey="$(ssh -o "$host_key_alias" "$target" cat /etc/ssh/ssh_host_ed25519_key.pub)"
require_recipient "$host" "$pubkey"

local_nix="$(readlink -f "$(command -v nix)")"
nixos_rebuild="$(nix build --no-link --print-out-paths --impure \
    --argstr flake "$PWD" \
    --argstr nix "${local_nix%/bin/nix}" \
    --expr '{ flake, nix }:
      let pkgs = import (builtins.getFlake flake).inputs.nixpkgs { };
      in pkgs.nixos-rebuild-ng.override { nix = builtins.storePath nix; }')"

TMPDIR=/tmp exec "$nixos_rebuild/bin/nixos-rebuild" switch --no-reexec \
    --flake ".#$host" \
    --target-host "$target" \
    --build-host "$target" \
    --sudo --ask-sudo-password
