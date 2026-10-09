_: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos
    ../../modules/personal
  ];

  networking.hostName = "lattice-mac";
  system.stateVersion = "26.11";

  ### ASAHI ###
  # `nix hash path /var/lib/lattice/vendorfw`; see lattice.asahi.firmwareHash.
  lattice.asahi.firmwareHash = "sha256-wETBAOJSRK5XrfeTa+vqluv3M1RxIQdGpB+6zW+2mYw=";

  ### DISPLAY ###
  # The panel is 3024x1890 across 302x189mm, so 254ppi. Hyprland's "auto" picks scale 2,
  # which leaves a 1512x945 logical desktop at 127 logical DPI -- and everything sized in
  # logical pixels (waybar's 28px bar and 12px font, the 5/10 gaps, the 2px borders, the
  # 16px cursor, the terminal's font size) is drawn against the 96 DPI convention, so at 2 it
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
  # `hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0",
  # scale = 2.1 })'` tries another live; it reverts on the next reload. Carry the position
  # along when trying one: a scale is a logical size, and the size is what the offset below
  # is measured against.
  # Measured off `hyprctl monitors -j`: the panel is 3024x1890 at scale 2.25 and the Samsung
  # 3840x2160 at 1.5, so their logical sizes are 1344x840 and 2560x1440. Both canvases are
  # those, and each scale is the monitor's own -- so every wallpaper rasterises to exactly
  # its screen's pixels, with nothing left for hyprpaper to magnify.
  lattice.display.canvas = {
    panel = {
      width = 1344;
      height = 840;
      scale = 2.25;
    };
    desk = {
      width = 2560;
      height = 1440;
      scale = 1.5;
    };
  };

  lattice.display.monitors."eDP-1" = {
    scale = "2.25";

    # 120Hz on the charger, 60 on battery. The DCP driver offers no VRR (`vrr: false` in
    # `hyprctl monitors`), so at 120 anything animating -- a cursor blink, a progress bar,
    # a scrolling page -- is composited twice as often as it needs to be on battery.
    batteryMode = "3024x1890@60";

    # Pinned to the origin rather than left at "auto", because auto is a placement pass
    # rather than a rule: it drops each output to the right of everything already laid out.
    # The moment the Samsung below takes a position of its own the panel is placed after it
    # and lands at x=3904, on the far side of the desk from where it is sitting. Pinning
    # either output means pinning both.
    position = "0x0";
  };

  # The Samsung on the desk. Pinned per-host rather than left to the desc-keyed rule in
  # ~/.dotfiles, so it can be tuned against this laptop without dragging other machines
  # along -- it happens to agree with that rule's 1.5 today, which is why the value looks
  # redundant.
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
  # "preferred", position = "1344x-1020", scale = 1.6 })'` tries another live; it reverts on
  # the next reload. A different scale wants a different offset -- see below.
  lattice.display.monitors."desc:Samsung Electric Company U32R59x" = {
    scale = "1.5";

    # To the right of the panel, and lifted so the seam matches the desk rather than the
    # pixels. Measured: this monitor's bottom edge sits 4.5" above the desk, the panel's
    # bottom 1", and the panel's top edge 3.5" above this monitor's bottom. Those three
    # agree -- they put the panel's visible height at 7.0" against the 7.44" its 189mm
    # would give flat, the lid being tilted back ~20 degrees -- and they say the panel
    # hangs 3.5" below this monitor with only its top 3.5" having screen beside it at all.
    #
    # No offset maps that exactly, because the two run at different logical densities by
    # construction: 840px over 7.0" is 120 px/inch on the panel, against 1440px over 15.35"
    # (390mm) = 94 px/inch here. That gap is the apparent-size choice above, not a mistake,
    # so an anchor is the most there is to have -- roughly 26px of drift per inch away from
    # whichever point is anchored. -1020 anchors the shared band at 3.5" measured in the
    # panel's inches, which is also where the two centres line up. The alternatives:
    #
    #   -1110  puts the panel's top edge at its true 8.0" instead, exact on this monitor's
    #          side rather than the panel's; 328px of shared band rather than 420
    #    -600  bottom edges flush, all 840px of the panel adjoining, at the cost of
    #          claiming its top edge is 13.4" off the desk rather than 8.0"
    #
    # Below y=420 the panel's right edge is a wall the pointer stops at, which is true of
    # the desk too: right of there is this monitor's stand. The offset rides on this output
    # rather than on the panel so that undocked the panel still holds the origin.
    position = "1344x-1020";
  };

  # Notification banners follow the Samsung when it is there and stay on the panel when it
  # is not -- see lattice.display.notificationOutput in modules/nixos/display.nix for why an
  # absent output needs no fallback of its own. Spelled as the connector rather than by
  # description because mako has no desc: matching; this is the built-in HDMI port, so it
  # changes if the Samsung is ever driven off USB-C DisplayPort instead.
  lattice.display.notificationOutput = "HDMI-A-1";
}
