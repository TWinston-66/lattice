{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    inputs.apple-silicon.nixosModules.apple-silicon-support
    ../../modules/nixos/base.nix
    ../../modules/nixos/dotfiles.nix
    ../../modules/nixos/profiles/laptop.nix
    ../../modules/nixos/profiles/graphical.nix
  ];

  networking.hostName = "lattice-mac";
  system.stateVersion = "26.11";

  ### ASAHI ###
  hardware.asahi = {
    enable = true;

    # The Asahi installer leaves the Wi-Fi, Bluetooth and camera firmware on the ESP. It is
    # Apple's and can't go in a public repo, so it is pinned by hash rather than committed.
    #
    # It is read from /var/lib and not from /boot directly, because the ESP is mounted
    # fmask=0077 and so is root-only, while `nixos-rebuild --sudo` evaluates as the
    # invoking user -- every rebuild would die here on a permission error. Keeping a copy
    # in the store does not rescue it either: fetchTree stats the source path before it
    # consults the store or the fetcher cache, so a valid copy whose hash matches this pin
    # exactly is still never reached.
    #
    # So the readable copy is made by hand, once per firmware update (re-running the Asahi
    # installer from macOS changes it), and the narHash below re-pinned from it:
    #
    #   sudo install -d -m 0755 /var/lib/lattice
    #   sudo cp -rT /boot/vendorfw /var/lib/lattice/vendorfw
    #   sudo chmod -R a+rX /var/lib/lattice/vendorfw
    #   nix hash path /var/lib/lattice/vendorfw          # the new narHash
    #
    # The masks the ESP is mounted with leave nothing executable, and chmod's `X` only
    # restores search on directories, so the copy hashes the same as the original.
    peripheralFirmwareDirectory =
      (builtins.fetchTree {
        type = "path";
        path = "/var/lib/lattice/vendorfw";
        narHash = "sha256-wETBAOJSRK5XrfeTa+vqluv3M1RxIQdGpB+6zW+2mYw=";
      }).outPath;
  };

  boot.loader.systemd-boot = {
    enable = true;
    # The ESP the Asahi installer makes is only ~500MB, and it also holds m1n1 and the
    # firmware, so fewer kernels fit than on the Dell.
    configurationLimit = 3;
  };

  ### DISPLAY ###
  # The panel is 3024x1890 across 302x189mm, so 254ppi. Hyprland's "auto" picks scale 2,
  # which leaves a 1512x945 logical desktop at 127 logical DPI -- and everything sized in
  # logical pixels (waybar's 28px bar and 12px font, the 5/10 gaps, the 2px borders, the
  # 16px cursor, ghostty's font-size) is drawn against the 96 DPI convention, so at 2 it
  # all lands at 76% of the size it was drawn for. Firefox and LibreOffice looked right
  # only because both size content off the real DPI rather than the nominal one; they were
  # the reference, and the shell around them was the thing that was wrong.
  #
  # 2.25 gives 1344x840 at 113 logical DPI. It reads correctly without surrendering as
  # much screen area as the scale that would make logical pixels exactly nominal. The
  # scales this panel admits -- whole logical pixels, and a multiple of 1/120, see
  # modules/nixos/display.nix:
  #
  #   2     -> 1512x945  127 dpi        2.25  -> 1344x840  113 dpi
  #   2.1   -> 1440x900  121 dpi        2.625 -> 1152x720   97 dpi (nominal)
  #
  # `hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto",
  # scale = 2.1 })'` tries another live; it reverts on the next reload.
  lattice.display.monitors."eDP-1".scale = "2.25";

  # Gecko sizes both its chrome and its content in nominal pixels, so unlike LibreOffice's
  # true-to-paper page it grew with the scale above instead of staying put. Pinning
  # devPixelsPerPx decouples it from the desktop scale: 1.8 against 2.25 draws Firefox and
  # Thunderbird at 80% of what the scale alone would give them, landing a little under
  # where they sat at scale 2 -- which was already slightly large.
  #
  # The Dell sets the same pair the other way, at 1.1, because its panel takes scale 1 and
  # wanted Gecko nudged up rather than reined in. Status "default" rather than the module's
  # "locked", there and here, so the number stays adjustable from about:config.
  programs = {
    firefox = {
      preferences."layout.css.devPixelsPerPx" = "1.8";
      preferencesStatus = "default";
    };
    thunderbird = {
      preferences."layout.css.devPixelsPerPx" = "1.8";
      preferencesStatus = "default";
    };
  };

  ### KEYBOARD ###
  # The built-in keyboard is bound to hid-apple (HID 05AC:0352), which can swap the two
  # modifiers in the driver itself: the Cmd key beside the space bar then reports Ctrl, and
  # the Ctrl key in the corner reports Super. Cmd+C/V/X/A/Z/S/F/T/W/Q land under the thumb
  # where macOS puts them, in every application, while Hyprland keeps all of its SUPER
  # binds on the letters and numbers they already use. The two modifiers stay functionally
  # distinct, so nothing is contended and no keymapper daemon -- Toshy, xremap -- is needed.
  #
  # What a swap cannot reproduce is macOS having two separate keys for this: there Cmd+C
  # copies while Ctrl+C interrupts. With a single Ctrl serving both, copying in ghostty is
  # Ctrl+Shift+C and SIGINT sits on the Cmd-position key. That one case is the only thing
  # that would justify an app-aware remapper on top of this.
  #
  # hid-apple binds only Apple HID devices, so a non-Apple keyboard on the dock keeps its
  # normal modifiers. Writing to /sys/module/hid_apple/parameters/swap_ctrl_cmd flips it
  # live, without a rebuild, which is how this was settled on.
  boot.extraModprobeConfig = "options hid_apple swap_ctrl_cmd=1";

  ### BTRFS ###
  fileSystems = lib.genAttrs [ "/" "/home" "/nix" ] (_: {
    options = [
      "compress=zstd"
      "noatime"
    ];
  });

  systemd.tmpfiles.rules = [ "v /home/.snapshots 0750 root users -" ];

  services = {
    btrfs.autoScrub.enable = true;

    snapper.configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "winston" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 12;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };

    tailscale.enable = true;
  };

  # As on the Dell: lets the bar's Tailscale pill run `tailscale up`/`down` without sudo.
  systemd.services.tailscale-operator = {
    description = "Allow winston to operate tailscaled without sudo";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale set --operator=winston";
    };
  };

  ### DOCKER ###
  virtualisation.docker.enable = true;

  ### VIRTUALIZATION ###
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.users.winston.extraGroups = [
    "docker"
    "libvirtd"
  ];
}
