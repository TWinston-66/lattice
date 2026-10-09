{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.lattice.user.name;
  home = config.users.users.${user}.home;

  # catppuccin/tmux 2.3.0, against nixpkgs' 2.1.3: the status modules tmux.conf builds its bar
  # from, and the @thm_* names theme.tmux sets, are the ones from 2.3.0.
  catppuccinTmux = pkgs.tmuxPlugins.catppuccin.overrideAttrs {
    version = "2.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "tmux";
      rev = "v2.3.0";
      hash = "sha256-3CJRQCgS8NAN7vOLBjNGiHbGXTIrIyY/FLmfZrXcEYc=";
    };
  };

  tmuxPlugins = {
    catppuccin = catppuccinTmux;
    inherit (pkgs.tmuxPlugins) resurrect continuum cpu;
    tmuxFzf = pkgs.tmuxPlugins.tmux-fzf;
    whichKey = pkgs.tmuxPlugins.tmux-which-key;
  };

  tmuxConf = lib.replaceStrings (map (n: "@${n}@") (lib.attrNames tmuxPlugins)) (map (p: p.rtp) (
    lib.attrValues tmuxPlugins
  )) (builtins.readFile ./configs/tmux.conf);

  # GTK CSS has no ~, so the path to the picked theme's CSS is spelled out per user.
  gtk4Css = ''
    /* libadwaita apps take no GTK theme, only this file, read at launch. Its colours are the
       theme lattice-theme has picked: theme.gtk.css, rewritten on every theme switch and
       wallpaper pick, the same file the GTK3 theme imports. */
    @import url("file://${home}/.cache/lattice/theme.gtk.css");
  '';

  # The launcher's entries, renamed or hidden. Each has the desktop-file ID of the entry it
  # replaces, and hiPrio is what settles the collision in the system profile in its favour.
  desktopEntries = lib.hiPrio (
    pkgs.runCommand "lattice-desktop-entries" { } ''
      mkdir -p $out/share/applications
      cp ${./configs/applications}/*.desktop $out/share/applications/
    ''
  );

  # Programs that read only from the home. Each gets a link to its file under /etc/xdg, and
  # `L` makes it only where nothing is there yet: a config of the user's own -- a real file,
  # or a link somewhere else -- is left alone and wins, as ~/.config does for every program
  # that looks in /etc/xdg by itself.
  homeOnly = [
    "mako/config"
    "satty/config.toml"
    "gtk-4.0/gtk.css"
  ];
in
{
  ### DESKTOP CONFIGS ###
  # The config each desktop program runs with, from ./configs. They all live under /etc,
  # where most of these programs look after the user's own config dir: foot, rofi,
  # swayosd and qt6ct through XDG_CONFIG_DIRS, tmux, zathura and mpv at fixed paths of
  # their own. A file of the same name in ~/.config takes over -- for foot and rofi
  # entirely; tmux, zathura, mpv and qt6ct read both, the user's last.
  environment.etc = {
    "xdg/foot/foot.ini".source = ./configs/foot.ini;
    "xdg/rofi.rasi".source = ./configs/rofi.rasi;
    "xdg/swayosd/style.css".source = ./configs/swayosd.css;
    "xdg/qt6ct/qt6ct.conf".source = ./configs/qt6ct.conf;
    "tmux.conf".text = tmuxConf;
    "xdg/gitmux/gitmux.conf".source = ./configs/gitmux.conf;
    "zathurarc".source = ./configs/zathurarc;
    "mpv/mpv.conf".source = ./configs/mpv.conf;

    "xdg/mako/config".source = ./configs/mako;
    "xdg/satty/config.toml".source = ./configs/satty.toml;
    "xdg/gtk-4.0/gtk.css".text = gtk4Css;
  };

  systemd.user.tmpfiles.users.${user}.rules =
    map (path: "L ${home}/.config/${path} - - - - /etc/xdg/${path}") homeOnly
    # btop has no system config and rewrites its own on exit, so it is seeded instead,
    # once: a copy only where there is none, naming the theme /etc/zshrc's btop alias
    # serves from ~/.cache/lattice. btop fills in every other key with its defaults.
    ++ [
      "d ${home}/.config/btop 0755 - - -"
      "C ${home}/.config/btop/btop.conf - - - - ${pkgs.writeText "btop.conf" ''
        color_theme = "catppuccin_mocha"
      ''}"
    ];

  environment.systemPackages = [ desktopEntries ];
}
