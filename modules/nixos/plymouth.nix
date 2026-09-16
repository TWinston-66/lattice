{
  config,
  lib,
  pkgs,
  ...
}:
let
  theme = config.lattice.theme;
  inherit (theme) palette;
  inherit (config.lattice) artwork;

  # Plymouth plays a throbber at 30fps, so this is a two-second loop.
  frames = 60;

  # Plymouth writes colours as hex integers.
  colour = c: "0x${lib.removePrefix "#" c}";

  themeFile = pkgs.writeText "lattice.plymouth" ''
    [Plymouth Theme]
    Name=lattice
    Description=The lattice mark, pulsing out from the centre.
    ModuleName=two-step

    [two-step]
    ImageDir=@imageDir@
    Font=${theme.fonts.monospace} 12
    TitleFont=${theme.fonts.monospace} 22

    # The mark sits dead centre, where hyprlock's clock and tuigreet's box also sit. The
    # passphrase field takes the same spot rather than sitting under the mark, because
    # two-step stops the throbber while it prompts -- the mark is not on screen to sit under.
    HorizontalAlignment=.5
    VerticalAlignment=.5
    DialogHorizontalAlignment=.5
    DialogVerticalAlignment=.5
    TitleHorizontalAlignment=.5
    TitleVerticalAlignment=.382
    MessageBelowAnimation=true

    Transition=none
    TransitionDuration=0.0

    # The wallpaper's gradient runs crust to base as well, so the desktop the splash hands
    # over to is the same picture with the lattice drawn in.
    BackgroundStartColor=${colour palette.crust}
    BackgroundEndColor=${colour palette.base}
    ProgressBarBackgroundColor=${colour palette.surface0}
    ProgressBarForegroundColor=${colour theme.accentHex}

    # UseAnimation keeps the throbber -- the pulse -- running for the whole boot.
    # UseEndAnimation would replace it with a one-shot animation this theme has no frames
    # for, and would also claim the throbber frames as that animation's.
    [boot-up]
    UseAnimation=true
    UseEndAnimation=false

    [shutdown]
    UseAnimation=true
    UseEndAnimation=false

    [reboot]
    UseAnimation=true
    UseEndAnimation=false
  '';

  splash =
    pkgs.runCommand "plymouth-lattice-theme"
      {
        nativeBuildInputs = [
          artwork.draw
          pkgs.librsvg
        ];
      }
      ''
        dir=$out/share/plymouth/themes/lattice
        mkdir -p $dir

        # One PNG per step of the pulse, numbered from 1. The prefix matters: two-step loops
        # `throbber-` for as long as the boot lasts, while `animation-` is the one-shot end
        # animation, which UseEndAnimation=false switches off -- name these `animation-` and
        # the splash is a blank screen until something asks for a password.
        for i in $(seq 0 ${toString (frames - 1)}); do
          phase=$(awk "BEGIN { printf \"%.4f\", $i / ${toString frames} }")
          lattice-art mark --phase "$phase" > frame.svg
          rsvg-convert frame.svg -o "$dir/$(printf 'throbber-%04d.png' $((i + 1)))"
        done

        # The password prompt: the field, the dots typed into it, the padlock beside it and
        # the caps-lock warning. The systemd initrd asks for the LUKS passphrase through
        # plymouth, so this dialog -- not a console prompt -- is what every boot opens with.
        for widget in entry bullet lock capslock; do
          lattice-art widget "$widget" > widget.svg
          rsvg-convert widget.svg -o "$dir/$widget.png"
        done

        substitute ${themeFile} $dir/lattice.plymouth --subst-var-by imageDir "$dir"
      '';
in
{
  # The splash is drawn from the palette, so don't rely on an importer pulling it in.
  imports = [ ./artwork.nix ];

  boot = {
    plymouth = {
      enable = true;
      theme = "lattice";
      themePackages = [ splash ];

      # The one font in the initrd, so the theme's Font= has to name this one.
      font = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";

      # Themes and tools that go looking for a distribution logo find lattice's, not the
      # NixOS snowflake. This theme doesn't draw it; `plymouth --show-splash` elsewhere might.
      logo =
        pkgs.runCommand "lattice-logo.png" { nativeBuildInputs = [ pkgs.librsvg ]; }
          "rsvg-convert -w 64 -h 64 ${
            theme.recolourSvg {
              name = "lattice-logo.svg";
              src = ../../.github/assets/logo.svg;
            }
          } -o $out";
    };

    ### SILENT BOOT ###
    # Nothing on screen between the loader and greetd but the splash. The kernel and
    # systemd still log everything to the journal; `journalctl -b` is unchanged.
    consoleLogLevel = 0;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
      "rd.udev.log_level=3"
      # Otherwise the console's cursor blinks over the splash on some handoffs.
      "vt.global_cursor_default=0"
    ];
  };

  # greetd waits on plymouth-quit-wait.service by default, so the splash stays up until
  # tuigreet is ready to draw, and the screen goes from splash straight to the greeter.
}
