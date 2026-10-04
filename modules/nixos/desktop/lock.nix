{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    theme
    palette
    hex
    mixHex
    currentDir
    currentPanel
    currentDesk
    ;

  # The keep-awake switch, and the one mechanism behind both surfaces that offer it.
  #
  # waybar's built-in idle_inhibitor was the obvious thing and is the wrong shape here: it
  # holds a zwp_idle_inhibit_manager_v1 lock on waybar's *own* surface, which nothing
  # outside waybar can read or release. So a Stream Deck key could only ever have been a
  # second switch disagreeing with the first -- press one and the other still shows the
  # opposite, both of them telling the truth about their own lock.
  #
  # So "stay awake" is a logind idle inhibitor held by a transient user unit, and
  # `systemctl is-active` on that unit is a state both surfaces can read and neither owns.
  # hypridle honours logind idle inhibitors (ignore_systemd_inhibit defaults to false), so
  # every listener pauses -- the lock, the blank and the deck dim alike.
  #
  # This used to stop hypridle outright, which also took out its before_sleep_cmd: with
  # keep-awake left on, a lid close suspended and resumed straight to an unlocked desktop
  # (2026-10-04). Keeping hypridle running keeps the lock-before-sleep, and its
  # inhibit_sleep still holds the suspend until hyprlock is up.
  #
  # `on` means staying awake, matching the bar's old activated/deactivated.
  idleInhibit = pkgs.writeShellApplication {
    name = "lattice-idle";
    runtimeInputs = [
      pkgs.systemd
      pkgs.procps
    ];
    text = ''
      unit=lattice-awake.service

      awake() { systemctl --user is-active --quiet "$unit"; }

      stay_awake() {
        awake || systemd-run --user --unit="$unit" --quiet \
          systemd-inhibit --what=idle --who=lattice-idle --why="Keep awake" sleep infinity
      }

      case "''${1:-toggle}" in
      on)  stay_awake ;;
      off) systemctl --user stop "$unit" ;;
      toggle)
        if awake; then
          systemctl --user stop "$unit"
        else
          stay_awake
        fi
        ;;
      status)
        if awake; then
          printf '{"text":"󰅶","tooltip":"Staying awake","class":"awake"}\n'
        else
          printf '{"text":"󰾪","tooltip":"Idle timers active","class":"idle"}\n'
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-idle [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+5 matches the "signal" of custom/idle in ~/.dotfiles/waybar. 1 to 4 are
      # sunset, tailscale, weather and dnd.
      pkill -RTMIN+5 waybar || true

      # And the deck's key for it, as the other three do.
      lattice-deck sync awake || true
    '';
  };
in
{
  environment.systemPackages = [
    idleInhibit
  ];

  systemd.user.services.waybar.path = [
    idleInhibit
  ];

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

      # The Stream Deck's backlight, on the same timeout as the lock above so the two go
      # dark together. It is only the backlight: streamdeck-ui knows nothing about the lock
      # screen, so its keys still work while the session is locked -- behind hyprlock's
      # input grab, where the windows they open cannot be seen or typed into.
      #
      # This rather than streamdeck-ui's own display_timeout, which is off in
      # modules/nixos/streamdeck.nix: its dimmer eats the first press after it dims, and a
      # key that does nothing the first time is worse than a lit deck.
      listener {
        timeout = 300
        on-timeout = lattice-deck dim
        on-resume = lattice-deck wake
      }
    '';

    "xdg/hypr/hyprlock.conf".text = ''
      # The colours that follow the wallpaper and the flavour. These are the fallback --
      # the build-time flavour with entry 0's pair, the live accent -- and lattice-palette
      # rewrites the sourced file on every pick and theme switch. hyprlang takes the last
      # definition of a variable, so the source has to come after these and both have to
      # come before the blocks that read them. A missing file is survivable: hyprlock logs
      # the error and falls through to these, which is the right answer anyway. Bare hex,
      # because the placeholder's markup takes them as well as rgb() -- there as "##", which
      # is hyprlang's escape for a literal '#'; a single one would start a comment.
      $lockOuter = ${mixHex 0.5 theme.accentHex palette.surface0}
      $lockCheck = ${hex theme.accentAltHex}
      $lockBase = ${hex palette.base}
      $lockMantle = ${hex palette.mantle}
      $lockText = ${hex palette.text}
      $lockSubtext = ${hex palette.subtext0}
      $lockMuted = ${hex palette.overlay0}
      $lockFail = ${hex palette.red}
      $lockCaps = ${hex palette.yellow}
      source = ${currentDir}/theme.hyprlock

      general {
        hide_cursor = true
      }

      # Two blocks for the same reason there are two of every wallpaper: an image sized for
      # the desk monitor has too small a mark on the panel. The generic one comes first and
      # the panel's second, so on eDP-1 the later block is the one left showing.
      background {
        monitor =
        path = ${currentDesk}
        color = rgb($lockBase)
      }

      background {
        monitor = eDP-1
        path = ${currentPanel}
        color = rgb($lockBase)
      }

      # Positions are absolute output pixels measured from the centre of the screen, positive
      # upwards -- not logical pixels, so the monitor scale does not enter into them, and not
      # a fraction of the screen either, so one set of numbers has to clear the mark on every
      # display it can land on.
      #
      # What they have to clear is the lattice mark in the middle of the wallpaper, and the
      # panel is the binding constraint: the same drawing is sized for the screen it is drawn
      # for, so on the panel canvas the mark covers y 640..1250 of 1890 (+/-305px, 16.1% of
      # the height either side of centre) while on the desk canvas it is only +/-203 of 2160
      # (9.4%). Clear 305 and the desk monitor is clear with room to spare.
      #
      # The old 360/260/-320 were tuned against the desk drawing and so put the date inside
      # the panel's mark and the clock and password field across its top and bottom rows --
      # three bright things on a bright hexagon, which is what made it unreadable. Measured
      # off headless renders at both canvas sizes, these land at y 396..491 (clock),
      # 558..580 (date) and 1342..1374 (field) on the panel: 60px clear above the mark and
      # 92 below.
      label {
        monitor =
        text = $TIME
        color = rgb($lockText)
        font_size = 96
        font_family = ${theme.fonts.monospace} ExtraBold
        position = 0, 500
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:60000] date +"%A, %B %-d"
        color = rgb($lockSubtext)
        font_size = 22
        font_family = ${theme.fonts.monospace}
        position = 0, 375
        halign = center
        valign = center
      }

      input-field {
        monitor =
        size = 320, 56
        position = 0, -400
        halign = center
        valign = center
        rounding = 14
        outline_thickness = 2
        outer_color = rgb($lockOuter)
        inner_color = rgb($lockMantle)
        font_color = rgb($lockText)
        font_family = ${theme.fonts.monospace}
        check_color = rgb($lockCheck)
        fail_color = rgb($lockFail)
        capslock_color = rgb($lockCaps)
        placeholder_text = <span foreground="##$lockMuted">password</span>
        fail_text = $FAIL
        fade_on_empty = false
        dots_size = 0.25
        dots_spacing = 0.3
      }
    '';
  };
}
