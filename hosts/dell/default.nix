{ lib, pkgs, ... }:
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

  ### GRAPHICS ###
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

  ### DISPLAY ###
  programs = {
    firefox = {
      preferences."layout.css.devPixelsPerPx" = "1.1";
      preferencesStatus = "default";
    };
    thunderbird = {
      preferences."layout.css.devPixelsPerPx" = "1.1";
      preferencesStatus = "default";
    };
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

    tailscale.enable = true;
  };

  # The bar's Tailscale pill toggles the tunnel with `tailscale up`/`down`, which tailscaled
  # refuses for anyone but root unless a user is named as the operator. The world-writable
  # socket is not enough: the daemon checks this preference itself. Set once per boot; the
  # preference persists in tailscaled's state either way, so this is belt and braces.
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
