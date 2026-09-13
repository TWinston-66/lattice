_: {
  networking.useNetworkd = false;
  networking.networkmanager.enable = true;
  users.users."winston".extraGroups = [ "networkmanager" ];

  services.fwupd.enable = true;
}
