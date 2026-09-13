#!/usr/bin/env bash
# Hash a user's login password and store it encrypted in secrets/common.yaml.
#
# Usage: scripts/set-password.sh [user]
set -euo pipefail

if ! command -v sops >/dev/null || ! command -v mkpasswd >/dev/null; then
    exec nix shell nixpkgs#sops nixpkgs#mkpasswd --command "$0" "$@"
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

user="${1:-winston}"
file="secrets/common.yaml"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"

read -rsp "New password for $user: " pw1
echo
read -rsp "Again: " pw2
echo
if [[ "$pw1" != "$pw2" ]]; then
    echo "passwords do not match" >&2
    exit 1
fi

hash="$(printf '%s' "$pw1" | mkpasswd --method=yescrypt --stdin)"
unset pw1 pw2

if [[ -f "$file" ]]; then
    sops set "$file" "[\"$user-password\"]" "\"$hash\""
else
    printf '%s-password: "%s"\n' "$user" "$hash" |
        sops encrypt --filename-override "$file" --input-type yaml --output-type yaml /dev/stdin >"$file"
fi

echo "stored $user-password in $file"
