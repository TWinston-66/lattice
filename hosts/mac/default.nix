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

  # The Samsung on the desk. Pinned per-host rather than left to the desc-keyed rule in
  # ~/.dotfiles, so it can be tuned against this laptop without dragging the Dell along --
  # it happens to agree with that rule's 1.5 today, which is why the value looks redundant.
  #
  # Set by eye, and the first attempt at setting it by arithmetic is worth recording as a
  # dead end. Matching the panel above on *logical dpi* -- 3840x2160 across 700x390mm is
  # 139 dpi native, so scale 1.25 lands 3072x1728 at 111 dpi against the panel's 113 -- is
  # a clean geometric match and reads far too small in practice. Equal logical dpi means
  # equal size in millimetres, and millimetres are not what the eye judges: a 32" monitor
  # sits most of an arm further away than a laptop panel, so matched physical size comes
  # out visibly smaller. Apparent size is the target, and viewing distance is a property of
  # the desk, not of either display, so there is no number here to derive. The scales this
  # monitor admits, on the usual two constraints (whole logical pixels, and a multiple of
  # 1/120, see modules/nixos/display.nix):
  #
  #   1.25 -> 3072x1728  (matches the panel in mm -- too small)
  #   1.5  -> 2560x1440  (22% larger than the panel in mm)
  #   1.6  -> 2400x1350  (30% larger)
  #   1.666667 -> 2304x1296  (35% larger)
  #
  # `hyprctl eval 'hl.monitor({ output = "desc:Samsung Electric Company U32R59x", mode =
  # "preferred", position = "auto", scale = 1.6 })'` tries another live; it reverts on the
  # next reload.
  lattice.display.monitors."desc:Samsung Electric Company U32R59x".scale = "1.5";

  # The built-in HDMI port lights that Samsung exactly once per boot. Every replug after
  # the first leaves it dark *and* stalls the whole desktop, ~10s per frame, for as long as
  # the cable is in -- badly enough that Hyprland stops answering hyprctl on its IPC
  # socket, so nothing in userspace can drive a recovery. Unplugging is the only way out.
  #
  # The cause is a missing modeset, not a missing signal. EDID reads fine over DDC the
  # whole time (39 modes, right make/model/serial), so from userspace the output looks
  # live. In the driver, set_digital_out_mode() -- the only thing that sets dcp->valid_mode
  # -- is called from dcp_crtc_atomic_modeset(), and *that* is reached only from
  # apple_crtc_atomic_enable() (apple_drv.c), which the atomic helpers call only when a
  # CRTC goes off->on in a modeset commit. Plain page-flips never reach it. On a replug
  # there is no such transition, so the modeset is never even attempted: the logs carry no
  # set_digital_out_mode line at all, failing or otherwise, where the working first plug
  # has `set_digital_out_mode finished:2064`. With valid_mode still 0 the firmware accepts
  # each swap and throws it away ("swallowed swap ... as fControllerPowerState is 0" /
  # "... as timinsg are not enabled"), the swap_complete callback never comes, and every
  # commit burns the full 10s in wait_for_flip_done -- which is the stall, and which is
  # also what keeps userspace from ever getting round to the modeset that would fix it.
  #
  # This patch breaks that loop at the one place it can be broken from inside the kernel:
  # while valid_mode is 0, dcp_flush() completes the frame through the delayed vblank work
  # instead of waiting on a swap the firmware has already discarded -- the same fallback
  # the busy-command-channel branch immediately above it already uses. The stalls go away,
  # so the compositor stays responsive and its own disable/enable of the output can land.
  #
  # Carried locally, from AsahiLinux/linux PR #622 (commit 8890ede, "drm/apple: Complete
  # swaps the DCP discards before a modeset"). Upstream closed it under the project's
  # generative-AI policy rather than on anything technical, so it will not arrive in this
  # form and this file is where it lives for now. It applies to asahi-7.1.13-3, where
  # dcp_flush() sits at drivers/gpu/drm/apple/iomfb.c:461; re-check it on every kernel
  # bump, because a bump will not bring it along. hardware.asahi wires boot.kernelPatches
  # into the linux-asahi override itself (modules/kernel/default.nix), so the stock NixOS
  # option is all this needs. Unbinding 289c00000.dcp -- the dcpext that drives HDMI, and a
  # separate device from the internal panel's 389c00000.dcp -- looks like it should reset
  # this port on its own, but dcp.c tears the device down with component_del(), which takes
  # the apple-drm component master and all of card1 (eDP included) with it, so it is not a
  # recovery path. Related upstream reports: AsahiLinux/linux#625 (same dcpext, same
  # swallowed-swap signature on a j416s) and #634.
  boot.kernelPatches = [
    {
      name = "drm-apple-complete-swallowed-swaps";
      patch = ./patches/drm-apple-complete-swallowed-swaps.patch;
    }
  ];

  # The night-light default of 4000K, which is plainly warm on the Dell's sRGB panel,
  # barely registers on this one -- it is wide-gamut and far brighter, so the same
  # transform is a much smaller share of what the panel can show. 2800K puts the shift
  # back where the Dell has it.
  lattice.display.sunsetTemperature = 2800;

  # Gecko sizes both its chrome and its content in nominal pixels, and devPixelsPerPx pins
  # that to an absolute ratio rather than to a multiple of the desktop scale -- so a single
  # number cannot be right on two monitors at once. The old 1.8 was tuned against this
  # panel's 2.25; on the Samsung at 1.5 the same pin drew Gecko at 1.2x that output's
  # native size, half again as large as it was meant to be, while ghostty and waybar
  # tracked the output correctly because they read the per-output scale. -1 hands the
  # choice back to the compositor, so Gecko follows whichever monitor the window is on and
  # re-scales as it moves between them.
  #
  # The 80% the pin used to buy back is recovered instead from levers that are proportional
  # rather than absolute, so they hold docked, undocked, and on either screen:
  #   - content: default zoom 80%. Gecko keeps this per profile in content-prefs.sqlite as
  #     browser.content.full-zoom and exposes no pref for it, so it cannot be set from
  #     here -- it is Settings > General > Zoom if the profile is ever rebuilt.
  #   - chrome: compact uidensity, plus the stylesheet below for what compact leaves alone.
  #
  # The Dell still pins 1.1 against its scale 1. One panel, so the ratio cannot drift there,
  # but it would break in exactly this way the first time that machine is docked. Status
  # "default" rather than the module's "locked", there and here, so the numbers stay
  # adjustable from about:config.
  programs = {
    firefox = {
      preferences = {
        "layout.css.devPixelsPerPx" = "-1";
        "browser.uidensity" = 1;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
      preferencesStatus = "default";
    };
    # Nothing compensates on this side yet: Thunderbird loses the pin's shrink and so draws
    # larger on this panel than it used to, until mail.uidensity -- whose values are ordered
    # differently from browser.uidensity -- and a stylesheet of its own are worked out.
    thunderbird = {
      preferences."layout.css.devPixelsPerPx" = "-1";
      preferencesStatus = "default";
    };
  };

  # The NixOS firefox module has no userChrome option and there is no home-manager here, so
  # the stylesheet is linked into the profile directly. That profile directory name is
  # generated at first run and is derivable from nothing in this file: a new profile means
  # this path has to be updated, and until it is the stylesheet stops applying silently.
  systemd.user.tmpfiles.rules =
    let
      profile = "%h/.config/mozilla/firefox/uk8qrdih.default";
      userChrome = pkgs.writeText "lattice-firefox-userChrome.css" ''
        /* Chrome font. Much of the chrome -- the vertical tab strip among it -- draws with
           `font: menu`, which resolves to the GTK font (gtk-font-name, Noto Sans 9 -> 12px)
           and resets font-size as part of the shorthand, so a smaller size inherited from
           :root never reaches it; setting the resolved size directly is what bites. These
           stay CSS pixels, which devPixelsPerPx goes on scaling per monitor. */
        #navigator-toolbox,
        #sidebar-main,
        #vertical-tabs {
          font-size: 10px !important;
        }

        /* Vertical tab rows. Under the sidebar.verticalTabs pref tabs.css sizes these as
           max(32px, line-height * 1em), so the 32px floor has to come down explicitly --
           the horizontal strip's own --tab-min-height never applies in this mode. */
        :root {
          --tab-min-height: 24px !important;
        }
      '';
    in
    [
      "d ${profile}/chrome 0755 - - -"
      "L+ ${profile}/chrome/userChrome.css - - - - ${userChrome}"
    ];

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

  ### POWER ###
  # tuned rather than power-profiles-daemon, which the laptop profile enables for the Dell.
  # PPD has no generic cpufreq driver: it drives intel_pstate, amd-pstate or an ACPI
  # platform_profile, and Apple Silicon offers none of the three. So it fell back to its
  # `placeholder` driver, which advertises exactly power-saver and balanced -- no
  # performance at all -- and applies nothing beyond the trickle_charge action:
  #
  #   $ powerprofilesctl set performance
  #   invalid choice: 'performance' (choose from 'power-saver', 'balanced')
  #
  # waybar's power-profiles-daemon module cycles whatever the daemon reports, so those two
  # entries are the whole reason the bar's bubble only ever toggled between power-saver and
  # balanced. tuned-ppd serves the same net.hadess.PowerProfiles name, so the bar needs no
  # change, and tuned's cpu plugin works off plain cpufreq sysfs -- which apple-cpufreq does
  # provide (ondemand, userspace, performance, schedutil).
  services.tuned = {
    enable = true;

    # `throughput-performance`, tuned's stock target for the performance profile, is a
    # server profile: alongside the governor it sets vm.swappiness=10, dirty_bytes=40% and a
    # 4096-sector readahead, which fight the zram tuning in the laptop profile. This does
    # the one thing wanted here. The stock profile's other cpu keys -- energy_perf_bias,
    # energy_performance_preference, boost -- are x86/ACPI only and would just log
    # "not supported" on this machine, so they are left out.
    profiles.lattice-performance = {
      main.summary = "Performance without throughput-performance's server sysctls";
      cpu.governor = "performance";
    };

    # The stock powersave and balanced profiles both resolve to the schedutil governor here,
    # since apple-cpufreq has neither `powersave` nor `conservative` and schedutil heads both
    # of their fallback lists. They still differ in what the rest of the profile touches:
    # vm.laptop_mode, dirty_writeback_centisecs, the audio timeout and SCSI ALPM.
    ppdSettings.profiles = {
      power-saver = "powersave";
      balanced = "balanced";
      performance = "lattice-performance";
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
