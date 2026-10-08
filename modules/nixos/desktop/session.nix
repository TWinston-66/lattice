{
  config,
  lib,
  pkgs,
  ...
}:
let
  # hyprsunset runs from session start but idles at its 6000K default, which is no filter
  # at all -- the daemon is only useful once something sets a temperature.
  #
  # Two things about driving it, both found by testing: the `hyprsunset` CLI flags spawn a
  # *new* daemon rather than talking to the running one (it then dies with "A CTM manager
  # is already running"), so control goes through `hyprctl hyprsunset`; and `identity`
  # leaves the reported temperature at its last set value, so it can't be used to detect
  # state. Toggling between 6000K and warm keeps the daemon's own reading authoritative,
  # which means the bar can't desync from the screen and no state file is needed.
  #
  # The warm end is per-host -- lattice.display.sunsetTemperature -- because how strong a
  # given temperature looks depends on the panel; see modules/nixos/display.nix.
  sunset = pkgs.writeShellApplication {
    name = "lattice-sunset";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.procps
    ];
    text = ''
      warm=${toString config.lattice.display.sunsetTemperature}
      neutral=6000

      current() { hyprctl hyprsunset temperature; }

      case "''${1:-toggle}" in
      on)     hyprctl hyprsunset temperature "$warm" >/dev/null ;;
      off)    hyprctl hyprsunset temperature "$neutral" >/dev/null ;;
      toggle)
        if [ "$(current)" -lt "$neutral" ]; then
          hyprctl hyprsunset temperature "$neutral" >/dev/null
        else
          hyprctl hyprsunset temperature "$warm" >/dev/null
        fi
        ;;
      status)
        temp=$(current)
        if [ "$temp" -lt "$neutral" ]; then
          printf '{"text":"󰖔","tooltip":"Night light on - %sK","class":"warm"}\n' "$temp"
        else
          printf '{"text":"󰖙","tooltip":"Night light off - %sK","class":"cool"}\n' "$temp"
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice sunset [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+1 matches the "signal" of the custom/sunset module in ~/.dotfiles/waybar.
      pkill -RTMIN+1 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync sunset || true
    '';
  };

  # The pieces that most often need a kick, under the names a person would use for them
  # rather than their units'. Each is what the session itself would do: mako and Hyprland
  # reload rather than restart (a restart drops the notification history), and audio goes
  # through the deck's own restart so the banner and its keys come along.
  restart = pkgs.writeShellApplication {
    name = "lattice-restart";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.mako
    ];
    text = ''
      case "''${1-}" in
      bar) systemctl --user restart waybar.service ;;
      deck) systemctl --user restart streamdeck.service ;;
      osd) systemctl --user reset-failed swayosd.service 2>/dev/null; systemctl --user restart swayosd.service ;;
      notifications) makoctl reload ;;
      hypr) hyprctl reload ;;
      audio) lattice-deck audio-restart ;;
      *)
        echo "usage: lattice restart <bar|deck|osd|notifications|hypr|audio>" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  ### SESSION ###
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # Apps get their own scopes. The launcher and the app binds in hyprland.lua start
  # everything through `uwsm app --`, which puts each one in its own scope under
  # app-graphical.slice. Before that, every app was a child of the compositor's own unit,
  # wayland-wm@hyprland.desktop.service. So the only thing systemd-oomd could have killed
  # for a runaway Firefox was Hyprland and the whole session with it, and it was set to
  # watch nothing at all, which left it idle.
  #
  # It watches app-graphical.slice only, and not app.slice above it. That slice holds the
  # session's own services too: waybar, mako, and tmux, whose loss would take every pane
  # down with it. Terminal workloads stay with the kernel's OOM killer, which kills a
  # process rather than a whole unit. The numbers are Omarchy's: half of each ten-second
  # window stalled on reclaim, held for 20s, by which point the desktop is already unusable.
  systemd.user.slices.app-graphical.sliceConfig = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "50%";
  };
  systemd.oomd.settings.OOM.DefaultMemoryPressureDurationSec = "20s";

  # GTK file-chooser portal; xdg-desktop-portal-hyprland doesn't implement it.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.systemPackages = with pkgs; [
    # hyprsunset ships only as a systemd.packages unit below, so its CLI -- which is how
    # the running daemon is driven -- wasn't on PATH for lattice-sunset or a shell.
    hyprsunset
    # notify-send: without it every script that tries to raise a notification fails
    # silently, mako itself was fine all along.
    libnotify
    # The same story as hyprsunset above, and for the same reason: mako ships as a
    # systemd.packages unit, which installs the service and nothing else. makoctl is how a
    # running mako is driven -- every bind in hyprland.lua goes through it, and Hyprland
    # execs those with the session PATH, not a wrapper's runtimeInputs.
    mako
    brightnessctl
    playerctl
    wl-clipboard
    cliphist
    # For udiskie-umount; the automounter itself runs as the udiskie unit below.
    udiskie
    grim
    satty
    swayosd
    xdg-user-dirs
    sunset
  ];

  systemd.user.services.waybar.path = [
    sunset
  ];

  ### AUDIO ###
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;

      # Every bluez5 codec nixpkgs ships (AAC, aptX, LDAC, LC3, Opus, mSBC) is already built in
      # and enabled by default, and bluetooth.profile-preference is already "quality", so codec
      # selection needs no help. Autoswitching does.
      #
      # With it on, anything that opens a capture stream -- a browser tab checking for a mic,
      # a meeting joining -- drags headphones from A2DP down to HFP, which is 8kHz mono, and
      # music sounds broken until they are power-cycled. Off means the headset mic is no longer
      # offered automatically; the laptop's own mic gets used instead, which is the better
      # trade here. Switch profiles by hand in blueman on the rare call that needs the headset.
      extraConfig."51-bluetooth-no-autoswitch" = {
        "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
  };

  ### SECRETS ###
  services.gnome = {
    gnome-keyring.enable = true;
    # SSH keys stay with programs.ssh.startAgent.
    gcr-ssh-agent.enable = false;
  };
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Run Electron apps natively on Wayland so they aren't blurry under fractional scaling.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  ### SESSION SERVICES ###
  systemd.packages = with pkgs; [
    hyprpaper
    mako
    hyprpolkitagent
    hyprsunset
  ];

  systemd.user.services = {
    hyprpaper.wantedBy = [ "graphical-session.target" ];
    # No start limit, for the same reason as swayosd below. On logout every OnFailure=
    # reporter and notifier D-Bus-activates mako against a compositor that is already
    # gone, which uses up the default five starts in ten seconds. A quick relogin then lands
    # inside that window, so mako refuses to start and every banner from the first half-
    # minute of the session is lost. lattice-network-notify died that way (2026-10-04).
    # Nothing sets Restart= here, so with no limit a broken mako costs one failed start
    # per notification and cannot spin.
    mako = {
      wantedBy = [ "graphical-session.target" ];
      startLimitIntervalSec = 0;
    };
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

    # No start limit: lattice-theme restarts this on every theme.css change, so a few picks
    # in quick succession are five starts inside ten seconds, and systemd's default limit
    # then leaves it failed -- where try-restart does nothing, and every volume, brightness
    # and Solaar mouse binding (all swayosd-client) goes silently dead until someone runs
    # reset-failed (2026-10-04). RestartSec keeps a real crash loop to one try a second.
    #
    # PartOf pipewire because swayosd-server does not survive pipewire going away under it:
    # its libpulse thread panics on the dropped connection, the process stays up, and every
    # key after that logs "sending into a closed channel" -- brightness included, since it
    # goes through the same dead server. Restart= never fires because nothing exited
    # (2026-10-08, after a plain `systemctl --user restart pipewire`).
    swayosd = {
      description = "Volume and brightness OSD";
      partOf = [
        "graphical-session.target"
        "pipewire.service"
      ];
      after = [
        "graphical-session.target"
        "pipewire.service"
      ];
      wantedBy = [ "graphical-session.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # Passwords stay out of the history without a filter here. wl-paste sets
    # CLIPBOARD_STATE=sensitive when the offer carries x-kde-passwordManagerHint, and
    # cliphist store drops those; Bitwarden desktop's native clipboard module sets the hint.
    # Copies from the Firefox extension carry no hint and are stored like anything else.
    cliphist = {
      description = "Clipboard history";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
      };
    };

    # Mounts USB drives as they arrive, under /run/media/winston, with a notification through
    # mako. udiskie ignores anything udisks reports as internal, so the macOS APFS partitions
    # on the Mac are never touched. No tray icon: the eject buttons in Thunar's sidebar
    # unmount, as does `udiskie-umount -a`.
    udiskie = {
      description = "Automount removable drives";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --notify --no-tray";
        Restart = "on-failure";
      };
    };

    # Starting with the session rather than at login gives tmux panes WAYLAND_DISPLAY, so GTK apps
    # launched from them don't fall back to XWayland and get upscaled blurry. Replaces continuum's boot unit.
    tmux = {
      description = "tmux default session (detached)";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # Inherit the session PATH instead of NixOS's minimal one; plugins and panes need the full system.
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.tmux}/bin/tmux new-session -d";
        ExecStop = [
          "%h/.local/share/tmux/plugins/tmux-resurrect/scripts/save.sh"
          "${pkgs.tmux}/bin/tmux kill-server"
        ];
      };
    };
  };

  lattice.cli.commands = {
    sunset = {
      exec = lib.getExe sunset;
      args = "[toggle|on|off|status]";
      summary = "Warm the screens for the night; toggle by default";
      group = "look";
      launch = [
        {
          label = "Night light: toggle";
          args = "toggle";
          icon = "weather-clear-night";
        }
      ];
    };
    restart = {
      exec = lib.getExe restart;
      args = "<bar|deck|osd|notifications|hypr|audio>";
      summary = "Restart one piece of the session";
      details = ''
        bar            waybar
        deck           the Stream Deck daemon
        osd            swayosd, the volume and brightness pill
        notifications  reload mako, keeping its history
        hypr           reload Hyprland's config
        audio          PipeWire and WirePlumber, for speakers that vanish
      '';
      group = "session";
      launch = [
        {
          label = "Restart the bar";
          args = "bar";
          icon = "view-refresh";
        }
        {
          label = "Restart the Stream Deck";
          args = "deck";
          icon = "view-refresh";
        }
        {
          label = "Restart the OSD";
          args = "osd";
          icon = "view-refresh";
        }
        {
          label = "Reload notifications";
          args = "notifications";
          icon = "view-refresh";
        }
        {
          label = "Reload Hyprland";
          args = "hypr";
          icon = "view-refresh";
        }
        {
          label = "Restart audio";
          args = "audio";
          icon = "view-refresh";
        }
      ];
    };
  };
}
