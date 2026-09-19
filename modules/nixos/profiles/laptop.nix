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
  networking.networkmanager.enable = true;
  users.users.winston.extraGroups = [ "networkmanager" ];
  hardware.bluetooth.enable = true;

  ### THUNDERBOLT ###
  # The controller runs at security level "user", so PCIe tunnels (dock Ethernet, NVMe, eGPU) need bolt to authorize devices.
  services.hardware.bolt.enable = true;

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
  # The goal is "close the lid, open it at the next class, carry on": stay in s2idle
  # through any realistic gap, and only spend the three-password cold boot when hibernating
  # is actually worth it. 30min was far too eager -- an hour-long class always came back
  # the slow way.
  #
  # systemd-sleep(5): with a battery present the ACPI _BTP low-battery alarm is armed
  # first, and when HibernateDelaySec is also set the system hibernates on "whichever comes
  # first: low battery or the configured delay". `/sys/class/power_supply/BAT0/alarm`
  # exists, so _BTP really is available here and the battery arm is the one that usually
  # matters. The 3h is a backstop for a bag overnight, not the normal trigger.
  #
  # Leaving HibernateDelaySec unset would be the purest version -- hibernate only once the
  # battery is genuinely low -- but s2idle draw on this machine is still unmeasured, and
  # with no S3 available Modern Standby can be expensive. The backstop bounds the worst
  # case until there is a number. It is also what makes HibernateOnACPower work at all:
  # that setting is only consulted when HibernateDelaySec is set, and it keeps the
  # countdown from starting while plugged in, so a lid closed at a desk never hibernates.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "3h";
    HibernateOnACPower = false;
  };

  # btintel_pcie fails its hibernate callback with -EBUSY often enough that roughly half of
  # the overnight lid-closes never actually hibernated:
  #
  #   btintel_pcie 0000:00:14.7: PM: failed to hibernate async: error -16
  #   PM: hibernation: Wakeup event detected during hibernation, rolling back.
  #
  # The kernel throws away the image it has just written and resumes; the lid is still shut,
  # so logind starts suspend-then-hibernate over, the delay has already elapsed, and it
  # fails again -- a loop every ~30s that ran for eleven hours on 2026-09-17 (2753 suspend
  # entries in one day against 1-4 on a good one), flattening the battery and writing 8.2G
  # per attempt. Taking the module out first keeps the failing callback off the hibernate
  # path entirely.
  #
  # Shaped after the sleep-actions service in nixpkgs' power-management.nix, but bound to
  # the targets that can actually hibernate rather than to sleep.target, so a plain
  # `suspend` from the power button or the session menu keeps Bluetooth connected. preStop
  # runs on resume; the mouse re-pairs on its own once the module is back.
  systemd.services.bluetooth-hibernate-workaround =
    let
      hibernating = [
        "hibernate.target"
        "hybrid-sleep.target"
        "suspend-then-hibernate.target"
      ];
    in
    {
      description = "Unload btintel_pcie, which fails hibernation with -EBUSY";
      wantedBy = hibernating;
      before = hibernating;
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # Neither direction is worth failing a hibernate over: if the module is already out,
      # or the reload races the PCI rescan, the sleep should still go ahead.
      script = "${pkgs.kmod}/bin/modprobe -r btintel_pcie || true";
      preStop = "${pkgs.kmod}/bin/modprobe btintel_pcie || true";
    };

  systemd.user.services.batsignal = lib.mkIf config.services.graphical-desktop.enable {
    description = "Low battery notifications";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.batsignal}/bin/batsignal -w 20 -c 10 -d 5";
      Restart = "on-failure";
    };
  };

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
