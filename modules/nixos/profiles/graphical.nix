_: {
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
