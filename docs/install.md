# Installing lattice

Every lattice machine is a host in the flake: a folder under `hosts/`, built from the
same modules as the others. Installing one means getting a minimal NixOS onto the
hardware, then letting the flake take over.

> [!IMPORTANT]
> Root is locked and login passwords only come from sops. A host the secrets aren't
> encrypted to boots with every account locked, so the rebuild scripts refuse to switch
> until its key is a recipient. Have an admin machine, one holding the age key at
> `~/.config/sops/age/keys.txt`, within reach.

## Which path

| Machine | Start with |
| --- | --- |
| An Intel or AMD PC or laptop | [Installing on a PC](#installing-on-a-pc), then [Adding a host](#adding-a-host) |
| A MacBook with Apple Silicon | [Installing on Apple Silicon](#installing-on-apple-silicon), which covers both |
| A machine already running NixOS | [Adding a host](#adding-a-host) |
| Anything else | [Other hardware](#other-hardware) first |

## Installing on a PC

`hosts/dell` is the model: UEFI with systemd-boot, a LUKS-encrypted btrfs root with `home`
and `nix` subvolumes, and a separate encrypted swap partition big enough to hibernate into.
Intel and AMD machines install the same way.

1. `dd` the minimal x86_64 [NixOS ISO](https://nixos.org/download/) to a USB stick and boot
   it in UEFI mode, not legacy BIOS. Keep the stick: it is this host's recovery stick.
2. Partition the disk: an EFI system partition, swap at least the size of RAM so it can
   hold a hibernation image, and the rest for the system. This erases the disk.

   ```sh
   lsblk                                   # find the disk
   sgdisk --zap-all /dev/<disk>
   sgdisk -n1:0:+1G -t1:ef00 -c1:boot \
          -n2:0:+<swap-size> -t2:8309 -c2:swap \
          -n3:0:0 -t3:8309 -c3:system /dev/<disk>
   ```

3. Encrypt, format and mount. Each LUKS device asks for its passphrase.

   ```sh
   cryptsetup luksFormat /dev/disk/by-partlabel/system
   cryptsetup luksFormat /dev/disk/by-partlabel/swap
   cryptsetup open /dev/disk/by-partlabel/system system
   cryptsetup open /dev/disk/by-partlabel/swap swap
   mkfs.fat -F32 -n BOOT /dev/disk/by-partlabel/boot
   mkswap /dev/mapper/swap
   mkfs.btrfs -L lattice /dev/mapper/system
   mount /dev/mapper/system /mnt
   btrfs subvolume create /mnt/home && btrfs subvolume create /mnt/nix
   mount -o subvol=home /dev/mapper/system /mnt/home
   mount -o subvol=nix /dev/mapper/system /mnt/nix
   mkdir /mnt/boot && mount -o fmask=0077,dmask=0077 /dev/disk/by-partlabel/boot /mnt/boot
   swapon /dev/mapper/swap
   nixos-generate-config --root /mnt
   ```

4. Edit `/mnt/etc/nixos/configuration.nix`: systemd-boot,
   `networking.hostName = "lattice-<host>"`, NetworkManager, git, and a `winston` user with
   an `initialPassword`. The generated `hardware-configuration.nix` already has the LUKS
   devices and swap. Run `nixos-install` and reboot into it.
5. Clone lattice to `~/Documents/Projects/lattice`, then carry on with
   [Adding a host](#adding-a-host) from step 2.

Some things in `hosts/dell` are that laptop's, not every PC's. Copy it as a starting point
and keep what fits:

- `boot.resumeDevice` is what makes hibernation work, and what puts Hibernate in the power
  menu. Point it at the swap's `/dev/mapper/luks-…` name from `hardware-configuration.nix`.
- `intel-media-driver` is Intel's video decode. AMD needs nothing, because Mesa covers it.
- The hibernation delay, the Bluetooth workaround and `lattice.display.webZoom` were tuned
  for the Dell's hardware and screen.

## Adding a host

1. Install NixOS with a `winston` user, plus OpenSSH and the deploy key if the host is remote.
2. Copy its `hardware-configuration.nix` into `hosts/<host>/` and add a `default.nix` that
   imports `base.nix` and the modules you want. Register the host in `flake.nix`, and in
   `scripts/deploy.sh` too if it's remote.
3. Add the host's age key to `.sops.yaml`. For a remote host, from the admin machine:

   ```sh
   ssh-keyscan -t ed25519 <address> | nix develop -c ssh-to-age
   ```

   For a local one, run `scripts/rebuild.sh <host>` on the host itself. It stops at the
   recipient check and prints the key.
4. Re-encrypt the secrets on the admin machine, then commit and push:

   ```sh
   nix develop -c sops updatekeys secrets/common.yaml
   ```

5. Switch the host: `scripts/deploy.sh <host>` from the admin machine, or pull and run
   `scripts/rebuild.sh <host>` on the host. After that first switch, `lattice rebuild`
   and `lattice deploy` do the same.

## Installing on Apple Silicon

`hosts/mac` runs the Asahi kernel from
[nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) next to macOS.
It is installed from a minimal config first: the installer can only copy its own kernel,
and the host can't decrypt secrets until its key is a recipient. The project's
[install guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md)
has the details. In short:

1. In macOS, run the Asahi installer. Resize (`r`) to leave 500 GB free, then install (`f`)
   **UEFI environment only**, named `lattice`, and finish the permissive-security steps it
   prints in recovery.

   ```sh
   curl https://alx.sh | sh
   ```

2. `dd` the latest [release ISO](https://github.com/nix-community/nixos-apple-silicon/releases)
   to a USB stick and boot it. Keep the stick: it is this host's recovery stick.
3. Create a partition in the free space, and only there. Damaging the GPT, the first or
   last partition, or the APFS containers can leave the Mac unbootable.

   ```sh
   sgdisk /dev/nvme0n1 -n 0:0 -s    # then sgdisk -p for its number
   mkfs.btrfs -L lattice /dev/nvme0n1p<number>
   mount /dev/disk/by-label/lattice /mnt
   btrfs subvolume create /mnt/home && btrfs subvolume create /mnt/nix
   mount -o subvol=home /dev/disk/by-label/lattice /mnt/home
   mount -o subvol=nix /dev/disk/by-label/lattice /mnt/nix
   mkdir /mnt/boot
   mount /dev/disk/by-partuuid/$(cat /proc/device-tree/chosen/asahi,efi-system-partition) /mnt/boot
   nixos-generate-config --root /mnt
   ```

4. Edit `/mnt/etc/nixos/configuration.nix` as the guide says, plus
   `networking.hostName = "lattice-mac"`, NetworkManager, git, and a `winston` user with an
   `initialPassword`. Then run `nixos-install` and reboot into it.
5. On NixOS, clone lattice to `~/Documents/Projects/lattice` and copy
   `/etc/nixos/hardware-configuration.nix` over the one in `hosts/mac/`. Run
   `scripts/rebuild.sh mac`: it stops at the recipient check and prints the host's age key.
6. Back in macOS, add the key to `.sops.yaml`, run `updatekeys` (step 4 of
   [Adding a host](#adding-a-host)) and push.
7. Back on NixOS, pull, pin the firmware hash (see the comment in `hosts/mac/default.nix`)
   and run `scripts/rebuild.sh mac`. The first switch builds the kernel, so give it a while.

## Other hardware

lattice runs on the two machines in `hosts/`. Anything else is new ground.

- **Other 64-bit ARM machines** (UEFI boards, ARM virtual machines) have never been tried.
  The flake already builds for aarch64 and the Asahi parts stay in `hosts/mac`, so one should
  install like a PC on the mainline kernel. `widevine.nix` applies to every aarch64 host,
  but it has only been checked on the Mac.
- **Raspberry Pi** isn't supported. A Pi doesn't boot through UEFI and systemd-boot the way
  these hosts do, so it needs its own boot setup, and the desktop has never run on one. A
  Pi would suit the `server` profile better than `graphical`, though no host uses that
  profile yet.

## Next

- [Everyday use](using.md): the `lattice` command, rebuilding and switching themes.
- [Backups](backups.md): set up the backup drive before you need it.
