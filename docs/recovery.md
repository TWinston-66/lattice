# Recovery

Root is locked and passwords only come from sops, so a host that can't decrypt its
secrets locks you out entirely. The fix is to make the secrets readable again, or to set
a new password, and reinstall over the top from a USB stick.

> [!TIP]
> Keep the lattice installer stick from [installing](install.md#installing) around: it is
> this machine's recovery stick.

## Locked out

1. Boot the stick. `cryptsetup open` the LUKS devices if the host has any, and mount the
   system under `/mnt`.
2. From an admin machine, do one of these:
   - Add the host's key, from `/mnt/etc/ssh/ssh_host_ed25519_key.pub`, to `.sops.yaml` and
     run `nix develop -c sops updatekeys secrets/common.yaml`.
   - Set a new password with `scripts/set-password.sh`.

   Commit and push either way.
3. Back on the stick, reinstall from a checkout with the fix. The flake reads the firmware
   from `/var/lib/lattice/vendorfw` on the system doing the install, so copy it there first:

   ```sh
   sudo mkdir -p /var/lib/lattice
   sudo cp -rT /mnt/var/lib/lattice/vendorfw /var/lib/lattice/vendorfw
   sudo nixos-install --root /mnt --flake .#<host> --no-root-passwd
   ```

4. Reboot and log in.

## Lost the machine entirely

Install a fresh host as in [Installing lattice](install.md), then follow
[Restoring a machine](backups.md#restoring-a-machine) to put its files back.
