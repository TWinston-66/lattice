{
  config,
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

  # The same drawing at three zoom levels: the mark stays the anchor, the grid around it
  # gets finer or coarser. The first is the one hyprpaper starts on and hyprlock dims.
  wallpapers = map (density: config.lattice.artwork.wallpaper { inherit density; }) [
    "1.0"
    "0.7"
    "1.4"
  ];
  wallpaper = lib.head wallpapers;

  # Switching between them, for a bind in ~/.dotfiles. hyprpaper 0.8 loads an image when it
  # is asked for -- `preload` is gone -- so the variants only have to exist in the store.
  # hyprpaper can also rotate a directory by itself, with `timeout` and `order` in the
  # wallpaper block below; this stays manual so the desktop only changes when asked.
  cycleWallpaper = pkgs.writeShellApplication {
    name = "lattice-wallpaper";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      wallpapers=(${lib.concatStringsSep " " wallpapers})
      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-wallpaper"
      index=$(cat "$state" 2>/dev/null || echo 0)
      count=''${#wallpapers[@]}

      case "''${1:-next}" in
      next) index=$(((index + 1) % count)) ;;
      prev) index=$(((index - 1 + count) % count)) ;;
      list)
        printf '%s\n' "''${wallpapers[@]}"
        exit 0
        ;;
      *[!0-9]*)
        echo "usage: lattice-wallpaper [next|prev|list|<index>]" >&2
        exit 2
        ;;
      *) index=$(($1 % count)) ;;
      esac

      hyprctl hyprpaper wallpaper ",''${wallpapers[index]}"
      echo "$index" >"$state"
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
  sunset = pkgs.writeShellApplication {
    name = "lattice-sunset";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.procps
    ];
    text = ''
      warm=4000
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
        local backend
        backend="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "NoState"' 2>/dev/null || echo NoState)"

        if [ "$backend" = Running ]; then
          tailscale down
        else
          # `tailscale up` blocks while it waits for a browser sign-in, so it is detached;
          # when already authenticated it returns at once and the signal lands immediately.
          tailscale up >/dev/null 2>&1 &
          disown || true
        fi

        # RTMIN+2 matches the "signal" of custom/tailscale in ~/.dotfiles/waybar.
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
    ];
    text = ''
      # Clicking the bar pill a second time should close the menu, not stack another
      # copy of it behind the first.
      if pgrep -x wlogout >/dev/null; then
        pkill -x wlogout
        exit 0
      fi

      exec wlogout \
        --layout /etc/xdg/wlogout/layout \
        --css /etc/xdg/wlogout/style.css \
        --buttons-per-row 3
    '';
  };

  # Catppuccin, matching ~/.dotfiles. Theme names follow lattice.theme.
  gtkTheme = "catppuccin-${theme.flavor}-${theme.accent}-standard";
  iconTheme = "Papirus-Dark";
  cursorTheme = "catppuccin-${theme.flavor}-dark-cursors";
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
in
{
  # Everything below reads config.lattice.theme, so don't rely on branding.nix pulling it in.
  imports = [
    ../artwork.nix
    ../theme.nix
    ../plymouth.nix
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
    ghostty
    rofi
    # hyprsunset ships only as a systemd.packages unit above, so its CLI -- which is how
    # the running daemon is driven -- wasn't on PATH for lattice-sunset or a shell.
    hyprsunset
    # notify-send: without it every script that tries to raise a notification fails
    # silently, mako itself was fine all along.
    libnotify
    brightnessctl
    playerctl
    wl-clipboard
    cliphist
    grim
    slurp
    satty
    swayosd
    xdg-user-dirs

    mpv
    imv
    xarchiver
    libreoffice-qt
    hunspellDicts.en_US
    hyphenDicts.en_US
    drawio
    telegram-desktop
    discord
    tor-browser
    cryptomator
    zathura
    impression
    firefoxpwa
    bitwarden-desktop
    wf-recorder

    (catppuccin-gtk.override {
      variant = theme.flavor;
      accents = [ theme.accent ];
    })
    (catppuccin-papirus-folders.override {
      inherit (theme) flavor accent;
    })
    catppuccin-cursors."${theme.flavor}Dark"

    cycleWallpaper
    sunset
    tailscale
    powerMenu
    # The drawing tool itself, for trying a density or a phase before wiring it in.
    config.lattice.artwork.draw
  ];

  programs = {
    firefox = {
      enable = true;
      nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
    };
    thunderbird.enable = true;
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
    # buys slowness at the cost of precision. `solaar config <device> dpi 1000` moves it
    # at the source instead, and the sensitivity in ~/.dotfiles/hypr/hyprland.lua can go
    # back toward 0.
    #
    # DPI is volatile: the mouse forgets it whenever it power-cycles or the Bluetooth link
    # drops, which on this laptop includes every hibernate -- see the btintel_pcie unload
    # in the laptop profile. The CLI alone would hold only until the next reconnect; the
    # user service is what makes it stick, reapplying ~/.config/solaar/config.yaml each
    # time the device comes back. It starts hidden, to the waybar tray.
    #
    # enable also turns on hardware.logitech.wireless, which is what installs the udev
    # rules that let a non-root user talk to the device at all.
    solaar = {
      enable = true;
      userService.enable = true;
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
    udev.packages = [ pkgs.swayosd ];
  };
  users.users.winston.extraGroups = [ "video" ];

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
  # LibreOffice picks its GTK3 backend outside KDE, which can't do fractional scaling and oversizes its icons.
  environment.sessionVariables.SAL_USE_VCLPLUGIN = "qt6";
  # LibreOffice finds spelling/hyphenation dictionaries under share/{hunspell,hyphen} in the system profile.
  environment.pathsToLink = [ "/share/hyphen" ];

  ### SESSION SERVICES ###
  systemd.packages = with pkgs; [
    hyprpaper
    mako
    hyprpolkitagent
    hyprsunset
  ];

  systemd.user.services = {
    hyprpaper.wantedBy = [ "graphical-session.target" ];
    mako.wantedBy = [ "graphical-session.target" ];
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

    # systemd user services get a bare default PATH -- coreutils, findutils, grep, sed,
    # systemd -- and notably *not* /run/current-system/sw/bin. Waybar runs its module
    # commands through `sh -c` with that environment, so anything they call has to be
    # named here or it fails with "command not found" and the module silently renders
    # empty. Keep this in step with the on-click/on-scroll/exec commands in
    # ~/.dotfiles/waybar/config.jsonc.
    waybar.path = [
      sunset
      tailscale
      powerMenu
      pkgs.wireplumber
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
  };

  ### DEFAULT APPS ###
  xdg.mime.defaultApplications =
    let
      assign = app: types: lib.genAttrs types (_: app);
    in
    assign "firefox.desktop" [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ]
    // assign "thunderbird.desktop" [ "x-scheme-handler/mailto" ]
    // assign "thunar.desktop" [ "inode/directory" ]
    // assign "org.pwmt.zathura.desktop" [ "application/pdf" ]
    // assign "imv.desktop" [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/avif"
      "image/bmp"
      "image/tiff"
    ]
    // assign "mpv.desktop" [
      "video/mp4"
      "video/webm"
      "video/x-matroska"
      "video/quicktime"
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/wav"
    ]
    // assign "xarchiver.desktop" [
      "application/zip"
      "application/x-tar"
      "application/gzip"
      "application/x-xz"
      "application/zstd"
      "application/x-7z-compressed"
      "application/vnd.rar"
    ];

  ### THEME ###
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

  # Qt apps (hyprpolkitagent, LibreOffice) take their palette and fonts from qt6ct, configured in ~/.dotfiles.
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
  environment.etc."xdg/hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${wallpaper}
      fit_mode = cover
    }

    splash = false
  '';

  ### LOGIN ###
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet";
  };

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

    # tuigreet takes ANSI colour names, not hex, so the accent maps to its nearest name.
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
  # gone from ~/.dotfiles/hypr/hyprland.lua entirely -- CTRL + ALT + Q opens this instead.
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
  # The order below is not the reading order. wlogout fills its grid *down the columns*,
  # so with --buttons-per-row 3 this lays out as
  #     Lock      Suspend   Hibernate
  #     Log out   Reboot    Shut down
  # which puts the three that end the session along the bottom row.
  environment.etc."xdg/wlogout/layout".text = ''
    {
      "label": "lock",
      "action": "pidof hyprlock || hyprlock",
      "text": "󰌾  Lock",
      "keybind": "l"
    }
    {
      "label": "logout",
      "action": "hyprctl dispatch 'hl.dsp.exit()'",
      "text": "󰗽  Log out",
      "keybind": "e"
    }
    {
      "label": "suspend",
      "action": "systemctl suspend",
      "text": "󰒲  Suspend",
      "keybind": "u"
    }
    {
      "label": "reboot",
      "action": "systemctl reboot",
      "text": "󰜉  Reboot",
      "keybind": "r"
    }
    {
      "label": "hibernate",
      "action": "systemctl hibernate",
      "text": "󰋊  Hibernate",
      "keybind": "h"
    }
    {
      "label": "shutdown",
      "action": "systemctl poweroff",
      "text": "󰐥  Shut down",
      "keybind": "s"
    }
  '';

  # GTK CSS, like waybar's and swayosd's, but written here rather than imported from
  # ~/.dotfiles: wlogout is Wayland-only, so there is no macOS half to keep in step.
  # The pill treatment carries over -- translucent @base, @surface0 border -- scaled up,
  # over a scrim that dims the desktop behind it.
  environment.etc."xdg/wlogout/style.css".text = ''
    * {
      background-image: none;
      box-shadow: none;
      font-family: "${theme.fonts.monospace}", "Symbols Nerd Font";
      font-size: 17px;
    }

    window {
      background-color: alpha(${palette.crust}, 0.72);
    }

    button {
      color: ${palette.text};
      background-color: alpha(${palette.base}, ${toString theme.opacity});
      border: 2px solid ${palette.surface0};
      border-radius: 14px;
      margin: 14px;
      padding: 28px;
      outline-style: none;
      /* GTK animates between the two states, so hover and focus fade rather than snap. */
      transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease;
    }

    button:focus,
    button:hover {
      color: ${theme.accentHex};
      background-color: alpha(${palette.surface0}, ${toString theme.opacity});
      border-color: ${theme.accentHex};
    }

    /* The two that can't be taken back warn in their own colour on the way past. */
    #reboot:focus,
    #reboot:hover {
      color: ${palette.peach};
      border-color: ${palette.peach};
    }

    #shutdown:focus,
    #shutdown:hover {
      color: ${palette.red};
      border-color: ${palette.red};
    }
  '';

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
    '';

    "xdg/hypr/hyprlock.conf".text = ''
      general {
        hide_cursor = true
      }

      background {
        monitor =
        path = ${wallpaper}
        color = rgb(${hex palette.base})
      }

      label {
        monitor =
        text = $TIME
        color = rgb(${hex palette.text})
        font_size = 96
        font_family = ${theme.fonts.monospace} ExtraBold
        position = 0, 360
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:60000] date +"%A, %B %-d"
        color = rgb(${hex palette.subtext0})
        font_size = 22
        font_family = ${theme.fonts.monospace}
        position = 0, 260
        halign = center
        valign = center
      }

      input-field {
        monitor =
        size = 320, 56
        position = 0, -320
        halign = center
        valign = center
        rounding = 14
        outline_thickness = 2
        outer_color = rgb(${hex theme.accentHex})
        inner_color = rgb(${hex palette.mantle})
        font_color = rgb(${hex palette.text})
        font_family = ${theme.fonts.monospace}
        check_color = rgb(${hex theme.accentAltHex})
        fail_color = rgb(${hex palette.red})
        capslock_color = rgb(${hex palette.yellow})
        placeholder_text = <span foreground="#${palette.overlay0}">password</span>
        fail_text = $FAIL
        fade_on_empty = false
        dots_size = 0.25
        dots_spacing = 0.3
      }
    '';
  };
}
