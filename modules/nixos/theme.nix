{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lattice.theme;

  # Catppuccin's ANSI 0-15 are not all palette entries: the bright half is its own set of
  # lighter variants, so they're kept beside the palette rather than derived from it.
  hexDigits = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    a = 10;
    b = 11;
    c = 12;
    d = 13;
    e = 14;
    f = 15;
  };

  byte =
    hex: at:
    let
      pair = lib.toLower (lib.substring at 2 hex);
    in
    16 * hexDigits.${lib.substring 0 1 pair} + hexDigits.${lib.substring 1 1 pair};

  # "#89b4fa" -> "137;180;250", for os-release's ANSI_COLOR.
  rgbOf =
    color:
    let
      hex = lib.removePrefix "#" color;
    in
    lib.concatMapStringsSep ";" (at: toString (byte hex at)) [
      0
      2
      4
    ];

  # The palette's chromatic half. catppuccin-gtk and catppuccin-papirus-folders only build
  # for these, so an accent outside the list has to fail here rather than inside an override.
  accentNames = [
    "rosewater"
    "flamingo"
    "pink"
    "mauve"
    "red"
    "maroon"
    "peach"
    "yellow"
    "green"
    "teal"
    "sky"
    "sapphire"
    "blue"
    "lavender"
  ];

  # The assets under .github/assets are drawn in stock Mocha with the blue accent, so
  # recolouring one is a straight substitution of those literals onto the live palette.
  assetColours = [
    {
      from = "#89b4fa";
      to = cfg.accentHex;
    }
    {
      from = "#b4befe";
      to = cfg.accentAltHex;
    }
    {
      from = "#45475a";
      to = cfg.palette.surface1;
    }
    {
      from = "#6c7086";
      to = cfg.palette.overlay0;
    }
    {
      from = "#cdd6f4";
      to = cfg.palette.text;
    }
    {
      from = "#1e1e2e";
      to = cfg.palette.base;
    }
    {
      from = "#181825";
      to = cfg.palette.mantle;
    }
    {
      from = "#11111b";
      to = cfg.palette.crust;
    }
  ];

  # Two passes through placeholders, so a replaced colour can't be matched again by a later
  # rule. Without them `accent = "lavender"` would collapse both accents onto one colour.
  sedArgs =
    let
      pass = f: lib.concatMapStrings (p: " -e 's/${f p}/g'") assetColours;
    in
    pass (p: "${p.from}/@@${lib.removePrefix "#" p.from}@@")
    + pass (p: "@@${lib.removePrefix "#" p.from}@@/${p.to}");

  recolourSvg =
    {
      name,
      src,
    }:
    pkgs.runCommand name { } "sed${sedArgs} ${src} > $out";

  # Every generated file gets the whole palette plus `accent`/`accentAlt` aliases, so
  # configs can name the role instead of the colour and follow a re-accent for free.
  named = cfg.palette // {
    accent = cfg.accentHex;
    accentAlt = cfg.accentAltHex;
  };

  renderNamed =
    f:
    lib.concatStrings (
      lib.mapAttrsToList f (lib.filterAttrs (n: _: n != "accent" && n != "accentAlt") named)
    );
in
{
  options.lattice.theme = {
    flavor = lib.mkOption {
      type = lib.types.str;
      default = "mocha";
      description = "Catppuccin flavour name, used to pick themed packages.";
    };

    palette = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "Colour name to `#rrggbb`. Every generated config is written from this.";
      default = {
        rosewater = "#f5e0dc";
        flamingo = "#f2cdcd";
        pink = "#f5c2e7";
        mauve = "#cba6f7";
        red = "#f38ba8";
        maroon = "#eba0ac";
        peach = "#fab387";
        yellow = "#f9e2af";
        green = "#a6e3a1";
        teal = "#94e2d5";
        sky = "#89dceb";
        sapphire = "#74c7ec";
        blue = "#89b4fa";
        lavender = "#b4befe";
        text = "#cdd6f4";
        subtext1 = "#bac2de";
        subtext0 = "#a6adc8";
        overlay2 = "#9399b2";
        overlay1 = "#7f849c";
        overlay0 = "#6c7086";
        surface2 = "#585b70";
        surface1 = "#45475a";
        surface0 = "#313244";
        base = "#1e1e2e";
        mantle = "#181825";
        crust = "#11111b";
      };
    };

    bright = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "Catppuccin's lighter ANSI 9-14 variants, which are not palette entries.";
      default = {
        red = "#f37799";
        green = "#89d88b";
        yellow = "#ebd391";
        blue = "#74a8fc";
        pink = "#f2aede";
        teal = "#6bd7ca";
      };
    };

    accent = lib.mkOption {
      type = lib.types.str;
      default = "blue";
      example = "mauve";
      description = "Palette entry used as the primary accent. Drives borders, prompts and highlights.";
    };

    accentAlt = lib.mkOption {
      type = lib.types.str;
      default = "lavender";
      description = "Palette entry used as the secondary accent, e.g. the far end of a gradient.";
    };

    fonts = {
      ui = lib.mkOption {
        type = lib.types.str;
        default = "Noto Sans";
        description = "UI font family.";
      };
      monospace = lib.mkOption {
        type = lib.types.str;
        default = "JetBrains Mono";
        description = "Monospace font family.";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 9;
        description = "UI font size in points.";
      };
    };

    accentHex = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = cfg.palette.${cfg.accent} or cfg.palette.blue;
      defaultText = lib.literalExpression "config.lattice.theme.palette.\${config.lattice.theme.accent}";
      description = "Resolved accent colour.";
    };

    accentAltHex = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = cfg.palette.${cfg.accentAlt} or cfg.palette.lavender;
      defaultText = lib.literalExpression "config.lattice.theme.palette.\${config.lattice.theme.accentAlt}";
      description = "Resolved secondary accent colour.";
    };

    rgbOf = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      default = rgbOf;
      defaultText = lib.literalExpression "color: \"r;g;b\"";
      description = "`\"#rrggbb\"` -> `\"r;g;b\"`, for the truecolor escape sequences.";
    };

    accentRgb = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = rgbOf cfg.accentHex;
      defaultText = lib.literalExpression "\"137;180;250\"";
      description = "Accent as decimal `r;g;b`, for escape sequences.";
    };

    recolourSvg = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      readOnly = true;
      default = recolourSvg;
      defaultText = lib.literalExpression "{ name, src }: <recoloured SVG>";
      description = ''
        `{ name, src }` -> that SVG with the stock Mocha literals swapped for the live
        palette. Assets stay drawn in the default palette and follow a re-accent for free.
      '';
    };

    accentAnsi = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        {
          rosewater = "white";
          flamingo = "white";
          pink = "magenta";
          mauve = "magenta";
          red = "red";
          maroon = "red";
          peach = "yellow";
          yellow = "yellow";
          green = "green";
          teal = "cyan";
          sky = "cyan";
          sapphire = "cyan";
          blue = "blue";
          lavender = "blue";
        }
        .${cfg.accent} or "blue";
      description = "Nearest ANSI colour name for the accent, for tools that take names, not hex.";
    };
  };

  config = {
    assertions = [
      {
        assertion = lib.elem cfg.accent accentNames;
        message = "lattice.theme.accent is \"${cfg.accent}\"; it must be one of ${lib.concatStringsSep ", " accentNames}.";
      }
      {
        assertion = lib.elem cfg.accentAlt accentNames;
        message = "lattice.theme.accentAlt is \"${cfg.accentAlt}\"; it must be one of ${lib.concatStringsSep ", " accentNames}.";
      }
    ];

    # Imported by the matching config in ~/.dotfiles, which keeps the layout. Each file
    # defines the full palette, because a name a config references but a file never defines
    # fails silently in GTK CSS and renders as a transparent or default colour.
    environment.etc = {
      # GTK CSS: @import url("file:///etc/xdg/waybar/lattice.css");
      "xdg/waybar/lattice.css".text = renderNamed (name: hex: "@define-color ${name} ${hex};\n") + ''
        @define-color accent @${cfg.accent};
        @define-color accentAlt @${cfg.accentAlt};
      '';

      # swayosd is GTK CSS too, so it takes the same file.
      "xdg/swayosd/lattice.css".source = config.environment.etc."xdg/waybar/lattice.css".source;

      # rofi rasi: @import "/etc/xdg/rofi/lattice.rasi"
      # `highlight` is the one property rofi's parser won't take a @reference for -- a
      # `highlight: bold @accent` anywhere makes it discard the whole theme, silently and
      # without a non-zero exit. So it's set here, where the accent is already a literal.
      "xdg/rofi/lattice.rasi".text = ''
        * {
        ${renderNamed (name: hex: "  ${name}: ${hex};\n")}  accent: @${cfg.accent};
          accentAlt: @${cfg.accentAlt};
          highlight: bold ${cfg.accentHex};
        }
      '';

      # mako ini: include=/etc/xdg/mako/lattice
      # Colours only, including the per-urgency borders; geometry, fonts and timeouts
      # stay in ~/.dotfiles. Criteria here merge with the same criteria there.
      "xdg/mako/lattice".text = ''
        background-color=${cfg.palette.base}
        text-color=${cfg.palette.text}
        border-color=${cfg.accentHex}
        progress-color=over ${cfg.palette.surface0}

        [urgency=low]
        border-color=${cfg.palette.surface1}

        [urgency=critical]
        border-color=${cfg.palette.peach}
      '';
    };

    ### CONSOLE ###
    console.colors = map (lib.removePrefix "#") [
      cfg.palette.base
      cfg.palette.red
      cfg.palette.green
      cfg.palette.yellow
      cfg.palette.blue
      cfg.palette.pink
      cfg.palette.teal
      cfg.palette.text
      cfg.palette.surface2
      cfg.bright.red
      cfg.bright.green
      cfg.bright.yellow
      cfg.bright.blue
      cfg.bright.pink
      cfg.bright.teal
      cfg.palette.subtext1
    ];
  };
}
