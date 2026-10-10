# The smallest lattice host, and the one an install starts from: the distro, this machine's
# disks and firmware, and a user. Everything else is a default in modules/nixos.
# lattice-install copies it to hosts/<name>; every folder in hosts/ is a host of the flake.
_: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos
  ];

  networking.hostName = "lattice";
  system.stateVersion = "26.11";
  time.timeZone = "America/New_York";

  # No hashedPasswordFile, so the password is whatever `passwd` sets. The installer sets the
  # first one.
  lattice.user.name = "lattice";

  # `nix hash path /var/lib/lattice/vendorfw` after copying the firmware there; see the
  # option's description for why the copy exists.
  lattice.asahi.firmwareHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
