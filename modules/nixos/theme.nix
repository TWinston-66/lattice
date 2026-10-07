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

  hexChars = "0123456789abcdef";

  # 0-255 -> "00".."ff". The inverse of `byte`, for building #rrggbbaa literals.
  hexByte = n: lib.substring (n / 16) 1 hexChars + lib.substring (lib.mod n 16) 1 hexChars;

  # "#rrggbb" blended channelwise with another; `keep` is how much of the first survives.
  # For the slots a non-Catppuccin flavour has no colour of its own for.
  mix =
    keep: a: b:
    let
      channel =
        at:
        hexByte (
          lib.min 255 (
            builtins.floor (
              keep * byte (lib.removePrefix "#" a) at + (1.0 - keep) * byte (lib.removePrefix "#" b) at + 0.5
            )
          )
        );
    in
    "#"
    + lib.concatMapStrings channel [
      0
      2
      4
    ];

  catppuccin = {
    mocha = {
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
    macchiato = {
      rosewater = "#f4dbd6";
      flamingo = "#f0c6c6";
      pink = "#f5bde6";
      mauve = "#c6a0f6";
      red = "#ed8796";
      maroon = "#ee99a0";
      peach = "#f5a97f";
      yellow = "#eed49f";
      green = "#a6da95";
      teal = "#8bd5ca";
      sky = "#91d7e3";
      sapphire = "#7dc4e4";
      blue = "#8aadf4";
      lavender = "#b7bdf8";
      text = "#cad3f5";
      subtext1 = "#b8c0e0";
      subtext0 = "#a5adcb";
      overlay2 = "#939ab7";
      overlay1 = "#8087a2";
      overlay0 = "#6e738d";
      surface2 = "#5b6078";
      surface1 = "#494d64";
      surface0 = "#363a4f";
      base = "#24273a";
      mantle = "#1e2030";
      crust = "#181926";
    };
    frappe = {
      rosewater = "#f2d5cf";
      flamingo = "#eebebe";
      pink = "#f4b8e4";
      mauve = "#ca9ee6";
      red = "#e78284";
      maroon = "#ea999c";
      peach = "#ef9f76";
      yellow = "#e5c890";
      green = "#a6d189";
      teal = "#81c8be";
      sky = "#99d1db";
      sapphire = "#85c1dc";
      blue = "#8caaee";
      lavender = "#babbf1";
      text = "#c6d0f5";
      subtext1 = "#b5bfe2";
      subtext0 = "#a5adce";
      overlay2 = "#949cbb";
      overlay1 = "#838ba7";
      overlay0 = "#737994";
      surface2 = "#626880";
      surface1 = "#51576d";
      surface0 = "#414559";
      base = "#303446";
      mantle = "#292c3c";
      crust = "#232634";
    };
  };

  # Tokyo Night, from folke/tokyonight.nvim's colors/storm.lua; Night differs only in its
  # three backgrounds. It has no soft pinks, so rosewater, flamingo, pink and lavender are
  # blends, and stay out of the wallpaper pool. Its greys run bg_highlight, fg_gutter,
  # terminal_black for the surfaces and dark3, comment, dark5 for the overlays, which is
  # the order they lighten in.
  tokyonightColors = {
    bg = "#24283b";
    bg_dark = "#1f2335";
    bg_dark1 = "#1b1e2d";
    bg_highlight = "#292e42";
    blue = "#7aa2f7";
    blue1 = "#2ac3de";
    comment = "#565f89";
    cyan = "#7dcfff";
    dark3 = "#545c7e";
    dark5 = "#737aa2";
    fg = "#c0caf5";
    fg_dark = "#a9b1d6";
    fg_gutter = "#3b4261";
    green = "#9ece6a";
    green1 = "#73daca";
    magenta = "#bb9af7";
    orange = "#ff9e64";
    red = "#f7768e";
    red1 = "#db4b4b";
    terminal_black = "#414868";
    yellow = "#e0af68";
  };

  tokyonight =
    {
      label,
      terminal,
      colorscheme,
      c,
    }:
    {
      inherit label terminal;
      nvim.colorscheme = colorscheme;
      palette = {
        rosewater = mix 0.5 c.orange c.fg;
        flamingo = mix 0.5 c.red c.fg;
        pink = mix 0.5 c.magenta c.red;
        mauve = c.magenta;
        red = c.red;
        maroon = c.red1;
        peach = c.orange;
        yellow = c.yellow;
        green = c.green;
        teal = c.green1;
        sky = c.cyan;
        sapphire = c.blue1;
        blue = c.blue;
        lavender = mix 0.5 c.blue c.magenta;
        text = c.fg;
        subtext1 = mix 0.5 c.fg c.fg_dark;
        subtext0 = c.fg_dark;
        overlay2 = c.dark5;
        overlay1 = c.comment;
        overlay0 = c.dark3;
        surface2 = c.terminal_black;
        surface1 = c.fg_gutter;
        surface0 = c.bg_highlight;
        base = c.bg;
        mantle = c.bg_dark;
        crust = c.bg_dark1;
      };
      # Its terminal colours repeat the normal half as the bright half.
      bright = {
        inherit (c) red green yellow;
        blue = c.blue;
        pink = c.magenta;
        teal = c.cyan;
      };
      accents = {
        blue = "blue";
        mauve = "magenta";
        teal = "teal";
        peach = "orange";
        sapphire = "azure";
        green = "green";
        maroon = "crimson";
        sky = "cyan";
        yellow = "yellow";
        red = "red";
      };
    };

  # Rosé Pine, from rose-pine/neovim's palette.lua. Six hues and a leaf green: love, gold,
  # rose, pine, foam, iris, leaf. Foam takes blue, the slot every default reaches for, since
  # it is the theme's cool highlight and pine is too dark to carry text. Its `surface` sits
  # barely above base, so the surfaces start at `overlay`, which is the step the theme
  # itself uses for raised things. Crust is the dimmed `nc` background darkened once more.
  rosePine =
    {
      label,
      terminal,
      colorscheme,
      c,
    }:
    {
      inherit label terminal;
      nvim.colorscheme = colorscheme;
      palette = {
        rosewater = mix 0.5 c.rose c.text;
        flamingo = c.rose;
        pink = c.rose;
        mauve = c.iris;
        red = c.love;
        maroon = mix 0.5 c.love c.rose;
        peach = mix 0.5 c.love c.gold;
        yellow = c.gold;
        green = c.leaf;
        teal = mix 0.5 c.pine c.foam;
        sky = mix 0.5 c.foam c.text;
        sapphire = c.pine;
        blue = c.foam;
        lavender = mix 0.5 c.iris c.foam;
        text = c.text;
        subtext1 = mix 0.3 c.subtle c.text;
        subtext0 = mix 0.6 c.subtle c.text;
        overlay2 = c.subtle;
        overlay1 = mix 0.5 c.muted c.subtle;
        overlay0 = c.muted;
        surface2 = c.highlight_high;
        surface1 = c.highlight_med;
        surface0 = c.overlay;
        base = c.base;
        mantle = c.nc;
        crust = mix 0.6 c.nc "#000000";
      };
      bright = {
        red = c.love;
        green = c.pine;
        yellow = c.gold;
        blue = c.foam;
        pink = c.iris;
        teal = c.rose;
      };
      accents = {
        blue = "foam";
        mauve = "iris";
        pink = "rose";
        red = "love";
        yellow = "gold";
        sapphire = "pine";
        green = "leaf";
      };
    };

  # Gruvbox Material, dark, medium contrast, material foreground -- sainnhe/gruvbox-material's
  # defaults -- from its autoload palette. Seven hues; the pinks, sky, sapphire, lavender and
  # the soft reds are blends of them.
  gruvboxMaterial =
    let
      c = {
        bg_dim = "#1b1b1b";
        bg0 = "#282828";
        bg1 = "#32302f";
        bg3 = "#45403d";
        bg5 = "#5a524c";
        grey0 = "#7c6f64";
        grey1 = "#928374";
        grey2 = "#a89984";
        fg0 = "#d4be98";
        red = "#ea6962";
        orange = "#e78a4e";
        yellow = "#d8a657";
        green = "#a9b665";
        aqua = "#89b482";
        blue = "#7daea3";
        purple = "#d3869b";
      };
    in
    {
      label = "Gruvbox Material";
      terminal = {
        foreground = "#d4be98";
        background = "#282828";
        cursor = "#d4be98";
        cursorText = "#282828";
        selectionForeground = "#282828";
        selectionBackground = "#d4be98";
        ansi = [
          "#282828"
          "#ea6962"
          "#a9b665"
          "#d8a657"
          "#7daea3"
          "#d3869b"
          "#89b482"
          "#d4be98"
          "#7c6f64"
          "#ea6962"
          "#a9b665"
          "#d8a657"
          "#7daea3"
          "#d3869b"
          "#89b482"
          "#ddc7a1"
        ];
      };
      nvim = {
        colorscheme = "gruvbox-material";
        globals = {
          gruvbox_material_background = "medium";
          gruvbox_material_foreground = "material";
        };
      };
      palette = {
        rosewater = mix 0.5 c.orange c.fg0;
        flamingo = mix 0.5 c.purple c.fg0;
        pink = mix 0.5 c.purple c.red;
        mauve = c.purple;
        red = c.red;
        maroon = mix 0.6 c.red c.purple;
        peach = c.orange;
        yellow = c.yellow;
        green = c.green;
        teal = c.aqua;
        sky = mix 0.5 c.blue c.aqua;
        sapphire = mix 0.6 c.blue c.fg0;
        blue = c.blue;
        lavender = mix 0.5 c.blue c.purple;
        text = c.fg0;
        subtext1 = mix 0.3 c.grey2 c.fg0;
        subtext0 = mix 0.6 c.grey2 c.fg0;
        overlay2 = c.grey2;
        overlay1 = c.grey1;
        overlay0 = c.grey0;
        surface2 = c.bg5;
        surface1 = c.bg3;
        surface0 = c.bg1;
        base = c.bg0;
        mantle = mix 0.5 c.bg0 c.bg_dim;
        crust = c.bg_dim;
      };
      bright = {
        inherit (c)
          red
          green
          yellow
          blue
          ;
        pink = c.purple;
        teal = c.aqua;
      };
      accents = {
        blue = "blue";
        mauve = "purple";
        teal = "aqua";
        peach = "orange";
        green = "green";
        yellow = "yellow";
        red = "red";
      };
    };

  # "#1e1e2e" -> "#1e1e2ed1" at the configured opacity. rofi's rasi and mako's ini have
  # no alpha() function, so a translucent surface has to be baked in as a literal; GTK
  # CSS does have one, so waybar/swayosd use `alpha(@base, ...)` in ~/.dotfiles instead.
  alphaOf =
    color:
    let
      clamped = lib.min 1.0 (lib.max 0.0 cfg.opacity);
    in
    color + hexByte (builtins.floor ((clamped * 255.0) + 0.5));

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

  # What `lattice-theme` swaps at run time, one directory per flavour: every file a consumer
  # reads from runtimeTheme, written out in full for that flavour. The accent is the one
  # thing a flavour does not decide -- it follows the wallpaper -- so it is left as tokens
  # that the run-time writer (lattice-palette, in desktop/theming.nix) fills in:
  #
  #   %ACCENT% %ALT%                the pair, as #rrggbb
  #   %ACCENT_BARE% %ALT_BARE%      the same without the '#', for hyprlang and Hyprland
  #   %LOCK_OUTER_BARE%             the accent half-mixed into surface0, for the lock screen
  #
  # A consumer added here is a consumer the writer handles: it walks the directory, so there
  # is no second list of file names to keep in step.
  kitFiles =
    name:
    let
      flavor = cfg.flavors.${name};
      inherit (flavor) palette;
      bare = lib.removePrefix "#";
      defineAll = f: lib.concatStrings (lib.mapAttrsToList f palette);
    in
    {
      # GTK CSS -- waybar, swayosd, wlogout -- through /etc/xdg/waybar/lattice.css.
      "theme.css" = defineAll (n: hex: "@define-color ${n} ${hex};\n") + ''
        @define-color accent %ACCENT%;
        @define-color accentAlt %ALT%;
      '';

      # rofi. `highlight` is a literal for the reason given at /etc/xdg/rofi/lattice.rasi.
      "theme.rasi" = ''
        * {
        ${defineAll (n: hex: "  ${n}: ${hex};\n")}  accent: %ACCENT%;
          accentAlt: %ALT%;
          highlight: bold %ACCENT%;
          baseAlpha: ${alphaOf palette.base};
        }
      '';

      # mako. The sections are safe in an included file: mako parses it from the root
      # section and the includer carries on in its own section afterwards.
      "theme.mako" = ''
        background-color=${alphaOf palette.base}
        text-color=${palette.text}
        border-color=%ACCENT%
        progress-color=over ${palette.surface0}

        [urgency=low]
        border-color=${palette.surface1}

        [urgency=critical]
        border-color=${palette.peach}
      '';

      # Hyprland, loadfile()d by ~/.dotfiles hyprland.lua and eval'd into the running one.
      "theme.lua" = ''
        hl.config({ general = { col = { active_border = { colors = { "rgba(%ACCENT_BARE%ff)", "rgba(%ALT_BARE%ff)" }, angle = 45 }, inactive_border = "rgba(${bare palette.surface1}aa)" } } })
      '';

      # hyprlock, sourced by /etc/xdg/hypr/hyprlock.conf after its own fallbacks. Bare hex,
      # since the placeholder's pango markup needs it that way as well as rgb().
      "theme.hyprlock" = ''
        $lockOuter = %LOCK_OUTER_BARE%
        $lockCheck = %ALT_BARE%
        $lockBase = ${bare palette.base}
        $lockMantle = ${bare palette.mantle}
        $lockText = ${bare palette.text}
        $lockSubtext = ${bare palette.subtext0}
        $lockMuted = ${bare palette.overlay0}
        $lockFail = ${bare palette.red}
        $lockCaps = ${bare palette.yellow}
      '';

      # catppuccin/tmux, sourced by ~/.dotfiles tmux.conf ahead of the plugin. The plugin's
      # own flavour files set these with -o, so plain -g here wins over them. Its two
      # subtext names are the other way round from the palette's in every flavour upstream
      # ships, so they are crossed here too, to draw exactly what the plugin would.
      "theme.tmux" =
        let
          thm = n: hex: "set -g @thm_${n} \"${hex}\"\n";
        in
        lib.concatStrings [
          (thm "bg" palette.base)
          (thm "fg" palette.text)
          (lib.concatMapStrings (n: thm n palette.${n}) accentNames)
          (thm "subtext_1" palette.subtext0)
          (thm "subtext_0" palette.subtext1)
          (thm "overlay_2" palette.overlay2)
          (thm "overlay_1" palette.overlay1)
          (thm "overlay_0" palette.overlay0)
          (thm "surface_2" palette.surface2)
          (thm "surface_1" palette.surface1)
          (thm "surface_0" palette.surface0)
          (thm "mantle" palette.mantle)
          (thm "crust" palette.crust)
        ];

      # foot, included by ~/.dotfiles foot.ini: the flavour's terminal colours. foot cannot
      # reload its config, so lattice-palette also reads this file back to recolour the
      # windows already open, with the OSC 4/10/11/12/17/19 equivalent of each line.
      "theme.foot" =
        let
          t = flavor.terminal;
          hex = lib.removePrefix "#";
        in
        lib.concatStrings (
          [
            "[colors-dark]\n"
            "foreground=${hex t.foreground}\n"
            "background=${hex t.background}\n"
            "cursor=${hex t.cursorText} ${hex t.cursor}\n"
            "selection-foreground=${hex t.selectionForeground}\n"
            "selection-background=${hex t.selectionBackground}\n"
          ]
          ++ lib.imap0 (
            i: colour: "${if i < 8 then "regular" else "bright"}${toString (lib.mod i 8)}=${hex colour}\n"
          ) t.ansi
        );

      # nvim, read and watched by ~/.dotfiles nvim theme.lua: the upstream colorscheme, with
      # whatever vim.g settings it takes. Every flavour gets its own theme's plugin rather
      # than its palette poured into Catppuccin's highlight groups.
      "theme-nvim.lua" =
        "return " + lib.generators.toLua { } { inherit (flavor.nvim) colorscheme globals; } + "\n";
    }
    // lib.mapAttrs (
      _: render:
      render {
        inherit palette;
        accent = "%ACCENT%";
        accentAlt = "%ALT%";
      }
    ) cfg.extraKitFiles
    // {

      # Every colour as a shell variable, for the scripts that draw their own markup -- the
      # bar's calendar and power-profile tooltip, and Hyprland's resize-mode banner. Sourced
      # at each run, so they follow without being told.
      "theme.sh" = defineAll (n: hex: "${n}='${hex}'\n") + ''
        accent='%ACCENT%'
        accentAlt='%ALT%'
      '';

      # GTK, through the named colours adw-gtk3 and libadwaita draw everything from. Imported
      # by the user GTK3 theme in desktop/theming.nix and by ~/.dotfiles gtk-4.0/gtk.css.
      "theme.gtk.css" = ''
        @define-color accent_color %ACCENT%;
        @define-color accent_bg_color %ACCENT%;
        @define-color accent_fg_color ${palette.crust};
        @define-color destructive_color ${palette.red};
        @define-color destructive_bg_color ${palette.red};
        @define-color destructive_fg_color ${palette.crust};
        @define-color success_color ${palette.green};
        @define-color success_bg_color ${palette.green};
        @define-color success_fg_color ${palette.crust};
        @define-color warning_color ${palette.yellow};
        @define-color warning_bg_color ${palette.yellow};
        @define-color warning_fg_color ${palette.crust};
        @define-color error_color ${palette.red};
        @define-color error_bg_color ${palette.red};
        @define-color error_fg_color ${palette.crust};
        @define-color window_bg_color ${palette.base};
        @define-color window_fg_color ${palette.text};
        @define-color view_bg_color ${palette.mantle};
        @define-color view_fg_color ${palette.text};
        @define-color headerbar_bg_color ${palette.mantle};
        @define-color headerbar_fg_color ${palette.text};
        @define-color headerbar_border_color ${palette.surface0};
        @define-color headerbar_backdrop_color ${palette.base};
        @define-color headerbar_shade_color rgba(0, 0, 0, 0.36);
        @define-color headerbar_darker_shade_color rgba(0, 0, 0, 0.9);
        @define-color sidebar_bg_color ${palette.mantle};
        @define-color sidebar_fg_color ${palette.text};
        @define-color sidebar_backdrop_color ${palette.base};
        @define-color sidebar_border_color ${palette.crust};
        @define-color sidebar_shade_color rgba(0, 0, 0, 0.36);
        @define-color secondary_sidebar_bg_color ${palette.base};
        @define-color secondary_sidebar_fg_color ${palette.text};
        @define-color secondary_sidebar_backdrop_color ${palette.base};
        @define-color secondary_sidebar_border_color ${palette.crust};
        @define-color secondary_sidebar_shade_color rgba(0, 0, 0, 0.36);
        @define-color card_bg_color ${palette.surface0};
        @define-color card_fg_color ${palette.text};
        @define-color card_shade_color rgba(0, 0, 0, 0.36);
        @define-color dialog_bg_color ${palette.base};
        @define-color dialog_fg_color ${palette.text};
        @define-color popover_bg_color ${palette.surface0};
        @define-color popover_fg_color ${palette.text};
        @define-color popover_shade_color rgba(0, 0, 0, 0.25);
        @define-color thumbnail_bg_color ${palette.surface0};
        @define-color thumbnail_fg_color ${palette.text};
        @define-color shade_color rgba(0, 0, 0, 0.36);
        @define-color scrollbar_outline_color rgba(0, 0, 0, 0.5);
      '';

      # fzf, through FZF_DEFAULT_OPTS_FILE (~/.dotfiles .zshrc), which fzf reads on every run.
      "theme.fzf" = ''
        --color=bg+:${palette.surface0},bg:${palette.base},spinner:${palette.rosewater},hl:${palette.red}
        --color=fg:${palette.text},header:${palette.red},info:${palette.mauve},pointer:${palette.rosewater}
        --color=marker:${palette.lavender},fg+:${palette.text},prompt:${palette.mauve},hl+:${palette.red}
        --color=selected-bg:${palette.surface1}
        --color=border:${palette.overlay0},label:${palette.text}
      '';

      # zsh-syntax-highlighting, which .zshrc re-sources at the prompt whenever this changes.
      "theme.zsh" = ''
        ZSH_HIGHLIGHT_STYLES[default]='fg=${palette.text}'
        ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=${palette.red},bold'
        ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=${palette.mauve}'
        ZSH_HIGHLIGHT_STYLES[alias]='fg=${palette.green}'
        ZSH_HIGHLIGHT_STYLES[builtin]='fg=${palette.green}'
        ZSH_HIGHLIGHT_STYLES[function]='fg=${palette.green}'
        ZSH_HIGHLIGHT_STYLES[command]='fg=${palette.green}'
        ZSH_HIGHLIGHT_STYLES[precommand]='fg=${palette.green},italic'
        ZSH_HIGHLIGHT_STYLES[path]='fg=${palette.text},underline'
        ZSH_HIGHLIGHT_STYLES[globbing]='fg=%ACCENT%'
        ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=${palette.yellow}'
        ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=${palette.yellow}'
        ZSH_HIGHLIGHT_STYLES[comment]='fg=${palette.overlay0},italic'
        ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=${palette.red}'
      '';

      # starship has no include, so lattice-palette splices this into a copy of
      # ~/.config/starship.toml (starship.toml here), which .zshrc points STARSHIP_CONFIG at.
      # starship reads its config at every prompt.
      "starship-palette.toml" = ''

        [palettes.lattice]
      ''
      + defineAll (n: hex: "${n} = \"${hex}\"\n");

      # bat, through BAT_CONFIG_PATH, read on every run.
      "theme.bat" = ''
        --theme="${flavor.bat}"
      '';

      # delta, through an [include] at the end of ~/.dotfiles .gitconfig, read on every run.
      # The diff backgrounds are the palette's red and green sunk into base, by the same
      # amounts Catppuccin's own delta theme uses.
      "theme.gitconfig" = ''
        [delta "lattice"]
        	blame-palette = "${palette.base} ${palette.mantle} ${palette.crust} ${palette.surface0} ${palette.surface1}"
        	commit-decoration-style = "${palette.overlay0}" bold box ul
        	dark = true
        	file-decoration-style = "${palette.overlay0}"
        	file-style = "${palette.text}"
        	hunk-header-decoration-style = "${palette.overlay0}" box ul
        	hunk-header-file-style = bold
        	hunk-header-line-number-style = bold "${palette.subtext0}"
        	hunk-header-style = file line-number syntax
        	line-numbers-left-style = "${palette.overlay0}"
        	line-numbers-minus-style = bold "${palette.red}"
        	line-numbers-plus-style = bold "${palette.green}"
        	line-numbers-right-style = "${palette.overlay0}"
        	line-numbers-zero-style = "${palette.overlay0}"
        	minus-emph-style = bold syntax "${mix 0.35 palette.red palette.base}"
        	minus-style = syntax "${mix 0.2 palette.red palette.base}"
        	plus-emph-style = bold syntax "${mix 0.35 palette.green palette.base}"
        	plus-style = syntax "${mix 0.2 palette.green palette.base}"
        	map-styles = bold purple => syntax "${
           mix 0.35 palette.mauve palette.base
         }", bold blue => syntax "${mix 0.35 palette.blue palette.base}", bold cyan => syntax "${
           mix 0.35 palette.sky palette.base
         }", bold yellow => syntax "${mix 0.35 palette.yellow palette.base}"
        	syntax-theme = ${flavor.bat}
        [delta]
        	features = lattice
      '';

      # lazygit, merged over its own config through LG_CONFIG_FILE, at launch.
      "theme.lazygit.yml" = ''
        gui:
          theme:
            activeBorderColor: ["%ACCENT%", bold]
            inactiveBorderColor: ["${palette.subtext0}"]
            optionsTextColor: ["%ACCENT%"]
            selectedLineBgColor: ["${palette.surface0}"]
            cherryPickedCommitBgColor: ["${palette.surface1}"]
            cherryPickedCommitFgColor: ["%ACCENT%"]
            unstagedChangesColor: ["${palette.red}"]
            defaultFgColor: ["${palette.text}"]
            searchingActiveBorderColor: ["${palette.yellow}"]
          authorColors:
            "*": "%ALT%"
      '';

      # zathura, through an `include` at the end of ~/.dotfiles zathurarc, at launch.
      "theme.zathura" = ''
        set default-fg                "#${bare palette.text}"
        set default-bg                "#${bare palette.base}"
        set completion-bg             "#${bare palette.surface0}"
        set completion-fg             "#${bare palette.text}"
        set completion-highlight-bg   "#${bare palette.surface2}"
        set completion-highlight-fg   "#${bare palette.text}"
        set completion-group-bg       "#${bare palette.surface0}"
        set completion-group-fg       "#%ACCENT_BARE%"
        set statusbar-fg              "#${bare palette.text}"
        set statusbar-bg              "#${bare palette.surface0}"
        set notification-bg           "#${bare palette.surface0}"
        set notification-fg           "#${bare palette.text}"
        set notification-error-bg     "#${bare palette.surface0}"
        set notification-error-fg     "#${bare palette.red}"
        set notification-warning-bg   "#${bare palette.surface0}"
        set notification-warning-fg   "#${bare palette.yellow}"
        set inputbar-fg               "#${bare palette.text}"
        set inputbar-bg               "#${bare palette.surface0}"
        set index-fg                  "#${bare palette.text}"
        set index-bg                  "#${bare palette.base}"
        set index-active-fg           "#${bare palette.text}"
        set index-active-bg           "#${bare palette.surface0}"
        set render-loading-bg         "#${bare palette.base}"
        set render-loading-fg         "#${bare palette.text}"
        set highlight-color           "#${bare palette.surface2}"
        set highlight-fg              "#${bare palette.pink}"
        set highlight-active-color    "#${bare palette.pink}"
        set recolor                   "false"
        set recolor-keephue           "true"
        set recolor-lightcolor        "#${bare palette.base}"
        set recolor-darkcolor         "#${bare palette.text}"
      '';

      # Qt, as qt6ct's colour scheme (color_scheme_path in ~/.dotfiles qt6ct.conf), at launch.
      "theme.qt6ct.conf" = ''
        [ColorScheme]
        active_colors=  #ff${bare palette.text}, #ff${bare palette.surface1}, #ff${bare palette.surface2}, #ff${bare palette.surface0}, #ff${bare palette.crust}, #ff${bare palette.mantle}, #ff${bare palette.text}, #ff${bare palette.text}, #ff${bare palette.text}, #ff${bare palette.base}, #ff${bare palette.mantle}, #ff${bare palette.crust}, #ff%ACCENT_BARE%, #ff${bare palette.crust}, #ff%ACCENT_BARE%, #ff${bare palette.lavender}, #ff${bare palette.mantle}, #ffffffff, #ff${bare palette.base}, #ff${bare palette.text}, #80${bare palette.overlay0}, #ff%ACCENT_BARE%
        inactive_colors=#ff${bare palette.overlay1}, #ff${bare palette.base}, #ff${bare palette.surface1}, #ff${bare palette.surface0}, #ff${bare palette.crust}, #ff${bare palette.mantle}, #ff${bare palette.overlay1}, #ff${bare palette.text}, #ff${bare palette.overlay1}, #ff${bare palette.base}, #ff${bare palette.mantle}, #ff${bare palette.crust}, #ff${bare palette.surface0}, #ff${bare palette.overlay1}, #ff${bare palette.overlay1}, #ff${bare palette.overlay1}, #ff${bare palette.mantle}, #ffffffff, #ff${bare palette.base}, #ff${bare palette.text}, #80${bare palette.overlay0}, #ff${bare palette.surface0}
        disabled_colors=#ff${bare palette.overlay0}, #ff${bare palette.surface0}, #ff${bare palette.surface1}, #ff${bare palette.surface0}, #ff${bare palette.crust}, #ff${bare palette.mantle}, #ff${bare palette.overlay0}, #ff${bare palette.text}, #ff${bare palette.overlay0}, #ff${bare palette.base}, #ff${bare palette.mantle}, #ff${bare palette.crust}, #ff${bare palette.mantle}, #ff${bare palette.overlay0}, #ff${bare palette.subtext0}, #ff${bare palette.subtext1}, #ff${bare palette.mantle}, #ffffffff, #ff${bare palette.base}, #ff${bare palette.text}, #80${bare palette.overlay0}, #ff${bare palette.mantle}
      '';

      # btop, at launch: .zshrc runs it with --themes-dir pointed here, which wins over
      # ~/.config/btop/themes, and btop.conf names catppuccin_mocha -- hence the file name.
      "catppuccin_mocha.theme" = ''
        theme[main_bg]="#${bare palette.base}"
        theme[main_fg]="#${bare palette.text}"
        theme[title]="#${bare palette.text}"
        theme[hi_fg]="#%ACCENT_BARE%"
        theme[selected_bg]="#${bare palette.surface1}"
        theme[selected_fg]="#%ACCENT_BARE%"
        theme[inactive_fg]="#${bare palette.overlay1}"
        theme[graph_text]="#${bare palette.rosewater}"
        theme[meter_bg]="#${bare palette.surface1}"
        theme[proc_misc]="#${bare palette.rosewater}"
        theme[cpu_box]="#${bare palette.mauve}" #Mauve
        theme[mem_box]="#${bare palette.green}" #Green
        theme[net_box]="#${bare palette.maroon}" #Maroon
        theme[proc_box]="#%ACCENT_BARE%" #Blue
        theme[div_line]="#${bare palette.overlay0}"
        theme[temp_start]="#${bare palette.green}"
        theme[temp_mid]="#${bare palette.yellow}"
        theme[temp_end]="#${bare palette.red}"
        theme[cpu_start]="#${bare palette.teal}"
        theme[cpu_mid]="#${bare palette.sapphire}"
        theme[cpu_end]="#${bare palette.lavender}"
        theme[free_start]="#${bare palette.mauve}"
        theme[free_mid]="#${bare palette.lavender}"
        theme[free_end]="#%ACCENT_BARE%"
        theme[cached_start]="#${bare palette.sapphire}"
        theme[cached_mid]="#%ACCENT_BARE%"
        theme[cached_end]="#${bare palette.lavender}"
        theme[available_start]="#${bare palette.peach}"
        theme[available_mid]="#${bare palette.maroon}"
        theme[available_end]="#${bare palette.red}"
        theme[used_start]="#${bare palette.green}"
        theme[used_mid]="#${bare palette.teal}"
        theme[used_end]="#${bare palette.sky}"
        theme[download_start]="#${bare palette.peach}"
        theme[download_mid]="#${bare palette.maroon}"
        theme[download_end]="#${bare palette.red}"
        theme[upload_start]="#${bare palette.green}"
        theme[upload_mid]="#${bare palette.teal}"
        theme[upload_end]="#${bare palette.sky}"
        theme[process_start]="#${bare palette.sapphire}"
        theme[process_mid]="#${bare palette.lavender}"
        theme[process_end]="#${bare palette.mauve}"
      '';
    };

  runtimeKit =
    name:
    pkgs.linkFarm "lattice-theme-${name}" (
      lib.mapAttrsToList (file: text: {
        name = file;
        path = pkgs.writeText file text;
      }) (kitFiles name)
    );

  # A kit file with the build-time accent filled in, for the configs that are also written
  # without a runtime directory.
  renderKit =
    file:
    lib.replaceStrings [ "%ACCENT%" "%ALT%" ] [ cfg.accentHex cfg.accentAltHex ]
      (kitFiles cfg.flavor).${file};
