{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    inputs.apple-silicon.nixosModules.apple-silicon-support
    ../../modules/nixos/base.nix
    ../../modules/nixos/dotfiles.nix
    ../../modules/nixos/profiles/laptop.nix
    ../../modules/nixos/profiles/graphical.nix
  ];

  networking.hostName = "lattice-mac";
  system.stateVersion = "26.11";

  ### ASAHI ###
  hardware.asahi = {
    enable = true;

    # The Asahi installer leaves the Wi-Fi, Bluetooth and camera firmware on the ESP. It is
    # Apple's and can't go in a public repo, and a pure flake can't read /boot, so it is
    # pinned by hash instead: once the store holds a copy with this hash, evaluation takes
    # it from there without touching /boot. /boot is root-only, so the copy is made by hand,
    # once per firmware update (re-running the Asahi installer from macOS changes it):
    #
    #   sudo nix hash path /boot/vendorfw               # the new narHash
    #   sudo nix store add --name source /boot/vendorfw
    peripheralFirmwareDirectory =
      (builtins.fetchTree {
        type = "path";
        path = "/boot/vendorfw";
        narHash = "sha256-wETBAOJSRK5XrfeTa+vqluv3M1RxIQdGpB+6zW+2mYw=";
      }).outPath;
  };

  # Keeps that copy in the system closure. Nothing else refers to it once the firmware is
  # unpacked, so `nh clean` would delete it and evaluating would need root again.
  environment.etc."lattice/vendorfw".source = config.hardware.asahi.peripheralFirmwareDirectory;

  boot.loader.systemd-boot = {
    enable = true;
    # The ESP the Asahi installer makes is only ~500MB, and it also holds m1n1 and the
    # firmware, so fewer kernels fit than on the Dell.
    configurationLimit = 3;
  };

  ### BTRFS ###
  fileSystems = lib.genAttrs [ "/" "/home" "/nix" ] (_: {
    options = [
      "compress=zstd"
      "noatime"
    ];
  });

  systemd.tmpfiles.rules = [ "v /home/.snapshots 0750 root users -" ];

  services = {
    btrfs.autoScrub.enable = true;

    snapper.configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "winston" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 12;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };

    tailscale.enable = true;
  };

  # As on the Dell: lets the bar's Tailscale pill run `tailscale up`/`down` without sudo.
  systemd.services.tailscale-operator = {
    description = "Allow winston to operate tailscaled without sudo";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale set --operator=winston";
    };
  };

  ### DOCKER ###
  virtualisation.docker.enable = true;

  ### VIRTUALIZATION ###
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.users.winston.extraGroups = [
    "docker"
    "libvirtd"
  ];
}
