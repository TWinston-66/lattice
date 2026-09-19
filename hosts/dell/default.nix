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

    # Hibernation is this host's, not the laptop profile's: Asahi can't hibernate at all.
    upower.criticalPowerAction = "Hibernate";
    logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";

    tailscale.enable = true;
  };

  ### HIBERNATION ###
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
  # battery is genuinely low -- but s2idle here costs 3.1 %/hr, which on this 52.1 Wh
  # battery is 1.62 W (measured 2026-09-19 over real suspends). That is a little above the
  # ~1.5 W a healthy S0ix should draw and ~8x a MacBook, so ~32h of sleep on a full charge:
  # fine for a class gap, not fine for a weekend. The numbers are what justify 3h rather
  # than something longer -- a 1-2h gap costs 3-6% and resumes instantly, and the backstop
  # trips at ~9%. It is also what makes HibernateOnACPower work at all:
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
