#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export NIX_CONFIG="experimental-features = nix-command flakes"

# Builds every host in "$@" (default: all of them) the way CI can: through the `ci` flake
# output, which leaves out Apple's firmware, and short of the Asahi kernel. The kernel has no
# binary cache and takes over an hour on a hosted runner, so it is skipped along with the
# handful of derivations that sit downstream of it (modules, initrd, boot loader, the
# toplevel itself). Everything else is built: every lattice script, so shellcheck runs on
# all of them, every config file, every override, and whatever cache.nixos.org lacks.

if (($# == 0)); then
    mapfile -t hosts < <(nix eval --json .#ci --apply builtins.attrNames | jq -r '.[]')
else
    hosts=("$@")
fi

need=() skip=()
for host in "${hosts[@]}"; do
    config=".#ci.$host.config"
    echo "evaluating $host" >&2
    toplevel="$(nix eval --raw "$config.system.build.toplevel.drvPath")"
    kernel="$(nix eval --raw "$config.boot.kernelPackages.kernel.drvPath")"

    # Eval wrote every .drv into the store, so the kernel's referrers are exactly what
    # depends on it.
    mapfile -t -O "${#skip[@]}" skip < <(nix-store --query --referrers-closure "$kernel")

    # What neither this store nor a substituter has. The dry run lists it under "will be
    # built", ahead of an optional "will be fetched" list.
    mapfile -t -O "${#need[@]}" need < <(
        nix build --dry-run "$toplevel^*" 2>&1 |
            awk '/will be built:$/ { f = 1; next } /will be fetched/ { f = 0 } f { print $1 }'
    )
done

mapfile -t need < <(printf '%s\n' "${need[@]}" | sort -u | grep .)
mapfile -t build < <(comm -23 <(printf '%s\n' "${need[@]}") <(printf '%s\n' "${skip[@]}" | sort -u))

echo "building ${#build[@]} derivations, skipping $((${#need[@]} - ${#build[@]})) downstream of the kernel" >&2
if ((${#build[@]})); then
    nix build --no-link --keep-going --print-build-logs "${build[@]/%/^*}"
fi
