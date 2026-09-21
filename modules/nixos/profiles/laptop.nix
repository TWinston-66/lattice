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
    runtimeInputs = [
      pkgs.upower
      pkgs.libnotify
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
    ];
    text = ''
      notify() {
        notify-send -a lattice-network -u "$1" -i "$2" \
          -h string:x-canonical-private-synchronous:lattice-network \
          "$3" "''${4:-}"
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
in
{
  ### KERNEL ###
  # A default only: the Mac has to run the Asahi kernel its hardware module sets.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  ### NETWORKING ###
  networking.useNetworkd = false;
  networking.networkmanager.enable = true;
  users.users.winston.extraGroups = [ "networkmanager" ];
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
      HandlePowerKey = "suspend";
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
  environment.systemPackages = [ kbdBacklight ];

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
