# shellcheck shell=bash
# Shared helpers for scripts/. Source from the repo root.

# Re-run the calling script inside the flake's dev shell, so its tools come
# from flake.lock rather than whatever happens to be installed.
use_dev_shell() {
    if [[ -z "${LATTICE_DEV_SHELL:-}" ]]; then
        exec nix develop --command "$@"
    fi
}

# Refuse to switch a host that can't decrypt secrets/common.yaml. Login
# passwords only come from there, so it would come up with every account
# locked.
require_recipient() {
    local host="$1" pubkey="$2" age
    age="$(ssh-to-age <<<"$pubkey")"
    if ! grep -q "recipient: $age\$" secrets/common.yaml; then
        cat >&2 <<EOF
$host can't decrypt secrets/common.yaml, so switching would lock every account.
Add its key to .sops.yaml:

    $age

then, from a machine with an admin key, run:

    nix develop -c sops updatekeys secrets/common.yaml
EOF
        exit 1
    fi
}
