#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
enter_dev_shell scripts/set-password.sh "$@"

user="${1:-winston}"
file=secrets/common.yaml
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"

read -rsp "New password for $user: " password
echo
read -rsp "Again: " again
echo
if [[ "$password" != "$again" ]]; then
    echo "passwords do not match" >&2
    exit 1
fi

hash="$(mkpasswd --method=yescrypt --stdin <<<"$password")"

if [[ -f "$file" ]]; then
    sops set "$file" "[\"$user-password\"]" "\"$hash\""
else
    echo "$user-password: \"$hash\"" | sops encrypt --filename-override "$file" --output "$file" /dev/stdin
fi

echo "stored $user-password in $file"
