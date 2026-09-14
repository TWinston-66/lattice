{ config, pkgs, ... }:
let
  toml = pkgs.formats.toml { };

  wallpaper = pkgs.runCommand "lattice-wallpaper.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    rsvg-convert -w 3840 -h 2400 ${../../../.github/assets/wallpaper.svg} -o $out
  '';
in
{
  ### SESSION ###
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  environment.systemPackages = [ pkgs.ghostty ];

  ### WALLPAPER ###
  systemd.packages = [ pkgs.hyprpaper ];
  systemd.user.services.hyprpaper.wantedBy = [ "graphical-session.target" ];

  environment.etc."xdg/hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${wallpaper}
      fit_mode = cover
    }

    splash = false
  '';

  ### LOGIN ###
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet";
  };

  environment.etc."tuigreet/config.toml".source = toml.generate "tuigreet.toml" {
    display = {
      greeting = "Welcome to lattice";
      show_time = true;
    };
    session = {
      command = "uwsm start -e -D Hyprland hyprland.desktop";
      sessions_dirs = [ "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions" ];
    };
    remember.username = true;
    secret = {
      mode = "characters";
      characters = "*";
    };
    power = {
      shutdown = "systemctl poweroff";
      reboot = "systemctl reboot";
    };

    theme = {
      container = "black";
      border = "blue";
      title = "blue";
      greet = "white";
      time = "white";
      text = "gray";
      prompt = "blue";
      input = "gray";
      action = "blue";
      button = "magenta";
    };
  };

  ### IDLE/LOCK ###
  programs.hyprlock.enable = true;

  environment.etc = {
    "xdg/hypr/hypridle.conf".text = ''
      general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
      }

      listener {
        timeout = 300
        on-timeout = loginctl lock-session
      }

      listener {
        timeout = 330
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
      }
    '';

    "xdg/hypr/hyprlock.conf".text = ''
      background {
        monitor =
        color = rgb(0, 0, 0)
      }

      input-field {
        monitor =
        size = 300, 50
        position = 0, 0
        halign = center
        valign = center
      }

      label {
        monitor =
        text = $TIME
        font_size = 64
        position = 0, 120
        halign = center
        valign = center
      }
    '';
  };
}
