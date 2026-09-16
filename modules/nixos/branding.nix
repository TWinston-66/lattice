{ config, pkgs, ... }:
{
  imports = [ ./theme.nix ];

  ### OS IDENTITY ###
  system.nixos = {
    distroId = "lattice";
    distroName = "lattice";
    vendorId = "lattice";
    vendorName = "lattice";
    extraOSReleaseArgs = {
      PRETTY_NAME = "lattice ${config.system.nixos.release}";
      HOME_URL = "https://github.com/TWinston-66/lattice";
      LOGO = "lattice";
      ANSI_COLOR = "38;2;${config.lattice.theme.accentRgb}";
    };
  };

  environment.systemPackages = [
    (pkgs.runCommand "lattice-logo" { } ''
      install -Dm644 ${../../.github/assets/logo.svg} $out/share/icons/hicolor/scalable/apps/lattice.svg
    '')
  ];

  # console.colors comes from ./theme.nix.
}
