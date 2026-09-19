{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.nix-index-database.nixosModules.nix-index
    ./branding.nix
    ./firewall.nix
  ];

  ### NIX ###
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    optimise.automatic = true;

    channel.enable = false;
  };

  # `nh os switch` / `nh clean` wrap nixos-rebuild and the collector with a readable diff of
  # what actually changed between generations. NH_FLAKE is what lets the subcommands run
  # from any directory; scripts/rebuild.sh still drives real rebuilds, since it also handles
  # the sops recipient check.
  #
  # nh.clean replaces nix.gc rather than joining it -- the module asserts they cannot both
  # be on. It is the better half of that trade: `nix-collect-garbage --delete-older-than`
  # only walks the system profile, while `nh clean all` also covers per-user profiles and
  # stale gcroots, which is where most of the reclaimable space on this machine sits.
  # `--keep 3` is the safety net the bare date option lacks: after two weeks away there is
  # still something to roll back to.
  programs = {
    nh = {
      enable = true;
      flake = "/home/winston/Documents/Projects/lattice";
      clean = {
        enable = true;
        extraArgs = "--keep-since 14d --keep 3";
      };
    };

    # Replaces command-not-found, which needs a nix-channel this config does not have
    # (`nix.channel.enable = false` above), so an unknown command currently just fails with
    # nothing useful. nix-index answers from a file database instead, and comma (`, foo`)
    # runs a binary straight out of nixpkgs without installing it.
    #
    # The database is the catch: `nix-index` takes several minutes and would have to be rerun
    # by hand. The nix-index-database input ships a prebuilt one updated weekly, which is the
    # only reason this is worth enabling at all.
    nix-index-database.comma.enable = true;
    nix-index.enable = true;
  };

  ### BOOT ###
  boot.loader.systemd-boot.editor = false;

  ### NETWORKING ###
  networking.useDHCP = false;
  networking.useNetworkd = lib.mkDefault true;
  systemd.network.networks."10-wired" = {
    matchConfig = {
      Type = "ether";
      Kind = "!*";
    };
    networkConfig.DHCP = "yes";
  };
  services.resolved.enable = true;

  ### SECRETS ###
  services.openssh.hostKeys = [
    {
      type = "ed25519";
      path = "/etc/ssh/ssh_host_ed25519_key";
    }
  ];
  sops = {
    defaultSopsFile = ../../secrets/common.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.winston-password.neededForUsers = true;
  };

  ### TIME/LOCALE ###
  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  ### USERS ###
  users.mutableUsers = false;
  users.users.winston = {
    isNormalUser = true;
    description = "winston";
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.winston-password.path;
  };

  ### PACKAGES ###
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    file
    pciutils
    usbutils
    exfatprogs
    python3
  ];

  environment.defaultPackages = [ ];
  documentation.nixos.enable = false;
}
