{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    rofiWithCalc
    ;

  # Do not disturb, as a mako mode rather than anything of our own: `[mode=dnd] invisible=1`
  # in ~/.dotfiles/mako is the whole implementation, and this only flips the mode and tells
  # the bar. mako owns the state, so the pill cannot desync from the daemon -- the same
  # reason lattice-sunset reads hyprsunset instead of keeping a state file.
  #
  # What `invisible` does and does not do, measured rather than read off the man page:
  # a hidden notification is still *live*, so nothing is dropped -- leaving the mode shows
  # whatever is still up, which for critical means everything, since urgency=critical carries
  # default-timeout=0. A normal notification instead times out unseen while the mode is on
  # and lands in the history, recoverable on SUPER+ALT+N. So the count below is the number
  # that will appear the moment the mode goes off, not the number missed.
  dnd = pkgs.writeShellApplication {
    name = "lattice-dnd";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      pkgs.gnugrep
      pkgs.procps
    ];
    text = ''
      # -x, because `makoctl mode` prints one mode per line and a substring match would
      # answer yes to any mode with dnd in the name.
      enabled() { makoctl mode | grep -qx dnd; }

      case "''${1:-toggle}" in
      on)  makoctl mode -a dnd >/dev/null ;;
      off) makoctl mode -r dnd >/dev/null ;;
      toggle)
        if enabled; then
          makoctl mode -r dnd >/dev/null
        else
          makoctl mode -a dnd >/dev/null
        fi
        ;;
      status)
        if enabled; then
          waiting=$(makoctl list -j | jq length)
          if [ "$waiting" -gt 0 ]; then
            printf '{"text":"󰂛","tooltip":"Do not disturb - %s waiting","class":"on"}\n' "$waiting"
          else
            printf '{"text":"󰂛","tooltip":"Do not disturb","class":"on"}\n'
          fi
        else
          printf '{"text":"󰂚","tooltip":"Notifications on","class":"off"}\n'
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice dnd [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+4 matches the "signal" of the custom/dnd module in ~/.dotfiles/waybar. 1, 2
      # and 3 are sunset, tailscale and weather.
      pkill -RTMIN+4 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync dnd || true
    '';
  };

  # Everything mako has already shown and timed out on, as a browsable list -- the whole of
  # what a "notification centre" would otherwise be a daemon for. Bound to SUPER+ALT+N; see
  # the mako binds in ~/.dotfiles/hypr/.config/hypr/hyprland.lua.
  #
  # jq, not a format string: `makoctl history` grew -f only after 1.11, which is what this
  # nixpkgs carries, so -j and a filter is the version-proof way to read it. The JSON is a
  # plain array of objects, newest first, with the fields below spelled exactly as mako
  # spells them (app_name, not app-name -- these are not the DBus hint names).
  notifyHistory = pkgs.writeShellApplication {
    name = "lattice-notifications";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      rofiWithCalc
      pkgs.wl-clipboard
      pkgs.libnotify
      pkgs.coreutils # cut
    ];
    text = ''
      # Captured once, and both passes read this copy. Reading it twice would race a
      # notification arriving mid-prompt, and the id picked from the first list would then
      # mean a different entry in the second.
      history="$(makoctl history -j)"

      # An empty prompt is indistinguishable from a bind that did nothing, and the answer
      # -- that nothing has arrived -- is worth saying out loud.
      if [ "$(printf '%s' "$history" | jq 'length')" -eq 0 ]; then
        notify-send -a lattice-notifications -u low \
          "No notification history" "Nothing has expired since mako started."
        exit 0
      fi

      # The id rides in a hidden first column, the way the cliphist bind does it, because
      # the summary alone is not unique -- a unit that fails twice has two identical lines.
      # Bodies are multi-line and rofi is not, so newlines collapse to spaces; @tsv would
      # escape them rather than break the row, but a literal \n mid-line reads badly.
      selection=$(
        printf '%s' "$history" \
          | jq -r '.[] | [
              (.id | tostring),
              ((.app_name // "?") + ": " + (.summary // "")
                + " | " + ((.body // "") | split("\n") | join(" ")))
            ] | @tsv' \
          | rofi -dmenu -i -p notifications -display-columns 2
      ) || exit 0
      [ -n "$selection" ] || exit 0
      # That `|| exit 0` is for rofi answering 1 on a dismissed prompt, which is a normal
      # outcome and must not take the script down under pipefail. It cannot tell a cancel
      # from rofi failing to reach the compositor at all, and deliberately: both end with
      # no selection and nothing to copy.

      # The body, not the summary. Going back to a notification that has already gone is
      # nearly always about something inside it -- a code, a path, a link -- and mako keeps
      # no action registry for an expired notification, so there is nothing to invoke.
      printf '%s' "$history" \
        | jq -r --argjson id "$(printf '%s' "$selection" | cut -f1)" \
            '.[] | select(.id == $id) | .body' \
        | wl-copy
    '';
  };

  # The reporter behind the OnFailure= lines on the session's own units. A unit that dies
  # is otherwise indistinguishable from a unit with nothing to say: lattice-battery-notify
  # failed on every boot for four days over one missing `awk`, and the only symptom was a
  # battery that never warned.
  notifyFailure = pkgs.writeShellApplication {
    name = "lattice-notify-failure";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.systemd
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      unit="$1"

      # Which manager owns the failing unit, because one reporter serves both. A session
      # unit's OnFailure= reaches this directly; a system unit's goes through the root
      # bridge in systemd.services below and arrives here as `system`. Only the flag
      # differs -- winston is in wheel, so the system manager and its journal are readable
      # from the session without privilege, and nothing has to be handed across.
      case "''${2:-user}" in
        user) manager=(--user) ;;
        system) manager=() ;;
        *)
          echo "usage: lattice-notify-failure <unit> [user|system]" >&2
          exit 1
          ;;
      esac

      # Two different answers, and the banner wants both. Result is systemd's own verdict
      # -- exit-code, start-limit-hit, timeout -- while the journal tail is where the
      # reason actually lives; the outage this was written for was one line of it.
      result="$(systemctl "''${manager[@]}" show -P Result -- "$unit" 2>/dev/null || true)"
      # `|| true` for grep exiting 1 on an empty capture, which pipefail would otherwise
      # turn into a failed reporter.
      log="$(journalctl "''${manager[@]}" --no-pager -o cat -n 5 -u "$unit" 2>/dev/null | grep -v '^$' || true)"

      body="''${result:-failed}"
      # An `if`, not `[ -n "$log" ] && body=...`: that list returns 1 when the tail is
      # empty and errexit takes the whole script down with it.
      if [ -n "$log" ]; then
        body="$(printf '%s\n\n%s' "$body" "$log")"
      fi

      # Onto the journal as well as the screen. If nothing owns org.freedesktop.Notifications
      # -- the one failure this cannot raise a banner for -- the attempt is still on record.
      printf '%s failed: %s\n' "$unit" "''${result:-unknown}"

      # Critical, so the default-timeout=0 in ~/.dotfiles/mako leaves it up until it is
      # dismissed: a unit breaking while nobody is looking is the case that must not time
      # out. Keyed synchronous per unit, so a unit that fails, gets fixed and fails again
      # replaces its own banner rather than stacking, while two units still get one each.
      notify-send -a lattice-systemd -u critical -i dialog-error \
        -h "string:x-canonical-private-synchronous:lattice-failure-''${2:-user}-$unit" \
        "$unit failed" "$body"
    '';
  };
