# The Logitech MX Master 3. Its buttons are Solaar rules (~/.config/solaar, in the dotfiles
# repo), and the Solaar service that serves them is the distro's (desktop/apps.nix).
_: {
  # DPI is the only speed knob for this mouse; these two exist to get out of its way.
  #
  # accel_profile "flat" turns off libinput's pointer acceleration, which otherwise scales
  # gain by how fast the hand is moving. With it on there is no single "speed" to tune -- the
  # same setting feels right on slow tracking and too loose on a quick flick -- which is what
  # makes too-fast and too-sensitive impossible to tell apart. Flat makes pointer travel
  # strictly proportional to hand travel, so DPI means one thing. Drop that line to get the
  # accelerated feel back.
  #
  # sensitivity 0 is no modification. Anything negative would discard motion counts the
  # sensor already reported, buying slowness at the cost of precision; the DPI in
  # ~/.config/solaar/config.yaml moves it at the source instead. scroll_factor is unrelated
  # to DPI: the default is 1.0, and lower is slower. The name is from `hyprctl devices`.
  lattice.hyprland.extraConfig = ''
    hl.device({
        name          = "logitech-wireless-mouse-mx-master-3-1",
        accel_profile = "flat",
        sensitivity   = 0,
        scroll_factor = 0.5,
    })
  '';

  # What rules.yaml makes the buttons do, for the SUPER + / cheatsheet.
  lattice.keys.extras = ''
    mouse	Gesture paddle (hold)	Acts as SUPER: with scroll or drag
    mouse	Back / Forward	Speaker volume
    mouse	Smart Shift button	App launcher
  '';
}
