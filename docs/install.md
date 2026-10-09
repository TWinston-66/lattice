# Installing lattice

lattice runs on Apple Silicon MacBooks (the M1 and M2 generations that
[Asahi Linux](https://asahilinux.org) supports), next to macOS. Every lattice machine is a
host in the flake: a folder under `hosts/`, built from the distro in `modules/nixos`.
`hosts/macbook` is the smallest one, and the one to start from.

> [!NOTE]
> These steps are written against the layout `hosts/macbook` expects, LUKS-encrypted btrfs,
> and have not yet been run end to end on hardware.

## Installing

lattice is installed from a minimal NixOS first, because the installer ISO can only copy its
own kernel. The [nixos-apple-silicon install guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md)
has the details. In short:

1. In macOS, run the Asahi installer. Resize (`r`) to leave the space you want for lattice,
   then install (`f`) **UEFI environment only**, named `lattice`, and finish the
   permissive-security steps it prints in recovery.

   ```sh
   curl https://alx.sh | sh
   ```

2. `dd` the latest [release ISO](https://github.com/nix-community/nixos-apple-silicon/releases)
   to a USB stick and boot it. Keep the stick: it is this machine's recovery stick.
3. Create a partition in the free space, and only there. Damaging the GPT, the first or
   last partition, or the APFS containers can leave the Mac unbootable.

   ```sh
   sgdisk /dev/nvme0n1 -n 0:0 -c 0:lattice -s    # then sgdisk -p for its number
   cryptsetup luksFormat /dev/disk/by-partlabel/lattice
   cryptsetup open /dev/disk/by-partlabel/lattice system
   mkfs.btrfs -L lattice /dev/mapper/system
   mount /dev/mapper/system /mnt
   btrfs subvolume create /mnt/home && btrfs subvolume create /mnt/nix
   mount -o subvol=home /dev/mapper/system /mnt/home
   mount -o subvol=nix /dev/mapper/system /mnt/nix
   mkdir /mnt/boot
   mount /dev/disk/by-partuuid/$(cat /proc/device-tree/chosen/asahi,efi-system-partition) /mnt/boot
   nixos-generate-config --root /mnt
   ```

4. Edit `/mnt/etc/nixos/configuration.nix` as the guide says, plus NetworkManager, git, and
   a user with an `initialPassword`. Then run `nixos-install` and reboot into it.
5. On NixOS, clone lattice to `~/lattice` and make a host for this machine:

   ```sh
   cp -r hosts/macbook hosts/<name>
   cp /etc/nixos/hardware-configuration.nix hosts/<name>/
   ```

   In `hosts/<name>/default.nix`, set the hostname, time zone and `lattice.user.name` (the
   user from step 4), and add the host to `flake.nix` next to `macbook`.
6. Copy the firmware where the flake can read it and pin its hash in
   `lattice.asahi.firmwareHash`:

   ```sh
   sudo install -d -m 0755 /var/lib/lattice
   sudo cp -rT /boot/vendorfw /var/lib/lattice/vendorfw
   sudo chmod -R a+rX /var/lib/lattice/vendorfw
   nix hash path /var/lib/lattice/vendorfw
   ```

7. `git add` the new host, then run `scripts/rebuild.sh <name>`. The first switch builds the
   Asahi kernel, so give it a while. After that, `lattice rebuild` does the same.

## Secrets (optional)

`hosts/mac` is the author's machine, and shows the other way to run a host: the password and
the service tokens in [sops](https://github.com/getsops/sops), via `modules/personal`. With
`lattice.user.hashedPasswordFile` set, users are immutable and the password lives only in the
flake; `scripts/rebuild.sh` then refuses to switch until the host's age key is a recipient of
`secrets/common.yaml`, since otherwise it would boot with every account locked.

## Next

- [Everyday use](using.md): the `lattice` command, rebuilding and switching themes.
- [Backups](backups.md): set up the backup drive before you need it.
