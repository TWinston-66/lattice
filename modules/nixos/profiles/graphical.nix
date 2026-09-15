{
  config,
  lib,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };

  wallpaper = pkgs.runCommand "lattice-wallpaper.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    rsvg-convert -w 3840 -h 2400 ${../../../.github/assets/wallpaper.svg} -o $out
  '';

  # Catppuccin Mocha with the blue accent, matching ~/.dotfiles.
  gtkTheme = "catppuccin-mocha-blue-standard";
  iconTheme = "Papirus-Dark";
  cursorTheme = "catppuccin-mocha-dark-cursors";
  # 9pt (12px) keeps UI text close to Ghostty and waybar; qt6ct in ~/.dotfiles uses the same fonts.
  uiFont = "Noto Sans 9";
  monospaceFont = "JetBrains Mono 9";

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
      variant = "mocha";
      accents = [ "blue" ];
    })
    (catppuccin-papirus-folders.override {
      flavor = "mocha";
      accent = "blue";
    })
    catppuccin-cursors.mochaDark
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
    wireplumber.enable = true;
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

    theme = {
      container = "black";
      border = "blue";
      title = "blue";
      greet = "white";
      time = "white";
      text = "gray";
      prompt = "blue";
      input = "gray";
      action = "blue";
      button = "magenta";
    };
  };

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
        color = rgb(1e1e2e)
      }

      label {
        monitor =
        text = $TIME
        color = rgb(cdd6f4)
        font_size = 96
        font_family = JetBrains Mono ExtraBold
        position = 0, 360
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:60000] date +"%A, %B %-d"
        color = rgb(a6adc8)
        font_size = 22
        font_family = JetBrains Mono
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
        outer_color = rgb(89b4fa)
        inner_color = rgb(181825)
        font_color = rgb(cdd6f4)
        font_family = JetBrains Mono
        check_color = rgb(b4befe)
        fail_color = rgb(f38ba8)
        capslock_color = rgb(f9e2af)
        placeholder_text = <span foreground="##6c7086">password</span>
        fail_text = $FAIL
        fade_on_empty = false
        dots_size = 0.25
        dots_spacing = 0.3
      }
    '';
  };
}