in
{
  options.lattice.theme = {
    flavor = lib.mkOption {
      type = lib.types.str;
      default = "mocha";
      description = ''
        The flavour the build is drawn in: one of `flavors`. Everything fixed at build time
        -- the GTK theme, cursors, folders, console, boot splash, greeter and deck keys --
        uses this one, and it is what the desktop starts on until `lattice-theme` picks
        another at run time.
      '';
    };

    # Every flavour carries the full 26 Catppuccin names, because every generated config is
    # written against them and a name missing from one would fail silently in GTK CSS, not
    # here. Catppuccin's dark three fill them natively (Latte is left out on purpose -- the
    # desktop is dark-only); the others are mapped onto them in the `let` above, from their
    # upstream palettes.
    flavors = lib.mkOption {
      description = ''
        Flavour name -> its palette and the upstream themes that go with it. Every one of
        these can be switched to at run time (`lattice-theme`).
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            label = lib.mkOption {
              type = lib.types.str;
              description = "Display name, for the picker. Flavours are listed in its order.";
            };
            palette = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              description = "Catppuccin's 26 colour names to `#rrggbb`.";
            };
            bright = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              description = "ANSI 9-14: red, green, yellow, blue, pink, teal. Only the console reads these.";
            };
            accents = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = lib.genAttrs accentNames (n: n);
              defaultText = lib.literalExpression "every chromatic name, labelled as itself";
              description = ''
                The chromatic names that are this flavour's own colours rather than blends
                made to fill a slot, each with what the flavour calls it. The wallpaper pool
                only draws these, and its menu shows the labels.
              '';
            };
            catppuccin = lib.mkOption {
              type = lib.types.enum [
                "mocha"
                "macchiato"
                "frappe"
              ];
              default = "mocha";
              description = ''
                The Catppuccin flavour nearest this one, for what is only packaged in
                Catppuccin -- the GTK theme, cursors and folder icons -- when this is the
                build-time flavour.
              '';
            };
            terminal = lib.mkOption {
              type = lib.types.submodule {
                options =
                  lib.genAttrs [
                    "foreground"
                    "background"
                    "cursor"
                    "cursorText"
                    "selectionForeground"
                    "selectionBackground"
                  ] (_: lib.mkOption { type = lib.types.str; })
                  // {
                    ansi = lib.mkOption { type = lib.types.listOf lib.types.str; };
                  };
              };
              description = ''
                The terminal's colours, ANSI 0-15 included: the upstream theme's own terminal
                colours rather than the palette's, as Ghostty bundles them.
              '';
            };
            bat = lib.mkOption {
              type = lib.types.str;
              default = "base16";
              description = ''
                bat's theme, also delta's syntax theme. bat ships Catppuccin's; for the rest,
                "base16" draws in the terminal's own ANSI colours, which foot already has
                in this flavour.
              '';
            };
            nvim = {
              colorscheme = lib.mkOption {
                type = lib.types.str;
                description = "The upstream nvim colorscheme, plugin installed in ~/.dotfiles.";
              };
              globals = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "vim.g settings the colorscheme reads, set before loading it.";
              };
            };
          };
        }
      );
      default = {
        mocha = {
          label = "Catppuccin Mocha";
          palette = catppuccin.mocha;
          bright = {
            red = "#f37799";
            green = "#89d88b";
            yellow = "#ebd391";
            blue = "#74a8fc";
            pink = "#f2aede";
            teal = "#6bd7ca";
          };
          catppuccin = "mocha";
          terminal = {
            foreground = "#cdd6f4";
            background = "#1e1e2e";
            cursor = "#f5e0dc";
            cursorText = "#1e1e2e";
            selectionForeground = "#cdd6f4";
            selectionBackground = "#585b70";
            ansi = [
              "#45475a"
              "#f38ba8"
              "#a6e3a1"
              "#f9e2af"
              "#89b4fa"
              "#f5c2e7"
              "#94e2d5"
              "#a6adc8"
              "#585b70"
              "#f37799"
              "#89d88b"
              "#ebd391"
              "#74a8fc"
              "#f2aede"
              "#6bd7ca"
              "#bac2de"
            ];
          };
          nvim.colorscheme = "catppuccin-mocha";
          bat = "Catppuccin Mocha";
        };

        macchiato = {
          label = "Catppuccin Macchiato";
          palette = catppuccin.macchiato;
          bright = {
            red = "#ec7486";
            green = "#8ccf7f";
            yellow = "#e1c682";
            blue = "#78a1f6";
            pink = "#f2a9dd";
            teal = "#63cbc0";
          };
          catppuccin = "macchiato";
          terminal = {
            foreground = "#cad3f5";
            background = "#24273a";
            cursor = "#f4dbd6";
            cursorText = "#24273a";
            selectionForeground = "#cad3f5";
            selectionBackground = "#5b6078";
            ansi = [
              "#494d64"
              "#ed8796"
              "#a6da95"
              "#eed49f"
              "#8aadf4"
              "#f5bde6"
              "#8bd5ca"
              "#a5adcb"
              "#5b6078"
              "#ec7486"
              "#8ccf7f"
              "#e1c682"
              "#78a1f6"
              "#f2a9dd"
              "#63cbc0"
              "#b8c0e0"
            ];
          };
          nvim.colorscheme = "catppuccin-macchiato";
          bat = "Catppuccin Macchiato";
        };

        frappe = {
          label = "Catppuccin Frappé";
          palette = catppuccin.frappe;
          bright = {
            red = "#e67172";
            green = "#8ec772";
            yellow = "#d9ba73";
            blue = "#7b9ef0";
            pink = "#f2a4db";
            teal = "#5abfb5";
          };
          catppuccin = "frappe";
          terminal = {
            foreground = "#c6d0f5";
            background = "#303446";
            cursor = "#f2d5cf";
            cursorText = "#303446";
            selectionForeground = "#c6d0f5";
            selectionBackground = "#626880";
            ansi = [
              "#51576d"
              "#e78284"
              "#a6d189"
              "#e5c890"
              "#8caaee"
              "#f4b8e4"
              "#81c8be"
              "#a5adce"
              "#626880"
              "#e67172"
              "#8ec772"
              "#d9ba73"
              "#7b9ef0"
              "#f2a4db"
              "#5abfb5"
              "#b5bfe2"
            ];
          };
          nvim.colorscheme = "catppuccin-frappe";
          bat = "Catppuccin Frappe";
        };

        tokyonight-night = tokyonight {
          label = "Tokyo Night";
          terminal = {
            foreground = "#c0caf5";
            background = "#1a1b26";
            cursor = "#c0caf5";
            cursorText = "#1a1b26";
            selectionForeground = "#c0caf5";
            selectionBackground = "#283457";
            ansi = [
              "#15161e"
              "#f7768e"
              "#9ece6a"
              "#e0af68"
              "#7aa2f7"
              "#bb9af7"
              "#7dcfff"
              "#a9b1d6"
              "#414868"
              "#f7768e"
              "#9ece6a"
              "#e0af68"
              "#7aa2f7"
              "#bb9af7"
              "#7dcfff"
              "#c0caf5"
            ];
          };
          colorscheme = "tokyonight-night";
          c = tokyonightColors // {
            bg = "#1a1b26";
            bg_dark = "#16161e";
            bg_dark1 = "#0c0e14";
          };
        };

        tokyonight-storm = tokyonight {
          label = "Tokyo Night Storm";
          terminal = {
            foreground = "#c0caf5";
            background = "#24283b";
            cursor = "#c0caf5";
            cursorText = "#1d202f";
            selectionForeground = "#c0caf5";
            selectionBackground = "#364a82";
            ansi = [
              "#1d202f"
              "#f7768e"
              "#9ece6a"
              "#e0af68"
              "#7aa2f7"
              "#bb9af7"
              "#7dcfff"
              "#a9b1d6"
              "#4e5575"
              "#f7768e"
              "#9ece6a"
              "#e0af68"
              "#7aa2f7"
              "#bb9af7"
              "#7dcfff"
              "#c0caf5"
            ];
          };
          colorscheme = "tokyonight-storm";
          c = tokyonightColors;
        };

        rose-pine = rosePine {
          label = "Rosé Pine";
          terminal = {
            foreground = "#e0def4";
            background = "#191724";
            cursor = "#e0def4";
            cursorText = "#191724";
            selectionForeground = "#e0def4";
            selectionBackground = "#403d52";
            ansi = [
              "#26233a"
              "#eb6f92"
              "#31748f"
              "#f6c177"
              "#9ccfd8"
              "#c4a7e7"
              "#ebbcba"
              "#e0def4"
              "#6e6a86"
              "#eb6f92"
              "#31748f"
              "#f6c177"
              "#9ccfd8"
              "#c4a7e7"
              "#ebbcba"
              "#e0def4"
            ];
          };
          colorscheme = "rose-pine-main";
          c = {
            nc = "#16141f";
            base = "#191724";
            surface = "#1f1d2e";
            overlay = "#26233a";
            muted = "#6e6a86";
            subtle = "#908caa";
            text = "#e0def4";
            love = "#eb6f92";
            gold = "#f6c177";
            rose = "#ebbcba";
            pine = "#31748f";
            foam = "#9ccfd8";
            iris = "#c4a7e7";
            leaf = "#95b1ac";
            highlight_med = "#403d52";
            highlight_high = "#524f67";
          };
        };

        rose-pine-moon = rosePine {
          label = "Rosé Pine Moon";
          terminal = {
            foreground = "#e0def4";
            background = "#232136";
            cursor = "#e0def4";
            cursorText = "#232136";
            selectionForeground = "#e0def4";
            selectionBackground = "#44415a";
            ansi = [
              "#393552"
              "#eb6f92"
              "#3e8fb0"
              "#f6c177"
              "#9ccfd8"
              "#c4a7e7"
              "#ea9a97"
              "#e0def4"
              "#6e6a86"
              "#eb6f92"
              "#3e8fb0"
              "#f6c177"
              "#9ccfd8"
              "#c4a7e7"
              "#ea9a97"
              "#e0def4"
            ];
          };
          colorscheme = "rose-pine-moon";
          c = {
            nc = "#1f1d30";
            base = "#232136";
            surface = "#2a273f";
            overlay = "#393552";
            muted = "#6e6a86";
            subtle = "#908caa";
            text = "#e0def4";
            love = "#eb6f92";
            gold = "#f6c177";
            rose = "#ea9a97";
            pine = "#3e8fb0";
            foam = "#9ccfd8";
            iris = "#c4a7e7";
            leaf = "#95b1ac";
            highlight_med = "#44415a";
            highlight_high = "#56526e";
          };
        };

        gruvbox-material = gruvboxMaterial;
      };
    };

    palette = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = cfg.flavors.${cfg.flavor}.palette;
      defaultText = lib.literalExpression "config.lattice.theme.flavors.\${config.lattice.theme.flavor}.palette";
      description = "The build-time flavour's palette. Every build-time config is written from this.";
    };

    bright = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = cfg.flavors.${cfg.flavor}.bright;
      defaultText = lib.literalExpression "config.lattice.theme.flavors.\${config.lattice.theme.flavor}.bright";
      description = "The build-time flavour's lighter ANSI 9-14 variants.";
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

    opacity = lib.mkOption {
      type = lib.types.float;
      default = 0.82;
      description = ''
        Background opacity for the shell surfaces that Hyprland blurs -- the waybar
        pills, the rofi window and mako notifications. 1.0 is fully opaque, which
        makes the `blur` layer rules in ~/.dotfiles/hypr a no-op.
      '';
    };

    runtimeTheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/winston/.cache/lattice";
      description = ''
        Directory holding the run-time theme: one file per `runtimeFiles` entry, each a
        `runtimeKits` file with the accent filled in. The generated palettes in /etc/xdg
        layer these over their own, so flavour and accent can both change without a
        rebuild. Every file has to exist: GTK drops a whole stylesheet over one import it
        cannot open, and mako a whole config over one include. null keeps the build-time
        theme only.
      '';
    };

    runtimeState = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/winston/.local/state/lattice/theme";
      description = ''
        The file `lattice-theme` keeps the run-time flavour's name in, for anything else that
        has to follow it -- the Stream Deck, which swaps its whole layout on a theme switch.
        Missing, unreadable or naming no flavour means the build-time one.
      '';
    };

    extraKitFiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.functionTo lib.types.str);
      default = { };
      example = lib.literalExpression ''{ "theme.foo" = { palette, accent, accentAlt }: "accent=''${accent}\\n"; }'';
      description = ''
        More files for every runtime kit, from modules that own a consumer theme.nix does
        not know about: file name -> `{ palette, accent, accentAlt }` -> its text. The
        accents arrive as the kit's %ACCENT% and %ALT% tokens, filled in at run time.
      '';
    };

    runtimeKits = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      default = lib.mapAttrs (name: _: runtimeKit name) cfg.flavors;
      defaultText = lib.literalExpression "{ <flavour> = <directory of theme files with accent tokens>; }";
      description = ''
        Flavour -> the directory a run-time switch copies into `runtimeTheme`, with the
        accent still as %ACCENT%, %ALT%, %ACCENT_BARE%, %ALT_BARE% and %LOCK_OUTER_BARE%.
      '';
    };

    runtimeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.attrNames (kitFiles cfg.flavor);
      description = "The file names every runtime kit holds, for seeding `runtimeTheme`.";
    };

    alphaOf = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      default = alphaOf;
      defaultText = lib.literalExpression "color: \"#rrggbbaa\"";
      description = "`\"#rrggbb\"` -> that colour at `opacity`, for configs with no alpha() function.";
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
        assertion = cfg.flavors ? ${cfg.flavor};
        message = "lattice.theme.flavor is \"${cfg.flavor}\"; it must be one of ${lib.concatStringsSep ", " (lib.attrNames cfg.flavors)}.";
      }
      {
        assertion = lib.elem cfg.accentAlt accentNames;
        message = "lattice.theme.accentAlt is \"${cfg.accentAlt}\"; it must be one of ${lib.concatStringsSep ", " accentNames}.";
      }
    ];

    # Imported by the matching config in ~/.dotfiles, which keeps the layout. Each file
    # defines the full palette, because a name a config references but a file never defines
    # fails silently in GTK CSS and renders as a transparent or default colour.
    #
    # With runtimeTheme set, each one ends by pulling in the run-time theme, where a second
    # definition of every name wins -- flavour and accent alike. GTK only honours @import
    # ahead of every other rule, hence the palette's own file for the GTK pair to import
    # first.
    environment.etc = {
      "xdg/lattice/palette.css".text = renderNamed (name: hex: "@define-color ${name} ${hex};\n") + ''
        @define-color accent @${cfg.accent};
        @define-color accentAlt @${cfg.accentAlt};
      '';

      # GTK CSS: @import url("/etc/xdg/waybar/lattice.css");
      # Bare paths rather than file:// URLs, which GTK takes the same: waybar's
      # reload_style_on_change follows the @import chain to find files to watch, and it only
      # recognises a plain path -- a file:// link ends the chain before theme.css.
      "xdg/waybar/lattice.css".text = ''
        @import url("/etc/xdg/lattice/palette.css");
      ''
      + lib.optionalString (cfg.runtimeTheme != null) ''
        @import url("${cfg.runtimeTheme}/theme.css");
      '';

      # swayosd is GTK CSS too, so it takes the same file.
      "xdg/swayosd/lattice.css".source = config.environment.etc."xdg/waybar/lattice.css".source;

      # rofi rasi: @import "/etc/xdg/rofi/lattice.rasi"
      # `highlight` is the one property rofi's parser won't take a @reference for -- a
      # `highlight: bold @accent` anywhere makes it discard the whole theme, silently and
      # without a non-zero exit. So the kit writes it where the accent is already a literal.
      "xdg/rofi/lattice.rasi".text =
        renderKit "theme.rasi"
        + lib.optionalString (cfg.runtimeTheme != null) ''
          @import "${cfg.runtimeTheme}/theme.rasi"
        '';

      # mako ini: include=/etc/xdg/mako/lattice
      # Colours only, including the per-urgency borders; geometry, fonts and timeouts
      # stay in ~/.dotfiles. Criteria here merge with the same criteria there. With a
      # runtime theme this is nothing but the include: that file always exists and carries
      # its own urgency sections, which a build-time copy after it would override.
      "xdg/mako/lattice".text =
        if cfg.runtimeTheme != null then
          "include=${cfg.runtimeTheme}/theme.mako\n"
        else
          renderKit "theme.mako";
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
