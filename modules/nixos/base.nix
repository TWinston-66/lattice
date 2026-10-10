{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nix-index-database.nixosModules.nix-index
    ./branding.nix
    ./backup.nix
    ./cli.nix
    ./firewall.nix
    ./user.nix
  ];

  ### NIX ###
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # What CI builds lands here (.github/workflows/ci.yml), so a rebuild after a green run
    # fetches the lattice packages and overrides instead of compiling them. cache.nixos.org
    # stays first; NixOS appends it after these.
    settings.substituters = [ "https://lattice.cachix.org" ];
    settings.trusted-public-keys = [
      "lattice.cachix.org-1:A37f+od4LYzAZVpYIpWKJBNFT9wG1N0HRubFlgbm8SY="
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
  # LLMNR broadcasts every unqualified name the host looks up to whoever shares the network,
  # which on public wifi is anyone. Nothing here uses it: the tailnet has MagicDNS, and the
  # .local names (AirPlay) are avahi's mDNS, not resolved's.
  services.resolved.settings.Resolve.LLMNR = false;

  # tailscaled puts accepted subnet routes in table 52 and looks it up at pref 5270, ahead of
  # main. OPNsense advertises the home LAN, so at home 10.0.10.0/24 went out tailscale0 from
  # the 100.x address even with wifi sitting on that same subnet. TCP survived the trip
  # through the router; AirPlay did not, because the HomePod answers its timing and control
  # channels over UDP to an address it has no route back to, and the sink tore itself down
  # (2026-10-08).
  #
  # suppress_prefixlength 0 consults main but ignores its default route, so only on-link and
  # other specific routes win here. Away from home the LAN is not on-link and table 52 still
  # carries it; the exit node's default is untouched either way.
  systemd.services.lattice-lan-before-tailnet = lib.mkIf config.services.tailscale.enable {
    description = "Prefer directly connected subnets over tailscale subnet routes";
    wantedBy = [ "multi-user.target" ];
    before = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      for v in -4 -6; do
        ip "$v" rule del pref 5200 2>/dev/null || true
        ip "$v" rule add pref 5200 lookup main suppress_prefixlength 0
      done
    '';
    preStop = ''
      for v in -4 -6; do ip "$v" rule del pref 5200 2>/dev/null || true; done
    '';
  };

  # Lets the bar's Tailscale pill run `tailscale up`/`down` without sudo.
  systemd.services.tailscale-operator = lib.mkIf config.services.tailscale.enable {
    description = "Allow the lattice user to operate tailscaled without sudo";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    # A pill that refuses to toggle is the symptom, and it points at the bar rather than
    # here. At boot there is no session to notify and only the journal line lands; the
    # failure this actually catches is the one during a `nixos-rebuild switch`, which is
    # when the ExecStart changes and so when it is most likely to break.
    onFailure = [ "lattice-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale set --operator=${config.lattice.user.name}";
    };
  };

  ### TIME/LOCALE ###
  i18n.defaultLocale = "en_US.UTF-8";

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
