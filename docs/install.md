# Installing lattice

lattice runs on Apple Silicon MacBooks (the M1 and M2 generations that
[Asahi Linux](https://asahilinux.org) supports), next to macOS. Every lattice machine is a
host in the flake: a folder under `hosts/`, built from the distro in `modules/nixos`.

## Installing

1. In macOS, run the Asahi installer. Resize (`r`) to leave the space you want for lattice
   (40 GiB at the very least), then install (`f`) **UEFI environment only**, named `lattice`,
   and finish the permissive-security steps it prints in recovery.

   ```sh
   curl https://alx.sh | sh
   ```

2. Get the lattice installer, `lattice-<version>-apple-silicon.iso`, from the
   [releases](https://github.com/TWinston-66/lattice/releases), or
   [build it](#building-the-installer). Write it to a USB stick (this erases the stick) and
   boot the Mac from it. Keep the stick: it is this machine's [recovery](recovery.md) stick.

   ```sh
   sudo dd if=lattice-<version>-apple-silicon.iso of=/dev/<stick> bs=4M status=progress oflag=sync
   ```

3. Run:

   ```sh
   sudo lattice-install
   ```

   With no network yet, it opens `nmtui` to join Wi-Fi, and the network it joins is kept on
   the installed system. It asks whether to install the personal setup in
   `modules/personal` (see [Secrets](#secrets-optional) below), a machine name, your user
   name and password, a disk passphrase, a time zone and a git URL for your dotfiles
   (cloned to `~/.dotfiles`, with its `dotfiles.sh` run if it has one), then where to put lattice: the free space the Asahi installer left, or a Linux
   partition from an earlier install, which it erases. Apple's partitions, the ESP and the
   partition table are never touched. Nothing is written until you type `yes` at the summary.

   From there it runs on its own: it encrypts the partition (LUKS2) with btrfs inside, copies
   Apple's firmware off the ESP and pins its hash, writes `hosts/<name>` from `hosts/macbook`,
   and installs. Most of the system comes from lattice's binary cache. If the Asahi kernel
   isn't in it, the kernel is compiled during the install, which takes a while.

4. Take out the stick and reboot. If macOS comes up, hold the power button at startup and
   pick lattice. The disk passphrase comes first, then the login.

The flake is in `~/lattice` (or where `modules/personal` keeps it), with the new host
staged but not committed. Commit it, and from
then on `lattice rebuild` applies changes. A log of the install is in
`/var/log/lattice-install.log`.

## Building the installer

On an aarch64 Linux machine with Nix, from a checkout of lattice:

```sh
nix build .#installer
```

The ISO is in `result/iso/`. It boots the same kernel a lattice host runs, so on a lattice
machine this builds in a minute or two; anywhere else, the kernel is compiled first. An ISO
built from a tree with uncommitted changes installs that tree; one built from a commit clones
lattice at that commit.

`scripts/installer-vm.sh` boots it in a virtual machine on a lattice Mac, against a disk laid
out the way the Asahi installer leaves one, and `sudo lattice-install --esp /dev/vda1` there
runs the whole install. `scripts/installer-vm.sh --boot` then starts what it installed. The
VM has no 3D acceleration, so the wallpaper fails to start in it; nothing else differs.

## Secrets (optional)

`hosts/mac` is the author's machine, and shows the other way to run a host: the password and
the service tokens in [sops](https://github.com/getsops/sops), via `modules/personal`. With
`lattice.user.hashedPasswordFile` set, users are immutable and the password lives only in the
flake; `scripts/rebuild.sh` then refuses to switch until the host's age key is a recipient of
`secrets/common.yaml`, since otherwise it would boot with every account locked.

Answering yes to the personal setup does that at install time: the account, its password and
the time zone come from `modules/personal` instead of being asked for, and so do the
dotfiles (`lattice.user.dotfiles`). The installer looks
for the admin age key, `sops-age-keys.txt`, at the top of any USB drive and checks that it
opens the secrets, makes the new host's SSH key, adds it to `.sops.yaml` and re-encrypts
`secrets/common.yaml`. The admin key stays in RAM and is never written to the new disk;
`.sops.yaml` and `secrets/common.yaml` are left staged next to the host, to commit and push.

## Next

- [Everyday use](using.md): the `lattice` command, rebuilding and switching themes.
- [Backups](backups.md): set up the backup drive before you need it.
