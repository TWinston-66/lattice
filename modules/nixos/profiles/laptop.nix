{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.lattice.user.name;

  upowerCfg = config.services.upower;

  # How the 5% alert words what upower is about to do at percentageAction.
  criticalAction =
    {
      PowerOff = "Shutting down";
      Hibernate = "Hibernating";
      HybridSleep = "Hybrid-sleeping";
      Suspend = "Suspending";
      Ignore = "Nothing happens";
    }
    .${upowerCfg.criticalPowerAction};

  # batsignal, which this replaces, only notifies at two levels while discharging (-w and
  # -c; -d runs a command rather than raising anything), so a 50/20/10/5 ladder cannot be
  # expressed with it. Reading upower directly also gets the time-to-empty estimate for
  # free, which is the number that actually decides whether to go find a charger.
  #
  # The last-resort action deliberately stays with upower (services.upower.percentageAction
  # below) rather than being driven from here: a polling shell loop is the wrong thing to
  # make the last line of defence for a flat battery.
  batteryNotify = pkgs.writeShellApplication {
    name = "lattice-battery-notify";
    # gawk, coreutils and gnugrep are as much runtime deps as upower is. writeShellApplication
    # appends the inherited PATH rather than replacing it, so leaving them out did not fail the
    # build -- it failed at runtime, and only for the one the user manager's PATH happened not
    # to carry: every start since 2026-09-19 died on `awk: command not found` at the first
    # upower read, five restarts and then start-limit-hit, so the whole 50/20/10/5 ladder was
    # silent while upower still powered off at percentageAction.
    runtimeInputs = [
      pkgs.upower
      pkgs.libnotify
      pkgs.gawk
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      interval=30

      # The battery that powers the machine is BAT0 on the Dell but macsmc-battery on the
      # Mac, so it is picked by role rather than name. That also skips the mouse and
      # headphones, which upower lists as batteries too.
      device=""
      for candidate in $(upower -e | grep /battery_); do
        # Not grep -q: exiting at the first match can SIGPIPE upower, and with pipefail
        # that would read as no match.
        if upower -i "$candidate" | grep 'power supply: *yes' >/dev/null; then
          device=$candidate
          break
        fi
      done
      [ -n "$device" ] || exit 0

      alert() {
        local threshold=$1 level=$2 remaining=$3
        local urgency icon title body

        case "$threshold" in
        50) urgency=low;      icon=battery-good-symbolic;    title="Battery at 50%" ;;
        20) urgency=normal;   icon=battery-low-symbolic;     title="Battery low" ;;
        10) urgency=critical; icon=battery-caution-symbolic; title="Battery very low" ;;
        *)  urgency=critical; icon=battery-empty-symbolic;   title="Battery critical" ;;
        esac

        body="$level% remaining"
        if [ -n "$remaining" ]; then
          body="$body, about $remaining left"
        fi
        if [ "$threshold" -eq 5 ]; then
          body="$body. ${criticalAction} at ${toString upowerCfg.percentageAction}%."
        fi

        # Without the synchronous hint, a drain that crosses two thresholds between polls
        # leaves both pills on screen; with it the lower one replaces the higher.
        notify-send -a lattice-battery -u "$urgency" -i "$icon" \
          -h string:x-canonical-private-synchronous:lattice-battery \
          "$title" "$body"
      }

      previous=""
      while :; do
        info=$(upower -i "$device")
        state=$(printf '%s\n' "$info" | awk '/^ *state:/ { print $2; exit }')
        level=$(printf '%s\n' "$info" | awk '/^ *percentage:/ { gsub(/%/, "", $2); print int($2); exit }')
        remaining=$(printf '%s\n' "$info" | awk -F'time to empty:' '/time to empty:/ { gsub(/^ +| +$/, "", $2); print $2; exit }')

        if [ "$state" = discharging ] && [ -n "$level" ]; then
          # The first reading only arms the ladder: with no previous level, every threshold
          # under the current charge would read as a fresh crossing and fire at once.
          if [ -n "$previous" ]; then
            for threshold in 50 20 10 5; do
              if [ "$previous" -gt "$threshold" ] && [ "$level" -le "$threshold" ]; then
                alert "$threshold" "$level" "$remaining"
              fi
            done
          fi
          previous=$level
        else
          # Charging re-arms the whole ladder, so unplugging after a top-up warns again.
          previous=""
        fi

        sleep "$interval"
      done
    '';
  };

  # The URI NetworkManager fetches to classify a link, and the body a network with nothing
  # in front of it answers with. Declared here because two things have to agree on it: the
  # connectivity block under NETWORKING, which is what makes NM detect a portal at all, and
  # lattice-portal below, which asks the same question again to find out where the portal
  # wants the browser sent.
  #
  # nixpkgs builds NetworkManager without a default URI and ships no conf.d drop-in setting
  # one, so until this exists the connectivity check is simply off. NM still transitions
  # between UNKNOWN and FULL as devices come and go, so the "Connectivity is now" arm of
  # lattice-network-notify does fire -- but FULL there is an assumption, not a measurement,
  # and the one verdict worth acting on can never be among them. Confirmed on this host
  # before the change: ConnectivityCheckAvailable and ConnectivityCheckEnabled both false
  # and ConnectivityCheckUri empty, while `nmcli general` reported "full" regardless.
  #
  # It has to be plain HTTP. The whole mechanism depends on an intermediary being able to
  # intercept and rewrite the answer, which is precisely what TLS exists to stop. The cost
  # is a beacon to a GNOME-run host every `interval` seconds on every network this laptop
  # joins; nmcheck.gnome.org is the endpoint NM upstream runs for the purpose, so it is the
  # least surprising choice, but any plain-HTTP URL that answers predictably would do.
  portalCheckUri = "http://nmcheck.gnome.org/check_network_status.txt";
  portalCheckResponse = "NetworkManager is online";

  # NM's connectivity check classifies the link and stops there. On GNOME or KDE the shell
  # is what turns a "portal" verdict into a sign-in window; there is no shell here, so this
  # is that step -- reachable from the notification lattice-network-notify raises, and by
  # hand from a terminal once that banner has been dismissed, which is the common case.
  #
  # The login URL is discovered, not guessed. A portal answers the check URI with a redirect
  # to wherever it wants the browser, so a request that deliberately does not follow it (-L
  # is absent on purpose) hands the target back in %{redirect_url}. Portals that instead
  # answer 200 with their own page carry no redirect header, and for those the check URI
  # itself is the right thing to hand the browser: the same interception happens again
  # there, where it can be followed properly.
  #
  # --private-window is what programs.captive-browser would otherwise have been for. That
  # module exists to solve two problems -- a browser profile whose DNS and HSTS state fight
  # the portal, and a resolver that isn't the portal's. The second is already handled here:
  # NM hands the wifi link's DHCP resolver to systemd-resolved, and nothing on this host
  # does DoH or DoT, so a portal's DNS interception lands. That leaves the profile, which a
  # private window covers -- no cookies in, none left behind -- without a second browser
  # engine in the closure for a page seen twice a year.
  portalSignIn = pkgs.writeShellApplication {
    name = "lattice-portal";
    runtimeInputs = [
      pkgs.curl
      pkgs.libnotify
      config.programs.firefox.finalPackage
    ];
    text = ''
      uri=${lib.escapeShellArg portalCheckUri}

      # -m 8 rather than curl's default of waiting forever: a portal that accepts the
      # connection and then never answers is a real failure mode, and this runs from a
      # click. Both requests are allowed to fail -- an unreachable check URI is itself
      # consistent with a portal, and opening the browser is the right move either way.
      target="$(curl -sS -m 8 -o /dev/null -w '%{redirect_url}' "$uri" 2>/dev/null || true)"

      if [ -z "$target" ]; then
        # No redirect. Either there is no portal, or there is one that serves its page
        # straight from the check URI -- the body is what tells the two apart, and it is
        # only worth a second request in this branch.
        if [ "$(curl -sS -m 8 "$uri" 2>/dev/null || true)" = ${lib.escapeShellArg portalCheckResponse} ]; then
          notify-send -a lattice-portal -u low -i network-wireless-symbolic \
            -h string:x-canonical-private-synchronous:lattice-portal \
            "No portal here" "This network is already passing traffic"
          exit 0
        fi
        target="$uri"
      fi

      # Detached, for the same reason lattice-tailscale detaches xdg-open: this is called
      # from a notification action, and a foreground browser would hold that open.
      firefox --private-window "$target" >/dev/null 2>&1 &
      disown || true
    '';
  };

  # NetworkManager raises nothing on its own -- nm-applet is what normally turns its events
  # into notifications, and installing it would also plant a tray icon next to blueman that
  # duplicates waybar's network module. `nmcli monitor` is the same event stream with no
  # applet attached.
  #
  # Line formats, captured from a real session on 2026-09-19 by cycling a throwaway dummy
  # connection (nmcli connection add type dummy):
  #
  #   NetworkManager is running
  #   wlp0s20f3: using connection 'some-ssid'
  #   wlp0s20f3: connecting (prepare)        <- and four more substates
  #   wlp0s20f3: connected
  #   wlp0s20f3: deactivating
  #   wlp0s20f3: disconnected
  #   wlp0s20f3: device created / device removed
  #   some-ssid: connection profile created / removed / changed
  #
  # Every class above is represented below. The four later `connecting (...)` substates
  # collapse into the one raised on (prepare), and `deactivating` is dropped because
  # `disconnected` always follows it -- otherwise a single join puts six pills on screen.
  networkNotify = pkgs.writeShellApplication {
    name = "lattice-network-notify";
    runtimeInputs = [
      pkgs.networkmanager
      pkgs.libnotify
      portalSignIn
    ];
    text = ''
      # `|| true` because a banner that can't be shown is no reason to stop watching. With
      # errexit, one notify-send failing while mako was down at login killed the monitor,
      # and Restart= went through all five tries in half a second against the same dead
      # daemon, so network banners stayed off for the rest of the session.
      notify() {
        notify-send -a lattice-network -u "$1" -i "$2" \
          -h string:x-canonical-private-synchronous:lattice-network \
          "$3" "''${4:-}" || true
      }

      # The one notification here that is not purely a report. `notify-send -A` implies
      # --wait: it blocks until the banner is acted on or closed, then prints the chosen
      # action's name. The loop below is draining `nmcli monitor` and cannot afford to
      # block -- every event behind it would queue up for however long the banner stands --
      # so the whole exchange is pushed into a background subshell.
      #
      # The action is named `default` deliberately. mako draws no buttons for actions; what
      # it does ship is on-button-left=invoke-default-action, so naming it this is what
      # makes a left click on the banner reach lattice-portal. The body says so out loud
      # for the same reason -- there is nothing on screen that looks clickable.
      #
      # Critical urgency, which /etc/xdg/mako/config gives default-timeout=0, so the banner
      # waits as long as the portal does instead of expiring in ten seconds and taking the
      # only way to act on it with it. And its own synchronous tag rather than
      # lattice-network's: the connect/disconnect pills replace each other on purpose, and
      # a portal banner sharing that group would be wiped by the next interface event.
      portal() {
        (
          action=$(notify-send -a lattice-network -u critical \
            -i network-wireless-acquiring-symbolic \
            -h string:x-canonical-private-synchronous:lattice-portal \
            -A 'default=Sign in' \
            "Sign-in required" "Click to open this network's portal" || true)
          if [ "$action" = default ]; then lattice-portal; fi
        ) &
      }

      declare -A profile

      # Process substitution rather than a pipe: a piped `while` runs in a subshell, and the
      # profile names stashed from "using connection" have to survive into the later
      # "connected" line that names them.
      while IFS= read -r line; do
        device=''${line%%:*}
        event=''${line#*: }

        # Container plumbing churns through veth pairs constantly, and the p2p-dev-* shadow
        # device mirrors every wifi transition the real interface already reports.
        case "$device" in
        veth* | br-* | docker* | virbr* | p2p-dev-*) continue ;;
        esac

        case "$line" in
        "NetworkManager is running")
          notify low network-wireless-symbolic "NetworkManager started" ;;
        "NetworkManager is now in the "*)
          notify low network-wireless-symbolic "NetworkManager" "$line" ;;
        "Connectivity is now 'portal'")
          portal ;;
        "Connectivity is now "*)
          notify low network-wireless-symbolic "Connectivity" "$line" ;;
        *": using connection "*)
          name=''${event#using connection }
          name=''${name#"'"}
          profile[$device]=''${name%"'"} ;;
        *": connecting (prepare)")
          notify low network-wireless-acquiring-symbolic "Connecting" "$device to ''${profile[$device]:-a network}" ;;
        *": connecting ("*) ;;
        *": connected")
          notify normal network-wireless-symbolic "Connected" "$device on ''${profile[$device]:-an unknown network}" ;;
        *": deactivating") ;;
        *": disconnected")
          notify normal network-wireless-offline-symbolic "Disconnected" "$device" ;;
        *": failed")
          notify critical network-error-symbolic "Connection failed" "$device" ;;
        *": unavailable")
          notify low network-wireless-offline-symbolic "Unavailable" "$device" ;;
        *": unmanaged")
          notify low network-wireless-offline-symbolic "Unmanaged" "$device" ;;
        *": device created")
          notify low network-wired-symbolic "Device added" "$device" ;;
        *": device removed")
          notify normal network-wired-symbolic "Device removed" "$device" ;;
        *": connection profile "*)
          notify low network-wireless-symbolic "Profile ''${event#connection profile }" "$device" ;;
        esac
      done < <(nmcli monitor)
    '';
  };

  # Neither laptop has a key for the keyboard backlight, so this is what the binds in
  # ~/.dotfiles/hypr call.
  #
  # On the Mac there is genuinely no such key to find: hid-apple picks its fn translation
  # table by bus and product, and this keyboard (on BUS_SPI) is not one of the two
  # special-cased MacBook Pro 13s, so it lands on magic_keyboard_2021_and_2024_fn_keys --
  # where F5 is MICMUTE, F6 is SLEEP, and nothing at all maps to KEY_KBDILLUM*. That
  # matches the legends Apple prints on the 2021+ function row, which has no backlight key
  # either; macOS puts it in Control Center. Note that `evtest`-style capability dumps are
  # misleading here -- the driver registers the *generic* table's capabilities
  # unconditionally at configure time, so KEY_KBDILLUMDOWN/UP show as supported on a
  # keyboard that never emits them.
  #
  # The OSD is raised by hand with --custom-progress, with the same icons swayosd picks for
  # its own keyboard pill. That built-in pill cannot be reached: swayosd-client has no flag
  # for it, and the server only raises it on UPower's BrightnessChangedWithSource when the
  # source is "internal" -- the firmware changing the light itself. A write from here, even
  # through UPower's SetBrightness ("external"), is deliberately ignored.
  kbdBacklight = pkgs.writeShellApplication {
    name = "lattice-kbd-backlight";
    runtimeInputs = [
      pkgs.brightnessctl
      pkgs.swayosd
    ];
    text = ''
      # kbd_backlight on the Mac, vendor-prefixed elsewhere (dell::kbd_backlight and so
      # on), and absent entirely on a machine without one -- where the bind should be a
      # no-op rather than an error. The glob stays literal when it matches nothing, which
      # the -e test below turns into that no-op.
      led=""
      for candidate in /sys/class/leds/*kbd_backlight*; do
        [ -e "$candidate/brightness" ] || continue
        led=$(basename "$candidate")
        break
      done
      [ -n "$led" ] || exit 0

      # 10% of the Mac's 255 steps, so ten presses from off to full.
      step=10

      case "''${1:-}" in
      raise) brightnessctl -q -d "$led" -c leds set "+''${step}%" ;;
      lower) brightnessctl -q -d "$led" -c leds set "''${step}%-" ;;
      *)
        echo "usage: lattice kbd-backlight [raise|lower]" >&2
        exit 2
        ;;
      esac

      # -m prints name,class,current,percent,max.
      IFS=, read -r _ _ current _ max < <(brightnessctl -m -d "$led" -c leds)
      if [ "$current" = 0 ]; then
        icon=keyboard-brightness-off-symbolic
      elif [ "$current" = "$max" ]; then
        icon=keyboard-brightness-high-symbolic
      else
        icon=keyboard-brightness-medium-symbolic
      fi
      # --custom-progress wants 0.0-1.0; the shell only has integers.
      percent=$(( current * 100 / max ))
      progress="$(( percent / 100 )).$(printf '%02d' $(( percent % 100 )))"
      # Best effort: no OSD server (a TTY, a crashed swayosd) must not fail the step.
      swayosd-client --custom-icon "$icon" --custom-progress "$progress" >/dev/null 2>&1 || true
    '';
  };
  # The keyboard backlight follows the room, the inverse of auto-brightness: lit in the dark,
  # off in daylight. Ported from Omarchy Mac's omarchy-brightness-keyboard-auto, including
  # its override rule. Any change this script did not make (the SUPER+brightness binds, or
  # anything else writing the LED) pauses it until the light has moved enough that the
  # manual choice no longer fits: 20 lux, or 40% of the reading at the time, whichever is
  # more.
  #
  # Two departures. Levels snap to the 10% steps of lattice-kbd-backlight, and a change is
  # only made when that step differs, so the light does not creep every few seconds as a
  # cloud passes. (It raises no OSD, unlike the manual step.) And
  # nothing is written with the lid shut: the sensor sits in the bezel and reads near 0
  # there, which would light the keys up under a closed, docked lid.
  #
  # The sensor is the iio device named *als* that reports in lux (aop-sensors-als on the
  # Mac; aop-sensors-las next to it is the lid angle). A machine without one never starts
  # the unit, which is gated on that path below.
  kbdBacklightAuto = pkgs.writeShellApplication {
    name = "lattice-kbd-backlight-auto";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      # Full brightness at or below darkLux, off at or above brightLux, linear between.
      darkLux=8
      brightLux=180
      step=10
      poll=5

      als=""
      for d in /sys/bus/iio/devices/iio:device*; do
        [ -r "$d/name" ] && [ -r "$d/in_illuminance_input" ] || continue
        read -r name < "$d/name"
        case "$name" in *als*) als="$d/in_illuminance_input"; break ;; esac
      done
      led=""
      for candidate in /sys/class/leds/*kbd_backlight*; do
        [ -w "$candidate/brightness" ] || continue
        led="$candidate"
        break
      done
      if [ -z "$als" ] || [ -z "$led" ]; then
        echo "no ambient light sensor or writable keyboard backlight" >&2
        exit 0
      fi
      read -r max < "$led/max_brightness"

      lidClosed() {
        [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
          org.freedesktop.login1.Manager LidClosed 2>/dev/null)" = "b true" ]
      }

      lastSet=""
      paused=0
      pauseLux=0
      while :; do
        read -r lux < "$als" || lux=""
        lux=''${lux%%.*}
        read -r current < "$led/brightness" || current=""
        case "$lux$current" in "" | *[!0-9]*) sleep "$poll"; continue ;; esac

        if [ -n "$lastSet" ] && [ "$current" != "$lastSet" ]; then
          paused=1
          pauseLux=$lux
          lastSet=$current
          echo "manual change to $current at $lux lux, pausing"
        fi

        if [ "$paused" = 1 ]; then
          delta=$(( lux > pauseLux ? lux - pauseLux : pauseLux - lux ))
          threshold=$(( pauseLux * 40 / 100 > 20 ? pauseLux * 40 / 100 : 20 ))
          if [ "$delta" -ge "$threshold" ]; then
            paused=0
            echo "light moved to $lux lux, resuming"
          fi
        fi

        if [ "$paused" = 0 ]; then
          if [ "$lux" -le "$darkLux" ]; then
            percent=100
          elif [ "$lux" -ge "$brightLux" ]; then
            percent=0
          else
            percent=$(( 100 * (brightLux - lux) / (brightLux - darkLux) ))
          fi
          percent=$(( (percent + step / 2) / step * step ))
          target=$(( max * percent / 100 ))
          # Against the value itself, not its step: 70% of 255 is 178, which reads back as 69%,
          # so comparing steps found the odd levels one short on every pass and rewrote (and
          # logged) them every five seconds forever.
          if [ "$current" != "$target" ] && ! lidClosed; then
            printf '%s\n' "$target" > "$led/brightness"
            echo "$lux lux: $percent%"
          fi
          read -r lastSet < "$led/brightness" || lastSet=$target
        fi
        sleep "$poll"
      done
    '';
  };
  # The panel follows the room the other way round: dim in the dark, full in daylight. Same
  # override rule as the keyboard above -- a change this script did not make (the brightness
  # keys through swayosd, mostly) pauses it until the light moves 20 lux or 40%.
  #
  # Eyes read light logarithmically, so the curve is a table of lux breakpoints rather than a
  # straight line, interpolated between them. 30 lux -> 35% is the level picked by hand in
  # the evening lamp light this was tuned in. A change is only made once the target is a
  # whole step away from where the panel is, so sensor jitter of a few lux never moves it.
  #
  # Nothing is written with the lid shut or the built-in panel powered off by DPMS: the
  # sensor reads near 0 under a closed lid, and there is no reason to poke a panel that is
  # off.
  screenBacklightAuto = pkgs.writeShellApplication {
    name = "lattice-screen-backlight-auto";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.hyprland
      pkgs.jq
    ];
    text = ''
      # lux:percent, ascending. Below the first point the first level holds, above the last
      # the last.
      curve="0:15 10:25 30:35 100:55 300:75 1000:100"
      step=5
      poll=5

      als=""
      for d in /sys/bus/iio/devices/iio:device*; do
        [ -r "$d/name" ] && [ -r "$d/in_illuminance_input" ] || continue
        read -r name < "$d/name"
        case "$name" in *als*) als="$d/in_illuminance_input"; break ;; esac
      done
      panel=""
      for candidate in /sys/class/backlight/*; do
        [ -w "$candidate/brightness" ] || continue
        panel="$candidate"
        break
      done
      if [ -z "$als" ] || [ -z "$panel" ]; then
        echo "no ambient light sensor or writable panel backlight" >&2
        exit 0
      fi
      read -r max < "$panel/max_brightness"

      lidClosed() {
        [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
          org.freedesktop.login1.Manager LidClosed 2>/dev/null)" = "b true" ]
      }
      # The built-in panel is eDP-* on both hosts. No hyprctl (outside Hyprland, or a
      # stale socket) counts as on, so the loop still works under anything else.
      panelOff() {
        hyprctl -j monitors 2>/dev/null \
          | jq -e 'any(.[]; (.name | startswith("eDP")) and (.dpmsStatus | not))' >/dev/null
      }

      percentFor() {
        local lux=$1 prevLux="" prevPct="" point l p
        for point in $curve; do
          l=''${point%%:*}
          p=''${point##*:}
          if [ "$lux" -le "$l" ]; then
            if [ -z "$prevLux" ]; then echo "$p"; else
              echo $(( prevPct + (p - prevPct) * (lux - prevLux) / (l - prevLux) ))
            fi
            return
          fi
          prevLux=$l
          prevPct=$p
        done
        echo "$prevPct"
      }

      lastSet=""
      paused=0
      pauseLux=0
      while :; do
        read -r lux < "$als" || lux=""
        lux=''${lux%%.*}
        read -r current < "$panel/brightness" || current=""
        case "$lux$current" in "" | *[!0-9]*) sleep "$poll"; continue ;; esac

        if [ -n "$lastSet" ] && [ "$current" != "$lastSet" ]; then
          paused=1
          pauseLux=$lux
          lastSet=$current
          echo "manual change to $current at $lux lux, pausing"
        fi

        if [ "$paused" = 1 ]; then
          delta=$(( lux > pauseLux ? lux - pauseLux : pauseLux - lux ))
          threshold=$(( pauseLux * 40 / 100 > 20 ? pauseLux * 40 / 100 : 20 ))
          if [ "$delta" -ge "$threshold" ]; then
            paused=0
            echo "light moved to $lux lux, resuming"
          fi
        fi

        if [ "$paused" = 0 ]; then
          percent=$(percentFor "$lux")
          have=$(( current * 100 / max ))
          diff=$(( percent > have ? percent - have : have - percent ))
          if [ "$diff" -ge "$step" ] && ! lidClosed && ! panelOff; then
            printf '%s\n' "$(( max * percent / 100 ))" > "$panel/brightness"
            echo "$lux lux: $percent%"
          fi
          read -r lastSet < "$panel/brightness" || lastSet=$current
        fi
        sleep "$poll"
      done
    '';
  };
  # What each suspend actually cost, as a number in the journal rather than a feeling.
  #
  # Recovering this after the fact meant reading upower's history as root and diffing it
  # by hand against the `PM: suspend entry` lines in the journal -- which is how the Mac's
  # 4.8 %/hr was first measured, and far too much work to repeat every time something in
  # the sleep path changes. The rate is the whole story on a host whose only sleep state
  # is s2idle, so it is worth having logged on every cycle.
  #
  # Reports rather than acts: nothing here changes power behaviour, it only measures it.
  sleepDrain = pkgs.writeShellApplication {
    name = "lattice-sleep-drain";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      state=/run/lattice-sleep-drain

      # Whichever supply calls itself a battery and counts in energy rather than charge:
      # macsmc-battery on the Mac, BAT0 on the Dell.
      bat=""
      for d in /sys/class/power_supply/*; do
        [ -r "$d/type" ] || continue
        [ "$(cat "$d/type")" = "Battery" ] || continue
        [ -r "$d/energy_now" ] || continue
        bat="$d"
        break
      done
      [ -n "$bat" ] || exit 0

      # Mains at either end makes the delta meaningless -- the machine may have been
      # charging for part of the sleep -- so the AC state is recorded going in and checked
      # again coming out, and any sample that saw a charger is dropped rather than logged
      # as a suspiciously good result.
      ac=0
      for d in /sys/class/power_supply/*; do
        if [ -r "$d/online" ] && [ "$(cat "$d/online")" = "1" ]; then
          ac=1
        fi
      done

      case "''${1-}" in
        record)
          printf '%s %s %s\n' "$(date +%s)" "$(cat "$bat/energy_now")" "$ac" > "$state"
          ;;

        report)
          [ -r "$state" ] || exit 0
          read -r t0 e0 ac0 < "$state"
          rm -f "$state"

          if [ "$ac0" != "0" ] || [ "$ac" != "0" ]; then
            echo "slept on mains, or charged during; no drain figure"
            exit 0
          fi

          awk -v t0="$t0" -v e0="$e0" \
              -v t1="$(date +%s)" \
              -v e1="$(cat "$bat/energy_now")" \
              -v ef="$(cat "$bat/energy_full")" '
            BEGIN {
              secs = t1 - t0

              # Under two minutes the gauge'"'"'s own granularity swamps the delta; the Mac
              # reports energy in µWh but only moves it in visible steps.
              if (secs < 120) exit

              hours = secs / 3600
              used  = (e0 - e1) / 1e6
              full  = ef / 1e6

              # Reading higher on resume than going in is gauge noise, not free charge.
              if (used <= 0 || full <= 0) exit

              watts = used / hours

              printf "slept %.2fh: %.2f Wh of %.1f Wh (%.2f W, %.2f %%/hr, %.0fh from full to empty)\n",
                     hours, used, full, watts, used / full * 100 / hours, full / watts
            }'
          ;;

        *)
          echo "usage: lattice-sleep-drain [record|report]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  ### KERNEL ###
  # A default only: the Mac has to run the Asahi kernel its hardware module sets.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  ### NETWORKING ###
  networking.useNetworkd = false;
  networking.networkmanager.enable = true;
  users.users.${user}.extraGroups = [ "networkmanager" ];

  # Detection, and only detection -- NM classifies the link and publishes the verdict on
  # D-Bus, which is where `nmcli monitor` picks it up for lattice-network-notify. Nothing
  # here signs in to anything; that is lattice-portal, up in the let block.
  #
  # `response` is left unset on purpose. NM then accepts either an "X-NetworkManager-Status:
  # online" header or a body of "NetworkManager is online", and the endpoint serves the body
  # while its CDN drops the custom header -- so the fallback is what actually matches today.
  # Pinning `response` to the body string would work now and break the moment the header is
  # the half that survives.
  #
  # 300 is NM's own default, restated because the number is the interesting part: it is the
  # ceiling on how long a portal that appears *after* a successful join goes unnoticed. The
  # join itself is checked as it happens, which is the case that actually matters.
  networking.networkmanager.settings.connectivity = {
    uri = portalCheckUri;
    interval = 300;
  };
  hardware.bluetooth = {
    enable = true;
    # Experimental is what exposes org.bluez.BatteryProvider1, so blueman and the tray show
    # a real battery percentage for the MX Master 3 and headphones instead of nothing. The
    # name oversells it -- it gates a handful of stable-in-practice D-Bus interfaces.
    settings.General.Experimental = true;
  };

  ### THUNDERBOLT ###
  # The controller runs at security level "user", so PCIe tunnels (dock Ethernet, NVMe, eGPU) need bolt to authorize devices.
  services.hardware.bolt.enable = true;

  ### MEMORY ###
  zramSwap.enable = true;
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  ### POWER ###
  services = {
    # mkDefault so a host whose hardware PPD cannot actually drive can swap in another
    # daemon on the same D-Bus name. hosts/mac does; see the tuned block there.
    power-profiles-daemon.enable = lib.mkDefault true;

    upower = {
      enable = true;
      # upower's own default, HybridSleep, needs hibernation, which not every host has.
      # Hosts that can hibernate raise this.
      criticalPowerAction = lib.mkDefault "PowerOff";

      # lattice-battery-notify's 5% alert promises the critical action at 3%; this is what
      # makes that true. upower requires action < critical < low; the other two are left at
      # their defaults, which already line up with the rest of the notification ladder.
      percentageAction = 3;
      percentageCritical = 5;
      percentageLow = 20;
    };

    logind.settings.Login = {
      HandleLidSwitch = lib.mkDefault "suspend";
      # Deliberately not "suspend". The power key is also what wakes this machine, and the
      # press that wakes it arrives at logind on resume as a fresh short press -- so waking
      # queued a second suspend straight away. Anything asked for inside that window lost:
      # logind refuses a poweroff while a sleep operation is in flight, so wlogout's Shut
      # down button returned "Action suspend already in progress" to the journal and the
      # laptop slept through the night looking like it had shut down. Suspending on purpose
      # still has the lid, hypridle, and the power menu's own button.
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "poweroff";
    };

    fwupd.enable = true;

    # Opens the keyboard-backlight LED to the video group, for lattice-kbd-backlight above.
    #
    # brightnessctl ships exactly this rule, but it chgrps to `input`, and membership of
    # `input` is read access to every evdev node on the machine -- a keylogger's worth of
    # privilege in exchange for a keyboard light. swayosd's rule, which the graphical
    # profile already installs, covers only SUBSYSTEM=="backlight" and so leaves this one
    # root-owned at 0644, which is why it has never been settable. So: the same two lines,
    # narrowed to the keyboard LED and pointed at `video`, which the graphical profile
    # already puts the user in for the panel backlight.
    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*kbd_backlight*", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';
  };

  # Levels survive reboots without help: systemd's own 99-systemd.rules tags any
  # *kbd_backlight* LED for systemd-backlight@leds:kbd_backlight.service, which saves on
  # shutdown and restores on boot.
  environment.systemPackages = [
    kbdBacklight
  ]
  ++ lib.optional config.services.graphical-desktop.enable portalSignIn;

  # Ordered Before=sleep.target and pulled in by it, so ExecStart lands going down and
  # ExecStop coming back up. StopWhenUnneeded is what makes ExecStop run at all: the unit
  # would otherwise stay active after resume and never report. Wants=, not the Requires=
  # the Mac's sleep guard uses -- a failure in instrumentation must never be the reason a
  # laptop declined to sleep.
  #
  # onFailure reaches the session through the bridge in desktop/notifications.nix, and this is
  # the system unit that most needs it: a suspend accounting unit that has stopped recording
  # looks exactly like a laptop that has not slept. Guarded on the desktop being there at
  # all, since the template only exists alongside a notifier to deliver it.
  systemd.services.lattice-sleep-drain = {
    description = "Record what each suspend cost in battery";

    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    onFailure = lib.optional config.services.graphical-desktop.enable "lattice-notify-failure@%n.service";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe sleepDrain} record";
      ExecStop = "${lib.getExe sleepDrain} report";
    };
  };

  # On resume, everything waking at once resolves hostnames before the network is back,
  # and each of those lookups holds an nsncd worker until resolved gives up on the
  # unreachable Tailscale DNS. With the default 8 workers that starves the passwd lookups
  # behind them, including hyprlock's PAM check, so the lock screen sits unresponsive
  # until nsncd hits its 10s handoff timeout and restarts. Enough workers that a burst of
  # hung DNS lookups leaves room for the account lookups queued behind it.
  systemd.services.nscd.environment.NSNCD_WORKER_COUNT = "64";

  # Both notifiers are no-ops without something owning org.freedesktop.Notifications, which
  # on this host is mako, out of the graphical profile.
  #
  # Both also carry onFailure, and they are the reason it exists: a notifier that has died
  # and a notifier with nothing to report look identical from the outside, so these two are
  # the units least able to announce their own absence. The template lives in the graphical
  # profile; %n hands it the failing unit's name.
  systemd.user.services = lib.mkIf config.services.graphical-desktop.enable {
    lattice-kbd-backlight-auto = {
      description = "Keyboard backlight from the ambient light sensor";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionPathExistsGlob = "/sys/bus/iio/devices/iio:device*/in_illuminance_input";
      serviceConfig = {
        ExecStart = lib.getExe kbdBacklightAuto;
        Restart = "on-failure";
      };
    };

    lattice-screen-backlight-auto = {
      description = "Screen brightness from the ambient light sensor";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionPathExistsGlob = "/sys/bus/iio/devices/iio:device*/in_illuminance_input";
      serviceConfig = {
        ExecStart = lib.getExe screenBacklightAuto;
        Restart = "on-failure";
      };
    };

    lattice-battery-notify = {
      description = "Battery level notifications";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      onFailure = [ "lattice-notify-failure@%n.service" ];
      serviceConfig = {
        ExecStart = lib.getExe batteryNotify;
        Restart = "on-failure";
      };
    };

    lattice-network-notify = {
      description = "NetworkManager event notifications";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      onFailure = [ "lattice-notify-failure@%n.service" ];
      serviceConfig = {
        ExecStart = lib.getExe networkNotify;
        Restart = "on-failure";
      };
    };
  };

  # Idling out sleeps the same way closing the lid does, so a host that hibernates does both.
  environment.etc."xdg/hypr/hypridle.conf".text = lib.mkIf config.services.hypridle.enable (
    lib.mkAfter ''
      listener {
        timeout = 900
        on-timeout = systemctl ${config.services.logind.settings.Login.HandleLidSwitch}
      }
    ''
  );

  lattice.cli.commands = {
    kbd-backlight = {
      exec = lib.getExe kbdBacklight;
      args = "<raise|lower>";
      summary = "Step the keyboard backlight";
      group = "devices";
    };
    sleep-drain = {
      exec = "${lib.getExe sleepDrain} report";
      summary = "Battery spent in each recent sleep";
      group = "devices";
      launch = [
        {
          label = "Battery spent in sleep";
          icon = "battery";
          terminal = true;
        }
      ];
    };
    portal = {
      exec = lib.getExe portalSignIn;
      summary = "Open the captive portal's sign-in page";
      group = "session";
      launch = [
        {
          label = "Captive portal sign-in";
          icon = "web-browser";
        }
      ];
    };
  };
}
