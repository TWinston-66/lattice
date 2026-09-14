{ config, pkgs, ... }:
{
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
      ANSI_COLOR = "38;2;137;180;250";
    };
  };

  environment.systemPackages = [
    (pkgs.runCommand "lattice-logo" { } ''
      install -Dm644 ${../../.github/assets/logo.svg} $out/share/icons/hicolor/scalable/apps/lattice.svg
    '')
  ];

  ### CONSOLE ###
  console.colors = [
    "1e1e2e"
    "f38ba8"
    "a6e3a1"
    "f9e2af"
    "89b4fa"
    "f5c2e7"
    "94e2d5"
    "cdd6f4"
    "585b70"
    "f37799"
    "89d88b"
    "ebd391"
    "74a8fc"
    "f2aede"
    "6bd7ca"
    "bac2de"
  ];
}
