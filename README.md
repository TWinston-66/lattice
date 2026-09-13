# lattice

My NixOS configuration, as a flake.

A small, boring core that every machine gets, with everything else layered on through profiles. 

## Deploying

From any machine with Nix and the SSH key:

```sh
scripts/deploy.sh [host] [ip]
```

The flake is evaluated locally, then built and activated on the target, so the
target does not need a copy of this repo. Each host has a default IP in the
script; pass one to override it. SSH host keys are pinned to the host name
rather than the IP, so a changed address can't silently point a deploy at a
different machine. You'll be asked for the sudo password during activation.

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
nix shell nixpkgs#sops -c sops secrets/common.yaml
```

## Adding a host

1. Install NixOS with the stock installer. Enable OpenSSH, and give your user
   the deploy SSH key and a password so the first deploy can use sudo.
2. Copy the generated `hardware-configuration.nix` into `hosts/<host>/` and
   write a `default.nix` that imports `base.nix` and the profiles you want.
   Add the host to `nixosConfigurations` in `flake.nix` and to the `case` in
   `scripts/deploy.sh`.
3. Let the host decrypt secrets. Get the age key for its SSH host key:

   ```sh
   ssh-keyscan -t ed25519 <ip> | nix shell nixpkgs#ssh-to-age -c ssh-to-age
   ```

   Add it to `.sops.yaml`, then re-encrypt:

   ```sh
   nix shell nixpkgs#sops -c sops updatekeys secrets/common.yaml
   ```

   Do this before the first deploy. Passwords only come from sops, so a host
   that can't decrypt them ends up with no working sudo.
4. Run `scripts/deploy.sh <host>`.

## License

[MIT](LICENSE)
