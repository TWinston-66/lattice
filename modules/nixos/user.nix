{ config, lib, ... }:
let
  cfg = config.lattice.user;
in
{
  ### USER ###
  # lattice is a single-seat desktop: one login, whose session every desktop module themes,
  # mounts drives for and sends notifications to. Modules read the name from here rather
  # than each spelling it out.
  options.lattice.user = {
    name = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = "The login account the desktop is built around.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A file holding the account's password hash, read at activation. With it, users are
        immutable and the flake is the only place a password can change. Without it, users
        stay mutable and the password is whatever `passwd` last set, which is how a fresh
        install gets one.
      '';
    };
  };

  config = {
    users.mutableUsers = cfg.hashedPasswordFile == null;
    users.users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.name;
      extraGroups = [ "wheel" ];
      inherit (cfg) hashedPasswordFile;
    };

    # Where `nh` and the lattice CLI find the flake. A host that keeps it elsewhere says so.
    programs.nh.flake = lib.mkDefault "${config.users.users.${cfg.name}.home}/lattice";
  };
}
