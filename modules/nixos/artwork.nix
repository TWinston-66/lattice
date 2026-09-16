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
    { accent, accentAlt }:
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
    };

  livePalette = paletteFor {
    accent = theme.accentHex;
    accentAlt = theme.accentAltHex;
  };

  # A later --palette wins, so a caller that wants other accents can pass its own.
  draw = pkgs.writeShellScriptBin "lattice-art" ''
    exec ${pkgs.python3}/bin/python3 ${../../assets/lattice-art.py} --palette ${livePalette} "$@"
  '';

  wallpaper =
    {
      # A string, because `toString 1.4` is "1.400000" and that ends up in the store name.
      density ? "1.0",
      accent ? theme.accentHex,
      accentAlt ? theme.accentAltHex,
      width ? 1920,
      height ? 1200,
      # The SVG is drawn at `width`x`height` and rasterised at a multiple of it, so the
      # falloff and the mark stay put while the output gains pixels for a larger screen.
      scale ? 2,
    }:
    pkgs.runCommand "lattice-wallpaper-${density}-${lib.removePrefix "#" accent}.png"
      {
        nativeBuildInputs = [
          draw
          pkgs.librsvg
        ];
      }
      ''
        lattice-art --palette ${paletteFor { inherit accent accentAlt; }} wallpaper \
          --width ${toString width} --height ${toString height} --density ${density} \
          > wallpaper.svg
        rsvg-convert -w ${toString (width * scale)} -h ${toString (height * scale)} wallpaper.svg -o $out
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

    wallpaper = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      readOnly = true;
      default = wallpaper;
      defaultText = lib.literalExpression "{ density ? \"1.0\", ... }: <wallpaper PNG>";
      description = ''
        `{ density, accent, accentAlt, width, height, scale }` -> the wallpaper as a PNG.
        `density` is a zoom on the lattice: above 1 the grid is finer and the mark smaller.
        The accents default to the live theme's, so a variant only has to name what differs.
      '';
    };
  };
}
