{ config, lib, ... }:
let
  user = config.lattice.user.name;
in
{
  ### BTRFS ###
  fileSystems = lib.genAttrs [ "/" "/home" "/nix" ] (_: {
    options = [
      "compress=zstd"
      "noatime"
    ];
  });

  systemd.tmpfiles.rules = [ "v /home/.snapshots 0750 root users -" ];

  services = {
    # Monthly, on every btrfs mount (btrfs-scrub@-.timer for /). It runs with -B, so a scrub
    # that finds errors it could not correct exits non-zero and the unit fails.
    btrfs.autoScrub.enable = true;

    snapper.configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ user ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 12;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };

  };

  # A scrub that finds damage says so on screen, through the same bridge as every other
  # failing unit, instead of only in the journal the doctor reads.
  systemd.services."btrfs-scrub@".onFailure =
    lib.optional config.services.graphical-desktop.enable "lattice-notify-failure@%n.service";
}
