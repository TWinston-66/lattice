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
    ./branding.nix
  ];

  ### NIX ###
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;

    channel.enable = false;
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
