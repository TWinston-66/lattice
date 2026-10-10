# Winston's own setup on top of the distro: the account, the secrets, and everything that
# talks to this particular house and homelab. Nothing under modules/nixos reads from here.
{ config, inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    ./airplay.nix
    ./books.nix
    ./mozilla.nix
    ./mouse.nix
  ];

  ### ACCOUNT ###
  lattice.user = {
    name = "winston";
    hashedPasswordFile = config.sops.secrets.winston-password.path;
  };
  programs.nh.flake = "/home/winston/Documents/Projects/lattice";

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
    secrets.restic-password = { };
    # Owned by winston rather than root: lattice-ha runs as the session, both from the deck's
    # user unit and from a shell. 0400 is sops-nix's default and is what is wanted.
    secrets.ha-token.owner = "winston";
  };

  # The Bitwarden copy of this is the one that matters when the host is gone, since its host
  # key went with it.
  lattice.backup.passwordFile = config.sops.secrets.restic-password.path;

  services.tailscale.enable = true;
  # OPNsense advertises the home LAN; without this tailscaled's health check flags the
  # unaccepted routes and the bar pill shows a warning. Prefs live in /var/lib/tailscale,
  # so a hand-run `tailscale set` was lost with the 2026-10-10 reinstall. The LAN still
  # goes direct when on-link (lattice-lan-before-tailnet, nixos/base.nix).
  services.tailscale.extraSetFlags = [ "--accept-routes" ];

  time.timeZone = "America/Denver";

  lattice.weather = {
    latitude = "40.015";
    longitude = "-105.2705";
    label = "Boulder, CO";
  };

  ### HOME ASSISTANT ###
  lattice.homeassistant = {
    enable = true;
    url = "http://ha.home.lan:8123";
    tokenFile = config.sops.secrets.ha-token.path;
  };

  ### STREAM DECK ###
  lattice.streamdeck = {
    enable = true;
    serial = "AL24J2C03581";

    # Devices along the top, moods along the middle, and the bottom row left as the lattice
    # ground for whatever the house grows next. Two rows rather than one long run, because
    # the two halves are pressed for different reasons: the top three are switches that are
    # on or off and say so, the four below are a whole room set at once and are over the
    # moment they are pressed.
    homePage = [
      # The two light groups rather than any of the bulbs inside them: `light.bedroom` is
      # ceiling + lamp + hex panel, `light.bathroom_lights` is the four over the mirror. A
      # group reports `on` when any member is, which is the reading the key wants -- one
      # bulb left on is not a key that should be showing off.
      {
        index = 0;
        name = "bedroom-lights";
        entity = "light.bedroom";
        label = "bedroom";
        kind = "toggle";
        icon = "bulb";
      }
      {
        index = 1;
        name = "bathroom-lights";
        entity = "light.bathroom_lights";
        label = "bathroom";
        kind = "toggle";
        icon = "bulb";
      }
      # The same physical fan is on the bus twice -- `fan.fan` and `switch.fan`, one device
      # named Fan in the Bedroom area. The fan domain is the honest one of the two, and it
      # is what a speed would hang off if this ever grows one; `switch.fan` is the outlet
      # underneath it.
      {
        index = 2;
        name = "bedroom-fan";
        entity = "fan.fan";
        label = "fan";
        kind = "toggle";
        icon = "fan";
      }
      # All four are scenes today. They are pressed through `activate`, which reads the
      # domain and picks the service -- so one that later becomes a script, or an
      # automation, is a changed id here and nothing else.
      {
        index = 5;
        name = "bed-time";
        entity = "scene.bed_time";
        label = "bed time";
        kind = "scene";
        icon = "bed";
      }
      {
        index = 6;
        name = "calm";
        entity = "scene.calm_work";
        label = "calm";
        kind = "scene";
        icon = "meditation";
      }
      {
        index = 7;
        name = "focus";
        entity = "scene.focus";
        label = "focus";
        kind = "scene";
        icon = "target";
      }
      {
        index = 8;
        name = "wind-down";
        entity = "scene.wind_down";
        label = "wind down";
        kind = "scene";
        icon = "dusk";
      }
    ];
  };
}
