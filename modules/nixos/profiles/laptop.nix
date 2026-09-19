{
  config,
  lib,
  pkgs,
  ...
}:
let
  # batsignal, which this replaces, only notifies at two levels while discharging (-w and
  # -c; -d runs a command rather than raising anything), so a 50/20/10/5 ladder cannot be
  # expressed with it. Reading upower directly also gets the time-to-empty estimate for
  # free, which is the number that actually decides whether to go find a charger.
  #
  # Hibernation deliberately stays with upower (services.upower.percentageAction below)
  # rather than being driven from here: a polling shell loop is the wrong thing to make the
  # last line of defence for a flat battery.
  batteryNotify = pkgs.writeShellApplication {
    name = "lattice-battery-notify";
    runtimeInputs = [
      pkgs.upower
      pkgs.libnotify
    ];
    text = ''
      interval=30

      device=$(upower -e | grep -m1 battery_BAT) || exit 0

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
          body="$body. Hibernating at 3%."
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
in
{
  ### KERNEL ###
  boot.kernelPackages = pkgs.linuxPackages_latest;

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
      criticalPowerAction = "Hibernate";

      # lattice-battery-notify's 5% alert promises hibernation at 3%; this is what makes
      # that true. upower requires action < critical < low; the other two are left at their
      # defaults, which already line up with the rest of the notification ladder.
      percentageAction = 3;
      percentageCritical = 5;
      percentageLow = 20;
    };

    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandlePowerKey = "suspend";
      HandlePowerKeyLongPress = "poweroff";
    };

    fwupd.enable = true;
  };
  # The goal is "close the lid, open it at the next class, carry on": stay in s2idle
  # through any realistic gap, and only spend the three-password cold boot when hibernating
  # is actually worth it. 30min was far too eager -- an hour-long class always came back
  # the slow way.
  #
  # systemd-sleep(5): with a battery present the ACPI _BTP low-battery alarm is armed
  # first, and when HibernateDelaySec is also set the system hibernates on "whichever comes
  # first: low battery or the configured delay". `/sys/class/power_supply/BAT0/alarm`
  # exists, so _BTP really is available here and the battery arm is the one that usually
  # matters. The 3h is a backstop for a bag overnight, not the normal trigger.
  #
  # Leaving HibernateDelaySec unset would be the purest version -- hibernate only once the
  # battery is genuinely low -- but s2idle here costs 3.1 %/hr, which on this 52.1 Wh
  # battery is 1.62 W (measured 2026-09-19 over real suspends). That is a little above the
  # ~1.5 W a healthy S0ix should draw and ~8x a MacBook, so ~32h of sleep on a full charge:
  # fine for a class gap, not fine for a weekend. The numbers are what justify 3h rather
  # than something longer -- a 1-2h gap costs 3-6% and resumes instantly, and the backstop
  # trips at ~9%. It is also what makes HibernateOnACPower work at all:
  # that setting is only consulted when HibernateDelaySec is set, and it keeps the
  # countdown from starting while plugged in, so a lid closed at a desk never hibernates.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "3h";
    HibernateOnACPower = false;
  };

  # btintel_pcie fails its hibernate callback with -EBUSY often enough that roughly half of
  # the overnight lid-closes never actually hibernated:
  #
  #   btintel_pcie 0000:00:14.7: PM: failed to hibernate async: error -16
  #   PM: hibernation: Wakeup event detected during hibernation, rolling back.
  #
  # The kernel throws away the image it has just written and resumes; the lid is still shut,
  # so logind starts suspend-then-hibernate over, the delay has already elapsed, and it
  # fails again -- a loop every ~30s that ran for eleven hours on 2026-09-17 (2753 suspend
  # entries in one day against 1-4 on a good one), flattening the battery and writing 8.2G
  # per attempt. Taking the module out first keeps the failing callback off the hibernate
  # path entirely.
  #
  # Shaped after the sleep-actions service in nixpkgs' power-management.nix, but bound to
  # the targets that can actually hibernate rather than to sleep.target, so a plain
  # `suspend` from the power button or the session menu keeps Bluetooth connected. preStop
  # runs on resume; the mouse re-pairs on its own once the module is back.
  systemd.services.bluetooth-hibernate-workaround =
    let
      hibernating = [
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
      ];
    in
    {
      description = "Unload btintel_pcie, which fails hibernation with -EBUSY";
      wantedBy = hibernating;
      before = hibernating;
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # Neither direction is worth failing a hibernate over: if the module is already out,
      # or the reload races the PCI rescan, the sleep should still go ahead.
      script = "${pkgs.kmod}/bin/modprobe -r btintel_pcie || true";
      preStop = "${pkgs.kmod}/bin/modprobe btintel_pcie || true";
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

  environment.etc."xdg/hypr/hypridle.conf".text = lib.mkIf config.services.hypridle.enable (
    lib.mkAfter ''
      listener {
        timeout = 900
        on-timeout = systemctl suspend-then-hibernate
      }
    ''
  );

  assertions = [
    {
      assertion = config.boot.resumeDevice != "";
      message = "The laptop profile hibernates, so the host needs boot.resumeDevice.";
    }
  ];
}