in
{
  environment.systemPackages = [
    notifyHistory
    dnd
  ];

  systemd.user.services.waybar.path = [
    dnd
  ];

  systemd.user.services = {
    # The OnFailure= target for the session's own units, so a unit that gives up says so
    # on screen instead of in the journal nobody reads. %i is the failing unit's full
    # name, handed over by `OnFailure=lattice-notify-failure@%n.service` at each use site.
    #
    # It fires on every failed attempt, not only when the unit gives up. On systemd 261 a
    # unit with Restart=on-failure triggers OnFailure= before each scheduled restart and
    # again when it hits its start limit: lattice-network-notify's five-restart crash loop
    # on 2026-10-04 raised six reports. The synchronous tag in the reporter keeps those to
    # one banner per unit, so a crash loop shows up as one banner being replaced rather
    # than a stack of them.
    #
    # Nothing sets OnFailure= on this unit, deliberately. A reporter that cannot report
    # has nothing left to report with, and a self-reference would only spin.
    "lattice-notify-failure@" = {
      description = "Report %i as a desktop notification";

      # The banner needs something to receive it, and mako is Type=dbus on
      # org.freedesktop.Notifications -- so ordering after it already means the name is
      # owned, with nothing to poll for. Wants and not Requires: when mako itself is the
      # broken thing, this should still run and leave its line in the journal. The only
      # place that names the daemon, so a swap away from mako would edit here.
      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i";
      };
    };

    # Where the system half lands. The bridge in systemd.services below starts this, and the
    # only difference from the template above is the scope the reporter is told to look in:
    # a system unit's Result and journal tail live in the system manager, and asking the
    # user manager for them yields an empty banner that says nothing but "failed".
    "lattice-notify-failure-system@" = {
      description = "Report system unit %i as a desktop notification";

      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i system";
      };
    };
  };

  # The same reporter, reached from the system manager. A unit's OnFailure= resolves in the
  # manager that owns it, so `lattice-notify-failure@%n.service` spelled in a host file's
  # systemd.services lands here rather than on the user template above -- one spelling for
  # both scopes, and a unit that moves between them needs no edit at its use site.
  #
  # `--machine=winston@.host` is the whole of it: root opens the user manager's own bus by
  # name and starts the unit there, so neither a uid nor a DBUS_SESSION_BUS_ADDRESS has to
  # be reconstructed the way the Mac's sleep guard still does for its own banner. Reaching
  # the session becomes the reporter's problem instead of the failing unit's.
  #
  # With nobody logged in there is no bus to open and this fails, leaving only its journal
  # line -- the same outcome as a banner with no one in front of it. So a boot-time oneshot
  # gets less out of this than it looks: the case it does cover is that unit failing during
  # a `nixos-rebuild switch`, where a session is up by definition.
  #
  # No OnFailure= of its own, for the same reason the user template has none.
  systemd.services."lattice-notify-failure@" = {
    description = "Report system unit %i as a desktop notification";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user --machine=winston@.host start lattice-notify-failure-system@%i.service";
    };
  };

  lattice.cli.commands = {
    dnd = {
      exec = lib.getExe dnd;
      args = "[toggle|on|off|status]";
      summary = "Do not disturb: banners go straight to the history";
      group = "session";
    };
    notifications = {
      exec = lib.getExe notifyHistory;
      summary = "Browse the notification history";
      group = "session";
    };
  };
}
