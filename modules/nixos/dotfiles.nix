{ pkgs, ... }:
{
  ### SHELL ###
  programs = {
    zsh = {
      enable = true;
      enableGlobalCompInit = false;
      promptInit = "";
    };
    ssh.startAgent = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
        glib
        gtk3
        nss
        nspr
        at-spi2-atk
        cups
        libdrm
        libxkbcommon
        mesa
        expat
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        alsa-lib
        libGL
        fuse3
        icu
        libunwind
        libuuid
      ];
    };
  };
  users.users.winston.shell = pkgs.zsh;

  environment.pathsToLink = [
    "/share/zsh-autosuggestions"
    "/share/zsh-syntax-highlighting"
  ];

  ### PACKAGES ###
  environment.systemPackages = with pkgs; [
    stow
    gum
    zsh-autosuggestions
    zsh-syntax-highlighting
    starship
    zoxide
    fzf
    eza
    bat
    fd
    ripgrep
    jq
    delta
    gh
    lazygit
    lazydocker
    tmux
    sesh
    gitmux
    btop
    duf
    dust
    procs
    gping
    nmap
    tealdeer
    imagemagick

    neovim
    tree-sitter
    gcc
    unzip
    wget
    nodejs
    go
    golangci-lint
    uv
    nixd
    nixfmt
    statix
    texliveFull

    claude-code
    pi-coding-agent
  ];
}
