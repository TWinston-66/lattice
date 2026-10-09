# The lattice distro: every module a lattice machine is built from. A host imports this,
# adds its own hardware-configuration.nix, firmware pin and panel geometry, and names its
# user; see hosts/macbook for the smallest one.
{
  imports = [
    ./base.nix
    ./devtools.nix
    ./storage.nix
    ./virtualisation.nix
    ./hardware/apple-silicon.nix
    ./profiles/laptop.nix
    ./profiles/graphical.nix
  ];
}
