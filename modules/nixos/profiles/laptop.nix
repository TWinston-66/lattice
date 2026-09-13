{
  config,
  lib,
  pkgs,
  ...
}:
{
  ### KERNEL ###
  boot.kernelPackages = pkgs.linuxPackages_latest;

  ### NETWORKING ###
  networking.useNetworkd = false;
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };
  users.users."winston".extraGroups = [ "networkmanager" ];

  ### MEMORY ###
  zramSwap.enable = true;
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  ### POWER ###
  services = {
    power-profiles-daemon.enable = true;

    upower = {
      enable = true;
      criticalPowerAction = "Hibernate";
    };

    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandlePowerKey = "suspend";
      HandlePowerKeyLongPress = "poweroff";
    };

    fwupd.enable = true;
  };
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  environment.etc."xdg/hypr/hypridle.conf".text = lib.mkIf config.services.hypridle.enable (
    lib.mkAfter ''
      listener {
        timeout = 900
        on-timeout = systemctl suspend-then-hibernate
      }
    ''
  );

  assertions = [
    {
      assertion = config.boot.resumeDevice != "";
      message = "The laptop profile hibernates, so the host needs boot.resumeDevice.";
    }
  ];
}
