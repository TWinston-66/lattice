{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    theme
    palette
    currentDir
    ;

  # Screenshots. HyprQuickFrame draws the selection overlay -- shader dimming, spring
  # animations on the selection, snap-to-window -- then hands the capture to satty for
  # annotation. It replaces the grim+slurp pair that used to be inlined here; grim is still
  # what actually takes the pixels, but HyprQuickFrame builds the geometry and the pipeline.
  #
  # Reachable two ways, because neither one covers both hosts on its own. Print is bound in
  # ~/.dotfiles/hypr/.config/hypr/hyprland.lua, and the key comes from the external keyboard
  # (NuPhy Halo65 V2), which is remapped in firmware and so emits a real KEY_SYSRQ wherever
  # it is plugged in. The Dell's built-in keyboard has a Print key too, but the Mac's
  # (hid-apple) lands on the magic_keyboard_2021_and_2024 fn table, which has no
  # KEY_SYSRQ on either fn layer -- so on the Mac with nothing plugged in, the launcher
  # entry below is the only way in. (evtest-style dumps do show KEY_SYSRQ on the internal
  # keyboard; that comes from the generic HID boot-keyboard descriptor, not from a key that
  # exists. Same trap as the backlight keys in profiles/laptop.nix.)
  #
  # Temp is the default action: HQF_ACTION below starts the overlay with the bar's "Temp"
  # toggle already on, so a capture goes to the clipboard and nowhere else -- no file in
  # ~/Pictures/Screenshots to go back and delete. Upstream reads that variable once at
  # startup (shell.qml, `tempActive`), and the toggle stays live, so the floating Temp
  # button still turns it back off mid-selection and Edit still hands off to satty. The
  # three actions are mutually exclusive, so HQF_ACTION=edit or =share picks those instead,
  # and any other value -- HQF_ACTION=save, say -- leaves all three off, which is upstream's
  # save-and-notify default.
  #
  # The bar's "Text" toggle is ours (patches/hyprquickframe-ocr.patch): it runs the capture
  # through tesseract and copies the text, on top of whatever Temp or Save does with the
  # image -- the image is copied first, so the text is what pastes and the image is one
  # entry back in cliphist. Edit is the one action it excludes, since satty would be
  # annotating a capture whose text has already been read. `o` toggles it in the overlay,
  # and HQF_OCR=1 starts with it on.
  #
  # Note that HyprQuickFrame spawns satty itself, with its own flags, so the only settings
  # of ours it honours are the ones in ~/.dotfiles/satty/.config/satty/config.toml that it
  # does not override -- `fullscreen` among them, which is why that moved out of the CLI
  # and into the config file. It passes its own --output-filename, --early-exit,
  # --init-tool and --copy-command.
  hqf = inputs.hyprquickframe.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Upstream reads theme.toml from, in order, ~/.config/hyprquickframe, then
  # ~/.config/quickshell/HyprQuickFrame, then its own install directory. XDG_CONFIG_DIRS is
  # never consulted, so the /etc/xdg drop-in that dresses waybar and mako cannot reach it.
  # Restacking the QML tree with our file as the install-directory copy themes it without
  # putting anything in $HOME.
  #
  # The parser on the other end is a hand-rolled line matcher, not a TOML library: it takes
  # `[section]` headers and `key = value`, folding the two into one camelCase name, and
  # understands bare true/false and numbers. Colours are read as #RRGGBBAA -- note that
  # upstream's own defaults look like Qt's #AARRGGBB and are simply wrong about their own
  # alpha, so every colour here is written the way the parser reads it.
  #
  # Written by hand rather than through pkgs.formats.toml, because it is wanted as text: the
  # same file is a runtime kit file (lattice.theme.extraKitFiles), so the overlay follows
  # lattice-theme and the wallpaper -- ~/.config/hyprquickframe/theme.toml, the first place
  # upstream looks, is linked to the kit's copy. The build-time copy below stays as the
  # install-directory fallback for a home that has no runtime theme yet.
  #
  # Comments stay out here, not in the file, since the parser is not TOML's. `animations` is
  # off: it gates only the two selectors (shell.qml wires it to RegionSelector's
  # globalAnimations and WindowSelector's animateSelection), where it puts a spring -- 5/0.7,
  # underdamped and slack -- between the pointer and the rectangle, so the region visibly
  # trails the cursor while you drag; the bar and toggles animate from springs of their own.
  # The toggles sit on an accent-coloured disc (toggleBackground falls back to accent), so
  # OCR's icon is crust rather than a palette colour some accent would swallow. kdeconnect is
  # not installed, so the share toggle can only ever report failure, but it is coloured
  # anyway rather than left the one thing on screen not in the theme.
  hqfThemeText =
    {
      palette,
      accent,
      accentAlt,
    }:
    ''
      accent = "${accent}"
      accentText = "${palette.crust}"
      dimOpacity = 0.6
      borderRadius = 10
      outlineThickness = 2
      bottomMargin = 60
      animations = false
      annotationTool = "satty"

      [bar]
      background = "${palette.surface0}cc"
      border = "${palette.overlay0}40"
      text = "${palette.subtext0}ff"
      shadow = "${palette.crust}80"

      [toggle]
      shadow = "${palette.crust}80"
      edit = "${palette.green}"
      temp = "${accentAlt}"
      ocr = "${palette.crust}"

      [share]
      connected = "${palette.sapphire}"
      pending = "${palette.overlay0}"
      errorIcon = "${palette.crust}"
      errorBackground = "${palette.red}"
    '';

  hqfTheme = pkgs.writeText "theme.toml" (hqfThemeText {
    inherit palette;
    accent = theme.accentHex;
    accentAlt = theme.accentAltHex;
  });

  hqfShell = pkgs.runCommand "hyprquickframe-shell" { } ''
    cp -r ${hqf}/share/hyprquickframe $out
    chmod -R u+w $out
    patch -p1 -d $out < ${./patches/hyprquickframe-ocr.patch}
    cp ${hqfTheme} $out/theme.toml

    # Each bar item is one Text holding "<glyph>  Region", the glyph coming from the
    # Material Design range of Nerd Fonts that waybar also draws from. Upstream names no
    # family, so the item takes the default UI font and every glyph comes out as tofu:
    # Qt's fontconfig backend builds its fallback list from the family alone and then
    # keeps only the fonts whose writing system it recognises, which no amount of
    # installing nerd-fonts.symbols-only changes -- that is a plain-PUA font and fc-match
    # finding it for :charset=f0489 is not something Qt ever asks. Naming the symbol font
    # outright is what works. Qt's fallback does run in the other direction, so the Latin
    # half of the string still lands on fontconfig's sans default, which is
    # theme.fonts.ui. font.families, Qt 6's real fallback list, is not reachable: the QML
    # font value type here exposes family and not families.
    #
    # Only the bar needs this. The floating toggles used to carry glyphs too -- the dead
    # `icon:` properties in shell.qml still hold them -- and upstream moved those to
    # bundled SVGs, presumably over the same thing.
    substituteInPlace $out/components/ControlBar.qml \
      --replace-fail 'font.pixelSize: 15' \
        'font.pixelSize: 15
                    font.family: "Symbols Nerd Font"'
  '';

  # What the patched overlay calls for the Text toggle: `hqf-ocr [--temp] <image>`, run
  # detached, so it owns the notification -- "Reading text..." at once, replaced in place
  # by the result -- and, with --temp, deleting the capture. tesseract is trained on dark
  # text on a light page and most of what is on screen here is the reverse, so a dark
  # capture is negated first. Small captures are upscaled 2x, which lifts 1x-scaled UI
  # text into the size it reads reliably; a large one is left alone, since at 4K it costs
  # seconds and the text in it is already big. English only -- the full language set is
  # several hundred MB.
  hqfOcr = pkgs.writeShellApplication {
    name = "hqf-ocr";
    runtimeInputs = [
      (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
      pkgs.imagemagick
      pkgs.wl-clipboard
      pkgs.libnotify
    ];
    text = ''
      temp=0
      if [ "$1" = --temp ]; then
        temp=1
        shift
      fi
      image=$1

      if [ "$temp" = 1 ]; then
        trap 'rm -f "$image"' EXIT
        where="Image copied to the clipboard"
        icon=()
      else
        where="Saved to ''${image%/*}"
        icon=(-i "$image" -h "string:image-path:$image")
      fi
      id=$(notify-send -p -a HyprQuickFrame "''${icon[@]}" "Reading text…" "$where")

      read -r dark w h < <(magick "$image" -colorspace gray -format '%[fx:mean<0.5] %w %h\n' info:)
      prep=(-colorspace gray)
      [ "$dark" = 1 ] && prep+=(-negate)
      (( w * h < 2000000 )) && prep+=(-resize 200%)

      text=$(magick "$image" "''${prep[@]}" png:- \
        | tesseract stdin stdout 2>/dev/null \
        | tr -d '\f' | sed -e 's/[[:space:]]*$//' -e '/./,$!d')

      if [ -z "$text" ]; then
        notify-send -r "$id" -a HyprQuickFrame "''${icon[@]}" "No text found" "$where"
        exit 0
      fi

      printf '%s' "$text" | wl-copy
      # mako renders Pango markup, so the preview is escaped before it goes in the body.
      preview=$(head -n 4 <<<"$text" | cut -c 1-80 \
        | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
      notify-send -r "$id" -a HyprQuickFrame "''${icon[@]}" "Text copied" "$preview"
    '';
  };

  # --path rather than upstream's --config: -c takes a *name* to look up under the
  # quickshell config directories, and only incidentally accepts a path. runtimeInputs is
  # load-bearing -- the QML shells out to every one of these by bare name.
  screenshot = pkgs.writeShellApplication {
    name = "lattice-screenshot";
    runtimeInputs = [
      pkgs.quickshell
      pkgs.grim
      pkgs.imagemagick
      pkgs.wl-clipboard
      pkgs.satty
      pkgs.libnotify
      pkgs.util-linux # setsid, which detaches hqf-ocr
      hqfOcr
    ];
    text = ''
      export HQF_ACTION="''${HQF_ACTION-temp}"
      exec quickshell --path ${hqfShell} -n "$@"
    '';
  };

  # What puts it in `rofi -show drun`. Papirus has accessories-screenshot; neither
  # HyprQuickFrame nor satty ships an icon of its own.
  screenshotItem = pkgs.makeDesktopItem {
    name = "lattice-screenshot";
    desktopName = "Screenshot";
    comment = "Select a region and annotate it";
    exec = "${screenshot}/bin/lattice-screenshot";
    icon = "accessories-screenshot";
    categories = [ "Graphics" ];
    # rofi matches these too, so the tool names find it even when "screenshot" isn't the
    # word that comes to mind.
    keywords = [
      "screenshot"
      "screen"
      "capture"
      "region"
      "snip"
      "grim"
      "satty"
      "hyprquickframe"
    ];
  };
in
{
  environment.systemPackages = [
    screenshot
    screenshotItem
  ];

  lattice.theme.extraKitFiles."theme.hqf.toml" = hqfThemeText;

  systemd.user.tmpfiles.users.winston.rules = [
    # The screenshot overlay's theme, at the first path HyprQuickFrame looks; see hqfThemeText.
    "d ${config.users.users.winston.home}/.config/hyprquickframe 0755 - - -"
    "L+ ${config.users.users.winston.home}/.config/hyprquickframe/theme.toml - - - - ${currentDir}/theme.hqf.toml"
  ];

}
