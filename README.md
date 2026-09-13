# lattice

My NixOS configuration, as a flake.

A small, boring core that every machine gets, with everything else layered on through profiles.

## Updating a host

Hosts with remote access (`remote-managed.nix`) can be deployed from any
machine with Nix and the SSH key:

```sh
scripts/deploy.sh [host] [ip]
```

The flake is evaluated locally, then built and activated on the target, so the
target does not need a copy of this repo. Each host has a default IP in the
script; pass one to override it. SSH host keys are pinned to the host name
rather than the IP, so a changed address can't silently point a deploy at a
different machine. You'll be asked for the sudo password during activation.

Any host can also rebuild itself from a checkout of this repo:

```sh
scripts/rebuild.sh [host]
```

The host defaults to the machine's hostname without the `lattice-` prefix.

Both scripts refuse to switch a host that can't decrypt its secrets, since it
would come up with every account locked. The scripts get their tools from the
flake's dev shell; run `nix develop` to use them yourself.

## Secrets

Secrets are encrypted with [sops-nix](https://github.com/Mic92/sops-nix).
`.sops.yaml` lists who can decrypt them: admins, with an age key at
`~/.config/sops/age/keys.txt`, and each host, using its SSH host key.

Set or change a login password:

```sh
scripts/set-password.sh [user]
```

Edit secrets directly:

```sh
nix develop -c sops secrets/common.yaml
```

## Adding a host

1. Install NixOS with the stock installer, with a user named `winston`. For a
   host with remote access, enable OpenSSH and give that user the deploy SSH
   key and a password so the first deploy can use sudo.
2. Copy the generated `hardware-configuration.nix` into `hosts/<host>/` and
   write a `default.nix` that imports `base.nix` and the profiles you want.
   Add the host to `nixosConfigurations` in `flake.nix`, and for remote access
   to the `case` in `scripts/deploy.sh`.
3. Let the host decrypt secrets. Get the age key for its SSH host key. For a
   host with remote access:

   ```sh
   ssh-keyscan -t ed25519 <ip> | nix develop -c ssh-to-age
   ```

   For any other host, clone this repo on it (`nix-shell -p git` has git on a
   stock install) and run `scripts/rebuild.sh <host>`. It creates the host key
   if needed and prints the age key.

   Add it to `.sops.yaml`, then re-encrypt from a machine with an admin key:

   ```sh
   nix develop -c sops updatekeys secrets/common.yaml
   ```

4. Run `scripts/deploy.sh <host>`, or `scripts/rebuild.sh <host>` on the host
   after pulling the re-encrypted secrets.

## Recovery

Keep a NixOS USB stick around. Passwords only come from sops, root is locked,
and there's no emergency shell, so if a host can't decrypt its secrets or you
forget its password, nothing on the machine will let you in.

1. Fix the cause from a machine with an admin key: add the host's age key to
   `.sops.yaml` and run `updatekeys`, or set a new password with
   `scripts/set-password.sh`. A host's public key is at
   `/etc/ssh/ssh_host_ed25519_key.pub` on its disk.
2. Boot the USB stick, unlock the LUKS devices with `cryptsetup open`, and
   mount the host's file systems under `/mnt` as `hardware-configuration.nix`
   describes.
3. Reinstall the fixed configuration from a checkout of this repo:

   ```sh
   sudo nixos-install --root /mnt --flake .#<host> --no-root-passwd \
       --option experimental-features 'nix-command flakes'
   ```

## License

[MIT](LICENSE)
