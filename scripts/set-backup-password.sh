#!/usr/bin/env bash
# Generates the restic password for modules/nixos/backup.nix, stores it in
# secrets/common.yaml, and puts it on the clipboard for Bitwarden. It refuses to replace one
# that is already set: the repository on the drive is locked with it, and a new one would
# have to be added with `restic key add` first.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
enter_dev_shell scripts/set-backup-password.sh "$@"

file=secrets/common.yaml
key=restic-password

# The admin key if this machine has it, otherwise this host's SSH key, which is a recipient
# too and needs sudo to read. sudo resets PATH, hence the full path to ssh-to-age.
keyfile="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"
if [[ -f "$keyfile" ]]; then
    export SOPS_AGE_KEY_FILE="$keyfile"
else
    SOPS_AGE_KEY="$(sudo "$(command -v ssh-to-age)" -private-key -i /etc/ssh/ssh_host_ed25519_key)"
    export SOPS_AGE_KEY
fi

if sops decrypt --extract "[\"$key\"]" "$file" >/dev/null 2>&1; then
    echo "$key is already set in $file; not replacing it" >&2
    exit 1
fi

password="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n')"
printf '%s' "$password" | jq -Rs . | sops set --value-stdin "$file" "[\"$key\"]"
echo "stored $key in $file"

# --sensitive keeps it out of cliphist (see session.nix). Cleared after two minutes unless
# something else has been copied since.
printf '%s' "$password" | wl-copy --sensitive
# shellcheck disable=SC2016 # expanded by the inner bash, from "$1"
setsid -f bash -c '
    sleep 120
    [[ "$(wl-paste -n 2>/dev/null)" == "$1" ]] && wl-copy --clear
' _ "$password" >/dev/null 2>&1
echo "The password is on the clipboard for the next two minutes. Save it in Bitwarden now:"
echo "it is the only way into the backups if this machine is lost."
