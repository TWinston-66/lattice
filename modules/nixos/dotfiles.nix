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
    nix-ld.enable = true;
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
