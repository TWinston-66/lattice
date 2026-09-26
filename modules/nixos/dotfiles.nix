{ pkgs, ... }:
let
  # A bubblewrap sandbox with a populated /usr/lib, /bin and a working ldconfig, entered
  # with `fhs`. nix-ld below already covers prebuilt binaries that only need a dynamic
  # linker; it does nothing for anything that expects to *compile* against a normal
  # filesystem -- a bare ./configure, a pip package with no prebuilt wheel for this
  # platform, a course toolchain with /usr/include baked into its Makefile. Those are the
  # cases that otherwise turn a twenty-minute assignment into authoring a flake.
  #
  # Not a container: $HOME, the process tree, the network and the SSH agent are the real
  # ones, so files written inside are just files and nothing has to be synced back out.
  fhs = pkgs.buildFHSEnv {
    name = "fhs";

    targetPkgs =
      pkgs: with pkgs; [
        # Toolchain. stdenv.cc.cc.lib is what puts libstdc++.so.6 under /usr/lib -- gcc
        # alone leaves anything C++ failing to resolve it at run time.
        gcc
        stdenv.cc.cc.lib
        gnumake
        cmake
        pkg-config
        binutils

        # Python the FHS way: pip compiling native extensions inside a venv, which is the
        # usual reason a requirements.txt does not survive this machine. `uv` on the host
        # stays the better path where a project tolerates it, since nix-ld already makes
        # uv's downloaded CPython run outside the sandbox.
        python3
        python3Packages.pip
        python3Packages.virtualenv

        # The headers and libraries the two groups above get asked for constantly.
        zlib
        openssl
        libffi
        bzip2
        readline
        sqlite
        ncurses
        xz

        nodejs
        git
        curl
        wget
        which
        file
        unzip

        # runScript starts zsh, which sources the stow'd ~/.zshrc, and that zshrc calls
        # starship, zoxide and friends unconditionally. Those are host packages and are
        # invisible inside the sandbox, so leaving them out means every shell opens on a
        # wall of "command not found" before the prompt even renders.
        zsh
        starship
        zoxide
        fzf
        eza
        bat
        fd
        ripgrep
        delta
      ];

    # Headers. nixpkgs keeps them in each package's `dev` output, and targetPkgs takes
    # only the default outputs, so without this /usr/include holds four stray entries and
    # `gcc x.c -lz` dies on a missing zlib.h. Doing it here rather than listing `zlib.dev`
    # and friends by hand means anything added to targetPkgs later brings its headers
    # along; packages with no dev output are filtered out rather than erroring.
    extraOutputsToInstall = [ "dev" ];

    runScript = "zsh";

    # nixpkgs builds zsh with its sysconfdir inside its own store path, and ships a
    # compiled `etc/zshenv.zwc` there whose non-NixOS branch sources /etc/zshenv. That
    # file lands in the FHS rootfs because zsh is in targetPkgs above, and zsh prefers a
    # `.zwc` over the script beside it -- so inside the sandbox `. /etc/zshenv` re-runs
    # the shim instead of the system zshenv, recursing until zsh gives up with
    # "/etc/zshenv:1: job table full or recursion limit exceeded" on every shell. Dropping
    # the compiled copy lets the sourced path reach the real /etc/zshenv bound in from the
    # host. (The shim's NixOS branch is no escape: /etc/NIXOS does not exist in the
    # sandbox, and that branch sources /etc/zshenv too.)
    extraBuildCommands = ''
      rm -f $out/etc/zshenv.zwc $out/etc/zshenv_zwc_is_used
    '';

    profile = ''
      # So the prompt can say which shell this is; key a segment on $FHS in ~/.zshrc if
      # it ever stops being obvious.
      export FHS=1

      # buildFHSEnv's own profile points PKG_CONFIG_PATH at /usr/lib/pkgconfig only, but
      # arch-independent packages install their .pc file under share -- zlib among them,
      # so `pkg-config --cflags zlib` failed while the header and library were both
      # there. Real distributions search both.
      export PKG_CONFIG_PATH="$PKG_CONFIG_PATH''${PKG_CONFIG_PATH:+:}/usr/share/pkgconfig"
    '';
  };
in
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
        pango
        cairo
        gdk-pixbuf
        freetype
        fontconfig
        nss
        nspr
        at-spi2-atk
        cups
        dbus
        libsecret
        libdrm
        libxkbcommon
        mesa
        # mesa no longer carries libgbm: as of this nixpkgs the mesa output has no
        # libgbm.so.1 in it at all, and the library lives in its own `libgbm`
        # derivation (mesa-libgbm). Anything Chromium- or Electron-based dlopens that
        # soname, so without this line mesa alone looks sufficient and is not.
        libgbm
        expat
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxshmfence
        libxtst
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
    ghostscript

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

    fhs

    claude-code
    pi-coding-agent
  ];
}
