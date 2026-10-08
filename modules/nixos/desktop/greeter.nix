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
    ;

  toml = pkgs.formats.toml { };

  # Where the greeter finds the theme the desktop was last in. It runs as `greeter`, which
  # cannot read ~/.cache/lattice, so lattice-palette copies the two files the greeter needs
  # here on every write -- the login pick, a wallpaper step, a theme switch -- and the next
  # boot's greeter wears whatever the last session ended on. Owned by winston, since the
  # writer runs as them; the greeter only reads.
  greeterThemeDir = "/var/lib/lattice/greeter";

  # tuigreet's [theme] block, as a runtime kit file so it follows the flavour and the accent
  # like the lock screen does -- and in the lock screen's roles: the field outline is the
  # same half-accent mix, the box is mantle, labels are overlay0. tuigreet takes #rrggbb as
  # well as ANSI names, so these are the palette's colours and not their nearest names.
  greeterThemeText =
    { palette, accent, ... }:
    ''
      container = "${palette.mantle}"
      border = "#%LOCK_OUTER_BARE%"
      title = "${accent}"
      greet = "${accent}"
      time = "${palette.subtext0}"
      text = "${palette.text}"
      prompt = "${palette.overlay0}"
      input = "${palette.text}"
      action = "${palette.overlay0}"
      button = "${accent}"
    '';

  # The same block in the build-time flavour and accent, for a boot that has no copy yet.
  greeterThemeFallback =
    lib.replaceStrings [ "%LOCK_OUTER_BARE%" ] [ (mixHex 0.5 theme.accentHex palette.surface0) ]
      (greeterThemeText {
        inherit palette;
        accent = theme.accentHex;
      });

  # Everything tuigreet is told except its colours, which greeterSession appends.
  greeterConfig = toml.generate "tuigreet.toml" {
    display = {
      greeting = "lattice";
      show_time = true;
      # The lock screen's date line, with the time beside it rather than above.
      time_format = "%A, %B %-d   %H:%M";
      # "Authenticate into <hostname>" -- the lock screen does not say where it is either.
      show_title = false;
    };
    layout.width = 44;
    # Power and caps lock are the hints worth a row. The rest -- the raw uwsm command line,
    # session and background pickers, Esc to reset -- are still bound, just not advertised.
    layout.widgets.status_bar = {
      show_reset = false;
      show_command = false;
      show_session = false;
      show_background = false;
      show_session_status = false;
      show_power = true;
      show_caps_lock = true;
    };
    session = {
      command = "uwsm start -e -D Hyprland hyprland.desktop";
      sessions_dirs = [ "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions" ];
    };
    remember.username = true;
    # hyprlock's dots.
    secret = {
      mode = "characters";
      characters = "•";
    };
    power = {
      shutdown = "systemctl poweroff";
      reboot = "systemctl reboot";
    };
  };

  # regular0-7 then bright0-7, read straight off the list ../theme.nix hands the kernel as
  # vt.default_red/grn/blu, so the greeter's sixteen colours and the console's are one
  # source. console.colors is already '#'-less, which is also foot's format.
  greeterAnsi = lib.concatStringsSep "\n" (
    lib.imap0 (
      i: colour: "${if i < 8 then "regular" else "bright"}${toString (lib.mod i 8)}=${colour}"
    ) config.console.colors
  );

  # The greeter's terminal: tuigreet draws into foot under cage rather than into fbcon on
  # VT1.
  #
  # Sizing is the whole reason. fbcon has one framebuffer and one bitmap font for every
  # output it takes over, so a docked boot shares a single 16x32 cell between the Mac's
  # 254 dpi panel and the 140 dpi Samsung: 0.13" of glyph on one and 0.26" on the other, the
  # same image mirrored. No console font setting fixes both at once -- shrinking it for the
  # monitor shrinks the panel by the same factor, because the font is pixels and the screens
  # differ in pixel size. A Wayland terminal can size type from each output's own physical
  # DPI instead, which is what dpi-aware does below.
  greeterTerminal = ''
    # foot, as the greeter's terminal: greetd runs cage -> foot -> tuigreet, wired up in the
    # LOGIN block of this profile. Written from lattice.theme, so it is not the place to keep
    # an edit -- change it there.

    # 7pt is measured, not picked. fbcon's TER16x32 cell is 32px tall; foot reads the panel
    # as `eDP-1: 3024x1890+0x0@120Hz scale=3, DPI=254.24/338.99 (physical/scaled)`;
    # and JetBrains Mono's cell comes out 1.345x its pixel size (28.25px of font -> 38px of
    # cell). So 32px of cell is 23.8px of font is 6.74pt, and 7pt rounds up rather than down.
    # Measured back, it lands a 15x34 cell against fbcon's 16x32 -- 0.134" a row against
    # 0.126", so the panel ends a shade larger than the console was, never smaller. dpi-aware
    # is what makes that a physical figure rather than a pixel one, so the Samsung renders the
    # same 0.134" from its own ~140 dpi and halves what it shows today.
    #
    # dpi-aware has to be `yes` rather than the default `no`, and not because of HiDPI as
    # such: cage has no scale of its own -- its entire option set is -d -D -h -m -s -v -- so
    # every output reports scale 1, and sizing by scale would land 7pt at 96 dpi on a 254 dpi
    # panel. `yes` ignores the scale and reads the output's millimetres, which appledrm does
    # report for both outputs even though it publishes no EDID for either.
    #
    # 7pt is the undocked size, i.e. the panel's. greeterSession overrides it when the greeter
    # is going to land on an external screen instead, because equal inches is the wrong target
    # across a desk -- see there.
    font=${theme.fonts.monospace}:size=7
    dpi-aware=yes

    # cage maximises its one client and asks it not to draw decorations, so padding is all
    # the geometry there is to set -- and none of it, because tuigreet centres its own box
    # inside whatever grid it is handed.
    pad=0x0

    # foot's own terminfo is not in the system profile, only ncurses' entries are, and the
    # greeter is the worst place to find that out. tuigreet drives the screen through
    # crossterm, which writes plain ANSI and never opens terminfo, so the entry only has to
    # exist for anything else that looks; xterm-256color always does.
    term=xterm-256color

    # The build-time flavour, the console's sixteen through vt.default_red/grn/blu.
    # greeterSession overrides these with the last session's theme.foot when there is one;
    # tuigreet's own colours are hex, in its [theme], so this is the backdrop and little else.
    [colors-dark]
    background=${hex palette.base}
    foreground=${hex palette.text}
    ${greeterAnsi}
  '';

  # cage's client, and the reason there is a script here at all: the size the greeter wants
  # depends on which screen cage is about to put it on, and that is knowable before foot
  # starts but not from inside foot's config.
  #
  # dpi-aware sizes type in inches, which made the two screens agree physically and then read
  # wrong anyway: 7pt is 0.134" a row on the panel at arm's length and the same 0.134" on a
  # 32" monitor most of a desk away, where it is roughly a third too small. Angle is what the
  # eye measures, so the monitor wants that 0.134" scaled by the ratio of the viewing
  # distances -- ~28" against ~20" -- which is 0.19" and, at 1.345 cells per pixel of font,
  # 10pt. That also lands between the two sizes already ruled out by eye: fbcon's 0.26" on
  # this monitor was too big, physical parity's 0.13" too small.
  #
  # The check is any connected output that is not an internal panel, rather than this Mac's
  # HDMI-A-1 by name, so the Dell's DP outputs pick the same branch. It reads the same sysfs
  # the greeter's compositor is about to read; nothing is cached between the two.
  greeterSession = pkgs.writeShellApplication {
    name = "lattice-greeter";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.foot
      pkgs.tuigreet
    ];
    text = ''
      size=7
      for status in /sys/class/drm/card*-*/status; do
        case "$status" in *-eDP-*) continue ;; esac
        if [ "$(cat "$status")" = connected ]; then
          size=10
          break
        fi
      done

      # The last session's theme, from lattice-palette's copy. The directory is writable by a
      # user and read by the greeter, so only colour lines are taken from it: foot keys could
      # bind commands, and a tuigreet section could change the session every user logs into.
      # Anything else -- or no copy at all -- leaves the build-time colours in place.
      overrides=()
      while IFS='=' read -r key value; do
        overrides+=("--override=colors-dark.$key=$value")
      done < <(grep -E '^(foreground|background|regular[0-7]|bright[0-7])=[0-9a-fA-F]{6}$' \
        ${greeterThemeDir}/theme.foot 2>/dev/null || true)

      colours=$(grep -E '^[a-z_]+ = "#[0-9a-fA-F]{6}"$' \
        ${greeterThemeDir}/theme.greeter.toml 2>/dev/null || true)
      [ -n "$colours" ] || colours=$(cat ${pkgs.writeText "greeter-theme.toml" greeterThemeFallback})

      work=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/lattice-greeter.XXXXXX")
      {
        cat ${greeterConfig}
        printf '\n[theme]\n%s\n' "$colours"
      } >"$work/tuigreet.toml"

      # -o rather than a second config file: everything else about the two cases is identical,
      # and a font line is the one thing that differs.
      exec foot \
        --config=/etc/greetd/foot.ini \
        --override="font=${theme.fonts.monospace}:size=$size" \
        "''${overrides[@]}" \
        tuigreet --config "$work/tuigreet.toml"
    '';
  };
