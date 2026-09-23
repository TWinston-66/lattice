{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Named rather than inlined because the grace period appears in the log line, the
  # notification and the timer, and the transient unit's name appears in both the timer and
  # the cancel instruction the notification prints.
  sleepGuard = {
    unit = "lattice-sleep-taint-guard";
    powerOffUnit = "lattice-taint-poweroff";
    user = "winston";
    graceSeconds = 10;
  };
in
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

  # The night-light default of 4000K, which is plainly warm on the Dell's sRGB panel,
  # barely registers on this one -- it is wide-gamut and far brighter, so the same
  # transform is a much smaller share of what the panel can show. 2800K puts the shift
  # back where the Dell has it.
  lattice.display.sunsetTemperature = 2800;

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

  ### TRACKPAD ###
  # The pad is a clickpad -- one physical button under the whole surface, BTN_LEFT the only
  # key code it reports -- so which button a press *means* is libinput's to decide. That
  # half is settled in the hypr dotfiles (clickfinger_behavior), which counts fingers the
  # way macOS does instead of cutting the bottom of the pad into invisible zones.
  #
  # Counting fingers only works if libinput knows which contacts are fingers, and that is
  # what this file is for. libinput 1.31 already carries a match for this device:
  #
  #   [Apple Laptop Touchpad (MTP)]   MatchName=Apple*MTP*  MatchVendor=0x05AC
  #   ModelAppleTouchpad=1  AttrSizeHint=104x75  AttrPalmSizeThreshold=1600
  #   AttrTouchSizeRange=150:130
  #
  # -- but it sets no thumb threshold at all, and its numbers were carried over from the
  # Intel bcm5974 and SPI pads. This one is a different controller reached through
  # hid-magicmouse, with its own ABS_MT_TOUCH_MAJOR scale (0..5000, though palms overshoot
  # the declared max and reach ~7700), so they were worth re-measuring rather than
  # trusting. Recorded with `libinput record` and analysed per contact -- peak
  # ABS_MT_TOUCH_MAJOR over each tracking id, ~10 contacts per gesture:
  #
  #   fingertip   388 .. 526     (minor 716..932)
  #   thumb       852 .. 1300    (one light outlier at 366)
  #   palm       3314 .. 7754    (plus fingers that land alongside, 246..590)
  #
  # Three clusters with two empty bands between them, which is what makes the two
  # thresholds below obvious rather than tuned. 700 sits 174 above the largest fingertip
  # and 152 below the lightest real thumb; 1800 sits 500 above the largest thumb and far
  # under the smallest real palm -- anything from 1400 to 3000 would behave identically on
  # this data, so the exact number is not load-bearing.
  #
  # The thumb one is the fix that matters. Without it a thumb resting low on the pad counts
  # as an ordinary finger, and under clickfinger that turns every click into a right-click
  # -- so enabling clickfinger without this would have traded one vague click for another.
  # It also keeps a resting thumb out of the two-finger scroll and tap counts.
  #
  # Deliberately absent: AttrPressureRange, AttrPalmPressureThreshold,
  # AttrThumbPressureThreshold. The pad does report ABS_MT_PRESSURE (0..6000) and the
  # obvious guess is that a palm presses harder, but measured it does not separate at all
  # -- fingertip 41..248, thumb 15..231, palm 0..498, three ranges sitting on top of one
  # another. Worse, pressure reads 0 on the first frames of a real touch, so handing
  # libinput a pressure range would move touch-down detection onto an axis that would drop
  # light taps. Size is the only axis on this device that carries the signal.
  #
  # AttrSizeHint is corrected here only as insurance. The kernel reports a resolution on
  # ABS_X/ABS_Y (98 and 97 units/mm, giving a true 125x77mm), and libinput consults the
  # hint only when resolution is missing, so today this line is inert -- but 104x75 is a
  # 20% error that would silently misplace the edge palm zones if a kernel ever stopped
  # reporting it.
  #
  # Re-measure with the libinput below, which is here for that and nothing else:
  #
  #   sudo libinput record -o /tmp/pad.yml /dev/input/event2
  #   sudo libinput debug-events --verbose        # what libinput decided at init
  #
  # `libinput quirks list /dev/input/event2` prints the merged result of this file and the
  # shipped one, which is the quickest check that a change here was actually picked up.
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Apple Laptop Touchpad (MTP) lattice-mac]
    MatchUdevType=touchpad
    MatchName=Apple*MTP*
    MatchVendor=0x05AC
    AttrSizeHint=125x77
    AttrPalmSizeThreshold=1800
    AttrThumbSizeThreshold=700
  '';

  environment.systemPackages = [ pkgs.libinput ];

  ### BLUETOOTH ###
  # hci_bcm4377 does not always survive an s2idle resume. The controller comes back deaf:
  # every HCI command times out, and the kernel's own attempt to power the radio down and
  # bring it back fails the same way, so the DMA rings are never torn down and the device
  # stays wedged with the adapter unpowered.
  #
  #   Bluetooth: hci0: command 0x0c01 tx timeout
  #   Bluetooth: hci0: Opcode 0x2041 failed: -110
  #   Bluetooth: hci0: Error when powering off device on rfkill (-110)
  #   hci_bcm4377 0000:01:00.1: failed to destroy transfer ring 6
  #
  # bluetoothd is healthy throughout -- it just reports `Failed to set mode: Failed (0x03)`
  # and `Powered: no` against `PowerState: on` -- so restarting the service does nothing.
  # Reloading the module is the only thing that clears it.
  #
  # This is not the Dell's hibernate bug wearing another driver. There btintel_pcie fails
  # going *into* hibernate and the fix is to unload it beforehand; here the chip fails
  # coming *out* of ordinary suspend. That service could not fire on this host in any
  # case: /sys/power/disk is [disabled] and the only swap is zram, so none of the
  # hibernate targets it binds to ever run.
  #
  # The fault is intermittent -- one resume in ten on 2026-09-20, and the cycle that broke
  # was an unusually short 11s one -- which is why the module is not simply unloaded before
  # every sleep the way the Dell's is. That would drop the mouse and the headphones on nine
  # healthy resumes to rescue the tenth. Instead the controller is asked for its local
  # version on the way back. That is a round trip to the chip, which is the point:
  # `btmgmt info` is answered by the kernel's mgmt socket from cached state and calls a
  # dead controller healthy. A live one replies in ~5ms; a wedged one never replies at all.
  powerManagement.resumeCommands = ''
    ${pkgs.util-linux}/bin/rfkill list bluetooth -no SOFT | ${pkgs.gnugrep}/bin/grep -q unblocked || exit 0

    # The adapter re-registers a moment after the resume hooks run, so a missing hci0 here
    # means "not back yet", not "absent". Only give up once it has stayed missing.
    n=0
    while [ ! -d /sys/class/bluetooth/hci0 ]; do
      n=$((n + 1))
      [ "$n" -ge 20 ] && exit 0
      sleep 0.5
    done

    # hcitool waits on the raw HCI socket for the reply with no timeout of its own. A
    # wedged controller never sends one -- the kernel's 10s tx timeout is internal and
    # synthesises no event -- so the bare call blocks forever and systemd kills the whole
    # script at TimeoutStopSec before the reload below is ever reached. Bound it.
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.bluez}/bin/hcitool -i hci0 cmd 0x04 0x0001 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -q '^> HCI Event' && exit 0

    echo "hci0 did not answer Read Local Version after resume; reloading hci_bcm4377"
    ${pkgs.kmod}/bin/modprobe -r hci_bcm4377 || true
    ${pkgs.kmod}/bin/modprobe hci_bcm4377 || true
  '';

  ### SUSPEND GUARD ###
  # On 2026-09-22 this machine went into s2idle and never came back:
  #
  #   Sep 21 21:41:04  PM: suspend entry (s2idle)
  #   Sep 22 08:50:45  PM: suspend exit           <- eleven hours, clean
  #   Sep 22 10:39:03  PM: suspend entry (s2idle)
  #   <journal ends here; unclean reboot at 12:32>
  #
  # No `suspend exit`, no systemd-shutdown, nothing flushed after the entry line. The SoC
  # stayed awake with the fans idle in a closed bag for nearly two hours.
  #
  # s2idle is not the problem and there is no alternative to it in any case: it is the only
  # state Asahi has, /sys/power/disk is [disabled] and the only swap is zram, so
  # suspend-then-hibernate cannot exist here the way it does on the Dell. What the suspend
  # could not survive was the state the kernel was already in. Three Oopses that morning,
  # all identical:
  #
  #   pc : get_pd_product_type+0x5c/0xc0 [typec]
  #   Call trace: get_pd_product_type -> dev_attr_show -> sysfs_kf_seq_show -> vfs_read
  #
  # -- reading a file under /sys/class/typec while a USB-C partner was being torn down by
  # the re-enumeration loop on xhci-hcd.4.auto. Each died inside kernfs_fop_read_iter
  # holding a kernfs active reference and of->mutex that are never released, so the kernel
  # carried the D taint from 09:08 onward and the 10:39 suspend was the first one after it.
  #
  # Powering off rather than merely refusing is the point of this. A bare refusal leaves the
  # lid closed over a fully awake desktop session, which is the same bag and rather more
  # heat than the hang produced.
  systemd.services.${sleepGuard.unit} = {
    description = "Power off instead of sleeping on a kernel that has already Oopsed";

    # RequiredBy=, not the WantedBy= that nixpkgs' own sleep-actions.service uses: a failing
    # Wants= dependency does not fail the target, and failing the target is the entire
    # mechanism. systemd-suspend.service carries `Requires=sleep.target` and
    # `After=sleep.target`, so once sleep.target fails the suspend is never reached.
    before = [ "sleep.target" ];
    requiredBy = [ "sleep.target" ];

    path = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.systemd
      pkgs.util-linux
    ];

    serviceConfig.Type = "oneshot";

    script = ''
      # /proc/sys/kernel/tainted is a bitmask, and this host is *always* tainted: Asahi runs
      # the CPU outside Apple's published spec, so bit 2 (TAINT_CPU_OUT_OF_SPEC -- the `S` in
      # every Oops header above) is set from boot and the file reads 4 on a perfectly healthy
      # system. Testing for nonzero would power the laptop off on every suspend it ever took.
      # Only bit 7, TAINT_DIE, means die() actually ran. Bit 9 (TAINT_WARN) is deliberately
      # not included: a WARN_ON leaves no lock behind and is far too common to act on.
      tainted=$(cat /proc/sys/kernel/tainted)
      if [ $(( tainted & 128 )) -eq 0 ]; then
        exit 0
      fi

      echo "kernel carries TAINT_DIE (tainted=$tainted); refusing to sleep, powering off in ${toString sleepGuard.graceSeconds}s"

      # Best effort, and never allowed to fail the guard. A system unit has no session bus of
      # its own, so the notification is handed to the user's by address; with nobody logged in
      # the socket is simply absent and there is no one to tell anyway.
      bus="/run/user/$(id -u ${sleepGuard.user})/bus"
      if [ -S "$bus" ]; then
        runuser -u ${sleepGuard.user} -- \
          env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
          notify-send -a lattice-sleep -u critical -i dialog-error \
            "Kernel has Oopsed" \
            "Sleeping is unsafe on this kernel. Powering off in ${toString sleepGuard.graceSeconds}s.
      Cancel with: systemctl stop ${sleepGuard.powerOffUnit}.timer" || true
      fi

      # Detached onto a timer rather than called straight out. logind refuses a poweroff while
      # a sleep operation is in flight -- the same thing that made wlogout's Shut down button
      # answer "Action suspend already in progress", see HandlePowerKey in the laptop profile
      # -- and this unit *is* that sleep operation until it exits. The delay lets the failed
      # sleep.target transaction unwind first, and doubles as the window the notification
      # offers for cancelling.
      systemd-run --quiet --unit=${sleepGuard.powerOffUnit} \
        --on-active=${toString sleepGuard.graceSeconds} \
        systemctl poweroff

      exit 1
    '';
  };

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
