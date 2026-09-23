{
  config,
  lib,
  pkgs,
  ...
}:
let
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
      notify() {
        notify-send -a lattice-network -u "$1" -i "$2" \
          -h string:x-canonical-private-synchronous:lattice-network \
          "$3" "''${4:-}"
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
  # table by bus and product, and this keyboard (BUS_SPI, 05AC:0352) is not one of the two
  # special-cased MacBook Pro 13s, so it lands on magic_keyboard_2021_and_2024_fn_keys --
  # where F5 is MICMUTE, F6 is SLEEP, and nothing at all maps to KEY_KBDILLUM*. That
  # matches the legends Apple prints on the 2021+ function row, which has no backlight key
  # either; macOS puts it in Control Center. Note that `evtest`-style capability dumps are
  # misleading here -- the driver registers the *generic* table's capabilities
  # unconditionally at configure time, so KEY_KBDILLUMDOWN/UP show as supported on a
  # keyboard that never emits them.
  #
  # No OSD call: swayosd's server watches the LED itself (keyboard_backlight = true, its
  # default) and raises its own pill, with the keyboard-brightness icons it bundles,
  # whenever anything else moves the value. swayosd-client has no flag for this -- the
  # KBD-BACKLIGHT action exists but is only reachable from the server's own watcher.
  kbdBacklight = pkgs.writeShellApplication {
    name = "lattice-kbd-backlight";
    runtimeInputs = [ pkgs.brightnessctl ];
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
        echo "usage: lattice-kbd-backlight [raise|lower]" >&2
        exit 2
        ;;
      esac
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
  users.users.winston.extraGroups = [ "networkmanager" ];

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
    power-profiles-daemon.enable = true;

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
  systemd.services.lattice-sleep-drain = {
    description = "Record what each suspend cost in battery";

    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe sleepDrain} record";
      ExecStop = "${lib.getExe sleepDrain} report";
    };
  };

  # Both notifiers are no-ops without something owning org.freedesktop.Notifications, which
  # on this host is mako, out of the graphical profile.
  systemd.user.services = lib.mkIf config.services.graphical-desktop.enable {
    lattice-battery-notify = {
      description = "Battery level notifications";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
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
}
