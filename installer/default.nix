# The lattice installer: nixos-apple-silicon's ISO (their iso-configuration, which this is
# layered on through mkInstallerBootstrapCustom in flake.nix) plus what it takes to go from
# the Asahi installer's empty space to a booting lattice in one sitting -- lattice's binary
# cache, its kernel, and `lattice-install`, which does every step of docs/install.md.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  version = lib.fileContents ../VERSION;

  # A released ISO clones lattice at the commit it was built from, so what it installs is
  # what it was tested with. An ISO built from an uncommitted tree has no such commit, and
  # carries the tree itself instead.
  source =
    if inputs.self ? rev then
      {
        inherit (inputs.self) rev;
        tree = "";
      }
    else
      {
        rev = "";
        tree = "${inputs.self}";
      };

  lattice-install = pkgs.writeShellApplication {
    name = "lattice-install";
    runtimeInputs = with pkgs; [
      btrfs-progs
      coreutils
      cryptsetup
      gawk
      git
      gnugrep
      gnused
      gptfdisk
      kmod
      mkpasswd
      networkmanager
      nix
      nixos-install-tools
      openssh
      sops
      ssh-to-age
      stow
      systemd
      util-linux
    ];
    runtimeEnv = {
      LATTICE_VERSION = version;
      LATTICE_REPO = "https://github.com/TWinston-66/lattice";
      LATTICE_REV = source.rev;
      LATTICE_TREE = source.tree;
    };
    text = builtins.readFile ./lattice-install.sh;
  };
in
{
  imports = [ ../modules/nixos/hardware/asahi-kernel.nix ];

  # iso-image.nix names the file after baseName and only reports fileName, which upstream
  # sets to its own pattern; both, so they agree.
  image.baseName = lib.mkForce "lattice-${version}-apple-silicon";
  image.fileName = lib.mkForce "lattice-${version}-apple-silicon.iso";
  isoImage.volumeID = "lattice-${version}";
  isoImage.prependToMenuLabel = "lattice ${version} installer (";
  isoImage.appendToMenuLabel = ")";

  # The installation-device profile starts sshd and lets root in, for headless boards. A Mac
  # has its own screen and keyboard, and a live system with empty passwords has no business
  # listening on the network.
  services.openssh.enable = false;

  # So the install downloads what CI built instead of compiling it; base.nix gives installed
  # systems the same pair.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [ "https://lattice.cachix.org" ];
    trusted-public-keys = [
      "lattice.cachix.org-1:A37f+od4LYzAZVpYIpWKJBNFT9wG1N0HRubFlgbm8SY="
    ];
  };

  environment.systemPackages = [
    lattice-install
    pkgs.git
  ];

  services.getty.helpLine = lib.mkForce ''

    This is the lattice ${version} installer. Connect to Wi-Fi with `nmtui` if there is no
    cable, then run:

        sudo lattice-install

    It asks for a name, a user and a password, puts lattice in the space the Asahi installer
    left, encrypts it, and installs. Nothing is written until you confirm.
  '';
}
