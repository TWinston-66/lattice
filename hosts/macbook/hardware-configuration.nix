# Stands in for what nixos-generate-config writes at install time, describing the layout
# lattice installs: btrfs on LUKS in the space the Asahi installer left, with home and nix
# subvolumes, and the Asahi ESP at /boot.
{ lib, ... }:
{
  boot.initrd.availableKernelModules = [
    "usb_storage"
    "sdhci_pci"
  ];

  boot.initrd.luks.devices.system.device = "/dev/disk/by-partlabel/lattice";

  fileSystems."/" = {
    device = "/dev/mapper/system";
    fsType = "btrfs";
  };

  fileSystems."/home" = {
    device = "/dev/mapper/system";
    fsType = "btrfs";
    options = [ "subvol=home" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/system";
    fsType = "btrfs";
    options = [ "subvol=nix" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI\\x20-\\x20NIXOS";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
