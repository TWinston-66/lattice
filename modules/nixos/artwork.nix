{
  config,
  lib,
  pkgs,
  ...
}:
let
  theme = config.lattice.theme;
  inherit (theme) palette;

  json = pkgs.formats.json { };

  # The generator draws from a palette file rather than baked-in colours, so the artwork
  # follows a re-accent like every other themed surface. These names are roles in the
  # drawing, not palette entries: `line` and `node` are the background grid, `warn` is the
  # boot splash's caps-lock indicator.
  paletteFor =
    {
      accent,
      accentAlt,
      palette ? theme.palette,
    }:
    json.generate "lattice-art-palette.json" {
      inherit accent accentAlt;
      inherit (palette)
        text
        base
        mantle
        crust
        ;
      line = palette.surface1;
      node = palette.overlay0;
      warn = palette.peach;
      label = palette.subtext1;
    };

  livePalette = paletteFor {
    accent = theme.accentHex;
    accentAlt = theme.accentAltHex;
  };

  # A later --palette wins, so a caller that wants other accents can pass its own.
  draw = pkgs.writeShellScriptBin "lattice-art" ''
    exec ${pkgs.python3}/bin/python3 ${../../assets/lattice-art.py} --palette ${livePalette} "$@"
  '';

  # The two fonts a deck key is drawn with, made visible to rsvg-convert inside the build
  # sandbox -- where fontconfig otherwise has no configuration at all and so finds nothing.
  # A missing family is not an error there: cairo falls back to whatever it has, a Nerd Font
  # codepoint is outside that, and the glyph rasterises as an empty box. Nothing in the
  # build log says so, which is why this is wired rather than left to the ambient config.
  keyFonts = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.nerd-fonts.symbols-only
      pkgs.jetbrains-mono
    ];
  };

  # One PNG per key, in one derivation rather than one derivation per key: forty-odd keys
  # is forty-odd python startups either way, but as a single build it is one store path and
  # one rebuild when the palette moves. The deck reads them straight off the store path --
  # streamdeck-ui takes an absolute icon path per button and never copies the file.
  # `colours` is `{ palette, accent, accentAlt }` to draw in, defaulting to the build-time
  # theme's -- the deck draws one set per flavour, so a theme switch can swap between them.
  deckKeysWith =
    colours: keys:
    pkgs.runCommand "lattice-deck-keys"
      {
        nativeBuildInputs = [
          draw
          pkgs.librsvg
        ];
        FONTCONFIG_FILE = keyFonts;
      }
      (
        ''
          mkdir -p $out
          # Somewhere writable to put a font cache, or fontconfig prints four lines of
          # complaint per key about /homeless-shelter before getting on with it anyway.
          export XDG_CACHE_HOME="$TMPDIR/cache"
        ''
        + lib.concatMapStrings (
          key:
          let
            # Interpolated rather than `toString`ed, which is not a style choice: toString
            # drops a path's string context, so an --embed file would name a store path that
            # the build was never told to depend on and so cannot see. Interpolating copies
            # the one file in and keeps the reference.
            arg =
              name: value:
              lib.optionalString (value != null && value != "")
                " ${name} ${lib.escapeShellArg (if builtins.isPath value then "${value}" else toString value)}";
          in
          ''
            lattice-art --palette ${paletteFor colours} key --index ${toString key.index}${
              arg "--glyph" (key.glyph or "")
            }${arg "--glyph-font" (key.glyphFont or "")}${arg "--glyph-size" (key.glyphSize or "")}${
              arg "--embed" (key.embed or null)
            }${arg "--label" (key.label or "")}${arg "--tone" (key.tone or "plain")}${
              arg "--bar" (key.bar or "none")
            } > key.svg
            rsvg-convert -w 72 -h 72 key.svg -o $out/${key.name}.png
          ''
        ) keys
      );

  deckKeys = deckKeysWith {
    accent = theme.accentHex;
    accentAlt = theme.accentAltHex;
  };

  wallpaper =
    {
      # A string, because `toString 1.4` is "1.400000" and that ends up in the store name.
      density ? "1.0",
      # What the generator varies the composition from -- which way the gradient runs and
      # which ring of the mark is lit. 0 varies nothing and draws the plain lattice; any
      # other number is one member of a pool.
      seed ? 0,
      accent ? theme.accentHex,
      accentAlt ? theme.accentAltHex,
      # The flavour's palette the rest of the drawing takes -- background, grid, mark text --
      # so a wallpaper can be drawn for a flavour other than the build-time one.
      palette ? theme.palette,
      # The canvas, in the units the drawing is laid out in -- and so, `spacing` being
      # fixed, what decides how much of the screen the mark covers. Sizing a canvas to a
      # screen's *logical* resolution is what puts the mark in the same relation to the UI
      # on every screen, which is the only sense in which two very different displays can
      # show the same wallpaper. See the `screens` attrset in profiles/graphical.nix.
      width ? 1920,
      height ? 1200,
      # The SVG is drawn at `width`x`height` and rasterised at a multiple of it, so the
      # falloff and the mark stay put while the output gains pixels for a larger screen.
      # Floored where it is used: a fractional scale is the normal case (2.25 on the Mac's
      # panel), and Nix renders 1344 * 2.25 as "3024.000000", which rsvg-convert rejects.
      scale ? 2,
    }:
    pkgs.runCommand
      "lattice-wallpaper-${toString seed}-${density}-${lib.removePrefix "#" accent}-${toString width}.png"
      {
        nativeBuildInputs = [
          draw
          pkgs.librsvg
        ];
      }
      ''
        lattice-art --palette ${paletteFor { inherit accent accentAlt palette; }} wallpaper \
          --width ${toString width} --height ${toString height} --density ${density} \
          --seed ${toString seed} \
          > wallpaper.svg
        rsvg-convert -w ${toString (builtins.floor (width * scale))} \
          -h ${toString (builtins.floor (height * scale))} wallpaper.svg -o $out
      '';
