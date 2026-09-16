{ config, lib, ... }:
let
  tailnet = config.services.tailscale;
in
{
  ### FIREWALL ###
  # The firewall is on by default in NixOS, so none of this changes behaviour on its
  # own. It is declared anyway: stating the policy here is what makes a service that
  # quietly sets `openFirewall = true` visible as a diff rather than a surprise.
  networking.firewall = {
    enable = true;
    allowPing = true;

    # Trust the tailnet. tailscaled authenticates a peer before its packets ever
    # reach the host, so per-port rules on this interface would only duplicate a
    # check that already happened.
    trustedInterfaces = lib.mkIf tailnet.enable [ tailnet.interfaceName ];
  };

  # Opens UDP 41641 so peers can hole-punch. Without it tailscale still works, but
  # every connection falls back to a DERP relay: slower, and someone else's bandwidth.
  services.tailscale.openFirewall = lib.mkIf tailnet.enable true;

  # SSH is reachable over the tailnet only -- `trustedInterfaces` above already
  # admits it there, so the global port would just be a second, unauthenticated
  # door onto whatever wifi the laptop has joined. A host with no tailnet keeps the
  # port open, because closing it would leave no way back in at all.
  services.openssh.openFirewall = lib.mkDefault (!tailnet.enable);
}
