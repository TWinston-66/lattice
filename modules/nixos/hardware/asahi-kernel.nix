# The Asahi kernel as lattice builds it: upstream's linux-asahi plus the patches carried here.
# Its own module because the installer ISO (installer/) boots the same kernel, so the one
# derivation the binary cache cannot get from CI is built once, on the Mac, for both.
_: {
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
  #
  # The USB-C ports lose USB3 after one failed PHY handshake, and then everything plugged in
  # comes up USB2, full speed, or not at all. Seen 2026-10-10: a stick that mounted at
  # SuperSpeed was pulled, phy-apple-atc logged "Pipehandler lock not acked" / "Failed to
  # lock pipehandler" in the same instant, and from then on the T3 came up high-speed only
  # and the stick failed at full speed with error -71. With both plugged in at power-on, one
  # port came up USB2 and the other hung the controller (hub_event stuck in xhci_alloc_dev).
  # The driver polls the lock ACK once for 1ms when it can take hundreds, leaves the
  # RXDETECT override set when that fails, and at boot can lose a race between xhci and
  # tipd's debounced mux switch. Likely the same thing as the iPhone's -71 loop in phone.nix.
  #
  # Carried locally, from AsahiLinux/linux PR #503 (commit 87a2ad1, "phy: apple: atc: fix
  # USB3 bring-up reliability at boot and on DP alt-mode hotplug"), open upstream since
  # 2026-05. Measured on an M1 (t8103) there; this Mac is an M2 Max. It applies to
  # asahi-7.1.13 with offsets only; re-check it on every kernel bump.
  boot.kernelPatches = [
    {
      name = "drm-apple-complete-swallowed-swaps";
      patch = ./patches/drm-apple-complete-swallowed-swaps.patch;
    }
    {
      name = "phy-apple-atc-usb3-bringup";
      patch = ./patches/phy-apple-atc-usb3-bringup.patch;
    }
  ];
}
