# Backups

Any host the drive labelled `lattice-backup` is plugged into backs itself up: as soon as
it's plugged in, then hourly. Every host goes into one encrypted, deduplicated restic
repository, read from btrfs snapshots so each copy is consistent. Backups cover the whole
machine except what the flake rebuilds, so a reinstall plus a restore puts it back as it was.

A bar pill shows progress and failures. A week without a backup turns it orange and sends
a daily reminder.

> [!IMPORTANT]
> The repository password is `restic-password` in sops, and a copy is in Bitwarden. The
> Bitwarden copy is the one that counts: a lost machine takes its host key, and so its
> sops copy, with it.

## Day to day

```sh
lattice backup status     # when this machine last backed up, and the drive's state
lattice backup now        # back up now
lattice backup check      # read every backup back to verify it
lattice backup stop       # stop a running backup; the next one carries on
lattice backup eject      # stop everything, unmount and power off the drive
```

## Getting files back

```sh
lattice backup browse     # mount every backup as folders; prints where
lattice backup unbrowse   # unmount them again
```

Copy what you need out of the mounted snapshots like any other folder.

## Setting up a drive

> [!WARNING]
> This erases the drive. Use its `/dev/disk/by-id` name so it's the right disk.

1. Set the repository password. This happens once, ever; save it in Bitwarden afterwards.

   ```sh
   scripts/set-backup-password.sh
   ```

2. Partition and format the drive:

   ```sh
   sudo wipefs -a /dev/disk/by-id/<drive>
   echo 'label: gpt
   type=linux, name=lattice-backup' | sudo sfdisk /dev/disk/by-id/<drive>
   sudo mkfs.btrfs -L lattice-backup /dev/disk/by-id/<drive>-part1
   ```

3. Plug it in. The first backup creates the repository.

A second drive formatted the same way works too, with its own repository.

## Restoring a machine

This puts back everything but `/nix` and `/boot`, which the install recreates.

1. Commit and push any config the new install needs, such as a new
   `hardware-configuration.nix`.
2. Install as usual, up to the point where the new system is mounted at `/mnt`. Then
   mount the drive and put the old host keys back first, so sops decrypts with the key it
   already knows. The password is in Bitwarden.

   ```sh
   mount /dev/disk/by-label/lattice-backup /media
   export RESTIC_REPOSITORY=/media/restic
   nix run nixpkgs#restic -- snapshots --host <hostname>
   nix run nixpkgs#restic -- restore latest --host <hostname> --include /etc/ssh --target /mnt
   ```

3. Install from the flake, then restore everything else over it. `/etc/static` is left out
   because it points into the old store; the first activation relinks it.

   ```sh
   nixos-install --flake .#<host>
   nix run nixpkgs#restic -- restore latest --host <hostname> --target /mnt --exclude /etc/static
   ```

4. Boot, `git pull` in the restored checkout, and run `lattice rebuild`.
