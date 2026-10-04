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
        echo "usage: lattice-sunset [toggle|on|off|status]" >&2
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
in
{
  ### SESSION ###
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

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
    mako.wantedBy = [ "graphical-session.target" ];
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

    # No start limit: lattice-theme restarts this on every theme.css change, so a few picks
    # in quick succession are five starts inside ten seconds, and systemd's default limit
    # then leaves it failed -- where try-restart does nothing, and every volume, brightness
    # and Solaar mouse binding (all swayosd-client) goes silently dead until someone runs
    # reset-failed (2026-10-04). RestartSec keeps a real crash loop to one try a second.
    swayosd = {
      description = "Volume and brightness OSD";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

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

}
