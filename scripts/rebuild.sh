#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
export NIX_CONFIG="experimental-features = nix-command flakes"
enter_dev_shell scripts/rebuild.sh "$@"

host="${1:-$(hostname)}"
host="${host#lattice-}"

key=/etc/ssh/ssh_host_ed25519_key
if [[ ! -f "$key" ]]; then
    sudo ssh-keygen -q -t ed25519 -N "" -f "$key"
fi
require_recipient "$host" "$(cat "$key.pub")"

# A switch writes this session's user units but does not start or restart them: systemd
# manages the system manager's own units and leaves the user manager's to the next login. So
# waybar, hypridle and the deck keep running the *previous* generation's unit -- its PATH,
# its ExecStart, its drop-ins -- and the config on disk quietly stops describing what is
# running. That is not theoretical: the unit that repaints the Stream Deck spent a login
# painting the VPN key wrong, because it was still running with the PATH it had before
# lattice-deck was added to it, and a missing command reads as an empty status rather than
# as an error.
#
# Hence: note what each of these units is given now, and after the switch restart the ones
# that actually changed. Comparing rather than restarting unconditionally is what keeps an
# unrelated rebuild from flashing the bar off and on.
#
# The value is any config the unit reads that is not the unit file or a drop-in; everything
# here is an /etc symlink into the store, so the targets are the whole of what a switch can
# change about it.
declare -A session_units=(
    [waybar]=""
    [hypridle]="/etc/xdg/hypr/hypridle.conf"
    [swayosd]=""
    [streamdeck]=""
)

session_generation() {
    local unit="$1" extra="$2" dropins="/etc/systemd/user/$1.service.d"
    {
        readlink -f "/etc/systemd/user/$unit.service" || true
        if [[ -d "$dropins" ]]; then
            find "$dropins" -type l -exec readlink -f {} + | sort || true
        fi
        if [[ -n "$extra" ]]; then
            readlink -f "$extra" || true
        fi
    } 2>/dev/null | sha256sum
}

# Whether each was running is recorded alongside, and it is the half that matters: a switch
# *stops* a user unit whose definition changed -- root's systemd cannot kill the user
# manager's cgroup, so it hands the stop over and never starts it again -- and the unit is
# then inactive by the time the loop below looks at it. Asking "is it running now" would skip
# exactly the units the switch just took down. The Stream Deck stayed dark through a whole
# rebuild that way.
declare -A before=() was_running=()
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    for unit in "${!session_units[@]}"; do
        before[$unit]="$(session_generation "$unit" "${session_units[$unit]}")"
        was_running[$unit]="$(systemctl --user is-active "$unit.service" || true)"
    done
fi

# What the switch changed in the store, for the summary below.
old_system="$(readlink -f /run/current-system)"

nixos-rebuild switch --flake ".#$host" --sudo

# The hypr configs this flake generates -- /etc/xdg/hypr/lattice.lua and the hyprpaper,
# hypridle and hyprlock confs beside it -- are /etc symlinks whose target moves on every
# switch. Hyprland's autoreload watches the path, not the store path behind it, so a running
# session keeps the config it started with until it is told to reread.
#
# Guarded on the signature rather than on `command -v hyprctl`: the variable is set only
# inside a Hyprland session, so a switch from a TTY or over SSH skips this instead of
# failing an otherwise good rebuild on a socket that is not there.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null

    # mako reads /etc/xdg/mako, which moves with the theme, and a reload rather than a
    # restart is deliberate: a restart drops the notification history that
    # lattice-notifications browses. Unconditional because it costs nothing and shows
    # nothing -- the same bargain as the hyprctl reload above.
    makoctl reload || true

    # So the manager has read the units just written, whether or not the switch did it.
    systemctl --user daemon-reload

    for unit in "${!session_units[@]}"; do
        if [[ "$(session_generation "$unit" "${session_units[$unit]}")" == "${before[$unit]}" ]]; then
            continue
        fi
        # Only what was up before the switch: a unit that was down is down on purpose, or is
        # waiting for the next login to be pulled in by graphical-session.target, and
        # starting it here would pre-empt that. `restart` rather than `start`, because this
        # has to cover both the unit the switch stopped and the one it left running.
        if [[ "${was_running[$unit]}" == "active" ]]; then
            echo "restarting $unit, which this generation changed"
            systemctl --user restart "$unit.service"
        fi
    done

    # Every wallpaper in the pool lands on a new store path whenever the artwork or the
    # canvases change, and hyprpaper goes on showing the old one -- which the next `nh clean`
    # deletes, taking hyprlock's background with it, since that is read from
    # ~/.cache/lattice at launch. Re-applying the index that is already up re-points both at
    # this generation's copy of the same image.
    wallpaper_state="${XDG_RUNTIME_DIR:-/tmp}/lattice-wallpaper"
    if [[ -r "$wallpaper_state" ]]; then
        lattice-wallpaper "$(cat "$wallpaper_state")" >/dev/null || true
    fi
fi

# What actually moved, read from the store rather than from the flake: every package whose
# version changed, and the size it cost. `nix store diff-closures` is already here, where nvd
# would be another input for the same answer.
#
# Capped, because the honest answer to a nixpkgs bump is hundreds of lines and this is meant
# to be the last thing read before the terminal is closed. The full command is printed in
# place of the tail so it is one paste away.
new_system="$(readlink -f /run/current-system)"
if [[ "$new_system" != "$old_system" ]]; then
    diff_lines="$(nix store diff-closures "$old_system" "$new_system" 2>/dev/null || true)"
    if [[ -z "$diff_lines" ]]; then
        echo "no package changes; the switch was configuration only"
    else
        echo
        head -n 25 <<<"$diff_lines"
        if (($(wc -l <<<"$diff_lines") > 25)); then
            printf '... %s more:\n    nix store diff-closures %s %s\n' \
                "$(($(wc -l <<<"$diff_lines") - 25))" "$old_system" "$new_system"
        fi
    fi
fi
