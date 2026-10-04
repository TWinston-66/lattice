{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };

  theme = config.lattice.theme;
  inherit (theme) palette;

  # hyprlang writes colours bare, without the leading '#'.
  hex = lib.removePrefix "#";

  # Blend two palette colours channelwise; `keep` is how much of the first survives. Only
  # the lock screen needs this, to sit the input field's outline between the wallpaper's
  # accent and the surface behind it -- see the hyprlock block at the bottom of this file.
  mixHex =
    keep: a: b:
    let
      channel = s: n: lib.fromHexString (builtins.substring n 2 (hex s));
      blend =
        n:
        let
          v = builtins.floor ((keep * channel a n) + ((1.0 - keep) * channel b n) + 0.5);
          h = lib.toLower (lib.toHexString (lib.min 255 v));
        in
        if builtins.stringLength h < 2 then "0" + h else h;
    in
    lib.concatMapStrings blend [
      0
      2
      4
    ];

  # The pool the session picks from. Every entry is its own PNG in the store and
  # `lattice-wallpaper random` draws one per login, so the desktop is a different member of
  # one family each session rather than the same image forever.
  #
  # The knobs split by which side knows the answer. The seed belongs to the generator: it
  # varies which way the background gradient runs and which ring of the mark is lit. It
  # leaves the mark centred and the lattice square to the screen, which is a correction
  # rather than an oversight -- both were seeded at first, and on a real screen a mark a
  # little off centre reads as misaligned and a grid a few degrees over reads as crooked,
  # because there is nothing else on the canvas for either to be off-balance against.
  #
  # The accents belong here, because the palette's chromatic names live in lattice.theme
  # and the generator only ever sees the nine roles it draws with. There is one entry per
  # chromatic name, all fourteen of them, each pairing its accent with a hue-adjacent
  # second -- the relation blue and lavender have -- so the mark stays two shades of one
  # colour rather than turning into a gradient. Walking the whole palette rather than
  # following lattice.theme.accent is the point: every one of those names is a colour of
  # this theme, and fourteen wallpapers in one hue would differ only in their seeded
  # composition. The first entry is the exception -- no accent and no seed, so it is the
  # live accent drawn plain,
  # which keeps it the image it was before the pool existed and the right one to seed the
  # wallpaper symlinks with before a home has ever picked.
  #
  # An entry names palette entries rather than colours, because the pool is drawn once per
  # flavour in lattice.theme.flavors: "mauve" is a different hex in each, and the runtime
  # theme switch (lattice-theme) swaps the whole pool for that flavour's drawing of it, so
  # the wallpaper's background moves with the rest of the desktop. The seed is its position
  # in the list, which makes appending a wallpaper cheap and reordering the list a redraw of
  # everything that moved.
  #
  # None of them names a density, deliberately: they all take the generator's 1.0. Density
  # divides the node spacing, and everything in the drawing is measured in spacings -- the
  # grid, the dots' radius, the mark -- so varying it across the pool redrew the artwork at
  # a different size on a correctly sized canvas. The entries used to cycle 1.0, 0.7, 1.4,
  # which meant no two neighbours shared one and a step could double the spacing. Cycling
  # wallpapers then read as the image being resized rather than as variety, and the colour
  # is the variety worth having.
  pool = [
    { }
    {
      accent = "mauve";
      accentAlt = "pink";
    }
    {
      accent = "teal";
      accentAlt = "sky";
    }
    {
      accent = "peach";
      accentAlt = "yellow";
    }
    {
      accent = "sapphire";
      accentAlt = "teal";
    }
    {
      accent = "lavender";
      accentAlt = "blue";
    }
    {
      accent = "green";
      accentAlt = "teal";
    }
    {
      accent = "pink";
      accentAlt = "mauve";
    }
    {
      accent = "maroon";
      accentAlt = "peach";
    }
    {
      accent = "sky";
      accentAlt = "sapphire";
    }
    {
      accent = "yellow";
      accentAlt = "peach";
    }
    {
      accent = "red";
      accentAlt = "maroon";
    }
    {
      accent = "flamingo";
      accentAlt = "rosewater";
    }
    {
      accent = "rosewater";
      accentAlt = "flamingo";
    }
  ];

  # Every entry is drawn twice, because no single image is the right size on both screens.
  # hyprpaper scales an image to cover whatever output it lands on, so a fixed image gives
  # the mark a fixed *fraction* of every screen -- and a fraction is the wrong invariant.
  # The Samsung on the desk is about 2.3x the panel's width, so an equal fraction made its
  # mark 2.3x the size, while the criterion that actually matters is the one the greeter
  # already uses a few hundred lines up: equal angle at the eye. The desk monitor sits
  # ~28in away against the panel's ~20in, so it should be about 1.4x, not 2.3x.
  #
  # Sizing each canvas near its screen's logical resolution is what delivers that, and it
  # needs no measurement to maintain: `spacing` is fixed, so the mark comes out a constant
  # number of canvas units, and a canvas the size of the logical screen therefore puts the
  # mark in the same relation to the UI drawn in those same units. It lands the two at a
  # ratio of ~1.44 against the 1.43 the greeter derived independently.
  #
  # The aspects are each screen's own, so cover has nothing to crop -- the old single
  # 16:10 image lost a tenth of its height on the 16:9 monitor. The panel figure is 16:10
  # because both laptops here have one; a 16:9 panel would crop that tenth back, which is
  # the cost of not knowing the panel until runtime.
  # Per host, in modules/nixos/display.nix: the numbers are a property of the screens in
  # front of the machine, and a canvas that does not match its screen's logical size is
  # magnified to cover it -- which is the whole of what the paragraph above is about.
  screens = config.lattice.display.canvas;

  # In the picker's order, which is by label so each family's variants sit together.
  flavorNames = lib.sort (a: b: theme.flavors.${a}.label < theme.flavors.${b}.label) (
    lib.attrNames theme.flavors
  );

  # The pool resolved against one flavour: the entries whose accent is one of that flavour's
  # own colours (its `accents`), as that flavour's hexes, plus the palette the rest of the
  # drawing takes. A blend made only to fill a slot would draw a near-twin of a wallpaper
  # already in the pool, so a flavour with seven hues gets seven wallpapers, not fourteen.
  # The seed stays the entry's position in the whole pool, so "red" is the same composition
  # in every flavour and only its colours move.
  #
  # Entry 0 names nothing and so takes lattice.theme.accent's pair, and is always kept: it is
  # the plain drawing, and in the build-time flavour exactly what the artwork module makes by
  # default -- the same store path as before flavours.
  poolFor =
    flavor:
    let
      inherit (theme.flavors.${flavor}) palette accents;
    in
    lib.filter (entry: entry.seed == 0 || accents ? ${entry.slot}) (
      lib.imap0 (
        seed: entry:
        let
          slot = entry.accent or theme.accent;
        in
        {
          inherit seed slot palette;
          label = accents.${slot} or slot;
          accent = palette.${slot};
          accentAlt = palette.${entry.accentAlt or theme.accentAlt};
        }
      ) pool
    );

  wallpapersFor =
    flavor: screen:
    map (
      entry:
      config.lattice.artwork.wallpaper (
        {
          inherit (entry)
            seed
            accent
            accentAlt
            palette
            ;
        }
        // screen
      )
    ) (poolFor flavor);

  panelWallpapers = lib.genAttrs flavorNames (flavor: wallpapersFor flavor screens.panel);
  deskWallpapers = lib.genAttrs flavorNames (flavor: wallpapersFor flavor screens.desk);

  # A bash `case` over the flavours, one arm each, from `arm flavor` -> the arm's body.
  # How the scripts below carry per-flavour arrays: the pool's hexes and store paths are
  # build-time facts, so they are baked in rather than looked up.
  flavorCase =
    arm:
    ''
      case "$flavor" in
    ''
    + lib.concatMapStrings (flavor: ''
      ${flavor})
      ${arm flavor}
        ;;
    '') flavorNames
    + ''
      esac
    '';

  # Where lattice-theme keeps the flavour, and the shell that reads it back. In ~/.local/state
  # rather than beside the wallpaper's per-boot pick in XDG_RUNTIME_DIR: the flavour is a
  # preference, and should survive a reboot. Anything unreadable or no longer in
  # lattice.theme.flavors falls back to the build-time one rather than failing.
  themeState = "${config.users.users.winston.home}/.local/state/lattice/theme";
  readFlavor = ''
    flavor=$(cat "${themeState}" 2>/dev/null || true)
    case "$flavor" in
    ${lib.concatStringsSep " | " flavorNames}) ;;
    *) flavor=${theme.flavor} ;;
    esac
  '';

  # The run-time palette as a bash associative array `c`, for scripts that draw their own
  # Pango markup: the build-time colours, then theme.sh over them when lattice-palette has
  # written one. Parsed with `read` rather than sourced, so it costs no fork -- the
  # power-profile pill runs it every two seconds -- and shellcheck can see every name used.
  readColours = ''
    declare -A c=(${
      lib.concatStrings (lib.mapAttrsToList (n: hex: " [${n}]='${hex}'") palette)
    } [accent]='${theme.accentHex}' [accentAlt]='${theme.accentAltHex}')
    if [[ -r "${currentDir}/theme.sh" ]]; then
      while IFS='=' read -r key value; do
        value=''${value#\'}
        c[$key]=''${value%\'}
      done <"${currentDir}/theme.sh"
    fi
  '';

  # What the wallpaper symlinks are seeded with: the plain drawing at desk size.
  wallpaper = lib.head deskWallpapers.${theme.flavor};

  # Where the picker records what it set, for the things that cannot be told. hyprlock
  # reads its backgrounds at launch from paths fixed at build time, so pointing it at these
  # is what keeps the lock screen showing the same wallpaper the desktop has; the `color`
  # beside them covers the gap before the first pick, and base is the gradient's own
  # bottom-right stop, so even that reads as the wallpaper's darkest corner. One per screen
  # size, for the same reason there are two of every wallpaper.
  currentDir = "${config.users.users.winston.home}/.cache/lattice";
  currentPanel = "${currentDir}/wallpaper-panel.png";
  currentDesk = "${currentDir}/wallpaper-desk.png";

  # Folder icons that follow the accent. catppuccin-papirus-folders recolours Papirus's
  # folders, but per flavour and accent at build time; this is its Mocha-blue set with the
  # four colours it draws in turned into tokens, which lattice-palette fills in at run time:
  # the accent, the folder's darker back (the accent 20 down per channel, as Catppuccin's
  # has it), the paper (text) and the ink on the emblems (surface0). Only the sizes that
  # Papirus-Dark draws in colour -- 32, 48 and 64 -- and only the files catppuccin's set
  # touches, plus every alias that ends at one, pointed straight at it. Everything else
  # comes from Papirus-Dark, which this inherits.
  folderIconTemplate =
    pkgs.runCommand "lattice-folder-icons"
      {
        src = "${
          pkgs.catppuccin-papirus-folders.override {
            flavor = "mocha";
            accent = "blue";
          }
        }/share/icons/Papirus";
      }
      ''
        sizes="32x32 48x48 64x64"
        for size in $sizes; do
          mkdir -p $out/$size/places
          for f in $src/$size/places/*; do
            name=''${f##*/}
            target=$(readlink -f "$f")
            case ''${target##*/} in
            folder-cat-mocha-blue*) ;;
            *) continue ;;
            esac
            if [ -L "$f" ]; then
              ln -s "''${target##*/}" $out/$size/places/$name
            else
              sed -e 's/#89B4FA/%ACCENT%/gI' -e 's/#75A0E6/%ACCENT_DARK%/gI' \
                -e 's/#CDD6F4/%PAPER%/gI' -e 's/#313244/%INK%/gI' "$f" > $out/$size/places/$name
            fi
          done
          ln -s $size $out/$size@2x
        done
        {
          printf '[Icon Theme]\nName=lattice-icons\nInherits=Papirus-Dark,hicolor\nDirectories='
          for size in $sizes; do printf '%s/places,%s@2x/places,' $size $size; done
          printf '\n'
          for size in $sizes; do
            n=''${size%%x*}
            printf '\n[%s/places]\nSize=%s\nContext=Places\nType=Fixed\n' $size $n
            printf '\n[%s@2x/places]\nSize=%s\nScale=2\nContext=Places\nType=Fixed\n' $size $n
          done
        } > $out/index.theme
      '';

  # The desktop's theme at run time -- flavour and accent both -- so it can follow the
  # wallpaper and lattice-theme instead of being fixed at lattice.theme until the next
  # rebuild. Every consumer is pointed at a file in ${currentDir} rather than sent the
  # colours: waybar, swayosd and wlogout through theme.css, which the palettes in /etc/xdg
  # import last (lattice.theme.runtimeTheme); rofi and mako through their own syntax of the
  # same; Hyprland's borders through theme.lua, which hyprland.lua in ~/.dotfiles loads
  # after its own default so a `hyprctl reload` keeps the pick; the lock screen through
  # theme.hyprlock; tmux, Ghostty and nvim through theme.tmux, theme.ghostty and
  # theme-nvim.lua. The files themselves are lattice.theme.runtimeKits, one directory per
  # flavour with the accent left as tokens; this fills those in and puts each file in place.
  #
  # Telling each one is the other half, and it is per program, and only for a file that
  # actually changed -- a wallpaper step changes the accent and nothing in tmux or Ghostty,
  # and re-sourcing tmux.conf for nothing costs a status-bar redraw. waybar watches
  # theme.css itself (reload_style_on_change in ~/.dotfiles/waybar/config.jsonc): that
  # restyles the bar in place, where the SIGUSR2 it used to get rebuilt every bar surface,
  # ate the next click on the wallpaper pill and aborted waybar outright on a few picks in
  # quick succession. nvim watches theme-nvim.lua the same way. mako has `makoctl reload`;
  # swayosd has no reload at all, so it is restarted; Hyprland takes the same Lua the file
  # holds, through `hyprctl eval` -- `keyword` refuses a Lua config. tmux re-sources its
  # whole config, because catppuccin/tmux expands its colours into the status formats as it
  # loads. Ghostty has a reload-config action on its GApplication, which is safer than its
  # SIGUSR2: on a build without the handler, that signal's default action is to exit. rofi,
  # wlogout and hyprlock read theirs at every launch. Every one is allowed to miss: a
  # program that is not up yet will read the file when it starts.
  #
  # The GTK theme, cursors, folder icons, Stream Deck keys, screenshot overlay, console,
  # boot splash and greeter stay on the build-time flavour and accent: all of them are
  # drawn or packaged per palette, and none can be told at run time.
  #
  # --write-only is for the build, which runs this same script to make the seeds below, and
  # for the login pick, which writes before anything that reads these has started.
  latticePalette = pkgs.writeShellApplication {
    name = "lattice-palette";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gnused
      pkgs.dconf
      pkgs.hyprland
      pkgs.mako
      pkgs.systemd
      pkgs.tmux
    ];
    text = ''
      usage() {
        echo "usage: lattice-palette [--write-only <dir>] <flavour> <#accent> <#accentAlt>" >&2
        exit 2
      }

      declare -A kits=(${
        lib.concatStrings (lib.mapAttrsToList (n: kit: " [${n}]=${kit}") theme.runtimeKits)
      })
      declare -A text=(${
        lib.concatStrings (lib.mapAttrsToList (n: f: " [${n}]=${f.palette.text}") theme.flavors)
      })
      declare -A surface0=(${
        lib.concatStrings (lib.mapAttrsToList (n: f: " [${n}]=${f.palette.surface0}") theme.flavors)
      })

      dir="${currentDir}"
      reload=1
      if [[ ''${1:-} == --write-only ]]; then
        (($# >= 2)) || usage
        dir=$2
        reload=0
        shift 2
      fi
      (($# == 3)) || usage
      flavor=$1
      [[ -n ''${kits[$flavor]:-} ]] || usage
      for colour in "$2" "$3"; do
        [[ $colour =~ ^#[0-9a-fA-F]{6}$ ]] || usage
      done
      accent=$2
      alt=$3

      # The lock screen's resting outline: half the accent, half the surface it sits on. The
      # full accent matches the mark exactly and then competes with it for the one bright
      # thing on the screen, and a flat grey matches nothing. Rounded the way mixHex in Nix
      # rounds, so the build-time seed and a run-time write agree to the bit.
      mix() {
        local a=''${1#\#} b=''${2#\#} out="" i
        for i in 0 2 4; do
          out+=$(printf '%02x' $(((16#''${a:i:2} + 16#''${b:i:2} + 1) / 2)))
        done
        echo "$out"
      }
      outer=$(mix "$accent" "''${surface0[$flavor]}")

      # Written beside the target and renamed over it. GTK and mako both reject their whole
      # configuration over a file they cannot read, so a reload landing mid-write must still
      # find a complete one.
      #
      # A file that already says the same thing is left alone, and `changed` records the ones
      # that did not: the login pick lands on files lattice-wallpaper --choose wrote before
      # the bar started, and reloading a bar that is already right only makes it blink.
      install -d "$dir"
      changed=" "
      # <file>, from what is already in .<file>.tmp.
      place() {
        if cmp -s "$dir/.$1.tmp" "$dir/$1"; then
          rm -f "$dir/.$1.tmp"
        else
          mv -f "$dir/.$1.tmp" "$dir/$1"
          changed+="$1 "
        fi
      }
      for src in "''${kits[$flavor]}"/*; do
        file=''${src##*/}
        sed -e "s/%ACCENT%/$accent/g" -e "s/%ALT%/$alt/g" \
          -e "s/%ACCENT_BARE%/''${accent#\#}/g" -e "s/%ALT_BARE%/''${alt#\#}/g" \
          -e "s/%LOCK_OUTER_BARE%/$outer/g" "$src" >"$dir/.$file.tmp"
        place "$file"
      done

      # starship has no include, so its config is ~/.config/starship.toml with the palette
      # line pointed at the kit's [palettes.lattice] and that table appended; .zshrc points
      # STARSHIP_CONFIG here. Rebuilt on every write, so an edit to the dotfile lands at the
      # next wallpaper pick, theme switch or login. Skipped where there is no such file --
      # the build's seed, which has no home to read it from.
      if [[ -r $HOME/.config/starship.toml ]]; then
        {
          sed 's/^palette = .*/palette = "lattice"/' "$HOME/.config/starship.toml"
          cat "$dir/starship-palette.toml"
        } >"$dir/.starship.toml.tmp"
        place starship.toml
      fi

      ((reload)) || exit 0

      # Hyprland whatever the files said: it read theme.lua when it started, which can be
      # before this session's pick was written, and setting a border never flickers.
      hyprctl eval "$(cat "$dir/theme.lua")" >/dev/null || true

      if [[ $changed == *" theme.css "* ]]; then
        systemctl --user try-restart swayosd.service || true
      fi
      if [[ $changed == *" theme.mako "* ]]; then
        makoctl reload 2>/dev/null || true
      fi
      # Only with a server already up: source-file is not one of the commands that starts
      # one, but has-session says so without the error.
      if [[ $changed == *" theme.tmux "* ]] && tmux has-session 2>/dev/null; then
        tmux source-file "$HOME/.config/tmux/tmux.conf" >/dev/null 2>&1 || true
      fi
      # GTK3 reads a theme's CSS once, when the theme is set, and the colours are a theme --
      # lattice-a and lattice-b, the same directory under two names (see gtkUserTheme). So a
      # change is told by flipping to the other name, which has every running GTK3 app
      # restyle from the new file. It runs on any setting that is neither name, too: that is
      # a home whose dconf still says what it said before these existed.
      gtkTheme=$(dconf read /org/gnome/desktop/interface/gtk-theme 2>/dev/null || true)
      if [[ $changed == *" theme.gtk.css "* || ($gtkTheme != "'lattice-a'" && $gtkTheme != "'lattice-b'") ]]; then
        next=lattice-a
        if [[ $gtkTheme == "'lattice-a'" ]]; then
          next=lattice-b
        fi
        dconf write /org/gnome/desktop/interface/gtk-theme "'$next'" || true
      fi
      # Folder icons: the template recoloured into whichever of lattice-icons-a and -b is not
      # in use, then the icon theme flipped to it -- so nothing ever reads a half-written set,
      # and the flip is what has running apps reload their icons. A stamp records what a set
      # was drawn for, and an unchanged one is left alone; a home whose dconf names neither
      # set gets one drawn too.
      icons="$HOME/.local/share/icons"
      stamp="$accent ''${text[$flavor]} ''${surface0[$flavor]}"
      iconTheme=$(dconf read /org/gnome/desktop/interface/icon-theme 2>/dev/null || true)
      iconTheme=''${iconTheme//\'/}
      if [[ ($iconTheme != lattice-icons-a && $iconTheme != lattice-icons-b) ||
        $(cat "$icons/$iconTheme/stamp" 2>/dev/null) != "$stamp" ]]; then
        next=lattice-icons-a
        if [[ $iconTheme == lattice-icons-a ]]; then
          next=lattice-icons-b
        fi
        darker=""
        for i in 1 3 5; do
          darker+=$(printf '%02x' $((16#''${accent:i:2} > 20 ? 16#''${accent:i:2} - 20 : 0)))
        done
        rm -rf "''${icons:?}/$next"
        install -d "$icons"
        cp -r --no-preserve=mode ${folderIconTemplate} "$icons/$next"
        find "$icons/$next" -type f -name '*.svg' -exec sed -i \
          -e "s/%ACCENT%/$accent/g" -e "s/%ACCENT_DARK%/#$darker/g" \
          -e "s/%PAPER%/''${text[$flavor]}/g" -e "s/%INK%/''${surface0[$flavor]}/g" {} +
        echo "$stamp" >"$icons/$next/stamp"
        dconf write /org/gnome/desktop/interface/icon-theme "'$next'" || true
      fi

      # The clock pill's calendar tooltip, which otherwise waits for the next minute.
      if [[ $changed == *" theme.sh "* ]]; then
        kill -USR1 "$(cat "''${XDG_RUNTIME_DIR:-/tmp}/lattice-clock.pid" 2>/dev/null)" 2>/dev/null || true
      fi
      if [[ $changed == *" theme.ghostty "* ]]; then
        busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty \
          org.gtk.Actions Activate 'sava{sv}' reload-config 0 0 >/dev/null 2>&1 || true
      fi
    '';
  };

  # What the runtime files hold before anything has picked: the build-time flavour and
  # accent pair, so a fresh home looks exactly as it did before either could move.
  themeSeed = pkgs.runCommand "lattice-theme-seed" { } ''
    ${lib.getExe latticePalette} --write-only $out ${
      lib.escapeShellArgs [
        theme.flavor
        theme.accentHex
        theme.accentAltHex
      ]
    }
  '';

  # Switching between them, for a bind in ~/.dotfiles and for the login pick below.
  # hyprpaper 0.8 loads an image when it is asked for -- `preload` is gone -- so the pool
  # only has to exist in the store. hyprpaper can also rotate a directory by itself, with
  # `timeout` and `order` in the wallpaper block further down; this stays a command so that
  # the desktop changes once at login and then only when asked.
  #
  # Which size goes where is decided here, at run time, rather than written into
  # hyprpaper.conf: hyprpaper's IPC takes an output *name* and rejects a `desc:` selector
  # (tested -- "Invalid monitor"), and a name is the one thing about a monitor that is not
  # knowable until it is plugged in. Reading the live output list also means the pick is
  # right whether this laptop is docked, undocked, or on a screen it has never seen.
  #
  # Which flavour's drawing of the pool is lattice-theme's to say; this reads it back on
  # every run, so `apply` after a theme switch redraws the same member in the new flavour.
  cycleWallpaper = pkgs.writeShellApplication {
    name = "lattice-wallpaper";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.jq
      latticePalette
    ];
    text = ''
      ${readFlavor}
      ${flavorCase (flavor: ''
        panel=(${lib.concatStringsSep " " panelWallpapers.${flavor}})
        desk=(${lib.concatStringsSep " " deskWallpapers.${flavor}})
        accents=(${lib.escapeShellArgs (map (entry: entry.accent) (poolFor flavor))})
        alts=(${lib.escapeShellArgs (map (entry: entry.accentAlt) (poolFor flavor))})
        slots=(${lib.escapeShellArgs (map (entry: entry.slot) (poolFor flavor))})
        labels=(${lib.escapeShellArgs (map (entry: entry.label) (poolFor flavor))})
      '')}
      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-wallpaper"
      count=''${#desk[@]}

      # The pick is kept as the palette name of its accent, not as a position: the flavours'
      # pools differ in length and membership, and a theme switch has to land on the same
      # wallpaper in the new flavour. -1 when nothing has been picked yet -- the state lives
      # in XDG_RUNTIME_DIR, so each boot starts out with no wallpaper of its own rather than
      # with the first one. A name this flavour has no wallpaper for comes back as the plain
      # one, entry 0, which every flavour has.
      picked=$(cat "$state" 2>/dev/null || true)
      current=-1
      if [[ -n $picked ]]; then
        current=0
        for i in "''${!slots[@]}"; do
          if [[ ''${slots[i]} == "$picked" ]]; then
            current=$i
          fi
        done
      fi
      index=$((current < 0 ? 0 : current))

      # --choose settles the pick and writes down everything that reads it -- the symlinks
      # and the theme files -- without telling anyone. It is for the login pick, which runs
      # before hyprpaper and the bar have started (lattice-wallpaper-choose below), so they
      # come up on the session's wallpaper and theme instead of on the defaults with the
      # pick landing over them a moment later.
      choose=0
      if [[ ''${1:-} == --choose ]]; then
        choose=1
        shift
      fi

      case "''${1:-next}" in
      next) index=$(((index + 1) % count)) ;;
      prev) index=$(((index - 1 + count) % count)) ;;
      # Drawn from the whole pool when nothing has been picked yet, which is the login
      # case: any of them is a fair wallpaper for the session, the plain one included.
      # A re-roll from a bind is a different question -- it is a request for a change, and
      # landing back on the one already up would read as the pick having silently failed --
      # so that one is drawn from the others.
      random)
        if ((current < 0)); then
          index=$((RANDOM % count))
        else
          index=$(((index + 1 + RANDOM % (count - 1)) % count))
        fi
        ;;
      list)
        for i in $(seq 0 $((count - 1))); do
          printf '%s\t%s\t%s\t%s\n' "$i" "''${labels[i]}" "''${desk[i]}" "''${panel[i]}"
        done
        exit 0
        ;;
      # What is up, as the index the verbs above count in, or -1 before the login pick has
      # landed. The state file is this script's own business -- the picker in
      # lattice-wallpaper-menu needs the answer to mark the row that is already set, and a
      # second reader of the path would be a second thing to change if it ever moves.
      current)
        echo "$current"
        exit 0
        ;;
      # The pick already made, pushed to hyprpaper again: for the second half of the login
      # pick, for a hyprpaper that has restarted on hyprpaper.conf, and for lattice-theme.
      apply) ;;
      *[!0-9]*)
        echo "usage: lattice-wallpaper [--choose] [next|prev|random|apply|list|current|<index>]" >&2
        exit 2
        ;;
      *) index=$(($1 % count)) ;;
      esac

      # Before hyprpaper is told, and recorded after it is: the lock screen reads these
      # rather than being sent anything, so they should be right even on the login pick,
      # where this races hyprpaper's own start and may have to be retried to get through.
      install -d "${currentDir}"
      ln -sfn "''${panel[index]}" "${currentPanel}"
      ln -sfn "''${desk[index]}" "${currentDesk}"

      if ((choose)); then
        lattice-palette --write-only "${currentDir}" "$flavor" "''${accents[index]}" "''${alts[index]}"
        echo "''${slots[index]}" >"$state"
        exit 0
      fi

      # An internal panel is a small screen a forearm away and gets the drawing sized for
      # one; anything else is taken for a monitor across a desk. Matching on the connector
      # name is what hyprland and the kernel both call these, and it covers the Dell's
      # eDP-1 as well as this Mac's.
      apply() {
        local output file
        for output in $(hyprctl monitors -j | jq -r '.[].name'); do
          case "$output" in
          eDP-* | LVDS-* | DSI-*) file="''${panel[index]}" ;;
          *) file="''${desk[index]}" ;;
          esac
          hyprctl hyprpaper wallpaper "$output,$file" || return 1
        done
      }

      # hyprpaper binds its IPC socket a moment after its process starts, so the login pick
      # can arrive before there is anything to answer it -- hyprctl does not wait, it exits
      # nonzero. Retrying here rather than letting the unit fail and restart is what keeps
      # the failure notification worth having: it now means hyprpaper is not coming, not
      # that the pick was a second early. Five seconds is many times the gap ever measured.
      for attempt in {1..10}; do
        if reply=$(apply 2>&1); then
          break
        fi
        if ((attempt == 10)); then
          echo "hyprpaper did not answer after $attempt tries: $reply" >&2
          exit 1
        fi
        sleep 0.5
      done

      # Only once the wallpaper is really up, so a pick that never landed does not leave
      # the desktop wearing the theme of a wallpaper it is not showing.
      lattice-palette "$flavor" "''${accents[index]}" "''${alts[index]}"

      echo "''${slots[index]}" >"$state"
    '';
  };

  # The flavour, for the bar's theme pill and its menu. It records the choice and hands the
  # rest to `lattice-wallpaper apply`, which draws the wallpaper already up in the
  # new flavour and rewrites the theme files from it -- so the accent the wallpaper set is
  # kept across a switch, in that flavour's shade of it.
  latticeTheme = pkgs.writeShellApplication {
    name = "lattice-theme";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      cycleWallpaper
    ];
    text = ''
      ${readFlavor}
      flavors=(${lib.escapeShellArgs flavorNames})
      labels=(${lib.escapeShellArgs (map (n: theme.flavors.${n}.label) flavorNames)})
      count=''${#flavors[@]}

      index=0
      for i in "''${!flavors[@]}"; do
        if [[ ''${flavors[i]} == "$flavor" ]]; then
          index=$i
        fi
      done

      case "''${1:-next}" in
      next) target=''${flavors[(index + 1) % count]} ;;
      prev) target=''${flavors[(index - 1 + count) % count]} ;;
      list)
        for i in "''${!flavors[@]}"; do
          printf '%s\t%s\n' "''${flavors[i]}" "''${labels[i]}"
        done
        exit 0
        ;;
      current)
        echo "$flavor"
        exit 0
        ;;
      *)
        target=$1
        if [[ " ''${flavors[*]} " != *" $target "* ]]; then
          echo "usage: lattice-theme [next|prev|list|current|${lib.concatStringsSep "|" flavorNames}]" >&2
          exit 2
        fi
        ;;
      esac

      install -d "$(dirname "${themeState}")"
      echo "$target" >"${themeState}.tmp"
      mv -f "${themeState}.tmp" "${themeState}"
      lattice-wallpaper apply

      # The Stream Deck has one layout per flavour (modules/nixos/streamdeck.nix) and reads it
      # only at start, so a new flavour is a restart; its seed step picks the layout from the
      # file just written. Only on a real change -- the deck goes blank for a second or two
      # and back to its first page -- and --no-block so the menu that ran this is not held.
      if [[ $target != "$flavor" ]]; then
        systemctl --user --no-block try-restart streamdeck.service || true
      fi
    '';
  };

  # hyprsunset runs from session start but idles at its 6000K default, which is no filter
  # at all -- the daemon is only useful once something sets a temperature.
  #
  # Two things about driving it, both found by testing: the `hyprsunset` CLI flags spawn a
  # *new* daemon rather than talking to the running one (it then dies with "A CTM manager
  # is already running"), so control goes through `hyprctl hyprsunset`; and `identity`
  # leaves the reported temperature at its last set value, so it can't be used to detect
  # state. Toggling between 6000K and warm keeps the daemon's own reading authoritative,
  # which means the bar can't desync from the screen and no state file is needed.
  #
  # The warm end is per-host -- lattice.display.sunsetTemperature -- because how strong a
  # given temperature looks depends on the panel; see modules/nixos/display.nix.
  sunset = pkgs.writeShellApplication {
    name = "lattice-sunset";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.procps
    ];
    text = ''
      warm=${toString config.lattice.display.sunsetTemperature}
      neutral=6000

      current() { hyprctl hyprsunset temperature; }

      case "''${1:-toggle}" in
      on)     hyprctl hyprsunset temperature "$warm" >/dev/null ;;
      off)    hyprctl hyprsunset temperature "$neutral" >/dev/null ;;
      toggle)
        if [ "$(current)" -lt "$neutral" ]; then
          hyprctl hyprsunset temperature "$neutral" >/dev/null
        else
          hyprctl hyprsunset temperature "$warm" >/dev/null
        fi
        ;;
      status)
        temp=$(current)
        if [ "$temp" -lt "$neutral" ]; then
          printf '{"text":"󰖔","tooltip":"Night light on - %sK","class":"warm"}\n' "$temp"
        else
          printf '{"text":"󰖙","tooltip":"Night light off - %sK","class":"cool"}\n' "$temp"
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-sunset [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+1 matches the "signal" of the custom/sunset module in ~/.dotfiles/waybar.
      pkill -RTMIN+1 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync sunset || true
    '';
  };

  # Do not disturb, as a mako mode rather than anything of our own: `[mode=dnd] invisible=1`
  # in ~/.dotfiles/mako is the whole implementation, and this only flips the mode and tells
  # the bar. mako owns the state, so the pill cannot desync from the daemon -- the same
  # reason lattice-sunset reads hyprsunset instead of keeping a state file.
  #
  # What `invisible` does and does not do, measured rather than read off the man page:
  # a hidden notification is still *live*, so nothing is dropped -- leaving the mode shows
  # whatever is still up, which for critical means everything, since urgency=critical carries
  # default-timeout=0. A normal notification instead times out unseen while the mode is on
  # and lands in the history, recoverable on SUPER+ALT+N. So the count below is the number
  # that will appear the moment the mode goes off, not the number missed.
  dnd = pkgs.writeShellApplication {
    name = "lattice-dnd";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      pkgs.gnugrep
      pkgs.procps
    ];
    text = ''
      # -x, because `makoctl mode` prints one mode per line and a substring match would
      # answer yes to any mode with dnd in the name.
      enabled() { makoctl mode | grep -qx dnd; }

      case "''${1:-toggle}" in
      on)  makoctl mode -a dnd >/dev/null ;;
      off) makoctl mode -r dnd >/dev/null ;;
      toggle)
        if enabled; then
          makoctl mode -r dnd >/dev/null
        else
          makoctl mode -a dnd >/dev/null
        fi
        ;;
      status)
        if enabled; then
          waiting=$(makoctl list -j | jq length)
          if [ "$waiting" -gt 0 ]; then
            printf '{"text":"󰂛","tooltip":"Do not disturb - %s waiting","class":"on"}\n' "$waiting"
          else
            printf '{"text":"󰂛","tooltip":"Do not disturb","class":"on"}\n'
          fi
        else
          printf '{"text":"󰂚","tooltip":"Notifications on","class":"off"}\n'
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-dnd [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+4 matches the "signal" of the custom/dnd module in ~/.dotfiles/waybar. 1, 2
      # and 3 are sunset, tailscale and weather.
      pkill -RTMIN+4 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync dnd || true
    '';
  };

  # The keep-awake switch, and the one mechanism behind both surfaces that offer it.
  #
  # waybar's built-in idle_inhibitor was the obvious thing and is the wrong shape here: it
  # holds a zwp_idle_inhibit_manager_v1 lock on waybar's *own* surface, which nothing
  # outside waybar can read or release. So a Stream Deck key could only ever have been a
  # second switch disagreeing with the first -- press one and the other still shows the
  # opposite, both of them telling the truth about their own lock.
  #
  # hypridle is what actually locks the session, blanks the screens and dims the deck, so
  # stopping it is the honest way to say "stay awake" -- and it stops all three rather than
  # only the blank, which is what the inhibit lock did too. `systemctl is-active` is then a
  # state both surfaces can read, and neither owns.
  #
  # `on` means staying awake, matching the bar's old activated/deactivated. That it stops a
  # unit to do so is the sort of inversion worth saying out loud.
  idleInhibit = pkgs.writeShellApplication {
    name = "lattice-idle";
    runtimeInputs = [
      pkgs.systemd
      pkgs.procps
    ];
    text = ''
      unit=hypridle.service

      awake() { ! systemctl --user is-active --quiet "$unit"; }

      case "''${1:-toggle}" in
      on)  systemctl --user stop "$unit" ;;
      off) systemctl --user start "$unit" ;;
      toggle)
        if awake; then
          systemctl --user start "$unit"
        else
          systemctl --user stop "$unit"
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

  # Tailscale has no Linux GUI, so the bar pill is the interface: the tooltip carries the
  # connection report and a click brings the tunnel up or down. `tailscale status --json`
  # exposes the daemon's own view, so there is no separate session state to keep in step --
  # the same reason lattice-sunset asks hyprsunset rather than tracking the temperature.
  #
  # Peer counts skip exit nodes: this tailnet has the Mullvad integration on, so 533 of its
  # 539 peers are exit nodes and counting them would hide the six real devices. Health is
  # reported as a second CSS class, so a running-but-warning node doesn't read as a
  # healthy green pill. The glyphs are Material Design Icons from Nerd Fonts 3.5.0;
  # there is no Tailscale mark in the set, and these are recoloured by style.css anyway.
  tailscale = pkgs.writeShellApplication {
    name = "lattice-tailscale";
    runtimeInputs = [
      pkgs.tailscale
      pkgs.jq
      pkgs.procps
      pkgs.xdg-utils
      pkgs.coreutils # sleep, while waiting on the sign-in URL
    ];
    text = ''
      glyph_connected=$'\U000F0582' # md-vpn
      glyph_stopped=$'\U000F0319'   # md-lan_disconnect
      glyph_login=$'\U000F08EE'     # md-lock_alert
      glyph_alert=$'\U000F0ECC'     # md-shield_alert

      # Waybar's custom-module JSON. `class` is an array, so a state and a warning can both
      # apply; style.css keys off the names. Built through jq rather than printf so newlines
      # and any awkward character in a hostname or health line are escaped, not trusted.
      emit() {
        local text="$1" tooltip="$2"
        shift 2
        jq -cn \
          --arg text "$text" \
          --arg tooltip "$tooltip" \
          --argjson class "$(jq -cn --args '$ARGS.positional' "$@")" \
          '{text: $text, tooltip: $tooltip, class: $class}'
      }

      status() {
        local json
        if ! json="$(tailscale status --json 2>/dev/null)" || [ -z "$json" ]; then
          emit "$glyph_stopped" $'Tailscale is not responding\ntailscaled may be stopped' stopped
          return 0
        fi

        local backend text
        local -a classes lines

        backend="$(jq -r '.BackendState // "NoState"' <<<"$json")"

        case "$backend" in
        Running)
          local host ip tailnet dns advertise online devs exit_id exit_name health
          host="$(jq -r '.Self.HostName // "this device"' <<<"$json")"
          ip="$(jq -r '.Self.TailscaleIPs[0] // ""' <<<"$json")"
          dns="$(jq -r '.Self.DNSName // "" | sub("\\.$"; "")' <<<"$json")"
          tailnet="$(jq -r '.CurrentTailnet.Name // ""' <<<"$json")"
          advertise="$(jq -r '.Self.ExitNode // false' <<<"$json")"

          read -r online devs <<<"$(jq -r '[([.Peer[] | select((.ExitNodeOption | not) and .Online)] | length), ([.Peer[] | select(.ExitNodeOption | not)] | length)] | @tsv' <<<"$json")"

          lines=("Tailscale: Connected" "$host  $ip")
          if [ -n "$tailnet" ]; then lines+=("tailnet: $tailnet"); fi
          lines+=("devices: $online/$devs online")

          # Using an exit node is the difference between "the tunnel is up" and "traffic
          # is actually going through Mullvad", so it gets its own class for style.css to
          # colour on: teal with one, red without. ExitNodeStatus is null unless this node
          # is routing through one; its ID names the peer to show in the tooltip.
          exit_id="$(jq -r '.ExitNodeStatus.ID // empty' <<<"$json")"
          local exit_class
          if [ -n "$exit_id" ]; then
            exit_name="$(jq -r --arg id "$exit_id" '[.Peer[] | select(.ID == $id)][0].HostName // $id' <<<"$json")"
            lines+=("exit node: $exit_name")
            exit_class=exit-node
          else
            lines+=("exit node: none")
            exit_class=no-exit-node
          fi
          if [ "$advertise" = true ]; then
            lines+=("advertising as an exit node")
          fi
          if [ -n "$dns" ]; then lines+=("$dns"); fi

          # Health is where tailscaled reports route conflicts and the like. Showing it as
          # a second class is the whole reason the running state isn't just the vpn glyph.
          health="$(jq -r '.Health // [] | .[]' <<<"$json")"
          if [ -n "$health" ]; then
            text="$glyph_alert"
            classes=(running warning)
            while IFS= read -r line; do lines+=("warning: $line"); done <<<"$health"
          else
            text="$glyph_connected"
            classes=(running "$exit_class")
          fi
          ;;

        Starting)
          text="$glyph_connected"
          classes=(starting)
          lines=("Tailscale: starting")
          ;;

        NeedsLogin | NeedsMachineAuth)
          local authurl
          text="$glyph_login"
          classes=(needs-login)
          authurl="$(jq -r '.AuthURL // empty' <<<"$json")"
          if [ "$backend" = NeedsMachineAuth ]; then
            lines=("Tailscale: waiting for approval")
          else
            lines=("Tailscale: signed out" "click to sign in")
          fi
          if [ -n "$authurl" ]; then lines+=("$authurl"); fi
          ;;

        *)
          text="$glyph_stopped"
          classes=(stopped)
          lines=("Tailscale: disconnected" "click to connect")
          ;;
        esac

        local tooltip
        printf -v tooltip '%s\n' "''${lines[@]}"
        emit "$text" "''${tooltip%$'\n'}" "''${classes[@]}"
      }

      toggle() {
        local json backend
        json="$(tailscale status --json 2>/dev/null || true)"
        backend="$(jq -r '.BackendState // "NoState"' <<<"$json" 2>/dev/null || echo NoState)"

        case "$backend" in
        Running)
          tailscale down
          ;;

        # Signed out, so there is no tunnel to raise -- there is a sign-in to finish, and
        # that needs a browser. `tailscale up` cannot be the whole answer here: it prints
        # the sign-in URL on its own stdout and then blocks until the browser leg
        # completes, and it has to be detached or the click would hang forever, which
        # threw the URL away and left the pill sitting at "signed out" with nothing on
        # screen. tailscaled publishes the same URL in its status once a flow exists --
        # the copy the tooltip already shows -- so take it from there and open it.
        NeedsLogin | NeedsMachineAuth)
          local authurl n=0
          authurl="$(jq -r '.AuthURL // empty' <<<"$json" 2>/dev/null || true)"

          # No flow yet: ask for one. The URL is minted by the control plane, so it lands
          # a beat after the request rather than with it. 10s is a generous round trip and
          # still short enough that an unreachable control plane doesn't leave this
          # spinning behind the bar.
          if [ -z "$authurl" ]; then
            tailscale up >/dev/null 2>&1 &
            disown || true

            while [ -z "$authurl" ] && [ "$n" -lt 40 ]; do
              sleep 0.25
              n=$((n + 1))
              authurl="$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty' 2>/dev/null || true)"
            done
          fi

          if [ -n "$authurl" ]; then
            xdg-open "$authurl" >/dev/null 2>&1 &
            disown || true
          fi
          ;;

        *)
          # Authenticated and merely down, or the daemon has no opinion yet: `up` returns
          # at once, so the signal below lands on the new state.
          tailscale up >/dev/null 2>&1 &
          disown || true
          ;;
        esac

        # RTMIN+2 matches the "signal" of custom/tailscale in ~/.dotfiles/waybar. After a
        # sign-in it only repaints the pill as "signed out" again -- the browser leg is
        # still in progress at this point -- so the switch to connected arrives with the
        # module's 30s interval.
        pkill -RTMIN+2 waybar 2>/dev/null || true
      }

      web() {
        xdg-open "https://login.tailscale.com/admin/machines" >/dev/null 2>&1 &
        disown || true
      }

      case "''${1:-status}" in
      status) status ;;
      toggle) toggle ;;
      web) web ;;
      *)
        echo "usage: lattice-tailscale [status|toggle|web]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # Weather, from Open-Meteo: no API key, no account, and -- the reason it is this rather
  # than the usual wttr.in one-liner -- it takes explicit coordinates. Anything that
  # geolocates by IP reads the Tailscale exit node instead of the laptop, and this tailnet
  # has the Mullvad integration on (see lattice-tailscale above), so the pill would quietly
  # report another country's weather most of the time. The coordinates are
  # lattice.weather.* in modules/nixos/weather.nix.
  #
  # The pill is glyph + temperature + apparent temperature, the last dimmed with Pango
  # markup rather than split into a second module, so the whole reading stays one bubble on
  # a bar whose right side is already full. Conditions are carried by the glyph and the
  # colour, which is why the text spells out neither: the script emits a class per
  # temperature band and style.css colours it, the same contract lattice-sunset and
  # lattice-tailscale use.
  #
  # The last good payload is cached in XDG_RUNTIME_DIR, so a resume with the Wi-Fi still
  # associating re-renders the previous reading greyed (.stale) instead of blanking the
  # pill. Runtime dir rather than /var/lib: a reading that survived a reboot would be too
  # old to show anyway.
  weather = pkgs.writeShellApplication {
    name = "lattice-weather";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.procps
      pkgs.coreutils # mktemp
    ];
    text = ''
      lat=${config.lattice.weather.latitude}
      lon=${config.lattice.weather.longitude}
      label=${lib.escapeShellArg config.lattice.weather.label}

      cache="''${XDG_RUNTIME_DIR:-/tmp}/lattice-weather.json"

      # forecast_days=1 because the tooltip only shows today's high, low and sunset; the
      # hourly block is left off for the same reason. `timezone=auto` resolves from the
      # coordinates, so the sunset timestamp is already local and needs no conversion.
      api="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day&daily=temperature_2m_max,temperature_2m_min,sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=1"

      # Written to a temp file and moved into place only once jq confirms the body parses,
      # so a captive portal's login page or a truncated response can't overwrite a good
      # cache with something that renders as an empty pill.
      fetch() {
        local tmp
        tmp=$(mktemp)
        if curl -fsS --max-time 10 "$api" -o "$tmp" && jq -e '.current.temperature_2m' "$tmp" >/dev/null 2>&1; then
          mv "$tmp" "$cache"
          return 0
        fi
        rm -f "$tmp"
        return 1
      }

      # 16 points of 22.5 degrees each. Integer arithmetic, so the half-degree is carried by
      # scaling both sides by 10: index = (deg * 10 + 112) / 225, which rounds to the
      # nearest point rather than truncating toward N.
      compass() {
        local points=(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW)
        echo "''${points[$((($1 * 10 + 112) / 225 % 16))]}"
      }

      # WMO 4677, as Open-Meteo documents it. Codes are grouped to the glyphs the Material
      # Design range actually has -- there is no "slight vs moderate drizzle" mark -- and
      # the day/night split only exists for the three clear-ish codes, which are the only
      # ones that look wrong with a sun in them at midnight.
      icon_for() {
        case "$1" in
        0)        if [ "$2" = 1 ]; then echo "󰖙 Clear"; else echo "󰖔 Clear"; fi ;;
        1)        if [ "$2" = 1 ]; then echo "󰖙 Mainly clear"; else echo "󰖔 Mainly clear"; fi ;;
        2)        if [ "$2" = 1 ]; then echo "󰖕 Partly cloudy"; else echo "󰼱 Partly cloudy"; fi ;;
        3)        echo "󰖐 Overcast" ;;
        45 | 48)  echo "󰖑 Fog" ;;
        51 | 53 | 55) echo "󰼳 Drizzle" ;;
        56 | 57)  echo "󰙿 Freezing drizzle" ;;
        61 | 63)  echo "󰖖 Rain" ;;
        65)       echo "󰖗 Heavy rain" ;;
        66 | 67)  echo "󰙿 Freezing rain" ;;
        71 | 73)  echo "󰖘 Snow" ;;
        75)       echo "󰼶 Heavy snow" ;;
        77)       echo "󰖘 Snow grains" ;;
        80 | 81)  echo "󰖖 Rain showers" ;;
        82)       echo "󰖗 Violent rain showers" ;;
        85 | 86)  echo "󰖘 Snow showers" ;;
        95)       echo "󰖓 Thunderstorm" ;;
        96 | 99)  echo "󰼯 Thunderstorm with hail" ;;
        *)        echo "󰼮 WMO $1" ;;
        esac
      }

      # Fahrenheit bands. The glyph says what is falling out of the sky; the colour says
      # whether to put a coat on, which is the part a forecast usually gets consulted for.
      band_for() {
        if   [ "$1" -lt 32 ]; then echo freezing
        elif [ "$1" -lt 50 ]; then echo cold
        elif [ "$1" -lt 75 ]; then echo mild
        elif [ "$1" -lt 90 ]; then echo warm
        else echo hot
        fi
      }

      render() {
        local stale="$1"
        local code isday temp feels hum wind wdir hi lo sunset
        local icon desc band classes text tooltip

        # One jq pass into positional fields rather than ten invocations. round() gives
        # integers, which is what the [ -lt ] comparisons in band_for need and what the
        # pill should show -- a tenth of a degree is noise at this size.
        IFS=$'\t' read -r code isday temp feels hum wind wdir hi lo sunset < <(
          jq -r '[
            .current.weather_code,
            .current.is_day,
            (.current.temperature_2m | round),
            (.current.apparent_temperature | round),
            .current.relative_humidity_2m,
            (.current.wind_speed_10m | round),
            (.current.wind_direction_10m | round),
            (.daily.temperature_2m_max[0] | round),
            (.daily.temperature_2m_min[0] | round),
            (.daily.sunset[0] | split("T")[1])
          ] | @tsv' "$cache"
        )

        read -r icon desc <<<"$(icon_for "$code" "$isday")"
        band=$(band_for "$temp")

        classes=$(jq -cn --arg b "$band" --argjson s "$stale" \
          'if $s then [$b, "stale"] else [$b] end')

        # Pango markup: the apparent temperature is the same size but dimmed, so it reads
        # as a qualifier on the number beside it rather than as a second reading competing
        # with it. waybar runs a custom module's text through set_markup, so this is parsed
        # rather than shown literally.
        #
        # Both temperatures are right-aligned in a three-character field. The bar font is
        # JetBrains Mono, so that makes the pill a fixed width whatever the reading is --
        # which is what lets the centre group's counterweight be a constant. Without it the
        # pill would be two characters narrower at 73° than at -5°, and the clock beside it
        # would wander off centre as the temperature changed. Three characters covers
        # -99..999; a reading outside that widens the pill, and the clock drifts by half the
        # difference until it comes back.
        text=$(printf '%s %3s° <span alpha="55%%">%3s°</span>' "$icon" "$temp" "$feels")

        tooltip=$(printf '<b>%s</b>\n%s\nH %s°  L %s°\nWind %s mph %s · Humidity %s%%\nSunset %s' \
          "$label" "$desc" "$hi" "$lo" "$wind" "$(compass "$wdir")" "$hum" "$sunset")

        if [ "$stale" = true ]; then
          tooltip=$(printf '%s\n<i>Offline - last known reading</i>' "$tooltip")
        fi

        jq -cn --arg text "$text" --arg tooltip "$tooltip" --argjson class "$classes" \
          '{text: $text, tooltip: $tooltip, class: $class}'
      }

      status() {
        local stale=false
        fetch || stale=true

        # Nothing cached and nothing fetched -- a cold boot with no network yet. A muted
        # glyph rather than an empty module, which waybar would collapse to a bare pill.
        if [ ! -s "$cache" ]; then
          printf '{"text":"󰅤","tooltip":"Weather unavailable","class":["unavailable"]}\n'
          return
        fi

        render "$stale"
      }

      case "''${1:-status}" in
      status) status ;;
      # The signal is the whole of it: waybar re-runs `status` on receipt, and that is what
      # re-fetches. Doing the fetch here as well would make every click two round trips.
      # RTMIN+3 matches the "signal" of custom/weather in ~/.dotfiles/waybar.
      refresh) pkill -RTMIN+3 waybar 2>/dev/null || true ;;
      *)
        echo "usage: lattice-weather [status|refresh]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # The power-profile pill, as a custom module rather than waybar's own
  # power-profiles-daemon. What the swap buys is the tooltip: four sparklines over a
  # two-minute window -- load, each core cluster's clock and the package's own draw in watts
  # -- under the profile's name, and below them the fans, the hottest sensor that names
  # itself and what the battery is doing. None of that could hang off the built-in module,
  # whose tooltip-format takes exactly one placeholder, {profile}.
  #
  # What it costs is the D-Bus subscription: the built-in module watched
  # net.hadess.PowerProfiles and repainted the instant anything else set a profile, where
  # this polls. At the pill's 2s interval a press on the deck's profile key, or a
  # `powerprofilesctl set` in a shell, lands within one tick -- close enough not to read as
  # a lag, and the reason the click below goes through lattice-deck rather than at busctl.
  #
  # The sampling has to run whether or not anyone is hovering, because a graph that only
  # started when the tooltip opened would be an empty one. So a tick is built to be cheap:
  # sysfs through bash's `read` rather than $(cat), the slow-moving readouts cached between
  # ticks, and one fork in the whole script -- busctl, for the profile. That measures ~15ms
  # per tick on this Mac, most of it bash's own startup. The window lives in
  # XDG_RUNTIME_DIR, so it is per-boot and never on disk.
  powerProfile = pkgs.writeShellApplication {
    name = "lattice-power-profile";
    runtimeInputs = [
      pkgs.systemd # busctl, for the profile the pill names
      pkgs.procps # pkill, to signal the bar after a click
    ];
    text = ''
      # The tooltip's palette, read from the run-time theme on every tick so a theme switch
      # reaches it too.
      # The three profile colours are the ones style.css gives the pill, so the name in the
      # tooltip and the glyph on the bar are the same colour; the series each get their own.
      ${readColours}
      c_dim=''${c[overlay1]}
      c_text=''${c[text]}
      c_load=''${c[blue]}
      c_pcore=''${c[lavender]}
      c_ecore=''${c[teal]}
      c_watt=''${c[peach]}
      c_saver=''${c[green]}
      c_balanced=''${c[mauve]}
      c_perf=''${c[peach]}
      c_none=''${c[overlay0]}
      # The graph is `width` samples of the waybar interval, so these two are the window: 60 at
      # 2s is the last two minutes. Keep `period` in step with "interval" on custom/power-profile
      # in ~/.dotfiles/waybar/config.jsonc -- it is only used to say how long the window is.
      width=60
      period=2
      extras_every=10

      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-power-profile"
      history="$state/history"
      extras="$state/extras"

      bars=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

      case "''${1:-status}" in
      status) ;;
      cycle)
        # The cycle itself belongs to lattice-deck: it already walks saver -> balanced ->
        # performance through only the profiles this machine's daemon offers, and repaints the
        # deck's key afterwards. Going through it rather than straight at busctl is what keeps the
        # bar and the deck from disagreeing about which profile is on -- the same reason both
        # audio pills mute through lattice-deck.
        lattice-deck profile
        # RTMIN+6 matches the "signal" of custom/power-profile in ~/.dotfiles/waybar. 1 to 5 are
        # sunset, tailscale, weather, dnd and idle.
        pkill -RTMIN+6 waybar 2>/dev/null || true
        exit 0
        ;;
      *)
        echo "usage: lattice-power-profile [status|cycle]" >&2
        exit 2
        ;;
      esac

      # Every reading here is a one-line sysfs file, and $(cat) would fork for each -- twenty-odd
      # of them per tick, every two seconds, all day. `read` into a global is the same thing with
      # no process: `rd path` leaves the value in $val, and a file that is missing, empty or
      # unreadable leaves it empty rather than failing the script.
      val=""
      rd() {
        val=""
        [ -r "$1" ] || return 0
        read -r val < "$1" 2>/dev/null || val=""
      }

      # Guards for everything that reaches arithmetic. sysfs gives unsigned; the state files carry
      # -1 for "this machine has no such sensor", and `sane` is the one test that covers a whole
      # series at once -- a line of digits, spaces and minus signs is safe to do sums on, and
      # anything else (a half-written file from a tick that was killed) starts the window again.
      uint() { case "''${1-}" in "" | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
      sane() { case "''${1-}" in *[!0-9\ -]*) return 1 ;; *) return 0 ;; esac; }

      ### SAMPLE ###

      [ -d "$state" ] || mkdir -p "$state"

      now=''${EPOCHREALTIME/./}

      # CPU busy fraction, as the jiffy counters' delta against the previous sample.
      read -r _ u n s idle iow irq sirq steal _ < /proc/stat
      busy=$((u + n + s + irq + sirq + steal))
      total=$((busy + idle + iow))

      # cpufreq, grouped by the ceiling each policy reports: one group on a machine whose cores
      # are all alike, two where the clusters differ -- this Mac's 4 E-cores and 8 P-cores, or an
      # Alder Lake. A third ceiling, if one ever turns up, folds into the fastest and the slowest.
      p_max=0 p_min=0 p_sum=0 p_n=0 p_gov=""
      e_max=0 e_min=0 e_sum=0 e_n=0
      for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        rd "$policy/cpuinfo_max_freq"
        uint "$val" || continue
        hi=$val
        rd "$policy/scaling_cur_freq"
        uint "$val" || continue
        cur=$val
        rd "$policy/cpuinfo_min_freq"
        if uint "$val"; then lo=$val; else lo=0; fi

        if [ "$hi" -gt "$p_max" ]; then
          # A faster group than anything seen so far. What was the fastest becomes the slowest,
          # unless something slower has already claimed that.
          if [ "$p_max" -gt 0 ] && { [ "$e_max" -eq 0 ] || [ "$p_max" -lt "$e_max" ]; }; then
            e_max=$p_max e_min=$p_min e_sum=$p_sum e_n=$p_n
          fi
          p_max=$hi p_min=$lo p_sum=$cur p_n=1
          rd "$policy/scaling_governor"
          p_gov=$val
        elif [ "$hi" -eq "$p_max" ]; then
          p_sum=$((p_sum + cur)) p_n=$((p_n + 1))
        elif [ "$e_max" -eq 0 ] || [ "$hi" -lt "$e_max" ]; then
          e_max=$hi e_min=$lo e_sum=$cur e_n=1
        elif [ "$hi" -eq "$e_max" ]; then
          e_sum=$((e_sum + cur)) e_n=$((e_n + 1))
        fi
      done
      if [ "$p_n" -gt 0 ]; then p_cur=$((p_sum / p_n)); else p_cur=0; fi
      if [ "$e_n" -gt 0 ]; then e_cur=$((e_sum / e_n)); else e_cur=0; fi

      # Draw, in milliwatts, from whichever of three sources this machine has. macsmc's "Total
      # System Power" is the whole-package figure and the reason this row is worth graphing at
      # all: it is the number a power profile is actually chosen for. The other two are what the
      # Dell has instead, and neither has been run there yet.
      power_mw=-1
      energy_uj=-1
      power_src=""
      for hwmon in /sys/class/hwmon/hwmon*; do
        for lbl in "$hwmon"/power*_label; do
          [ -e "$lbl" ] || continue
          rd "$lbl"
          [ "$val" = "Total System Power" ] || continue
          rd "''${lbl%_label}_input"
          uint "$val" || continue
          power_mw=$((val / 1000))
          power_src=smc
        done
      done
      if [ -z "$power_src" ]; then
        # Intel's RAPL package counter is microjoules since boot, so it needs the previous reading
        # and the interval between the two -- the same delta the jiffies take above.
        rd /sys/class/powercap/intel-rapl:0/energy_uj
        if uint "$val"; then
          energy_uj=$val
          power_src=rapl
        fi
      fi
      if [ -z "$power_src" ]; then
        # Last resort: what the battery is passing. Only true while discharging -- on AC most
        # laptops report the charge rate here, or zero -- so the row it draws is the honest one
        # for a machine on battery and not much otherwise.
        for supply in /sys/class/power_supply/*; do
          rd "$supply/scope"
          [ "$val" = Device ] && continue
          rd "$supply/status"
          [ "$val" = Discharging ] || continue
          rd "$supply/power_now"
          uint "$val" || continue
          power_mw=$((val / 1000))
          power_src=battery
          break
        done
      fi

      ### HISTORY ###

      # Five lines: the counters the next tick differences against, then one line per series. The
      # series are stored across rather than down -- a line of numbers each, trimmed to the
      # graph's width -- so the render below reads its four graphs with four `read -a` and never
      # parses a sample. It lives in XDG_RUNTIME_DIR, so a reboot starts a fresh window.
      hist=()
      [ -r "$history" ] && mapfile -t hist < "$history"

      prev=()
      cpus=() pfreqs=() efreqs=() watts=()
      if [ "''${#hist[@]}" -ge 5 ] && sane "''${hist[0]}" && sane "''${hist[1]}" &&
        sane "''${hist[2]}" && sane "''${hist[3]}" && sane "''${hist[4]}"; then
        read -r -a prev <<<"''${hist[0]}"
        read -r -a cpus <<<"''${hist[1]}"
        read -r -a pfreqs <<<"''${hist[2]}"
        read -r -a efreqs <<<"''${hist[3]}"
        read -r -a watts <<<"''${hist[4]}"
      fi

      prev_ts=0 prev_busy=0 prev_total=0 prev_energy=-1
      uint "''${prev[0]-}" && prev_ts=''${prev[0]}
      uint "''${prev[1]-}" && prev_busy=''${prev[1]}
      uint "''${prev[2]-}" && prev_total=''${prev[2]}
      uint "''${prev[3]-}" && prev_energy=''${prev[3]}

      d_busy=$((busy - prev_busy))
      d_total=$((total - prev_total))
      if [ "$prev_total" -gt 0 ] && [ "$d_total" -gt 0 ] && [ "$d_busy" -ge 0 ]; then
        cpu=$((d_busy * 100 / d_total))
      else
        # First sample after a boot, or after a window that did not survive its sanity check. The
        # counters' lifetime average is not what this pill is for, so the graph starts at the floor
        # and the next tick is the first real reading.
        cpu=0
      fi
      [ "$cpu" -gt 100 ] && cpu=100

      if [ "$power_src" = rapl ] && [ "$prev_energy" -ge 0 ] && [ "$prev_ts" -gt 0 ]; then
        d_us=$((now - prev_ts))
        d_uj=$((energy_uj - prev_energy))
        # The counter wraps at max_energy_range_uj, which shows up as a negative delta. Dropping
        # that one sample is cheaper than carrying the range around to correct it.
        if [ "$d_us" -gt 0 ] && [ "$d_uj" -ge 0 ]; then power_mw=$((d_uj * 1000 / d_us)); fi
      fi

      cpus+=("$cpu")
      pfreqs+=("$p_cur")
      efreqs+=("$e_cur")
      watts+=("$power_mw")
      [ "''${#cpus[@]}" -gt "$width" ] && cpus=("''${cpus[@]: -$width}")
      [ "''${#pfreqs[@]}" -gt "$width" ] && pfreqs=("''${pfreqs[@]: -$width}")
      [ "''${#efreqs[@]}" -gt "$width" ] && efreqs=("''${efreqs[@]: -$width}")
      [ "''${#watts[@]}" -gt "$width" ] && watts=("''${watts[@]: -$width}")

      printf '%s\n' \
        "$now $busy $total $energy_uj" \
        "''${cpus[*]}" \
        "''${pfreqs[*]}" \
        "''${efreqs[*]}" \
        "''${watts[*]}" > "$history"

      ### EXTRAS ###

      # Fans, temperatures and the battery are readouts rather than series, and on this Mac every
      # one of them is an SMC round trip. They also move slowly, so they are re-read on their own
      # cadence and cached in between; the sampling above is the part that has to happen on every
      # tick. Line 1 is the stamp that says when this last ran, and a sensor the machine does not
      # have writes an empty line rather than a number -- so the render tests for emptiness and
      # never does arithmetic on a guess.
      ex=()
      [ -r "$extras" ] && mapfile -t ex < "$extras"
      stamp=0
      uint "''${ex[0]-}" && stamp=''${ex[0]}

      if [ $((now / 1000000 - stamp)) -ge "$extras_every" ]; then
        fan_rpm=() heat_mw="" hot_c="" hot_label=""
        for hwmon in /sys/class/hwmon/hwmon*; do
          for f in "$hwmon"/fan*_input; do
            [ -e "$f" ] || continue
            rd "$f"
            # A zero is kept: on this Mac the fans are off most of the time, and "off" is a
            # reading. The row goes missing only on a machine with no tachometer at all, rather
            # than appearing and disappearing under the other rows as the fans come and go.
            uint "$val" && fan_rpm+=("$val")
          done

          for lbl in "$hwmon"/power*_label; do
            [ -e "$lbl" ] || continue
            rd "$lbl"
            [ "$val" = "Heatpipe Power" ] || continue
            rd "''${lbl%_label}_input"
            uint "$val" && heat_mw=$((val / 1000))
          done

          # The hottest sensor that names itself. Unlabelled ones are skipped deliberately: on
          # this Mac they are the six speaker amplifiers, which say nothing about the SoC -- and
          # there is no die temperature to prefer over them, because Asahi's SMC does not expose
          # one. So the row names the sensor it used rather than claiming to be a CPU temperature.
          for lbl in "$hwmon"/temp*_label; do
            [ -e "$lbl" ] || continue
            rd "$lbl"
            [ -n "$val" ] || continue
            label=$val
            rd "''${lbl%_label}_input"
            uint "$val" || continue
            if [ -z "$hot_c" ] || [ "$((val / 1000))" -gt "$hot_c" ]; then
              hot_c=$((val / 1000))
              hot_label=$label
            fi
          done
        done

        batt_state="" batt_mw="" batt_pct="" batt_min=""
        for supply in /sys/class/power_supply/*; do
          rd "$supply/type"
          [ "$val" = Battery ] || continue
          # The Logitech mouse is a power supply too, and says so with scope=Device.
          rd "$supply/scope"
          [ "$val" = Device ] && continue
          rd "$supply/status"
          batt_state=$val
          rd "$supply/capacity"
          uint "$val" && batt_pct=$val
          rd "$supply/power_now"
          uint "$val" && batt_mw=$((val / 1000))
          rd "$supply/energy_now"
          if uint "$val" && [ -n "$batt_mw" ] && [ "$batt_mw" -gt 0 ]; then
            # Microwatt-hours over milliwatts, in minutes.
            batt_min=$((val * 60 / 1000 / batt_mw))
          fi
          break
        done

        ex=(
          "$((now / 1000000))"
          "''${fan_rpm[*]-}"
          "$heat_mw"
          "$hot_c"
          "$hot_label"
          "$batt_state"
          "$batt_mw"
          "$batt_pct"
          "$batt_min"
        )
        printf '%s\n' "''${ex[@]}" > "$extras"
      fi

      ### RENDER ###

      # The active profile, off the same interface the deck's key reads: net.hadess.PowerProfiles,
      # which power-profiles-daemon serves on the Dell and tuned-ppd on this Mac, so neither end
      # has to know which daemon is behind it. --json=short rather than jq, because the whole reply
      # is {"type":"s","data":"balanced"} and two trims take that apart -- this runs every two
      # seconds, and the busctl is already the one fork it cannot do without.
      profile=""
      reply=$(busctl --json=short get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
        net.hadess.PowerProfiles ActiveProfile 2>/dev/null) || reply=""
      case "$reply" in
      *'"data":"'*)
        reply=''${reply##*'"data":"'}
        profile=''${reply%%'"'*}
        ;;
      esac

      case "$profile" in
      power-saver) glyph=󰾆 name="Power saver" colour=$c_saver ;;
      balanced) glyph=󰾅 name="Balanced" colour=$c_balanced ;;
      performance) glyph=󰓅 name="Performance" colour=$c_perf ;;
      *)
        # No daemon on the bus, or a profile none of the three names matches. The graphs are still
        # worth drawing -- they come from sysfs, not from the daemon -- so the pill greys out and
        # says what is missing instead of going blank.
        glyph=󰾉 name="No power profile daemon" colour=$c_none profile=unknown
        ;;
      esac

      # Scale a series into the block glyphs. A zero draws the shortest bar rather than a gap, so
      # an idle stretch reads as a flat line along the bottom instead of a hole in the graph.
      spark=""
      sparkline() {
        local max=$1 v i pad
        shift
        spark=""
        # Until the window has filled -- the first two minutes after a boot, and again after any
        # tick that had to start it over -- there are fewer than `width` samples to draw. Blanking
        # the ones that are missing is what makes the graph scroll rather than grow: the newest
        # sample sits at the right edge from the very first tick, so the reading beside it holds
        # its column instead of being pushed right once every two seconds. A space is the same
        # advance as a block glyph in a monospaced font, and printf's `*` width pads without a
        # fork -- the same reason the rows are built with printf -v rather than echoed.
        pad=$((width - $#))
        [ "$pad" -gt 0 ] && printf -v spark '%*s' "$pad" ""
        [ "$max" -gt 0 ] || max=1
        for v in "$@"; do
          i=$((v * 8 / max))
          [ "$i" -gt 7 ] && i=7
          [ "$i" -lt 0 ] && i=0
          spark+=''${bars[$i]}
        done
      }

      # bash has no floats, and printf cannot round one it never had: fixed point by hand, to the
      # one decimal every reading on this tooltip is quoted at.
      dec=""
      tenths() {
        dec=$((($1 * 10 + $2 / 2) / $2))
        dec="''${dec%?}.''${dec: -1}"
        [ "''${dec:0:1}" = . ] && dec="0$dec"
        return 0
      }

      # One row of the tooltip, appended in place. A function that echoed instead would be a
      # subshell per row, and the point of the reading loops above is that a tick costs one fork.
      # The label column is eight wide, so every graph starts on the same column.
      tip=""
      row() { # label, graph colour, graph, reading, trailing dim note
        local line=""
        printf -v line "<span foreground='%s'>%-8s</span>" "$c_dim" "$1"
        # A readout row has no graph, and an empty span in its place is markup for nothing.
        [ -n "$3" ] && printf -v line "%s<span foreground='%s'>%s</span>" "$line" "$2" "$3"
        printf -v line "%s  <span foreground='%s'>%s</span>" "$line" "$c_text" "$4"
        [ -n "''${5-}" ] && printf -v line "%s<span foreground='%s'>   %s</span>" "$line" "$c_dim" "$5"
        tip+="$line"'\n'
        return 0
      }

      tip="<span foreground='$colour'>$glyph  $name</span>"
      [ -n "$p_gov" ] && tip+="<span foreground='$c_dim'>  ·  $p_gov</span>"
      tip+='\n\n'

      sparkline 100 "''${cpus[@]}"
      row "CPU" "$c_load" "$spark" "$cpu%"

      # Both frequency rows are scaled to their own cluster's floor and ceiling rather than to a
      # shared axis. What a frequency graph is asked is "how much of what this core can do is it
      # doing", and on this Mac the E-cores' ceiling is barely above the P-cores' idle.
      freqrow() { # label, colour, floor, ceiling, current, series...
        local label=$1 colour=$2 lo=$3 hi=$4 cur=$5 span f
        local scaled=()
        shift 5
        span=$((hi - lo))
        [ "$span" -gt 0 ] || span=1
        for f in "$@"; do scaled+=("$(((f - lo) * 100 / span))"); done
        sparkline 100 "''${scaled[@]}"
        tenths "$cur" 1000000
        row "$label" "$colour" "$spark" "$dec GHz"
      }

      if [ "$p_max" -gt 0 ]; then
        # "Freq" rather than "P-core" on a machine with only the one kind of core.
        if [ "$e_max" -gt 0 ]; then p_label=P-core; else p_label=Freq; fi
        freqrow "$p_label" "$c_pcore" "$p_min" "$p_max" "$p_cur" "''${pfreqs[@]}"
      fi
      if [ "$e_max" -gt 0 ]; then
        freqrow E-core "$c_ecore" "$e_min" "$e_max" "$e_cur" "''${efreqs[@]}"
      fi

      if [ "$power_mw" -ge 0 ]; then
        peak_mw=0
        drawn=()
        for mw in "''${watts[@]}"; do
          # A -1 is a tick that had no power source; it plots as the floor rather than breaking the
          # run of the graph.
          if [ "$mw" -lt 0 ]; then mw=0; fi
          drawn+=("$mw")
          [ "$mw" -gt "$peak_mw" ] && peak_mw=$mw
        done
        # A 10 W floor under the scale: an idle machine's draw wanders by a few hundred milliwatts,
        # and a graph scaled to its own noise reads as though something is happening.
        scale=$peak_mw
        [ "$scale" -lt 10000 ] && scale=10000
        sparkline "$scale" "''${drawn[@]}"
        tenths "$power_mw" 1000
        reading="$dec W"
        tenths "$peak_mw" 1000
        row "Power" "$c_watt" "$spark" "$reading" "peak $dec W"
      fi

      # The readouts, from the cached block. Each is drawn only if this machine has the sensor.
      fans=''${ex[1]-} heat_mw=''${ex[2]-} hot_c=''${ex[3]-} hot_label=''${ex[4]-}
      batt_state=''${ex[5]-} batt_mw=''${ex[6]-} batt_pct=''${ex[7]-} batt_min=''${ex[8]-}

      tip+='\n'

      if [ -n "$batt_state" ]; then
        batt="''${batt_pct:-?}%"
        case "$batt_state" in
        Discharging)
          if uint "$batt_mw"; then
            tenths "$batt_mw" 1000
            batt+="  ·  $dec W out"
          fi
          if uint "$batt_min" && [ "$batt_min" -gt 0 ]; then
            batt+="  ·  $((batt_min / 60))h $((batt_min % 60))m left"
          fi
          ;;
        Charging)
          batt+="  ·  charging"
          if uint "$batt_mw" && [ "$batt_mw" -gt 0 ]; then
            tenths "$batt_mw" 1000
            batt+=" at $dec W"
          fi
          ;;
        *) batt+="  ·  ''${batt_state,,}" ;;
        esac
        row Battery "$c_text" "" "$batt"
      fi

      if [ -n "$fans" ]; then
        case "$fans" in
        *[1-9]*) row Fans "$c_text" "" "''${fans// / \/ } rpm" ;;
        *) row Fans "$c_text" "" "off" ;;
        esac
      fi

      heat=""
      if uint "$heat_mw"; then
        tenths "$heat_mw" 1000
        heat="$dec W heatpipe"
      fi
      if [ -n "$hot_c" ] && [ -n "$hot_label" ]; then
        [ -n "$heat" ] && heat+="  ·  "
        heat+="$hot_c°C $hot_label"
      fi
      [ -n "$heat" ] && row Heat "$c_text" "" "$heat"

      tip+="\n<span foreground='$c_dim'>last $((width * period / 60)) min  ·  click to cycle</span>"

      # waybar reads one JSON object per run of the exec. The tooltip is pango markup -- single
      # quotes on the attributes, because a double one would end the JSON string -- the class is
      # what style.css colours the pill by, and the \n are JSON escapes rather than real newlines:
      # %s passes them through, and waybar's parser turns them into line breaks.
      printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$glyph" "$tip" "$profile"
    '';
  };

  # rofi with the calculator mode compiled in. A rofi plugin is a shared object loaded from
  # rofi's own -plugin-path, so `rofi-calc` on its own in systemPackages would be a file
  # nothing ever opens: the nixpkgs wrapper is what joins the plugin into $out/lib/rofi and
  # passes that flag. `rofi -h` lists it under "Detected modes" once it is there, which is
  # the quick check that a nixpkgs bump hasn't broken the plugin ABI -- rofi 2.0 changed it,
  # and a plugin built against the wrong one is silently not loaded.
  #
  # Every caller below takes this one rather than pkgs.rofi. Two wrappers differing only in
  # the plugin would otherwise collide in the system profile, and whichever won would decide
  # whether `-show calc` finds anything.
  #
  # The engine is libqalculate, which is what makes this worth a launcher mode rather than a
  # window: bases and units convert in place (`0xff to bin`, `1 GiB to MB`, `0.1+0.2 to
  # double` for the IEEE bits), solve/diff/sum and matrices work, and integers stay exact.
  # nixpkgs patches the plugin's `qalc` lookup to an absolute store path, so nothing needs to
  # be on PATH for the mode itself; libqalculate is in systemPackages below only for the
  # `qalc` CLI, and adds no closure of its own because the plugin already pulls it in.
  rofiWithCalc = pkgs.rofi.override { plugins = [ pkgs.rofi-calc ]; };

  # The Wi-Fi picker behind the network pill. NetworkManager's own front ends are either a
  # tray applet that would duplicate the pill (nm-applet, already turned down in
  # profiles/laptop.nix) or a window (nm-connection-editor); what is actually wanted from
  # the bar is the short list of networks in range. So this is rofi -- already themed from
  # /etc/xdg/rofi/lattice.rasi, already the launcher, and it lets an SSID be found by
  # typing rather than by hunting down a list.
  #
  # It raises no notifications of its own for joining or leaving: lattice-network-notify
  # (profiles/laptop.nix) is already watching `nmcli monitor` and reports connecting,
  # connected and failed for every interface, so anything said here would arrive as a
  # second pill saying the same thing. The two it does raise are for the cases the monitor
  # cannot describe, because no connection is attempted at all.
  wifiMenu = pkgs.writeShellApplication {
    name = "lattice-wifi";
    runtimeInputs = [
      pkgs.networkmanager
      rofiWithCalc
      pkgs.gawk
      pkgs.libnotify
      # makoctl, to take the scan banner back down; see scanning() below.
      pkgs.mako
    ];
    text = ''
      # Anchored under the right end of the bar rather than centred like the launcher.
      # The offsets are counted from the *usable* area, not from the screen: waybar holds
      # a layer-shell exclusive zone, so a north-east anchor already starts below it, at
      # the bar's bottom edge. y-offset is therefore the gap itself -- 5px, the same
      # spacing the pills use between themselves -- and not the 37 it would take to clear
      # a bar that had to be measured (margin-top 4 plus height 28), which double-counts
      # it and hangs the menu 37px low. Measured with `hyprctl layers`: waybar sits at
      # xywh 10 4 1324 28, and the menu lands at y 32 with an offset of 0, y 37 with 5.
      #
      # x-offset has no exclusive zone to account for, so -10 is waybar's own margin-right
      # and lines the menu's right edge up with the last pill.
      #
      # It is not put under the network pill itself -- every pill to its right is variable
      # width (the battery percentage, the tailscale state), so there is no fixed offset
      # that would stay under it.
      #
      # The rest is what makes this read as a bar dropdown rather than as the launcher
      # wearing a different position. The launcher is a full-attention surface and sized
      # for it; this is a glance, so the type is two points down from the 12 in
      # ~/.dotfiles/rofi/config.rasi and the rows are tightened to match. Overriding it
      # here rather than in config.rasi is deliberate: config.rasi still dresses `rofi
      # -show drun` at its own size.
      theme='
        window { location: north east; anchor: north east; x-offset: -10px; y-offset: 5px; width: 340px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { padding: 7px 10px; }
        element { padding: 5px 10px; }
        listview { lines: 12; }

        /* The connected network, marked with rofi -a. config.rasi draws an active row in
           lavender, which reads as a shade of the ordinary text rather than as a state --
           the launcher has nothing to mark, so the colour was never chosen for this.
           Green instead, the same "this is up" green the battery pill uses, and the
           accent block inverts to dark-on-green when the cursor is on it, the way
           selected.urgent already does. */
        element normal.active, element alternate.active { text-color: @green; }
        element selected.active { background-color: @green; text-color: @crust; }
      '

      # rofi ships the convention for a list you browse: one click highlights a row, two
      # accept it. This is a menu you pick from, and every other surface on the bar acts
      # on the first click, so accept moves onto the single primary click. Select has to
      # be unbound in the same breath -- leave it and both bindings want the same button.
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      # -mesg is the one string rofi renders as pango markup, so an SSID with an ampersand
      # in it would otherwise take the whole message down with a parse error.
      pango() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g'; }

      notice() {
        notify-send -a lattice-wifi -i "$1" \
          -h string:x-canonical-private-synchronous:lattice-wifi "$2" "''${3:-}"
      }

      # The profile whose stored SSID matches, if there is one. `connection show` reports the
      # profile *name*, which is usually the SSID but does not have to be, so the ssid
      # property is what gets compared. UUIDs are listed rather than names because a UUID
      # cannot contain a colon, which keeps the terse output trivially splittable.
      profile_for() {
        local uuid ssid
        while IFS= read -r uuid; do
          ssid=$(nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null || true)
          if [ "$ssid" = "$1" ]; then printf '%s' "$uuid"; return 0; fi
        done < <(nmcli -g UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')
        return 1
      }

      connect() {
        local ssid=$1 uuid password

        case "''${security["$ssid"]}" in
        *802.1X*)
          # Enterprise wants an EAP method, an identity and usually a CA certificate. That
          # is more than one prompt can collect, and a half-filled profile fails in ways
          # that are harder to unpick than never having made one.
          notice network-wireless-symbolic "Enterprise network" \
            "$ssid needs 802.1X settings -- join it once with nmtui"
          return 0
          ;;
        esac

        # A known network is brought up from its saved profile, which is also what holds the
        # stored key; only a genuinely new secured network reaches the prompt.
        if uuid=$(profile_for "$ssid"); then
          nmcli connection up uuid "$uuid" >/dev/null 2>&1 || true
        elif [ -z "''${security["$ssid"]}" ]; then
          nmcli device wifi connect "$ssid" >/dev/null 2>&1 || true
        else
          password=$(
            rofi -dmenu -password -p "Password" -mesg "Password for $(pango "$ssid")" \
              -theme-str "$theme" \
              -theme-str 'mainbox { children: [ inputbar, message ]; }' </dev/null
          ) || return 0
          [ -n "$password" ] || return 0
          nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1 || true
        fi
      }

      device=$(nmcli -g DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }')
      if [ -z "$device" ]; then
        notice network-wireless-offline-symbolic "No Wi-Fi device" "NetworkManager reports no wifi interface"
        exit 0
      fi

      # Nothing to list while the radio is off, and the only useful thing to offer is
      # turning it back on -- so that is the whole menu.
      if [ "$(nmcli radio wifi)" != enabled ]; then
        choice=$(printf '󰖩  Turn Wi-Fi on\n' |
          rofi -dmenu -i -no-cycle -format i -p "Wi-Fi" -mesg "Wi-Fi is off" \
            -theme-str "$theme" "''${click[@]}" || true)
        [ "''${choice:-}" = 0 ] && nmcli radio wifi on
        exit 0
      fi

      # A sweep of the band takes ~6s on this radio and NetworkManager ages its results
      # out, so a menu that insisted on a current list would routinely leave the click
      # unanswered for six seconds. It never waits: the menu is always drawn from the
      # cache nmcli returns instantly (--rescan no), and when that cache holds nothing but
      # the network already joined a sweep is asked for in the background, so the list is
      # there the next time rather than this time. Rescan is the row that waits on
      # purpose, and --rescan yes is what blocks until the sweep finishes.
      #
      # SSID is last in -f on purpose. nmcli's terse output escapes a colon inside a value
      # as '\:', which would shift every field after it -- with the SSID last, the first
      # three splits happen before any of that and the rest of the line is the SSID,
      # whatever it contains.
      scan() {
        nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "$1"
      }

      # The blocking sweep needs to say why the menu has not come back, but mako's
      # default-timeout is 15s -- more than twice the scan -- so a fire-and-forget banner
      # outlives the thing it was explaining and sits on top of the menu that replaced it.
      # `notify-send -p` hands back the id it was given, which makoctl closes the moment
      # the scan returns, so the banner lasts exactly as long as the wait does.
      scanning() {
        local id
        id=$(notify-send -p -a lattice-wifi -i network-wireless-acquiring-symbolic \
          -h string:x-canonical-private-synchronous:lattice-wifi "Scanning for networks")
        lines=$(scan yes)
        [ -n "$id" ] && makoctl dismiss -n "$id" >/dev/null 2>&1 || true
      }

      rescan=no
      while true; do
        if [ "$rescan" = yes ]; then
          scanning
          rescan=no
        else
          lines=$(scan no)
          if [ "$(printf '%s\n' "$lines" | awk 'NF' | wc -l)" -le 1 ]; then
            nmcli device wifi rescan >/dev/null 2>&1 &
          fi
        fi

        unset best security
        declare -A best security
        active=""

        while IFS= read -r line; do
          inuse=''${line%%:*}; rest=''${line#*:}
          signal=''${rest%%:*}; rest=''${rest#*:}
          sec=''${rest%%:*}; ssid=''${rest#*:}
          ssid=''${ssid//\\:/:}

          # A hidden network reports an empty SSID and there is nothing to click on.
          [ -n "$ssid" ] || continue

          # One network is usually several APs, and both bands of each; keep the strongest
          # reading rather than listing the same SSID once per radio.
          if [ -z "''${best["$ssid"]:-}" ] || [ "$signal" -gt "''${best["$ssid"]}" ]; then
            best["$ssid"]=$signal
            security["$ssid"]=$sec
          fi
          [ "$inuse" = "*" ] && active=$ssid
        done <<<"$lines"

        # The actions come first, and not as a matter of taste: the network list is the
        # part that may be a stale cache or empty, and Rescan is what fixes that -- so the
        # row that answers a disappointing list has to be above it, not below however many
        # networks did turn up. They are a parallel array of verbs, because the choice
        # comes back as an index and nothing should have to parse a rendered row apart.
        rows=()
        actions=()
        if [ -n "$active" ]; then
          actions+=(disconnect)
          rows+=("󰅖  Disconnect")
        fi
        actions+=(rescan)
        rows+=("󰑓  Rescan")
        actions+=(radio-off)
        rows+=("󰖪  Turn Wi-Fi off")
        offset=''${#actions[@]}

        mapfile -t ordered < <(
          for ssid in "''${!best[@]}"; do printf '%s\t%s\n' "''${best["$ssid"]}" "$ssid"; done |
            sort -rn -k1,1 | cut -f2-
        )

        selected=()
        for ssid in "''${ordered[@]}"; do
          signal=''${best["$ssid"]}
          if [ "$signal" -ge 75 ]; then icon=󰤨
          elif [ "$signal" -ge 50 ]; then icon=󰤥
          elif [ "$signal" -ge 25 ]; then icon=󰤢
          else icon=󰤟
          fi

          lock=" "
          [ -n "''${security["$ssid"]}" ] && lock=󰌾

          # rofi's -a marks a row "active", which the theme already draws in lavender --
          # so the network in use is coloured rather than carrying a marker glyph that
          # would push the columns out of line.
          [ "$ssid" = "$active" ] && selected=(-a "''${#rows[@]}")

          rows+=("$(printf '%s  %-20.20s %3s%%  %s' "$icon" "$ssid" "$signal" "$lock")")
        done

        # Enter should join the strongest network, not fire whichever action happens to
        # sit in the first row -- so the cursor starts below them, and the actions are
        # reached by scrolling up or by typing their name.
        start=()
        [ "''${#ordered[@]}" -gt 0 ] && start=(-selected-row "$offset")

        if [ -n "$active" ]; then
          mesg="Connected to $(pango "$active")"
        else
          mesg="$device  not connected"
        fi

        choice=$(printf '%s\n' "''${rows[@]}" |
          rofi -dmenu -i -no-cycle -format i -p "Wi-Fi" -mesg "$mesg" \
            -theme-str "$theme" "''${click[@]}" "''${selected[@]}" "''${start[@]}" || true)
        [ -n "''${choice:-}" ] || exit 0

        if [ "$choice" -ge "$offset" ]; then
          # Selecting the network already in use should do nothing rather than tear the
          # connection down and put it straight back up.
          ssid=''${ordered[$((choice - offset))]}
          [ "$ssid" = "$active" ] || connect "$ssid"
          exit 0
        fi

        case "''${actions[$choice]}" in
        disconnect)
          nmcli device disconnect "$device" >/dev/null 2>&1 || true
          exit 0
          ;;
        rescan) rescan=yes ;;
        radio-off)
          nmcli radio wifi off
          exit 0
          ;;
        esac
      done
    '';
  };

  # The output and input pickers, behind the volume and microphone pills. Same shape as
  # lattice-wifi above and for the same reason: what a bar pill wants is the short list of
  # devices to switch between, and rofi is already themed, already the launcher, and lets
  # one be found by typing rather than hunted down a list.
  #
  # One script for both. The two menus differ only in which nodes they list and which pactl
  # verbs move them; the theme, the rendering and the loop are the same, and two copies of
  # that would drift.
  #
  # Picking a device moves what is already playing over with the default rather than only
  # redirecting the next stream to start -- `pactl set-default-sink` on its own leaves the
  # current song on the old speakers, which is not what picking speakers from a menu means.
  # That is the pairing `lattice-deck audio` already makes for the deck's round-robin key.
  audioMenu = pkgs.writeShellApplication {
    name = "lattice-audio";
    runtimeInputs = [
      rofiWithCalc
      # pactl, for the listing, the default and moving live streams. wpctl can set a
      # default but has no equivalent of move-sink-input, and `pactl -f json` is a document
      # to query rather than a table to scrape -- the same reason lattice-deck takes it.
      pkgs.pulseaudio
      pkgs.jq
      # swayosd-client for the mute row, so muting from the menu raises the same pill the
      # mute key does. Nothing here calls wpctl.
      pkgs.swayosd
      pkgs.libnotify
    ];
    text = ''
            case "''${1:-}" in
            output)
              noun=Output; nodes=sinks; streams=sink-inputs; get_default="get-default-sink"
              set_default="set-default-sink"; move="move-sink-input"
              osd=--output-volume; topic=mute; fallback=󰓃
              ;;
            input)
              noun=Input; nodes=sources; streams=source-outputs; get_default="get-default-source"
              set_default="set-default-source"; move="move-source-output"
              osd=--input-volume; topic=mic; fallback=󰍬
              ;;
            *)
              echo "usage: lattice-audio output|input" >&2
              exit 2
              ;;
            esac

            # Anchored and sized exactly like lattice-wifi's menu -- the long note on the theme
            # there says what each offset is counted from. It is not hung under the pill that
            # opened it for the reason that one isn't either: everything to the right of both is
            # variable width, so no fixed offset stays under them.
            #
            # Wider than that menu's 340px, because these labels are longer than an SSID:
            # "Built-in Audio Headset Microphone" is 33 characters, and a device list that
            # truncates the word saying which device it is has lost the plot. A glyph, a
            # 34-column description and a right-aligned reading come to 43 columns of JetBrains
            # Mono 10 -- ~345px, against the ~412px this leaves once config.rasi's 12px window
            # padding, its 2px border and the element padding above are taken off. 400px was not
            # enough and rofi answered by ellipsising the reading off the end of every row.
            theme='
              window { location: north east; anchor: north east; x-offset: -10px; y-offset: 5px; width: 460px; }
              * { font: "JetBrains Mono 10"; }
              inputbar { padding: 7px 10px; }
              element { padding: 5px 10px; }
              listview { lines: 12; }

              /* The device in use, marked with rofi -a, in the same green lattice-wifi gives the
                 network in use -- config.rasi draws an active row in lavender, which reads as a
                 shade of the ordinary text rather than as a state. */
              element normal.active, element alternate.active { text-color: @green; }
              element selected.active { background-color: @green; text-color: @crust; }
            '

            # One click accepts, as on every other bar surface; see lattice-wifi.
            click=(-me-select-entry "" -me-accept-entry MousePrimary)

            # -mesg is the one string rofi renders as pango markup, and a device description is
            # free text -- "Family & Friends Dock" would take the whole message down otherwise.
            pango() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g'; }

            # PipeWire names the hardware, not the shape of it, so the glyph is guessed from what
            # the device says about itself: device.icon_name first, since that is the field meant
            # for this, then the form factor, then the node name for what neither covers. Order
            # matters -- a Bluetooth headset is both, and the bus is the more useful of the two
            # to draw.
            #
            # Anything unrecognised keeps the per-menu fallback rather than drawing nothing:
            # speakers for an output, a microphone for an input. Also a guess, but the right one
            # more often than not, and a blank column would take the row out of line.
            glyph_for() {
              case "$1|$2|$3" in
              *bluez* | *luetooth*)   printf '󰂯' ;;
              *headset*)              printf '󰋎' ;;
              *headphone*)            printf '󰋋' ;;
              *hdmi* | *isplayport*)  printf '󰡁' ;;
              *speaker*)              printf '󰓃' ;;
              *)                      printf '%s' "$fallback" ;;
              esac
            }

            # A monitor is the loopback of a sink and is a source only as an accident of the
            # PulseAudio model: there is nothing to record from, and listing them would fill the
            # input menu with a second copy of the output one. device.class marks them, and the
            # name suffix is checked as well because a node that sets neither is still a monitor
            # if it is called one. Both are no-ops on the sink side, which has none.
            #
            # value_percent arrives as "100%" and the row builds its own reading, so it is
            # stripped to digits here and the parsing stays in one place. Channels can differ and
            # the first is taken -- a balance that is not centred is not what this menu is for.
            #
            # Every column is emitted non-empty, "-" standing in for a property the node does not
            # set. That is load-bearing rather than tidiness: the reader below splits on tab, tab
            # is IFS whitespace, and `read` collapses a run of IFS whitespace into one delimiter
            # -- so one empty field in the middle silently shifts every column after it left by
            # one. A device with no icon name read its form factor as its mute state, and every
            # output in the menu drew as muted. "-" matches none of the glyph patterns, so an
            # unknown lands on the fallback, which is where it belongs anyway.
            read_nodes() {
              pactl -f json list "$nodes" | jq -r --arg default "$default" '
                def dash: if (. // "") == "" then "-" else . end;

                # An ALSA jack is a node whether or not anything is in it, and its active port is
                # what says which. Listing the ones that are empty is worse than not listing them:
                # picking the headphone socket with nothing plugged into it sets the default,
                # WirePlumber sees an unavailable port and puts it straight back, and the menu
                # looks broken rather than honest. Ports that report "unknown" -- which is most
                # of them, and every USB device -- are kept; only an explicit no is a no.
                #
                # A node with no ports at all is kept too. The MacBook speakers are one: they are
                # a virtual node in front of the convolver, not a jack, so there is nothing to
                # ask. And the device in use is always listed whatever it claims, because a menu
                # that hides what you are listening through is not one worth opening.
                def available:
                  (.active_port // "") as $port
                  | .name == $default
                    or $port == ""
                    or (([.ports[]? | select(.name == $port) | .availability] | first) // "unknown")
                       != "not available";

                .[]
                | select((.properties["device.class"] // "") != "monitor")
                | select(.name | endswith(".monitor") | not)
                | select(available)
                | [ .name,
                    .description,
                    (.volume | to_entries | .[0].value.value_percent | gsub("[^0-9]"; "")),
                    (if .mute then "muted" else "live" end),
                    (.properties["device.icon_name"] | dash),
                    (.properties["device.form_factor"] | dash)
                  ] | @tsv'
            }

            while true; do
              default=$(pactl "$get_default" 2>/dev/null || true)

              names=(); rows=(); selected=(); mesg=""; default_muted=""; gone_desc=""
              while IFS=$'\t' read -r name desc vol muted icon ff; do
                [ -n "$name" ] || continue

                # The per-row reading is the level, or the muted glyph in its place -- a device
                # that is muted at 60% is muted, and the number would read as the live state.
                if [ "$muted" = muted ]; then reading=󰝟; else reading="$vol%"; fi

                if [ "$name" = "$default" ]; then
                  selected=(-a "''${#rows[@]}")
                  default_muted=$muted
                  # Kept for the note below, which has to name a device that no longer exists.
                  gone_desc=$desc
                  if [ "$muted" = muted ]; then
                    mesg="$(pango "$desc")  ·  muted at $vol%"
                  else
                    mesg="$(pango "$desc")  ·  $vol%"
                  fi
                fi

                names+=("$name")
                rows+=("$(printf '%s  %-34.34s %5s' "$(glyph_for "$icon" "$ff" "$name")" "$desc" "$reading")")
              done < <(read_nodes)

              if [ "''${#names[@]}" -eq 0 ]; then
                notify-send -a lattice-audio -i audio-card \
                  -h string:x-canonical-private-synchronous:lattice-audio \
                  "No $noun device" "PipeWire is reporting nothing to switch to"
                exit 0
              fi

              if [ "$default_muted" = muted ]; then action="󰕾  Unmute"; else action="󰝟  Mute"; fi

              # -a indexes the rendered list, so the mark moves down by the action row about to be
              # put above it.
              [ "''${#selected[@]}" -eq 2 ] && selected=(-a "$((selected[1] + 1))")

              # The cursor starts on the first device rather than on the action, the way
              # lattice-wifi starts below its own: Enter should act on a device, and mute is
              # reached by scrolling up or by typing it.
              choice=$(printf '%s\n' "$action" "''${rows[@]}" |
                rofi -dmenu -i -no-cycle -format i -p "$noun" -mesg "''${mesg:-no default device}" \
                  -theme-str "$theme" "''${click[@]}" "''${selected[@]}" -selected-row 1 || true)
              [ -n "''${choice:-}" ] || exit 0

              if [ "$choice" -eq 0 ]; then
                swayosd-client "$osd" mute-toggle
                # The deck's key draws this device's mute state and only knows what it is told.
                # `|| true` for the reason lattice-sunset gives: an unplugged deck, or a
                # lattice-deck that is not on this caller's PATH, must not fail a mute that has
                # already happened.
                lattice-deck sync "$topic" || true
                continue
              fi

              target=''${names[$((choice - 1))]}
              # Picking the device already in use should do nothing, rather than set a default it
              # already has and walk every live stream across to where it already is.
              [ "$target" = "$default" ] && exit 0

              pactl "$set_default" "$target"
              while read -r stream; do
                [ -n "$stream" ] || continue
                pactl "$move" "$stream" "$target" 2>/dev/null || true
              done < <(pactl list short "$streams" | cut -f1)

              # Moving a live stream off the MacBook's speakers takes the speakers away with it:
              # the ALSA node behind asahi-audio's convolver hangs up ("poll fd error/hangup
              # (card removed?)" in wireplumber's journal), the software-dsp filter in front of it
              # goes with it, and neither comes back until pipewire is restarted -- restarting
              # wireplumber alone is not enough, because the node that died belongs to the daemon.
              # Nothing here causes it: `lattice-deck audio` has always done the same two steps
              # and has always had the same effect. Setting the default alone does not do it, and
              # ordinary playback stopping does not either; it takes the unlink.
              #
              # swayosd is in the restart because it is collateral: swayosd-server resolves the
              # default sink once and holds it, so a pipewire that came back underneath it leaves
              # every --output-volume call a silent no-op until it is restarted too.
              #
              # So the menu says so rather than leaving someone to find the speakers missing from
              # it later and conclude the picker is broken. Only when it actually happens: the
              # node list is read back, and this is silent unless what was just switched away from
              # has genuinely gone. The second is for the teardown, which is not instant.
              #
              # The fix is a verb rather than the four-unit systemctl line it wraps, because the
              # Stream Deck's media page has a key for it and a banner that names the same command
              # the key runs is one thing to remember instead of two. See modules/nixos/
              # streamdeck.nix, which is also where the why is written down.
              sleep 1
              if [ -n "$default" ] && ! read_nodes | cut -f1 | grep -qxF "$default"; then
                notify-send -a lattice-audio -i audio-card \
                  -h string:x-canonical-private-synchronous:lattice-audio \
                  "$noun switched" \
                  "$gone_desc is gone from the list -- an Asahi quirk. \
      The deck's restart key, or <tt>lattice-deck audio-restart</tt>, brings it back."
              fi

              # The new device brings its own mute state with it, which is what the deck draws.
              lattice-deck sync "$topic" || true
              exit 0
            done
    '';
  };

  # The wallpaper picker, behind a right-click on the bar's wallpaper pill. Same shape as
  # the two menus above and for the same reason: `next` is a fine way to move one along --
  # it is all the Stream Deck's key does -- and a poor way to reach the ninth of fourteen.
  #
  # The rows are baked in here rather than read back out of `lattice-wallpaper list`,
  # because the one thing this menu has to show is the colour, and a colour never reaches
  # the CLI -- the pool's hexes are a build-time fact, one set per flavour, picked by the
  # same `case` lattice-wallpaper uses. Both sides come off `poolFor`, so
  # the list and the menu cannot disagree about what is in the pool or what it is called.
  #
  # The swatch is the wallpaper's own glyph in the wallpaper's own accent, which is what
  # makes this worth being a menu at all: the names are the palette's, and "sapphire"
  # against "sky" is a distinction the eye makes instantly in colour and slowly in words.
  # The glyph is md-wallpaper, the one the pill that opens this wears and the one on the
  # deck's key for `next` -- see ~/.dotfiles/waybar/config.jsonc and streamdeck.nix.
  wallpaperMenu = pkgs.writeShellApplication {
    name = "lattice-wallpaper-menu";
    runtimeInputs = [
      rofiWithCalc
      cycleWallpaper
    ];
    text = ''
      ${readFlavor}
      ${flavorCase (flavor: ''
        rows=(
          ${lib.concatMapStringsSep "\n  " (
            entry: "'<span color=\"${entry.accent}\">󰸉</span>  ${entry.label}'"
          ) (poolFor flavor)}
        )
      '')}

      # Anchored north *west*, unlike lattice-wifi and lattice-audio: this pill lives in the
      # left group, so the fixed edge to hang from is the other one. 10px is waybar's own
      # margin-left and lines the menu's left edge up with the bar's; y-offset is the 5px
      # gap between pills, counted from the bar's bottom edge because waybar's exclusive
      # zone is where a north anchor already starts. The long note in lattice-wifi has the
      # measurements. It is not hung under the pill itself for that menu's reason in
      # mirror image -- everything to this one's left is variable width, since the
      # workspace pills carry a glyph per open window and the privacy pill appears from
      # nothing when something starts capturing.
      #
      # 240px against that menu's 340: a swatch and a palette name is 12 columns, where an
      # SSID can be anything. lines is the whole pool, so the list never scrolls -- it is a
      # fixed set, not a listing of whatever happens to be in range -- and the pool's size
      # is the flavour's, so it is counted rather than written in.
      theme='
        window { location: north west; anchor: north west; x-offset: 10px; y-offset: 5px; width: 240px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { padding: 7px 10px; }
        element { padding: 5px 10px; }
        listview { lines: '"''${#rows[@]}"'; }

        /* The one already up, marked with rofi -a, in the same green lattice-wifi gives the
           network in use. It colours the name only -- the swatch carries its own colour in
           markup and keeps it -- which is what is wanted: the mark says "this one", the
           swatch says which one. */
        element normal.active, element alternate.active { text-color: @green; }
        element selected.active { background-color: @green; text-color: @crust; }
      '

      # One click accepts, as on every other bar surface; see lattice-wifi.
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      # -1 before the session's own pick has landed, which is a real state and not an error:
      # lattice-wallpaper-choose failed or has not run, so hyprpaper is up on whatever the
      # symlink last named. Nothing gets marked, rather than the first row on a guess.
      current=$(lattice-wallpaper current)
      selected=()
      ((current >= 0)) && selected=(-a "$current")

      # -markup-rows for the swatch. The rows are generated from the palette, so there is
      # no free text in them to escape.
      choice=$(printf '%s\n' "''${rows[@]}" |
        rofi -dmenu -i -no-cycle -markup-rows -format i -p Wallpaper \
          -theme-str "$theme" "''${click[@]}" "''${selected[@]}" || true)
      [ -n "''${choice:-}" ] || exit 0

      # Re-picking the one already up costs a redraw of two outputs and nothing else, so it
      # is left to fall through rather than special-cased into a no-op.
      lattice-wallpaper "$choice"
    '';
  };

  # The bar's clock and calendar, replacing waybar's built-in clock module, whose calendar
  # colours could only be literals in config.jsonc -- and waybar re-reads its config only on
  # a full reload, the one that was crashing it (see lattice-palette). These draw from the
  # run-time theme instead.
  #
  # `markup [offset]` is one month as Pango markup, the month `offset` away from this one:
  # a title, the weekday row and the grid, every line padded to the same 20 columns so a
  # centred box keeps the columns straight. Today is in the accent. Sunday first, as the
  # en_US locale and the old module had it.
  #
  # With no argument it is the calendar menu behind a click on the clock: the month as the
  # menu's message and three buttons under it, previous, today and next, each a rofi row
  # laid out as columns. A button reopens the menu on the new month -- rofi has no way to
  # rewrite its message in place -- and keeps that button selected, so paging is repeated
  # clicks on one spot. Anchored north, under the clock, for the reason lattice-wifi gives.
  calendar = pkgs.writeShellApplication {
    name = "lattice-calendar";
    runtimeInputs = [
      pkgs.coreutils
      rofiWithCalc
    ];
    text = ''
      ${readColours}

      month() {
        local offset=$1 first title start days today="" pad line d cell col
        first=$(date -d "$(date +%Y-%m-01) $offset month" +%F)
        title=$(date -d "$first" '+%B %Y')
        start=$(date -d "$first" +%w)
        days=$(date -d "$first +1 month -1 day" +%-d)
        if ((offset == 0)); then
          today=$(date +%-d)
        fi

        pad=$(((20 - ''${#title}) / 2))
        printf '%*s<span foreground="%s"><b>%s</b></span>%*s\n' "$pad" "" "''${c[text]}" "$title" \
          $((20 - pad - ''${#title})) ""
        printf '<span foreground="%s">Su Mo Tu We Th Fr Sa</span>\n' "''${c[subtext0]}"

        printf -v line '%*s' $((start * 3)) ""
        col=$start
        for ((d = 1; d <= days; d++)); do
          printf -v cell '%2d' "$d"
          if [[ $d == "$today" ]]; then
            line+="<span foreground=\"''${c[accent]}\"><b><u>$cell</u></b></span>"
          else
            line+="<span foreground=\"''${c[subtext1]}\">$cell</span>"
          fi
          col=$((col + 1))
          if ((col == 7)); then
            printf '%s\n' "$line"
            line="" col=0
          else
            line+=" "
          fi
        done
        if ((col > 0)); then
          printf '%s%*s\n' "$line" $(((7 - col) * 3 - 1)) ""
        fi
      }

      if [[ ''${1:-} == markup ]]; then
        month "''${2:-0}"
        exit 0
      fi

      theme='
        window { location: north; anchor: north; y-offset: 5px; width: 250px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { enabled: false; }
        message { padding: 8px 10px 4px; border: 0; }
        textbox { horizontal-align: 0.5; }
        listview { columns: 3; lines: 1; padding: 4px 6px 6px; }
        element { padding: 5px 0; }
        element-text { horizontal-align: 0.5; }
      '
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      offset=0
      selected=1
      while true; do
        choice=$(printf '%s\n' "󰅁" "Today" "󰅂" |
          rofi -dmenu -no-custom -format i -p Calendar -markup \
            -mesg "<tt>$(month "$offset")</tt>" -selected-row "$selected" \
            -theme-str "$theme" "''${click[@]}" || true)
        case "$choice" in
        0) offset=$((offset - 1)) ;;
        1) offset=0 ;;
        2) offset=$((offset + 1)) ;;
        *) exit 0 ;;
        esac
        selected=$choice
      done
    '';
  };

  # The clock pill: the time, and this month's calendar as its tooltip. A long-running exec
  # rather than an interval, so the minute turns over on the minute: it sleeps to the next
  # one, and a USR1 -- from lattice-palette when the theme changes -- cuts the sleep short
  # and redraws at once. Its pid is kept in XDG_RUNTIME_DIR for that.
  clock = pkgs.writeShellApplication {
    name = "lattice-clock";
    runtimeInputs = [
      pkgs.coreutils
      calendar
    ];
    text = ''
      pidfile="''${XDG_RUNTIME_DIR:-/tmp}/lattice-clock.pid"
      echo $$ >"$pidfile"
      trap ':' USR1

      while true; do
        # As one JSON string: newlines escaped, and the markup's double-quoted attributes
        # turned single so they do not end it.
        tip=$(lattice-calendar markup 0)
        tip=''${tip//$'\n'/\\n}
        tip=''${tip//\"/\'}
        printf '{"text": "%s", "tooltip": "<tt>%s</tt>"}\n' "$(date '+%a %b %d  %H:%M')" "$tip"

        sleep $((60 - 10#$(date +%S))) &
        sleeper=$!
        wait "$sleeper" || true
        kill "$sleeper" 2>/dev/null || true
      done
    '';
  };

  # The caps-lock pill, which is only on the bar while caps lock is: the Mac's keyboard has
  # an LED for it and the NuPhy does not. Read from the keyboards' LED nodes in sysfs, which
  # are world-readable, rather than waybar's keyboard-state module -- that one opens
  # /dev/input itself and so wants the input group, which is every keystroke on the seat
  # handed to anything running as this user. Hyprland drives every keyboard's LED from the
  # one shared lock state, so any of them being lit is the answer.
  #
  # sysfs attributes do not raise inotify events, so it polls; five reads of a few bytes a
  # second is nothing, and it only prints when the state flips. The glob is expanded on
  # every pass so a keyboard plugged in later is picked up. Empty text hides the pill.
  capsLock = pkgs.writeShellApplication {
    name = "lattice-capslock";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      last=
      while true; do
        state=off
        for led in /sys/class/leds/*::capslock/brightness; do
          [[ -r $led ]] || continue
          read -r v <"$led" || continue
          if [[ $v != 0 ]]; then
            state=on
            break
          fi
        done

        if [[ $state != "$last" ]]; then
          if [[ $state == on ]]; then
            printf '{"text": "󰘲 CAPS", "class": "on", "tooltip": "Caps lock is on"}\n'
          else
            printf '{"text": ""}\n'
          fi
          last=$state
        fi
        sleep 0.2
      done
    '';
  };

  # The battery pill, replacing waybar's built-in battery module. That module never reads
  # the kernel's `capacity` attribute: it works the percentage out itself from
  # energy_now / energy_full. On the Mac those disagree -- macsmc-battery's capacity is the
  # SMC's own state of charge, the number macOS shows, and it read 80% while the energy
  # ratio read 77% (47.2 / 61.4 Wh) -- and neither `bat` nor `weighted-average` changes
  # which one the module uses. upower reports `capacity`, and so do fastfetch, the
  # power-profile tooltip, lattice-battery-notify's ladder and the 80% charge cap, so the
  # bar was the one reading out of step with everything else.
  #
  # The battery is picked by role the way lattice-battery-notify picks it, so the mouse
  # and headphones are skipped. `upower --monitor` prints a line whenever any device
  # changes, which is the redraw trigger; the read timeout is a backstop for the minutes
  # where upower publishes nothing. Empty text hides the pill on a host with no battery.
  batteryPill = pkgs.writeShellApplication {
    name = "lattice-battery-pill";
    runtimeInputs = [
      pkgs.upower
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      device=""
      for candidate in $(upower -e | grep /battery_); do
        if upower -i "$candidate" | grep 'power supply: *yes' >/dev/null; then
          device=$candidate
          break
        fi
      done
      if [[ -z $device ]]; then
        printf '{"text": ""}\n'
        exec sleep infinity
      fi

      # The same ten glyphs, empty to full, that the built-in module's format-icons held.
      icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)

      render() {
        local info state level time icon class tooltip
        info=$(upower -i "$device")
        state=$(awk '/^ *state:/ { print $2; exit }' <<<"$info")
        level=$(awk '/^ *percentage:/ { gsub(/%/, "", $2); print int($2 + 0.5); exit }' <<<"$info")
        [[ -n $level ]] || return 0

        case $state in
        charging)
          icon=󰂄
          class='"charging"'
          time=$(awk -F'time to full: *' 'NF > 1 { print $2; exit }' <<<"$info")
          tooltip="Charging''${time:+, $time to full}"
          ;;
        discharging)
          icon=''${icons[level * 9 / 100]}
          class='"discharging"'
          time=$(awk -F'time to empty: *' 'NF > 1 { print $2; exit }' <<<"$info")
          tooltip="On battery''${time:+, $time left}"
          ;;
        fully-charged)
          icon=󰚥
          class='"plugged"'
          tooltip="Fully charged"
          ;;
        *)
          # pending-charge: on the charger but held, which on the Mac is the charge cap.
          icon=󰚥
          class='"plugged"'
          tooltip="Plugged in, not charging"
          ;;
        esac

        # The thresholds the built-in module's `states` had; the stylesheet only colours
        # them while not charging.
        if ((level <= 10)); then
          class+=', "critical"'
        elif ((level <= 25)); then
          class+=', "warning"'
        fi

        printf '{"text": "%s %s%%", "tooltip": "%s", "class": [%s]}\n' \
          "$icon" "$level" "$tooltip" "$class"
      }

      coproc MONITOR { upower --monitor; }
      # Its first line is a "Monitoring activity" banner, not a change.
      read -r -t 5 -u "''${MONITOR[0]:-}" _ || true
      while true; do
        render
        # A timeout is a status over 128. Anything else means upower --monitor has gone
        # away, and without the sleep the loop would spin.
        read -r -t 60 -u "''${MONITOR[0]:-}" _ || { (($? > 128)) || sleep 60; }
      done
    '';
  };

  # The flavour picker, behind a right-click on the bar's theme pill -- the wallpaper menu's
  # twin, and placed the same way for the same reasons; see there. A row is a strip of the
  # flavour's own colours, darkest surface to text and then two accents, because the
  # flavours differ mostly in how light their surfaces sit and that is quicker seen than
  # read. The strip's first block is that flavour's base against this flavour's, which is
  # the comparison that matters.
  themeMenu = pkgs.writeShellApplication {
    name = "lattice-theme-menu";
    runtimeInputs = [
      rofiWithCalc
      latticeTheme
    ];
    text = ''
      flavors=(${lib.escapeShellArgs flavorNames})
      rows=(
        ${lib.concatMapStringsSep "\n  " (
          name:
          let
            inherit (theme.flavors.${name}) label palette;
            block = c: "<span color=\"${palette.${c}}\">██</span>";
          in
          "'${
            lib.concatMapStrings block [
              "crust"
              "base"
              "surface1"
              "overlay1"
              "text"
              "mauve"
              "blue"
            ]
          }  ${label}'"
        ) flavorNames}
      )

      theme='
        window { location: north west; anchor: north west; x-offset: 10px; y-offset: 5px; width: 360px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { padding: 7px 10px; }
        element { padding: 5px 10px; }
        listview { lines: ${toString (lib.length flavorNames)}; }
        element normal.active, element alternate.active { text-color: @green; }
        element selected.active { background-color: @green; text-color: @crust; }
      '

      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      current=$(lattice-theme current)
      selected=()
      for i in "''${!flavors[@]}"; do
        if [[ ''${flavors[i]} == "$current" ]]; then
          selected=(-a "$i")
        fi
      done

      choice=$(printf '%s\n' "''${rows[@]}" |
        rofi -dmenu -i -no-cycle -markup-rows -format i -p Theme \
          -theme-str "$theme" "''${click[@]}" "''${selected[@]}" || true)
      [ -n "''${choice:-}" ] || exit 0

      lattice-theme "''${flavors[choice]}"
    '';
  };

  # Resuming needs somewhere to resume from, so a host without a resume device has no
  # business offering hibernation.
  canHibernate = config.boot.resumeDevice != "";

  powerButton = label: action: text: keybind: {
    inherit
      label
      action
      text
      keybind
      ;
  };
  lock = powerButton "lock" "pidof hyprlock || hyprlock" "󰌾  Lock" "l";
  logout = powerButton "logout" "hyprctl dispatch 'hl.dsp.exit()'" "󰗽  Log out" "e";
  suspend = powerButton "suspend" "systemctl suspend" "󰒲  Suspend" "u";
  reboot = powerButton "reboot" "systemctl reboot" "󰜉  Reboot" "r";
  hibernate = powerButton "hibernate" "systemctl hibernate" "󰋊  Hibernate" "h";
  shutdown = powerButton "shutdown" "systemctl poweroff" "󰐥  Shut down" "s";

  powerButtons =
    if canHibernate then
      [
        lock
        logout
        suspend
        reboot
        hibernate
        shutdown
      ]
    else
      [
        lock
        suspend
        logout
        reboot
        shutdown
      ];

  # Screenshots. HyprQuickFrame draws the selection overlay -- shader dimming, spring
  # animations on the selection, snap-to-window -- then hands the capture to satty for
  # annotation. It replaces the grim+slurp pair that used to be inlined here; grim is still
  # what actually takes the pixels, but HyprQuickFrame builds the geometry and the pipeline.
  #
  # Reachable two ways, because neither one covers both hosts on its own. Print is bound in
  # ~/.dotfiles/hypr/.config/hypr/hyprland.lua, and the key comes from the external keyboard
  # (NuPhy Halo65 V2), which is remapped in firmware and so emits a real KEY_SYSRQ wherever
  # it is plugged in. The Dell's built-in keyboard has a Print key too, but the Mac's
  # (hid-apple, 05AC:0352) lands on the magic_keyboard_2021_and_2024 fn table, which has no
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

  # Everything mako has already shown and timed out on, as a browsable list -- the whole of
  # what a "notification centre" would otherwise be a daemon for. Bound to SUPER+ALT+N; see
  # the mako binds in ~/.dotfiles/hypr/.config/hypr/hyprland.lua.
  #
  # jq, not a format string: `makoctl history` grew -f only after 1.11, which is what this
  # nixpkgs carries, so -j and a filter is the version-proof way to read it. The JSON is a
  # plain array of objects, newest first, with the fields below spelled exactly as mako
  # spells them (app_name, not app-name -- these are not the DBus hint names).
  notifyHistory = pkgs.writeShellApplication {
    name = "lattice-notifications";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      rofiWithCalc
      pkgs.wl-clipboard
      pkgs.libnotify
      pkgs.coreutils # cut
    ];
    text = ''
      # Captured once, and both passes read this copy. Reading it twice would race a
      # notification arriving mid-prompt, and the id picked from the first list would then
      # mean a different entry in the second.
      history="$(makoctl history -j)"

      # An empty prompt is indistinguishable from a bind that did nothing, and the answer
      # -- that nothing has arrived -- is worth saying out loud.
      if [ "$(printf '%s' "$history" | jq 'length')" -eq 0 ]; then
        notify-send -a lattice-notifications -u low \
          "No notification history" "Nothing has expired since mako started."
        exit 0
      fi

      # The id rides in a hidden first column, the way the cliphist bind does it, because
      # the summary alone is not unique -- a unit that fails twice has two identical lines.
      # Bodies are multi-line and rofi is not, so newlines collapse to spaces; @tsv would
      # escape them rather than break the row, but a literal \n mid-line reads badly.
      selection=$(
        printf '%s' "$history" \
          | jq -r '.[] | [
              (.id | tostring),
              ((.app_name // "?") + ": " + (.summary // "")
                + " | " + ((.body // "") | split("\n") | join(" ")))
            ] | @tsv' \
          | rofi -dmenu -i -p notifications -display-columns 2
      ) || exit 0
      [ -n "$selection" ] || exit 0
      # That `|| exit 0` is for rofi answering 1 on a dismissed prompt, which is a normal
      # outcome and must not take the script down under pipefail. It cannot tell a cancel
      # from rofi failing to reach the compositor at all, and deliberately: both end with
      # no selection and nothing to copy.

      # The body, not the summary. Going back to a notification that has already gone is
      # nearly always about something inside it -- a code, a path, a link -- and mako keeps
      # no action registry for an expired notification, so there is nothing to invoke.
      printf '%s' "$history" \
        | jq -r --argjson id "$(printf '%s' "$selection" | cut -f1)" \
            '.[] | select(.id == $id) | .body' \
        | wl-copy
    '';
  };

  # The SUPER + / cheatsheet: every bind that says what it does, in one rofi list. Nothing
  # is written down twice -- the rows come live from the configs themselves, Hyprland binds
  # with a description, tmux binds with a note and nvim maps with a desc, so a key goes on
  # the sheet by being described where it is bound, and a rebind can't leave it stale.
  # ~/.config/hypr/keys.tsv (the hypr stow package) adds what no config can report -- the
  # trackpad gesture, the mouse's Solaar rules -- and hides rows not worth the space.
  #
  # tmux and nvim come from PATH rather than runtimeInputs: tmux has to be the build the
  # server is running, and nvim has to be the one the config and its plugins were set up for.
  hyprKeys = pkgs.writeText "lattice-keys-hypr.jq" ''
    # hyprctl binds -j -> "<keys>\t<description>", for the described binds only. Binds that
    # share a description, modifiers and submap fold into one row ("SUPER + 0-9"), in the
    # order the config makes them.
    def mods:
      . as $m
      | [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
      | map(select(($m / .[0] | floor) % 2 == 1) | .[1]);
    def pretty:
      {
        left: "←", right: "→", up: "↑", down: "↓",
        mouse_down: "Scroll", mouse_up: "Scroll",
        "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB",
        slash: "/", escape: "Esc", return: "Enter", SPACE: "Space",
        XF86AudioRaiseVolume: "Vol+", XF86AudioLowerVolume: "Vol-",
        XF86AudioMute: "Mute", XF86AudioMicMute: "MicMute",
        XF86MonBrightnessUp: "Bright+", XF86MonBrightnessDown: "Bright-",
        XF86AudioPlay: "Play", XF86AudioPause: "Pause",
        XF86AudioNext: "Next", XF86AudioPrev: "Prev"
      }[.] // .;
    def keylist:
      if length == 10 and all(test("^[0-9]$")) then "0-9"
      elif (sort == ["down", "left", "right", "up"]) then "Arrows"
      else map(pretty) | reduce .[] as $k ([]; if index([$k]) then . else . + [$k] end) | join("/")
      end;

    reduce (.[] | select(.has_description)) as $b ({order: [], groups: {}};
      ([$b.submap, ($b.modmask | tostring), $b.description] | join("\u0001")) as $id
      | if .groups[$id] == null then
          .order += [$id]
          | .groups[$id] = {submap: $b.submap, modmask: $b.modmask, desc: $b.description, keys: [$b.key]}
        elif (.groups[$id].keys | index([$b.key])) then .
        else .groups[$id].keys += [$b.key]
        end)
    | .groups as $g
    | .order[]
    | $g[.]
    | ((.modmask | mods) + [.keys | keylist] | join(" + ")) as $keys
    | [(if .submap == "" then $keys else .submap + ": " + $keys end), .desc]
    | @tsv
  '';
  nvimKeys = pkgs.writeText "lattice-keys-nvim.lua" ''
    -- Every map the user's config describes, as "<keys>\t<description>" lines on stdout.
    -- LSP maps are buffer-local and only made on LspAttach, which a headless nvim with no
    -- server never sees, so it is fired by hand on the empty buffer first.
    pcall(vim.api.nvim_exec_autocmds, "LspAttach", { buffer = 0, data = {} })

    local leader = vim.g.mapleader or "\\"
    local modes = { n = "n", x = "v", o = "o", i = "i", t = "t", c = "c" }
    local order, rows = {}, {}

    local function add(map, mode)
      -- sid < 0 is nvim's own runtime: its default maps carry descs too, and are not ours.
      if not map.desc or map.desc == "" or map.sid < 0 then
        return
      end
      local lhs = map.lhs
      if lhs:sub(1, #leader) == leader then
        lhs = "<leader>" .. lhs:sub(#leader + 1)
      end
      lhs = lhs:gsub(" ", "<Space>")
      local id = lhs .. "\t" .. map.desc
      if not rows[id] then
        rows[id] = { lhs = lhs, desc = map.desc, modes = {} }
        table.insert(order, id)
      end
      if not vim.tbl_contains(rows[id].modes, mode) then
        table.insert(rows[id].modes, mode)
      end
    end

    for query, mode in pairs(modes) do
      for _, map in ipairs(vim.api.nvim_get_keymap(query)) do
        add(map, mode)
      end
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, query)) do
        add(map, mode)
      end
    end

    table.sort(order)
    for _, id in ipairs(order) do
      local row = rows[id]
      table.sort(row.modes)
      local desc = row.desc
      -- Normal mode goes without saying; anything else is spelled out.
      if not (#row.modes == 1 and row.modes[1] == "n") then
        desc = desc .. "  [" .. table.concat(row.modes, ",") .. "]"
      end
      io.stdout:write(row.lhs, "\t", desc, "\n")
    end
  '';
  keybindings = pkgs.writeShellApplication {
    name = "lattice-keys";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      rofiWithCalc
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    text = ''
      extras="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/keys.tsv"

      # What is in front of you decides which section leads: nvim if the tmux pane last typed
      # into is running it, tmux if a terminal has focus, the desktop otherwise. Everything is
      # still listed and searchable; this only saves scrolling past the rest.
      focus=hypr
      if [[ $(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""') == com.mitchellh.ghostty ]]; then
        focus=tmux
        pane=$(tmux list-clients -F '#{client_activity} #{pane_current_command}' 2>/dev/null \
          | sort -rn | head -n1 | cut -d' ' -f2-) || true
        [[ $pane == nvim ]] && focus=nvim
      fi
      case $focus in
        nvim) order=(nvim tmux hypr mouse) ;;
        tmux) order=(tmux nvim hypr mouse) ;;
        *) order=(hypr mouse tmux nvim) ;;
      esac

      live() {
        hyprctl binds -j | jq -r -f ${hyprKeys} | sed 's/^/hypr\t/'

        # Only binds the config itself notes: tmux notes every default too, so those are listed
        # by a throwaway server that has read no config and taken out. The prefix is set on it
        # first so its rows read the same as the live ones. No server, no tmux section --
        # starting one with the real config would set tmux-continuum restoring sessions.
        if prefix=$(tmux show -gv prefix 2>/dev/null); then
          tmux list-keys -N \
            | grep -vxFf <(tmux -L "lattice-keys-$$" -f /dev/null start-server \; \
                set -g prefix "$prefix" \; list-keys -N \; kill-server 2>/dev/null) \
            | sed -E 's/^([^ ]+ [^ ]+) +/tmux\t\1\t/' || true
        fi

        # The real config, headless, against an empty buffer. timeout so a plugin that wants
        # an answer at startup costs a missing section rather than a picker that never opens.
        if command -v nvim >/dev/null; then
          (cd "''${XDG_RUNTIME_DIR:-/tmp}" && timeout 5 nvim --headless \
            -c "luafile ${nvimKeys}" -c 'qa!' 2>/dev/null) | sed 's/^/nvim\t/' || true
        fi
      }

      # keys.tsv rows are added, and a "-" description takes the matching live row out. awk
      # reads the extras first so it knows what to drop by the time the live rows arrive. By
      # name rather than FNR == NR, which an empty or missing keys.tsv would turn true for both.
      rows=$(
        awk -F '\t' -v OFS='\t' -v order="''${order[*]}" '
          BEGIN { n = split(order, o, " "); for (i = 1; i <= n; i++) rank[o[i]] = i }
          FILENAME == ARGV[1] {
            if ($0 ~ /^#/ || NF < 3) next
            if ($3 == "-") hide[$1 FS $2] = 1
            else extra[++e] = $0
            next
          }
          !(($1 FS $2) in hide) && !seen[$0]++ { print rank[$1] + 0, ++i, $0 }
          END { for (j = 1; j <= e; j++) { split(extra[j], f, FS); print rank[f[1]] + 0, ++i, extra[j] } }
        ' <(cat "$extras" 2>/dev/null || true) <(live) \
          | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
      )

      # Read-only: picking a row does nothing, it is the search that is the point.
      # Padded into columns rather than rofi's -display-columns, which joins but never aligns.
      # The font is monospace (config.rasi), so spaces line up.
      printf '%s\n' "$rows" \
        | awk -F '\t' '
            { s[NR] = $1; k[NR] = $2; d[NR] = $3; if (length($2) > w) w = length($2) }
            END { for (i = 1; i <= NR; i++) printf "%-5s  %-*s  %s\n", s[i], w, k[i], d[i] }
          ' \
        | rofi -dmenu -i -no-custom -p "keys" \
            -theme-str 'window { width: 960px; } listview { lines: 14; }' \
        >/dev/null || true
    '';
  };

  # wlogout reads $XDG_CONFIG_HOME/wlogout/{layout,style.css} and then falls straight back
  # to its own store path -- it never consults XDG_CONFIG_DIRS, so the /etc/xdg drop-in
  # trick the other shell surfaces use doesn't reach it. The paths are passed explicitly
  # instead, which is why the menu is only ever opened through this wrapper.
  #
  # wlogout runs each action through `sh -c`, inheriting this script's environment, so
  # runtimeInputs is also what puts hyprctl within reach of the logout button when the
  # menu is launched from waybar's systemd unit (see waybar.path below).
  powerMenu = pkgs.writeShellApplication {
    name = "lattice-power";
    runtimeInputs = [
      pkgs.wlogout
      pkgs.hyprland
      config.programs.hyprlock.package
      pkgs.procps
      pkgs.systemd
      pkgs.jq # the focused screen's height, for the margin below
    ];
    text = ''
      # Clicking the bar pill a second time should close the menu, not stack another
      # copy of it behind the first.
      if pgrep -x wlogout >/dev/null; then
        pkill -x wlogout
        exit 0
      fi

      # How tall a button comes out, and the only lever there is for it. wlogout gives every
      # button vexpand, so a button is exactly its share of the grid's height -- no padding,
      # min-height or margin in style.css can make it shorter than that, they only ever raise
      # the floor. What the grid gets is the screen minus wlogout's own margin, so the margin
      # is the thing to set: take the height the buttons should have out of the middle of the
      # screen and give the rest away.
      #
      # It is measured rather than written down because one number is a different button on
      # every screen -- this menu is a single row of five here and two rows of three on a host
      # that hibernates, and the Mac's 840 logical rows are not the Dell's.
      #
      # The measurement is the *shortest* screen attached, not the focused one. wlogout draws
      # the grid on every output and has only one set of margins for all of them, so a margin
      # taken from a tall docked screen is more than a laptop panel has to give -- the band it
      # asks to keep clear is taller than the panel, and the menu lands off the bottom of it.
      # The shortest screen is the one that fits everywhere.
      rows=${toString (if canHibernate then 2 else 1)}
      height=140
      # The button's own margin in /etc/xdg/wlogout/style.css, which is outside the height
      # above -- so a change there wants the same change here.
      gap=14

      margin=()
      if screen=$(hyprctl monitors -j 2>/dev/null |
        jq -e -r '[.[] | .height / .scale] | min | floor'); then
        v=$(((screen - rows * (height + 2 * gap)) / 2))
        # A screen too short to seat the menu at that height keeps a thin band top and bottom
        # rather than a negative margin, and the buttons come out shorter than asked for.
        [ "$v" -lt 40 ] && v=40
        margin=(--margin-top "$v" --margin-bottom "$v")
      fi

      # No margin flags if the query failed, which leaves wlogout's own 230 on every side --
      # the full-height buttons this replaced, rather than no menu at all.
      exec wlogout \
        --layout /etc/xdg/wlogout/layout \
        --css /etc/xdg/wlogout/style.css \
        "''${margin[@]}" \
        --buttons-per-row ${toString (if canHibernate then 3 else lib.length powerButtons)}
    '';
  };

  # The reporter behind the OnFailure= lines on the session's own units. A unit that dies
  # is otherwise indistinguishable from a unit with nothing to say: lattice-battery-notify
  # failed on every boot for four days over one missing `awk`, and the only symptom was a
  # battery that never warned.
  notifyFailure = pkgs.writeShellApplication {
    name = "lattice-notify-failure";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.systemd
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      unit="$1"

      # Which manager owns the failing unit, because one reporter serves both. A session
      # unit's OnFailure= reaches this directly; a system unit's goes through the root
      # bridge in systemd.services below and arrives here as `system`. Only the flag
      # differs -- winston is in wheel, so the system manager and its journal are readable
      # from the session without privilege, and nothing has to be handed across.
      case "''${2:-user}" in
        user) manager=(--user) ;;
        system) manager=() ;;
        *)
          echo "usage: lattice-notify-failure <unit> [user|system]" >&2
          exit 1
          ;;
      esac

      # Two different answers, and the banner wants both. Result is systemd's own verdict
      # -- exit-code, start-limit-hit, timeout -- while the journal tail is where the
      # reason actually lives; the outage this was written for was one line of it.
      result="$(systemctl "''${manager[@]}" show -P Result -- "$unit" 2>/dev/null || true)"
      # `|| true` for grep exiting 1 on an empty capture, which pipefail would otherwise
      # turn into a failed reporter.
      log="$(journalctl "''${manager[@]}" --no-pager -o cat -n 5 -u "$unit" 2>/dev/null | grep -v '^$' || true)"

      body="''${result:-failed}"
      # An `if`, not `[ -n "$log" ] && body=...`: that list returns 1 when the tail is
      # empty and errexit takes the whole script down with it.
      if [ -n "$log" ]; then
        body="$(printf '%s\n\n%s' "$body" "$log")"
      fi

      # Onto the journal as well as the screen. If nothing owns org.freedesktop.Notifications
      # -- the one failure this cannot raise a banner for -- the attempt is still on record.
      printf '%s failed: %s\n' "$unit" "''${result:-unknown}"

      # Critical, so the default-timeout=0 in ~/.dotfiles/mako leaves it up until it is
      # dismissed: a unit breaking while nobody is looking is the case that must not time
      # out. Keyed synchronous per unit, so a unit that fails, gets fixed and fails again
      # replaces its own banner rather than stacking, while two units still get one each.
      notify-send -a lattice-systemd -u critical -i dialog-error \
        -h "string:x-canonical-private-synchronous:lattice-failure-''${2:-user}-$unit" \
        "$unit failed" "$body"
    '';
  };

  # Opens the NuPhy Halo65 V2's raw-HID node to whoever holds the seat, so the keyboard can
  # be remapped from nuphy.io in the Chromium below. The board is QMK underneath: its
  # interface 1 reports usage page 0xFF60, QMK's raw-HID endpoint and the transport both
  # NuPhy Console and VIA speak. That node is root-only by default, and the resulting
  # failure is badly disguised -- the WebHID chooser comes up empty and reads as "no
  # compatible devices found", which looks like the site not supporting the keyboard
  # rather than like a permission problem.
  #
  # This is a udev *package* rather than services.udev.extraRules, and that is the whole
  # point of it. uaccess is not applied by the rule that sets the tag; systemd's
  # 73-seat-late.rules is what turns TAG+="uaccess" into an ACL. extraRules is hardcoded
  # into 99-local.rules, which udev reaches long after 73, so the tag is set after the
  # only rule that would consume it and nothing happens -- silently, with the rule
  # present and correct in the file. Numbering this below 73 is what makes it fire, and
  # is why the MX Master's own rule ships at 42. udev.packages takes the filename from
  # the destination, so the 60- prefix here is load-bearing.
  #
  # pkgs.qmk-udev-rules is no substitute: all 89 of its lines are bootloader VID/PIDs for
  # flashing, and none touch hidraw on a running board.
  #
  # Scoped to the one product and to hidraw only. The evdev nodes stay shut -- remapping
  # happens in the keyboard's own firmware, so nothing here needs to read keystrokes.
  nuphyHidAccess = pkgs.writeTextFile {
    name = "nuphy-halo65-udev-rules";
    destination = "/lib/udev/rules.d/60-nuphy-halo65.rules";
    text = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="19f5", ATTRS{idProduct}=="3315", TAG+="uaccess"
    '';
  };

  # GTK is adw-gtk3 -- libadwaita's look, ported to GTK3 -- recoloured from the run-time
  # theme, so GTK apps follow lattice-theme and the wallpaper's accent like the rest of the
  # desktop. adw-gtk3 draws everything from libadwaita's named colours, and theme.gtk.css in
  # the runtime kit redefines those; this user theme is adw-gtk3-dark with that file
  # imported after it, where a second definition wins.
  #
  # It is installed under two names, lattice-a and lattice-b, both this one directory.
  # GTK3 reads a theme's CSS once, when the theme is set, so a running app only restyles
  # when the name changes -- lattice-palette flips between the two whenever theme.gtk.css
  # changes. libadwaita apps take no GTK theme at all; they read ~/.config/gtk-4.0/gtk.css,
  # which in ~/.dotfiles imports the same file, at launch.
  #
  # Cursors and folder icons stay Catppuccin's, built in the build-time flavour's nearest
  # one and blue: they are packaged per flavour and accent and cannot change at run time.
  catppuccinFlavor = theme.flavors.${theme.flavor}.catppuccin;
  gtkUserTheme =
    let
      adw = "${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark";
      css = file: ''
        @import url("file://${adw}/gtk-3.0/${file}");
        @import url("file://${currentDir}/theme.gtk.css");
      '';
    in
    pkgs.runCommand "lattice-gtk-theme" { } ''
      mkdir -p $out/gtk-3.0
      cp ${pkgs.writeText "gtk.css" (css "gtk.css")} $out/gtk-3.0/gtk.css
      cp ${pkgs.writeText "gtk-dark.css" (css "gtk-dark.css")} $out/gtk-3.0/gtk-dark.css
      printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=lattice\n\n[X-GNOME-Metatheme]\nGtkTheme=lattice\n' \
        > $out/index.theme
    '';
  gtkTheme = "lattice-a";
  iconTheme = "Papirus-Dark";
  cursorTheme = "catppuccin-${catppuccinFlavor}-dark-cursors";
  # 9pt (12px) keeps UI text close to Ghostty and waybar; qt6ct in ~/.dotfiles uses the same fonts.
  uiFont = "${theme.fonts.ui} ${toString theme.fonts.size}";
  monospaceFont = "${theme.fonts.monospace} ${toString theme.fonts.size}";

  gtkSettings = ''
    [Settings]
    gtk-theme-name=${gtkTheme}
    gtk-icon-theme-name=${iconTheme}
    gtk-cursor-theme-name=${cursorTheme}
    gtk-cursor-theme-size=16
    gtk-application-prefer-dark-theme=true
    gtk-font-name=${uiFont}
  '';

  # regular0-7 then bright0-7, read straight off the list ../theme.nix hands the kernel as
  # vt.default_red/grn/blu, so the greeter's sixteen colours and the console's are one
  # source. console.colors is already '#'-less, which is also foot's format.
  greeterAnsi = lib.concatStringsSep "\n" (
    lib.imap0 (
      i: colour: "${if i < 8 then "regular" else "bright"}${toString (lib.mod i 8)}=${colour}"
    ) config.console.colors
  );

  # The greeter's terminal. tuigreet is untouched by this -- same binary, same config, same
  # theme block below -- it just draws into foot under cage now rather than into fbcon on
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
    # as `eDP-1: 3024x1890+0x0@120Hz 14.03" scale=3, DPI=254.24/338.99 (physical/scaled)`;
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

    # tuigreet is themed by ANSI colour name, so this block is where those names get their
    # values: `blue` in its theme is the palette's blue, exactly as it was on the console,
    # which gets these same sixteen through vt.default_red/grn/blu.
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

      # -o rather than a second config file: everything else about the two cases is identical,
      # and a font line is the one thing that differs.
      exec foot \
        --config=/etc/greetd/foot.ini \
        --override="font=${theme.fonts.monospace}:size=$size" \
        tuigreet
    '';
  };
in
{
  # Everything below reads config.lattice.theme, so don't rely on branding.nix pulling it in.
  imports = [
    ../artwork.nix
    ../theme.nix
    ../plymouth.nix
    ../display.nix
    ../weather.nix
    ../streamdeck.nix
    ../webapps.nix
    ../widevine.nix
    ../phone.nix
    ../bitwarden.nix
  ];

  ### SESSION ###
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # GTK file-chooser portal; xdg-desktop-portal-hyprland doesn't implement it.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  ### APPS ###
  environment.systemPackages = with pkgs; [
    # 1.3.1's GTK build spends every touchpad sideways scroll on switching tabs and never
    # hands it to the terminal, so nvim's <ScrollWheelLeft/Right> never fire. Upstream's
    # gtk-horizontal-tab-scroll (ghostty-org/ghostty#12659, due in 1.4.0) forwards it
    # instead when set false, which ~/.config/ghostty-nixos/config does. Drop the patch
    # once nixpkgs ships 1.4.0.
    (ghostty.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/ghostty-horizontal-tab-scroll.patch ];
    }))
    rofiWithCalc
    # The same libqalculate engine at its other two surfaces: `qalc` in a terminal, and a
    # real window for the times a calculation is worth keeping on screen and editing --
    # qalculate-gtk carries the history, stored variables, user functions and the plot
    # button that a one-line launcher prompt has nowhere to put. It is GTK3, so the
    # run-time GTK theme (gtkUserTheme) dresses it; it lands in `rofi -show drun` as "Qalculate!".
    # libqalculate is free here (rofi-calc already put it in the closure) and qalculate-gtk
    # adds ~8 MiB on top of it.
    libqalculate
    qalculate-gtk
    # hyprsunset ships only as a systemd.packages unit above, so its CLI -- which is how
    # the running daemon is driven -- wasn't on PATH for lattice-sunset or a shell.
    hyprsunset
    # notify-send: without it every script that tries to raise a notification fails
    # silently, mako itself was fine all along.
    libnotify
    # The same story as hyprsunset above, and for the same reason: mako ships as a
    # systemd.packages unit, which installs the service and nothing else. makoctl is how a
    # running mako is driven -- every bind in hyprland.lua goes through it, and Hyprland
    # execs those with the session PATH, not a wrapper's runtimeInputs.
    mako
    brightnessctl
    playerctl
    wl-clipboard
    cliphist
    grim
    satty
    swayosd
    xdg-user-dirs

    mpv
    imv
    xarchiver
    hunspellDicts.en_US
    drawio
    telegram-desktop
    zathura
    bitwarden-desktop
    wf-recorder

    # Not a browser: Firefox keeps http/https under DEFAULT APPS below, and nothing here
    # changes that. This is on the machine for WebHID (navigator.hid) alone, which is the
    # only way to reach the NuPhy Halo65 V2's QMK raw-HID interface from this host. The
    # native clients cannot: pkgs.via and pkgs.vial are both x86_64-only AppImages in
    # nixpkgs, so on aarch64 the configurator is nuphy.io (or usevia.app) in a Chromium
    # tab. Firefox is not an option either -- Mozilla lists WebHID as harmful and ships no
    # implementation -- which is the whole reason a second browser exists here.
    #
    # Ungoogled rather than pkgs.chromium, and it costs nothing to prefer: both are cached
    # for aarch64 at ~200 MiB, and NIXOS_OZONE_WL below already makes either a native
    # Wayland client. The keyboard's hidraw node still needs the udev rule below before
    # the page can open the device.
    ungoogled-chromium

    # Everything below was once picked per host, because the obvious client is x86-only
    # in nixpkgs and the Mac needed a stand-in. Running the stand-in on both is simpler
    # than keeping two app sets: each is cross-arch, cached for aarch64, and close
    # enough to what it replaces that having one of them in muscle memory is worth more
    # than the nicer x86 build.
    #
    # Vesktop, for Discord: an Electron shell around the web client, so it is the same
    # app the official build wraps, plus Vencord and working Wayland screen share.
    #
    # cryptomator-cli, for Cryptomator: same vaults, same format -- `cryptomator-cli
    # unlock` mounts one over FUSE and it is a normal directory from there. The GUI is
    # x86-only because nixpkgs pins `platforms = [ "x86_64-linux" ]`; that looks like an
    # untested restriction rather than a real one (zulu25 has an aarch64 JDK with
    # JavaFX, and the derivation evaluates fine on aarch64 with the meta relaxed), so an
    # overlay is the way back to the GUI on both if the CLI ever grates.
    #
    # Popsicle, for Impression: Impression is not merely unbuilt on ARM, it depends on
    # syslinux, which is genuinely x86-only, so this one has no way back.
    vesktop
    cryptomator-cli
    popsicle

    # Tor Browser used to sit here, on the Dell alone. It is dropped rather than gated:
    # the Tor Project ships no ARM Linux build (only tor-browser-linux-x86_64), and
    # Mullvad Browser is x86-only for the same reason, so there is nothing to make the
    # two hosts agree on. `nix run nixpkgs#tor-browser` on the Dell for the rare need.

    adw-gtk3
    (catppuccin-papirus-folders.override {
      flavor = catppuccinFlavor;
      inherit (theme) accent;
    })
    catppuccin-cursors."${catppuccinFlavor}Dark"

    cycleWallpaper
    wallpaperMenu
    latticePalette
    latticeTheme
    themeMenu
    sunset
    idleInhibit
    tailscale
    powerProfile
    wifiMenu
    audioMenu
    powerMenu
    notifyHistory
    keybindings
    dnd
    screenshot
    screenshotItem
    # The drawing tool itself, for trying a density or a phase before wiring it in.
    config.lattice.artwork.draw
  ];

  programs = {
    # No nativeMessagingHosts: firefoxpwa was the one entry here, and its host is only
    # reachable by the PWAsForFirefox extension, which isn't installed. Web apps are
    # Firefox's own Taskbar Tabs instead -- see modules/nixos/webapps.nix for why.
    firefox.enable = true;
    # Microsoft Graph accounts, hidden behind these prefs as of 156. The CU Microsoft 365
    # tenant 403s every EWS request ("EWS is blocked by policy") since Exchange Online's
    # EWS retirement began on 2026-10-01, so that mailbox is a Graph account now. Both
    # prefixes pass the policy allowlist, so they ride the module rather than the Mac's
    # user.js.
    thunderbird = {
      enable = true;
      preferences = {
        "mail.graph.enabled" = true;
        "calendar.graph.enabled" = true;
      };
    };
    thunar = {
      enable = true;
      plugins = [
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
      ];
    };
    waybar.enable = true;

    # Logitech HID++ control, for the MX Master 3. Its sensor ships at 4000 DPI, which is
    # what makes the pointer read as fast however far down Hyprland's per-device
    # `sensitivity` goes -- libinput can only discard motion counts after the fact, so it
    # buys slowness at the cost of precision. `solaar config <device> dpi <n>` moves it at
    # the source instead, which is why the device block in ~/.dotfiles/hypr/.config/hypr/
    # hyprland.lua now sits at sensitivity 0 with accel_profile flat: DPI is the only
    # speed knob, and pointer travel is proportional to hand travel so it means one thing.
    #
    # DPI is volatile: the mouse forgets it whenever it power-cycles or the Bluetooth link
    # drops, which on the Dell includes every hibernate -- see the btintel_pcie unload
    # in hosts/dell. The CLI alone would hold only until the next reconnect; the
    # user service is what makes it stick, reapplying ~/.config/solaar/config.yaml each
    # time the device comes back. It runs with no window and no tray icon at all -- see
    # the note on the package override below.
    #
    # That config.yaml is a symlink into the dotfiles repo (the solaar stow package), so
    # the DPI is shared rather than re-set per machine. Solaar rewrites it with a plain
    # open(path, "w"), which writes through the symlink instead of replacing it.
    #
    # enable also turns on hardware.logitech.wireless, which is what installs the udev
    # rules that let a non-root user talk to the device at all.
    #
    # The buttons are mapped in ~/.config/solaar/rules.yaml, the other half of the same
    # stow package: config.yaml diverts Back, Forward, Smart Shift and the gesture button
    # away from their built-in meanings, and rules.yaml says what they do instead (volume
    # on back/forward, the launcher on Smart Shift, and Hyprland navigation on the gesture
    # button). Rules are read once at start-up, so editing that file means
    # `systemctl --user restart solaar`.
    #
    # Most of those rules run commands rather than synthesising keystrokes. Execute needs
    # no privilege, and the uwsm-populated user environment already carries
    # HYPRLAND_INSTANCE_SIGNATURE into the service, which is what makes hyprctl work from
    # there. Its PATH does not carry /run/current-system/sw/bin, though, so the rules name
    # every binary absolutely.
    #
    # The exception is the gesture button, which holds SUPER down for as long as it is
    # held. That one needs KeyPress, which writes to /dev/uinput -- hence the
    # hardware.uinput block below. It buys the thing Solaar cannot do on its own: its
    # mouse-gesture mode only reports the direction once the button is released (the
    # notification is pushed from release_action, with no mid-gesture hook), so a gesture
    # can move one workspace per press and no more. Held as a modifier instead, the button
    # feeds the SUPER+scroll and SUPER+drag binds already in hyprland.lua, and workspaces
    # cycle continuously under the wheel. The cost is that a button is diverted as Mouse
    # Gestures or as a plain key, never both, so the four directional gestures are gone.
    #
    # The tray icon is built out rather than hidden. Solaar draws the mouse's battery
    # level into it, which put a second battery readout on the bar next to blueman's
    # bluetooth icon -- both live in waybar's one `tray` pill, and waybar's tray has no
    # per-item filter to drop one of them with. Solaar's own `--window only` switches the
    # icon off but also makes closing the window quit the process, which is the one thing
    # this service must not do: it is what reapplies the DPI and serves rules.yaml.
    #
    # So the indicator is removed at the source. Solaar asks gobject-introspection for
    # AyatanaAppIndicator3, then AppIndicator3, and falls back to Gtk.StatusIcon when
    # neither typelib is on GI_TYPELIB_PATH -- and GtkStatusIcon is X11 XEmbed, so under
    # Wayland it registers nothing. Dropping libappindicator from buildInputs is what
    # takes the typelib out of the wrapper; the fallback is upstream's own code path, and
    # it costs five Gtk-CRITICAL lines in the journal at start-up and nothing after.
    #
    # The window is still reachable -- solaar.desktop is still installed, and Solaar is a
    # single-instance GApplication, so launching it again pops the running process's
    # window rather than starting a second one.
    solaar = {
      enable = true;
      userService.enable = true;
      package = pkgs.solaar.overrideAttrs (old: {
        buildInputs = lib.filter (p: p != pkgs.libappindicator) old.buildInputs;
      });
    };

    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  services = {
    gvfs.enable = true;
    tumbler.enable = true;
    blueman.enable = config.hardware.bluetooth.enable;
    flatpak.enable = true;

    # swayosd writes backlight brightness through sysfs, which its udev rule opens to the video group.
    #
    # nuphyHidAccess opens the Halo65 V2's raw-HID node so the configurator can reach it;
    # see the note on the package itself for why it is a package here and not extraRules.
    udev.packages = [
      pkgs.swayosd
      nuphyHidAccess
    ];
  };
  # /dev/uinput, for the Solaar rule that holds SUPER while the mouse's gesture button is
  # down. The NixOS module loads the module, makes the group and writes the udev rule; the
  # group membership is what the solaar user service actually needs. Supplementary groups
  # are fixed when the session starts, so this only reaches a running Solaar after a
  # re-login -- until then KeyPress fails silently, which is its only failure mode.
  hardware.uinput.enable = true;

  users.users.winston.extraGroups = [
    "video"
    "uinput"
  ];

  ### AUDIO ###
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;

      # Every bluez5 codec nixpkgs ships (AAC, aptX, LDAC, LC3, Opus, mSBC) is already built in
      # and enabled by default, and bluetooth.profile-preference is already "quality", so codec
      # selection needs no help. Autoswitching does.
      #
      # With it on, anything that opens a capture stream -- a browser tab checking for a mic,
      # a meeting joining -- drags headphones from A2DP down to HFP, which is 8kHz mono, and
      # music sounds broken until they are power-cycled. Off means the headset mic is no longer
      # offered automatically; the laptop's own mic gets used instead, which is the better
      # trade here. Switch profiles by hand in blueman on the rare call that needs the headset.
      extraConfig."51-bluetooth-no-autoswitch" = {
        "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
  };

  ### SECRETS ###
  services.gnome = {
    gnome-keyring.enable = true;
    # SSH keys stay with programs.ssh.startAgent.
    gcr-ssh-agent.enable = false;
  };
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Run Electron apps natively on Wayland so they aren't blurry under fractional scaling.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  ### SESSION SERVICES ###
  systemd.packages = with pkgs; [
    hyprpaper
    mako
    hyprpolkitagent
    hyprsunset
  ];

  systemd.user.services = {
    # The OnFailure= target for the session's own units, so a unit that gives up says so
    # on screen instead of in the journal nobody reads. %i is the failing unit's full
    # name, handed over by `OnFailure=lattice-notify-failure@%n.service` at each use site.
    #
    # It fires once per failure, not once per restart attempt: OnFailure= triggers on
    # entry to the failed state, and an automatic restart is not that -- a unit with
    # Restart=on-failure reports when it exhausts its start limit and gives up, not five
    # times on the way there.
    #
    # Nothing sets OnFailure= on this unit, deliberately. A reporter that cannot report
    # has nothing left to report with, and a self-reference would only spin.
    "lattice-notify-failure@" = {
      description = "Report %i as a desktop notification";

      # The banner needs something to receive it, and mako is Type=dbus on
      # org.freedesktop.Notifications -- so ordering after it already means the name is
      # owned, with nothing to poll for. Wants and not Requires: when mako itself is the
      # broken thing, this should still run and leave its line in the journal. The only
      # place that names the daemon, so a swap away from mako would edit here.
      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i";
      };
    };

    # Where the system half lands. The bridge in systemd.services below starts this, and the
    # only difference from the template above is the scope the reporter is told to look in:
    # a system unit's Result and journal tail live in the system manager, and asking the
    # user manager for them yields an empty banner that says nothing but "failed".
    "lattice-notify-failure-system@" = {
      description = "Report system unit %i as a desktop notification";

      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i system";
      };
    };

    hyprpaper.wantedBy = [ "graphical-session.target" ];
    mako.wantedBy = [ "graphical-session.target" ];
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

    # One wallpaper out of the pool per login, in two halves. This one settles it before
    # anything draws: hyprpaper.conf names the symlink it writes, and the bar, mako and
    # swayosd read the accent files it writes, so all of them start on the session's pick.
    # It needs nothing running -- no IPC, only files -- so ordering it ahead of them is
    # all there is to it. No After= on the target, for the reason the next unit gives.
    lattice-wallpaper-choose = {
      description = "Choose this session's wallpaper and accent";

      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      before = [
        "hyprpaper.service"
        "waybar.service"
        "mako.service"
        "swayosd.service"
      ];
      onFailure = [ "lattice-notify-failure@%n.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cycleWallpaper} --choose random";
      };
    };

    # And this one hands it to hyprpaper per output, which only IPC can do: hyprpaper.conf
    # has one path for every screen, and the panel wants its own size of the same drawing.
    #
    # It hangs off hyprpaper rather than off graphical-session.target, which is not a
    # stylistic choice: hyprpaper's own unit is `After=graphical-session.target`, so a unit
    # that the target wants *and* that waits for hyprpaper closes a loop -- the target waits
    # for the pick, the pick waits for hyprpaper, hyprpaper waits for the target. systemd
    # spots that at activation and breaks it by deleting a job from the cycle, which is a
    # warning in the journal and a wallpaper that never changes, not a failure anyone is
    # told about. Being wanted by hyprpaper instead says the same thing -- apply once the
    # wallpaper daemon is up -- with no edge back to the target. It also means a hyprpaper
    # that died and restarted gets the session's pick back at the right size per screen.
    #
    # There is no Restart= here on purpose. hyprpaper is Type=simple, so ordering after it
    # only means its process has been forked and its IPC socket may not be bound yet -- but
    # riding that out with a restart makes systemd enter the failed state first, and
    # OnFailure= fires on entry, not on giving up, so every login would raise a banner that
    # the retry then quietly disproved. The waiting belongs in the command instead, which is
    # where it is; reaching this unit's OnFailure= now means hyprpaper never arrived at all.
    lattice-wallpaper-pick = {
      description = "Pick this session's wallpaper";

      after = [ "hyprpaper.service" ];
      wantedBy = [ "hyprpaper.service" ];
      # Stop-propagation only -- PartOf implies no ordering, so it adds no edge back to the
      # target. It is here so a pick still retrying cannot outlive the session it is for.
      partOf = [ "graphical-session.target" ];
      onFailure = [ "lattice-notify-failure@%n.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cycleWallpaper} apply";
      };
    };

    # systemd user services get a bare default PATH -- coreutils, findutils, grep, sed,
    # systemd -- and notably *not* /run/current-system/sw/bin. Waybar runs its module
    # commands through `sh -c` with that environment, so anything they call has to be
    # named here or it fails with "command not found" and the module silently renders
    # empty. Keep this in step with the on-click/on-scroll/exec commands in
    # ~/.dotfiles/waybar/config.jsonc.
    #
    # That reaches one step further than the commands themselves. The scripts below are
    # writeShellApplications, so each prepends its own runtimeInputs and finds its own
    # tools regardless of this list -- but a tool that in turn execs something by *name*
    # is back to this PATH. xdg-open is the one that does: it resolves
    # x-scheme-handler/https to firefox.desktop from the assignment further down and then
    # runs `firefox`, so without the browser here lattice-tailscale's sign-in click and
    # its right-click to the admin console both resolved a URL and then opened nothing.
    # xdg-open does say so -- it walks its whole fallback list of browser names, reports
    # "no method available", and exits 3 -- but both call it with output on /dev/null
    # (they must: it is detached), so the complaint went nowhere and the pill just sat
    # there.
    waybar.path = [
      sunset
      dnd
      idleInhibit
      tailscale
      weather
      # Both ends of the power-profile pill: waybar runs `status` on the interval and
      # `cycle` on a click, and the script's own runtimeInputs cover everything it calls
      # except lattice-deck, which streamdeck.nix puts on this same PATH.
      powerProfile
      wifiMenu
      audioMenu
      powerMenu
      # Both of the wallpaper pill's buttons: left click runs `lattice-wallpaper next`
      # straight, right click opens the menu, which in turn calls it by name again.
      cycleWallpaper
      wallpaperMenu
      # And the theme pill's, the same pair one level up.
      latticeTheme
      themeMenu
      # The clock, and the calendar menu a click on it opens.
      clock
      calendar
      # The caps-lock pill's exec.
      capsLock
      # The battery pill's.
      batteryPill
      pkgs.wireplumber
      config.programs.firefox.finalPackage
    ];

    swayosd = {
      description = "Volume and brightness OSD";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
      };
    };

    cliphist = {
      description = "Clipboard history";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
      };
    };

    # Starting with the session rather than at login gives tmux panes WAYLAND_DISPLAY, so GTK apps
    # launched from them don't fall back to XWayland and get upscaled blurry. Replaces continuum's boot unit.
    tmux = {
      description = "tmux default session (detached)";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # Inherit the session PATH instead of NixOS's minimal one; plugins and panes need the full system.
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.tmux}/bin/tmux new-session -d";
        ExecStop = [
          "%h/.local/share/tmux/plugins/tmux-resurrect/scripts/save.sh"
          "${pkgs.tmux}/bin/tmux kill-server"
        ];
      };
    };

    # Collabora Office replaces LibreOffice: the same engine under Collabora Online's
    # interface, which nixpkgs only packages as the server. Flathub builds the desktop app
    # for both arches, so it lands as a per-user Flatpak at session start -- installed when
    # missing and never updated here, so a login doesn't turn into a 400 MiB download;
    # `flatpak update` is the upgrade.
    #
    # Its Qt UI comes out a size too big on both screens; QT_SCALE_FACTOR multiplies each
    # output's own scale, so one factor shrinks it on the 2.25x panel and the 1.5x Samsung
    # alike. Re-applied every run so the value here stays the source of truth.
    lattice-flatpaks = {
      description = "Install lattice's Flatpak apps";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      # Fails when the session starts offline; say so rather than leave Collabora quietly
      # missing from rofi.
      onFailure = [ "lattice-notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "lattice-flatpaks";
            runtimeInputs = [ config.services.flatpak.package ];
            text = ''
              app=com.collaboraoffice.Office
              flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
              flatpak info --user "$app" >/dev/null 2>&1 \
                || flatpak install --user --noninteractive flathub "$app"
              flatpak override --user --env=QT_SCALE_FACTOR=0.8 "$app"
            '';
          }
        );
      };
    };
  };

  # The same reporter, reached from the system manager. A unit's OnFailure= resolves in the
  # manager that owns it, so `lattice-notify-failure@%n.service` spelled in a host file's
  # systemd.services lands here rather than on the user template above -- one spelling for
  # both scopes, and a unit that moves between them needs no edit at its use site.
  #
  # `--machine=winston@.host` is the whole of it: root opens the user manager's own bus by
  # name and starts the unit there, so neither a uid nor a DBUS_SESSION_BUS_ADDRESS has to
  # be reconstructed the way the Mac's sleep guard still does for its own banner. Reaching
  # the session becomes the reporter's problem instead of the failing unit's.
  #
  # With nobody logged in there is no bus to open and this fails, leaving only its journal
  # line -- the same outcome as a banner with no one in front of it. So a boot-time oneshot
  # gets less out of this than it looks: the case it does cover is that unit failing during
  # a `nixos-rebuild switch`, where a session is up by definition.
  #
  # No OnFailure= of its own, for the same reason the user template has none.
  systemd.services."lattice-notify-failure@" = {
    description = "Report system unit %i as a desktop notification";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user --machine=winston@.host start lattice-notify-failure-system@%i.service";
    };
  };

  ### DEFAULT APPS ###
  #
  # Only the exact type is ever consulted. xdg-open's open_generic asks `xdg-mime query
  # default` for the detected type and does not walk the subclass chain, so a type absent
  # here does not fall back to its parent -- it falls off the end of the script into the
  # hardcoded browser list, which is why an unassigned .md, .py or .json opened as a
  # Firefox tab rather than failing. Silent and wrong, so anything worth opening needs its
  # own line.
  #
  # What is left out is decided by mimeinfo.cache order, which is arbitrary and moves when
  # a package does. So the rule for being on this list is: either two installed apps claim
  # the type, or nothing claimed it at all.
  xdg.mime.defaultApplications =
    let
      assign = app: types: lib.genAttrs types (_: app);
    in
    assign "firefox.desktop" [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      # Both of these resolved to ungoogled-chromium, which is on the machine for the
      # Halo65's WebHID configurator alone -- see the note on the package above. Firefox
      # renders XML and XHTML perfectly well, and nothing should reach the other browser
      # by accident.
      "application/xml"
      "application/xhtml+xml"
    ]
    // assign "thunderbird.desktop" [
      "x-scheme-handler/mailto"
      "x-scheme-handler/mid"
      "message/rfc822"
      "text/calendar"
      # Thunderbird registers these itself, by writing a userapp-Thunderbird-*.desktop
      # into ~/.local/share/applications and pointing ~/.config/mimeapps.list at it. That
      # is also how it broke them: three of those generated files are gone and the entries
      # naming them are still there, so webcal had no working handler at all. A system
      # assignment to the real thunderbird.desktop is the stable spelling -- but the user
      # list still outranks /etc/xdg, so these only take effect once its stale entries are
      # cleared.
      "x-scheme-handler/webcal"
      "x-scheme-handler/webcals"
      # What Firefox hands off when a calendar invite is downloaded rather than followed as
      # a link, so it needs naming separately from text/calendar above.
      "application/x-extension-ics"
    ]
    # Also claimed by org.pwmt.zathura-cb.desktop, which declares inode/directory,
    # application/zip, x-tar and x-7z-compressed on its way to the comic formats. Pinning
    # the file manager and the archiver is what keeps a folder or a .zip from opening in a
    # comic reader.
    // assign "thunar.desktop" [ "inode/directory" ]
    // assign "org.pwmt.zathura.desktop" [ "application/pdf" ]
    # The Flatpak's export, installed by lattice-flatpaks. CSV is left out on purpose: it is
    # as often something to read in a terminal as a spreadsheet.
    // assign "com.collaboraoffice.Office.desktop" [
      "application/vnd.oasis.opendocument.text"
      "application/vnd.oasis.opendocument.spreadsheet"
      "application/vnd.oasis.opendocument.presentation"
      "application/vnd.oasis.opendocument.graphics"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "application/msword"
      "application/vnd.ms-excel"
      "application/vnd.ms-powerpoint"
      "application/rtf"
      "text/rtf"
    ]
    # .cbz is detected as application/vnd.comicbook+zip; zathura-cb only declares the
    # older application/x-cbz, so every real comic went to xarchiver instead -- the reader
    # was installed and unreachable.
    // assign "org.pwmt.zathura-cb.desktop" [
      "application/vnd.comicbook+zip"
      "application/x-cbz"
    ]
    # imv.desktop and imv-dir.desktop declare an identical MimeType list, and imv-dir
    # opens the whole containing directory as a playlist. Whichever of the two the cache
    # happens to return first is not a choice, so every type imv declares and we care
    # about is named here. image/x-icon deliberately is not: imv has no .ico loader, and
    # an assignment to an app that cannot open the file is worse than none.
    // assign "imv.desktop" [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/avif"
      "image/bmp"
      "image/tiff"
      "image/svg+xml"
      "image/heif"
      "image/jxl"
    ]
    # The editor for everything that is text and had no handler. vim, gvim and neovim all
    # ship entries claiming text/plain as well, and gvim -- X11 only, so XWayland and
    # blurry -- was the one winning application/x-shellscript. The two Terminal=true
    # entries among them could not have worked from xdg-open anyway: nothing here provides
    # a terminal for them to open in.
    // assign "dev.zed.Zed.desktop" [
      "text/plain"
      "text/markdown"
      "application/json"
      "text/x-python"
      "text/x-nix"
      "application/x-shellscript"
      "text/x-shellscript"
    ]
    // assign "mpv.desktop" [
      "video/mp4"
      "video/webm"
      "video/x-matroska"
      "video/quicktime"
      "video/x-msvideo"
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/wav"
      "audio/mp4"
      "audio/aac"
      "audio/x-m4a"
      "audio/opus"
    ]
    # The compound types are the ones a .tar.gz or .tar.zst actually detects as -- the
    # plain application/gzip below only matches a bare .gz. They already resolved here,
    # but by cache order rather than by decision.
    // assign "xarchiver.desktop" [
      "application/zip"
      "application/x-tar"
      "application/gzip"
      "application/x-xz"
      "application/zstd"
      "application/x-7z-compressed"
      "application/vnd.rar"
      "application/x-compressed-tar"
      "application/x-xz-compressed-tar"
      "application/x-bzip-compressed-tar"
      "application/x-zstd-compressed-tar"
      "application/x-bzip2"
    ];

  ### THEME ###
  # The palettes in /etc/xdg layer lattice-palette's files over their own; see there.
  lattice.theme.runtimeTheme = currentDir;
  lattice.theme.runtimeState = themeState;
  lattice.theme.extraKitFiles."theme.hqf.toml" = hqfThemeText;

  xdg.icons.fallbackCursorThemes = [ cursorTheme ];

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = gtkTheme;
        icon-theme = iconTheme;
        cursor-theme = cursorTheme;
        cursor-size = lib.gvariant.mkInt32 16;
        font-name = uiFont;
        monospace-font-name = monospaceFont;
      };
    }
  ];

  # Qt apps (hyprpolkitagent) take their palette and fonts from qt6ct, configured in ~/.dotfiles.
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      jetbrains-mono
      nerd-fonts.symbols-only
      # Microsoft core fonts (Times New Roman, Arial, Courier New, ...) so documents render as their authors saw them.
      corefonts
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans" ];
      monospace = [ "JetBrains Mono" ];
    };
  };

  environment.etc."xdg/gtk-3.0/settings.ini".text = gtkSettings;
  environment.etc."xdg/gtk-4.0/settings.ini".text = gtkSettings;

  ### WALLPAPER ###
  # The desk-sized copy of the session's pick, which lattice-wallpaper-choose has written
  # before hyprpaper starts; the panel gets its own size a moment later over IPC.
  environment.etc."xdg/hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${currentDesk}
      fit_mode = cover
    }

    splash = false
  '';

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

    # tuigreet takes ANSI colour names, not hex, so the accent maps to its nearest name. What
    # those names resolve to is foot's [colors-dark] block above, which is ../theme.nix's
    # palette -- so `blue` is the palette's blue rather than a terminal's idea of blue, and a
    # re-accent carries through here without touching this block.
    theme = {
      container = "black";
      border = theme.accentAnsi;
      title = theme.accentAnsi;
      greet = "white";
      time = "white";
      text = "gray";
      prompt = theme.accentAnsi;
      input = "gray";
      action = theme.accentAnsi;
      button = "magenta";
    };
  };

  ### POWER MENU ###
  # Replaces the rofi -dmenu confirmation the logout bind used to shell out to, which is
  # gone from ~/.dotfiles/hypr/hyprland.lua entirely -- CTRL + SUPER + Q opens this instead.
  # Lock runs hyprlock directly, matching the SUPER + L bind rather than going through
  # `loginctl lock-session`, which does nothing if hypridle isn't there to answer it. The
  # layout is a sequence of bare JSON objects, not an array -- that is the format
  # wlogout's parser wants. `label` is also the CSS id of the button it makes.
  #
  # Icons are Nerd Font glyphs in the label rather than wlogout's shipped PNGs, which
  # are a fixed white and would stay that colour through a re-accent. They have to sit
  # on one line with the word: wlogout's JSON reader doesn't decode escapes, so a "\n"
  # in `text` reaches the button as a literal backslash-n.
  #
  # wlogout fills its grid *down the columns*, so with --buttons-per-row 3 the order of
  # powerButtons lays out as
  #     Lock      Suspend   Hibernate
  #     Log out   Reboot    Shut down
  # which puts the three that end the session along the bottom row. A host that can't
  # hibernate gets one row of five instead: wlogout reads a button for every cell of its
  # grid, so five buttons in a three-wide grid would run off the end of the list.
  environment.etc."xdg/wlogout/layout".text = lib.concatMapStrings (button: ''
    {
      "label": "${button.label}",
      "action": "${button.action}",
      "text": "${button.text}",
      "keybind": "${button.keybind}"
    }
  '') powerButtons;

  # GTK CSS, like waybar's and swayosd's, but written here rather than imported from
  # ~/.dotfiles: wlogout is Wayland-only, so there is no macOS half to keep in step.
  # The pill treatment carries over -- translucent @base, @surface0 border -- scaled up,
  # over a scrim that dims the desktop behind it. Every colour comes in through the bar's
  # palette by name rather than as a literal, so the menu follows lattice-palette's flavour
  # and accent like the bar does.
  environment.etc."xdg/wlogout/style.css".text = ''
    @import url("file:///etc/xdg/waybar/lattice.css");

    * {
      background-image: none;
      box-shadow: none;
      font-family: "${theme.fonts.monospace}", "Symbols Nerd Font";
      font-size: 17px;
    }

    window {
      background-color: alpha(@crust, 0.72);
    }

    button {
      color: @text;
      background-color: alpha(@base, ${toString theme.opacity});
      border: 2px solid @surface0;
      border-radius: 14px;
      /* Outside the height lattice-power sizes the grid to -- keep `gap` there in step. */
      margin: 14px;
      padding: 28px;
      outline-style: none;
      /* GTK animates between the two states, so hover and focus fade rather than snap. */
      transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease;
    }

    button:focus,
    button:hover {
      color: @accent;
      background-color: alpha(@surface0, ${toString theme.opacity});
      border-color: @accent;
    }

    /* The two that can't be taken back warn in their own colour on the way past. */
    #reboot:focus,
    #reboot:hover {
      color: @peach;
      border-color: @peach;
    }

    #shutdown:focus,
    #shutdown:hover {
      color: @red;
      border-color: @red;
    }
  '';

  ### IDLE/LOCK ###
  programs.hyprlock.enable = true;

  # `C` copies only when the target is absent, so this seeds the theme files on a fresh home
  # and then never touches them again -- every later write is lattice-palette's.
  #
  # Per-user rather than systemd.user.tmpfiles.rules: those go to every user manager, and
  # the greeter's starts one too, failing on winston's home at every boot.
  systemd.user.tmpfiles.users.winston.rules = [
    "d ${currentDir} 0755 - - -"
  ]
  # `L` without `+` for the same reason as `C`: only on a home that has never picked, so
  # hyprpaper.conf names something even before the first lattice-wallpaper-choose.
  ++ [
    "L ${currentDesk} - - - - ${wallpaper}"
    "L ${currentPanel} - - - - ${lib.head panelWallpapers.${theme.flavor}}"
  ]
  ++ map (file: "C ${currentDir}/${file} 0644 - - - ${themeSeed}/${file}") theme.runtimeFiles
  # The screenshot overlay's theme, at the first path HyprQuickFrame looks; see hqfThemeText.
  ++ [
    "d ${config.users.users.winston.home}/.config/hyprquickframe 0755 - - -"
    "L+ ${config.users.users.winston.home}/.config/hyprquickframe/theme.toml - - - - ${currentDir}/theme.hqf.toml"
  ]
  # The GTK user theme under both of its names; see gtkUserTheme. `L+` so each boot points
  # them at this build's copy.
  ++
    map
      (name: "L+ ${config.users.users.winston.home}/.local/share/themes/${name} - - - - ${gtkUserTheme}")
      [
        "lattice-a"
        "lattice-b"
      ]
  # What the accent-only writer, lattice-accent, left behind; theme.* replaced all of it.
  ++ map (file: "r ${currentDir}/${file}") [
    "accent.css"
    "accent.rasi"
    "accent.mako"
    "accent.lua"
    "lock-accent.conf"
  ];

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
