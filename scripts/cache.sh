#!/usr/bin/env bash
set -euo pipefail

# Where the store paths a system brought in came from: which binary cache, or built on this
# machine. With no arguments, the last switch: the boot default against the generation
# before it. With two, any pair of systems; rebuild.sh passes the running system and the one
# it just built.
#
# Read from the store rather than from the build log, so it answers after the fact too. A
# substituted path carries the cache's signature (cache.nixos.org-1, lattice.cachix.org-1),
# and a path built here is "ultimate" and carries none. Of the ones built here, most are
# trivial -- unit files, config text, symlink farms, marked preferLocalBuild or
# allowSubstitutes = false because a cache round trip costs more than writing them -- so
# those are only counted, and lattice's own scripts are counted apart from the packages
# that really compiled.
if (($# == 2)); then
    old="$1" new="$2"
elif (($# == 0)); then
    mapfile -t generations < <(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' -printf '%f\n' | sort -t- -k2,2n)
    if ((${#generations[@]} < 2)); then
        echo "only one system generation; nothing to compare" >&2
        exit 1
    fi
    old="/nix/var/nix/profiles/${generations[-2]}"
    new="/nix/var/nix/profiles/${generations[-1]}"
    echo "${generations[-2]%-link} -> ${generations[-1]%-link}"
else
    echo "usage: lattice cache [old-system new-system]" >&2
    exit 2
fi

old="$(readlink -f "$old")"
new="$(readlink -f "$new")"

mapfile -t added < <(comm -13 <(nix-store -qR "$old" | sort) <(nix-store -qR "$new" | sort))
if ((${#added[@]} == 0)); then
    echo "no new store paths"
    exit 0
fi

info="$(nix path-info --json --json-format 1 "${added[@]}")"

echo "${#added[@]} new store paths"
jq -r '
    [.[] | select(.ultimate | not) | (.signatures // [])[0] // "unsigned" | split(":")[0] | sub("-[0-9]+$"; "")]
    | group_by(.) | sort_by(-length)[]
    | if .[0] == "unsigned" then "  \(length) copied in, unsigned" else "  \(length) from \(.[0])" end
' <<<"$info"

mapfile -t derivers < <(jq -r '.[] | select(.ultimate) | .deriver // empty' <<<"$info" | sort -u)
if ((${#derivers[@]} == 0)); then
    exit 0
fi
nix derivation show "${derivers[@]}" 2>/dev/null | jq -r --argjson n "${#derivers[@]}" '
    [.derivations[] | ((.structuredAttrs // {}) + .env) as $a
        | {name, trivial: (($a.preferLocalBuild // "") == "1" or $a.preferLocalBuild == true
            or ($a.allowSubstitutes // "1") == "" or $a.allowSubstitutes == false)}] as $d
    | [$d[] | select(.trivial | not) | .name] as $real
    | [$real[] | select(startswith("lattice") or startswith("unit-"))] as $ours
    | [$real[] | select(startswith("lattice") or startswith("unit-") | not)] as $pkgs
    | "  \($n) built here: \($pkgs | length) packages, \($ours | length) lattice scripts, \($n - ($real | length)) config files",
      ($pkgs | sort[] | "    \(.)")
'
