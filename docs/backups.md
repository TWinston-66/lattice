# Backups

Any host the drive labelled `lattice-backup` is plugged into backs itself up: as soon as
it's plugged in, then hourly. Every host goes into one encrypted, deduplicated restic
repository, read from btrfs snapshots so each copy is consistent. Backups cover the whole
machine except what the flake rebuilds, so a reinstall plus a restore puts it back as it was.

A bar pill shows progress and failures; right-click it to eject the drive or browse the
backups. A week without a backup turns it orange and sends a daily reminder.

Pulling the drive out mid-backup is safe. The run stops, the backups already on the drive
are untouched, and the next time it's plugged in the interrupted backup starts again.

> [!IMPORTANT]
> Keep the repository password in a password manager. On a host with sops it is also
> `restic-password` in the secrets, but the password manager's copy is the one that counts:
> a lost machine takes its host key, and so its sops copy, with it.

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

1. Set the repository password. This happens once, ever; save it in your password manager
   afterwards. On a host with sops, this stores it in the secrets and copies it to the
   clipboard:

   ```sh
   scripts/set-backup-password.sh
   ```

   On a host without sops, put it in a root-only file instead, and do the same on each
   host that shares the drive:

   ```sh
   sudo install -D -m 400 /dev/stdin /var/lib/lattice-backup/password <<<'<password>'
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

This puts back everything but `/nix` and `/boot`, which the install recreates. The new
install makes its own SSH host key, so the old one stays out of it.

1. Commit and push any config the new install needs. The installer clones the flake fresh,
   so anything only in the old checkout is lost.
2. Install as usual with `sudo lattice-install`. When it says lattice is installed, don't
   reboot yet: the new system is still mounted at `/mnt`.
3. Plug in the drive and restore over the new system. restic asks for the repository
   password. `/etc/ssh` and the flake checkout keep the install's, and `/etc/static` points
   into the old store, so all three are left out.

   ```sh
   sudo mount /dev/disk/by-label/lattice-backup /media
   export RESTIC_REPOSITORY=/media/restic
   sudo -E nix run nixpkgs#restic -- snapshots --host <hostname>
   sudo -E nix run nixpkgs#restic -- restore latest --host <hostname> --target /mnt \
     --exclude /etc/ssh --exclude /etc/static --exclude /home/<user>/lattice
   ```

   If `modules/personal` keeps the flake somewhere else, exclude that path instead of
   `~/lattice`. On a host without sops, the restore also puts the backup password back in
   `/var/lib/lattice-backup/password`.
4. Reboot, commit and push what the installer staged, and run `lattice rebuild`.
