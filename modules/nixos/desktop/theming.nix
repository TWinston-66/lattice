{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.lattice.user.name;

  inherit (import ./lib.nix { inherit config lib pkgs; })
    theme
    palette
    flavorNames
    poolFor
    panelWallpapers
    deskWallpapers
    flavorCase
    themeState
    readFlavor
    wallpaper
    currentDir
    currentPanel
    currentDesk
    rofiWithCalc
    ;

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
  # same; Hyprland's borders through theme.lua, which hyprland.lua (./configs) loads
  # after its own default so a `hyprctl reload` keeps the pick; the lock screen through
  # theme.hyprlock; tmux, foot and nvim through theme.tmux, theme.foot and
  # theme-nvim.lua. The files themselves are lattice.theme.runtimeKits, one directory per
  # flavour with the accent left as tokens; this fills those in and puts each file in place.
  #
  # Telling each one is the other half, and it is per program, and only for a file that
  # actually changed -- a wallpaper step changes the accent and nothing in foot, and
  # re-sourcing tmux.conf for nothing costs a status-bar redraw (tmux does take the accent,
  # for its active pane border). waybar watches
  # theme.css itself (reload_style_on_change in waybar.nix): that
  # restyles the bar in place, where the SIGUSR2 it used to get rebuilt every bar surface,
  # ate the next click on the wallpaper pill and aborted waybar outright on a few picks in
  # quick succession. nvim watches theme-nvim.lua the same way. mako has `makoctl reload`;
  # swayosd has no reload at all, so it is restarted; Hyprland takes the same Lua the file
  # holds, through `hyprctl eval` -- `keyword` refuses a Lua config. tmux re-sources its
  # whole config, because catppuccin/tmux expands its colours into the status formats as it
  # loads. foot cannot reload its config at all, so its open windows are sent the colours
  # as escape codes, the way a program inside one would set them; a new window reads the
  # file. rofi,
  # wlogout and hyprlock read theirs at every launch. Every one is allowed to miss: a
  # program that is not up yet will read the file when it starts.
  #
  # The GTK theme, cursors, folder icons, Stream Deck keys, screenshot overlay, console and
  # boot splash stay on the build-time flavour and accent: all of them are drawn or packaged
  # per palette, and none can be told at run time. The greeter follows a boot late, from a
  # copy made below.
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
      pkgs.procps
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

      # starship has no include, so its config is ~/.config/starship.toml, or lattice's
      # (configs/starship.toml) when there is none, with the palette line pointed at the
      # kit's [palettes.lattice] and that table appended; /etc/zshrc points STARSHIP_CONFIG
      # here. Rebuilt on every write, so an edit to the file lands at the next wallpaper
      # pick, theme switch or login. The build's seed has no home and gets lattice's.
      starship=$HOME/.config/starship.toml
      [[ -r $starship ]] || starship=${./configs/starship.toml}
      {
        sed 's/^palette = .*/palette = "lattice"/' "$starship"
        cat "$dir/starship-palette.toml"
      } >"$dir/.starship.toml.tmp"
      place starship.toml

      # The greeter's copy, for the next boot's login screen (see greeterThemeDir in
      # greeter.nix). Before the reload check, because the login pick is --write-only and is
      # exactly the write the greeter should remember. The build's seed has no such directory
      # and skips it.
      greeter=/var/lib/lattice/greeter
      if [[ -w $greeter ]]; then
        for file in theme.foot theme.greeter.toml; do
          cp "$dir/$file" "$greeter/.$file.tmp" && mv -f "$greeter/.$file.tmp" "$greeter/$file" || true
        done
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
        tmux source-file /etc/tmux.conf \; source-file -q "$HOME/.config/tmux/tmux.conf" >/dev/null 2>&1 || true
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
      # Every line of theme.foot as its OSC, written to each foot window's pty: the one every
      # child of foot -- the shell, or the tmux client it went on to run -- has as stdin.
      # Writing there is output, so it goes to foot and never to the program reading it.
      if [[ $changed == *" theme.foot "* ]]; then
        e=$'\e'
        osc=""
        while IFS='=' read -r key value; do
          value=''${value##* }
          rgb="rgb:''${value:0:2}/''${value:2:2}/''${value:4:2}"
          case $key in
            foreground) osc+="$e]10;$rgb$e\\" ;;
            background) osc+="$e]11;$rgb$e\\" ;;
            cursor) osc+="$e]12;$rgb$e\\" ;;
            selection-background) osc+="$e]17;$rgb$e\\" ;;
            selection-foreground) osc+="$e]19;$rgb$e\\" ;;
            regular[0-7]) osc+="$e]4;''${key#regular};$rgb$e\\" ;;
            bright[0-7]) osc+="$e]4;$((''${key#bright} + 8));$rgb$e\\" ;;
          esac
        done <"$dir/theme.foot"
        while read -r pid; do
          for task in /proc/"$pid"/task/*/children; do
            kids=()
            read -ra kids 2>/dev/null <"$task" || true
            for kid in "''${kids[@]}"; do
              pty=$(readlink /proc/"$kid"/fd/0 2>/dev/null) || continue
              if [[ $pty == /dev/pts/* ]]; then
                printf '%s' "$osc" 2>/dev/null >"$pty" || true
              fi
            done
          done
        done < <(pgrep -x -u "$(id -u)" foot || true)
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

  # Switching between them, for a bind in hyprland.lua and for the login pick below.
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
        echo "usage: lattice wallpaper [next|prev|random|apply|list|current|<index>]" >&2
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
          echo "usage: lattice theme [next|prev|list|current|${lib.concatStringsSep "|" flavorNames}]" >&2
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
  # deck's key for `next` -- see the pill below and streamdeck.nix.
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
  # which configs.nix links to a file importing the same CSS, at launch.
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

  # 9pt (12px) keeps UI text close to foot and waybar; qt6ct.conf in ./configs uses the same fonts.
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
in
{
  # The wallpaper. An action rather than a toggle -- the pool has fourteen members and none
  # of them is an "on" -- so there is no state to read back and the pill is a static format
  # with click handlers. Left click is `next`, exactly what the deck's paper key runs; right
  # click opens lattice-wallpaper-menu, a rofi list of the pool by accent name with a swatch
  # per row and the one already up marked. Middle click re-rolls -- `random` skips whatever
  # is up, so a re-roll always lands somewhere new.
  #
  # And the flavour, its other half: that one moves the accent, this one the whole palette
  # under it -- bar, borders, menus, lock screen, terminal, tmux and nvim. Left click steps
  # to the next flavour, right click opens lattice-theme-menu, a strip of each flavour's
  # colours. Both keep the wallpaper that is up and redraw it in the new flavour.
  lattice.bar.modules = {
    "custom/wallpaper" = {
      section = "group/toggles";
      order = 40;
      settings = {
        format = "󰸉";
        tooltip = true;
        tooltip-format = "Wallpaper";
        on-click = "lattice-wallpaper next";
        on-click-right = "lattice-wallpaper-menu";
        on-click-middle = "lattice-wallpaper random";
      };
    };
    "custom/theme" = {
      section = "group/toggles";
      order = 50;
      settings = {
        format = "󰏘";
        tooltip = true;
        tooltip-format = "Theme";
        on-click = "lattice-theme next";
        on-click-right = "lattice-theme-menu";
      };
    };
  };

  environment.systemPackages = with pkgs; [
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
    # The drawing tool itself, for trying a density or a phase before wiring it in.
    config.lattice.artwork.draw
  ];

  systemd.user.services.waybar.path = [
    # Both of the wallpaper pill's buttons: left click runs `lattice-wallpaper next`
    # straight, right click opens the menu, which in turn calls it by name again.
    cycleWallpaper
    wallpaperMenu
    # And the theme pill's, the same pair one level up.
    latticeTheme
    themeMenu
  ];

  systemd.user.services = {
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
  };

  ### THEME ###
  # The palettes in /etc/xdg layer lattice-palette's files over their own; see there.
  lattice.theme.runtimeTheme = currentDir;
  lattice.theme.runtimeState = themeState;

  xdg.icons.fallbackCursorThemes = [ cursorTheme ];

  # Hyprland's own cursor and its children's. XCURSOR for X11 and toolkit apps, HYPRCURSOR
  # for the compositor; the Catppuccin package carries both formats.
  lattice.hyprland.extraConfig = lib.mkBefore ''
    hl.env("XCURSOR_THEME", "${cursorTheme}")
    hl.env("XCURSOR_SIZE", "16")
    hl.env("HYPRCURSOR_THEME", "${cursorTheme}")
    hl.env("HYPRCURSOR_SIZE", "16")
  '';

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

  # Qt apps (hyprpolkitagent) take their palette and fonts from qt6ct, configured in ./configs.
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
      # foot's font. The tmux bar's rounded pills are Nerd Font powerline caps, and foot draws
      # them at the size of whichever font holds them: from symbols-only they come out
      # shorter than the row, where Ghostty stretched them to the cell itself. The patched
      # JetBrains Mono carries them sized to its own line height.
      nerd-fonts.jetbrains-mono
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

  # `C` copies only when the target is absent, so this seeds the theme files on a fresh home
  # and then never touches them again -- every later write is lattice-palette's.
  #
  # Per-user rather than systemd.user.tmpfiles.rules: those go to every user manager, and
  # the greeter's starts one too, failing on winston's home at every boot.
  systemd.user.tmpfiles.users.${user}.rules = [
    "d ${currentDir} 0755 - - -"
  ]
  # `L` without `+` for the same reason as `C`: only on a home that has never picked, so
  # hyprpaper.conf names something even before the first lattice-wallpaper-choose.
  ++ [
    "L ${currentDesk} - - - - ${wallpaper}"
    "L ${currentPanel} - - - - ${lib.head panelWallpapers.${theme.flavor}}"
  ]
  ++ map (file: "C ${currentDir}/${file} 0644 - - - ${themeSeed}/${file}") theme.runtimeFiles
  # The GTK user theme under both of its names; see gtkUserTheme. `L+` so each boot points
  # them at this build's copy.
  ++
    map
      (name: "L+ ${config.users.users.${user}.home}/.local/share/themes/${name} - - - - ${gtkUserTheme}")
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

  lattice.cli.commands = {
    theme = {
      exec = lib.getExe latticeTheme;
      args = "[next|prev|list|current|<flavour>]";
      complete = [
        "next"
        "prev"
        "list"
        "current"
      ]
      ++ flavorNames;
      summary = "Switch the flavour at run time; next by default";
      group = "look";
      launch = [
        {
          label = "Next theme";
          args = "next";
          icon = "preferences-desktop-theme";
        }
      ];
    };
    "theme menu" = {
      exec = lib.getExe themeMenu;
      summary = "Pick a flavour from a menu";
      group = "look";
      launch = [
        {
          label = "Theme…";
          icon = "preferences-desktop-theme";
        }
      ];
    };
    wallpaper = {
      exec = lib.getExe cycleWallpaper;
      args = "[next|prev|random|apply|list|current|<index>]";
      summary = "Step through the wallpaper pool; next by default";
      group = "look";
      launch = [
        {
          label = "Next wallpaper";
          args = "next";
          icon = "preferences-desktop-wallpaper";
        }
        {
          label = "Random wallpaper";
          args = "random";
          icon = "preferences-desktop-wallpaper";
        }
      ];
    };
    "wallpaper menu" = {
      exec = lib.getExe wallpaperMenu;
      summary = "Pick a wallpaper from a menu";
      group = "look";
      launch = [
        {
          label = "Wallpaper…";
          icon = "preferences-desktop-wallpaper";
        }
      ];
    };
    art = {
      exec = lib.getExe config.lattice.artwork.draw;
      args = "<wallpaper|mark|widget|key> [options]";
      summary = "Draw lattice artwork as SVG, with the live palette";
      details = "Each kind takes --help for its own knobs.";
      group = "look";
    };
    palette = {
      exec = lib.getExe latticePalette;
      args = "[--write-only <dir>] <flavour> <#accent> <#accentAlt>";
      summary = "Write the run-time theme files and tell every app";
      group = "look";
      hidden = true;
    };
  };
}