in
{
  # The artwork is drawn from the palette, so don't rely on an importer pulling it in.
  imports = [ ./theme.nix ];

  options.lattice.artwork = {
    draw = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = draw;
      defaultText = lib.literalExpression "<lattice-art, with the live palette>";
      description = ''
        `assets/lattice-art.py` wrapped with the live palette, as `lattice-art`. Run
        `lattice-art wallpaper --help` or `lattice-art mark --help` for the knobs.
      '';
    };

    deckKeys = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      readOnly = true;
      default = deckKeys;
      defaultText = lib.literalExpression "keys: <a directory of 72px key PNGs>";
      description = ''
        A list of Stream Deck key faces -> a directory of `<name>.png`, one per key, at the
        deck's native 72px. Each key takes `name`, `index` (0..14, across then down, which
        is what decides its slice of the deck-wide lattice) and any of `glyph`, `embed` (an
        SVG file to draw instead of a glyph), `glyphFont`, `glyphSize`, `label`, `tone` and `bar`. See
        `lattice-art key --help`; modules/nixos/streamdeck.nix is the caller.
      '';
    };

    deckKeysWith = lib.mkOption {
      type = lib.types.functionTo (lib.types.functionTo lib.types.package);
      readOnly = true;
      default = deckKeysWith;
      defaultText = lib.literalExpression "{ palette, accent, accentAlt }: keys: <a directory of 72px key PNGs>";
      description = ''
        `deckKeys` drawn in other colours: `{ palette, accent, accentAlt }` (palette optional,
        defaulting to the build-time theme's), then the same key list.
      '';
    };

    wallpaper = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      readOnly = true;
      default = wallpaper;
      defaultText = lib.literalExpression "{ density ? \"1.0\", ... }: <wallpaper PNG>";
      description = ''
        `{ density, seed, accent, accentAlt, palette, width, height, scale }` -> the wallpaper as a
        PNG. `density` is a zoom on the lattice: above 1 the grid is finer and the mark
        smaller. `width`/`height` are the canvas, which sets how much of a screen the mark
        covers; `scale` is how many output pixels each canvas unit is rasterised to. `seed`
        varies gradient direction and the lit ring, and 0, the default, varies nothing. The
        accents and `palette` default to the build-time theme's, so a variant only has to
        name what differs.
      '';
    };
  };
}
