#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export NIX_CONFIG="experimental-features = nix-command flakes"

# Nothing in a lattice build floats: every package version comes from the revisions pinned
# in flake.lock, and a rebuild evaluates against that lock and nothing else. Updating is
# this, and only this -- move the lock, then switch to what it now describes.
#
# No dev shell. Unlike rebuild.sh and deploy.sh this needs neither ssh-to-age nor sops, and
# rebuild.sh enters the shell for itself when we hand off at the end.

# Hashed rather than diffed against HEAD: the lock is routinely already dirty here -- an
# update left unswitched, or a second narrowing run -- and `git diff` would call that
# movement every time and go on to offer a rebuild with nothing behind it.
before="$(sha256sum flake.lock 2>/dev/null || true)"

# Argument-for-argument what `nix flake update` takes: input names to bump, or nothing at
# all to bump every one of them. `scripts/update.sh nixpkgs` is the common narrow case.
nix flake update "$@"

if [[ "$before" == "$(sha256sum flake.lock)" ]]; then
    echo
    echo "flake.lock unchanged -- already on the newest revision of everything asked for."
    exit 0
fi

# `nix flake update` has just printed old rev/date -> new rev/date per input, which is the
# whole diff in the only form worth reading; regenerating it from the lock would say less.
# The commit is the part that matters: it is what makes the update revertible, and what
# lets `git diff flake.lock` answer "what changed under me" a month from now.
echo
echo "flake.lock moved. Commit it once the switch below works out:"
echo "    git add flake.lock && git commit -m 'flake: update'"

# Asked rather than assumed because a nixpkgs or apple-silicon bump is not a cheap switch on
# the Mac: nixos-apple-silicon ships no binary cache, so a moved kernel is built on the
# machine itself (see the input's comment in flake.nix). The Dell only ever pulls from cache.
echo
read -rp "Rebuild now? [Y/n] " reply
case "$reply" in
    "" | [yY]*) ;;
    *)
        echo "Left the lock updated. Run ./scripts/rebuild.sh when ready."
        exit 0
        ;;
esac

exec ./scripts/rebuild.sh