in
{
  ### LOGIN ###
  services.greetd = {
    enable = true;

    # cage -> foot -> tuigreet, for the per-screen sizing the console cannot do; see
    # greeterTerminal above for the arithmetic. cage is a kiosk compositor -- one client,
    # maximised, no decorations -- and it exits when that client does, so greetd starts the
    # session on exactly the same signal it did when tuigreet owned the VT. The cost over the
    # console path is 6.9 MB of store (cage brings wlroots and xwayland; foot brings 976 KB
    # and nothing that was not already here) and ~50 MB of RSS that is gone before the
    # desktop starts.
    #
    # `-m last` rather than letting cage extend across both outputs, which is what decides
    # where the greeter appears. Extending puts the window on the first output, eDP-1, and that
    # is the one output which might be a closed lid -- a greeter nobody can see. `last` follows
    # whichever output came up last instead, and a docked boot confirms that is the HDMI one:
    # the panel is already live out of simpledrm while dcp debounces its HPD for 500ms. The
    # panel then stays dark while docked, which is the other half of why greeterSession sizes
    # for the external screen when one is attached -- the greeter is on exactly one screen,
    # never both, so there is one right size rather than a compromise between two.
    #
    # `-s` keeps VT switching, which is the way out if the greeter ever comes up blank; `-d`
    # stops cage asking foot for decorations it would then have to draw.
    #
    # `-m last` is also why cage is patched. In wlroots 0.20 the output layout is freed when
    # the display's destroy signal fires, but the DRM backend tears its outputs down only
    # after that, from the event loop's destroy. On the first of them cage's `last` handler
    # re-enables whichever output remains, which adds it to the freed layout, and cage
    # segfaults in output_layout_add on every login. The handoff has already happened by
    # then, so nothing visible breaks, but it leaves a coredump per boot. cage-kiosk/cage#525
    # (for #515) skips the re-enable once the server is terminating. Drop the patch once
    # nixpkgs' cage includes it.
    #
    # No useTextGreeter: that option only adjusts greetd's own TTY plumbing so systemd cannot
    # scribble over a TUI sharing VT1 with it. The TUI is inside a compositor now, and there
    # is nothing left on the VT to protect.
    settings.default_session.command = lib.concatStringsSep " " [
      "${
        pkgs.cage.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/cage-last-mode-teardown.patch ];
        })
      }/bin/cage"
      "-s"
      "-d"
      "-m"
      "last"
      "--"
      (lib.getExe greeterSession)
    ];
  };

  # Beside tuigreet's own config below rather than in the store path of the command above, so
  # a size can be tried with `foot --config=/etc/greetd/foot.ini -o font=...` from a terminal
  # before it is committed to a boot -- and because dpi-aware sizes in inches, a window opened
  # that way on a screen renders at exactly the size the greeter will on that same screen.
  environment.etc."greetd/foot.ini".text = greeterTerminal;

  lattice.theme.extraKitFiles."theme.greeter.toml" = greeterThemeText;

  systemd.tmpfiles.rules = [ "d ${greeterThemeDir} 0755 winston - -" ];
}
