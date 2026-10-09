{ config, ... }:
{
  ### DOCKER ###
  # Socket-activated: docker.socket stays up and the daemon starts on the first `docker`
  # call. Started at boot, docker.service pulls in network-online.target, which held the
  # graphical target behind NetworkManager-wait-online for ~7.5s on every boot. The cost is
  # that containers with a restart policy no longer come back on their own until then.
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };

  ### VIRTUALIZATION ###
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.users.${config.lattice.user.name}.extraGroups = [
    "docker"
    "libvirtd"
  ];
}
