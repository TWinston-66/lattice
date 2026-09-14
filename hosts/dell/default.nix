{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/remote-managed.nix
    ../../modules/nixos/dotfiles.nix
    ../../modules/nixos/profiles/laptop.nix
    ../../modules/nixos/profiles/graphical.nix
  ];

  networking.hostName = "lattice-dell";
  system.stateVersion = "26.05";

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
      };
      efi.canTouchEfiVariables = true;
    };

    initrd.luks.devices = {
      "luks-6dbb1fe5-333b-4392-a81a-bd52ef847e3f" = {
        device = "/dev/disk/by-uuid/6dbb1fe5-333b-4392-a81a-bd52ef847e3f";
        allowDiscards = true;
      };
      "luks-7ae8c7b4-9729-468e-a0b6-833f8cce4abb".allowDiscards = true;
    };

    resumeDevice = "/dev/mapper/luks-6dbb1fe5-333b-4392-a81a-bd52ef847e3f";
  };

  ### DISPLAY ###
  programs.firefox = {
    preferences."layout.css.devPixelsPerPx" = "1.1";
    preferencesStatus = "default";
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

    ### POWER ###
    thermald.enable = true;
  };
}
