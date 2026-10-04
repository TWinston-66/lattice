# Shared by the desktop modules: the palette helpers, the wallpaper pool and where the
# run-time theme lives. Not a module -- each one imports it with its own config.
{
  config,
  lib,
  pkgs,
}:
let
  theme = config.lattice.theme;
  inherit (theme) palette;

  # hyprlang writes colours bare, without the leading '#'.
  hex = lib.removePrefix "#";

  # Blend two palette colours channelwise; `keep` is how much of the first survives. Only
  # the lock screen needs this, to sit the input field's outline between the wallpaper's
  # accent and the surface behind it -- see hyprlock.conf in lock.nix.
  mixHex =
    keep: a: b:
    let
      channel = s: n: lib.fromHexString (builtins.substring n 2 (hex s));
      blend =
        n:
        let
          v = builtins.floor ((keep * channel a n) + ((1.0 - keep) * channel b n) + 0.5);
          h = lib.toLower (lib.toHexString (lib.min 255 v));
        in
        if builtins.stringLength h < 2 then "0" + h else h;
    in
    lib.concatMapStrings blend [
      0
      2
      4
    ];

  # The pool the session picks from. Every entry is its own PNG in the store and
  # `lattice-wallpaper random` draws one per login, so the desktop is a different member of
  # one family each session rather than the same image forever.
  #
  # The knobs split by which side knows the answer. The seed belongs to the generator: it
  # varies which way the background gradient runs and which ring of the mark is lit. It
  # leaves the mark centred and the lattice square to the screen, which is a correction
  # rather than an oversight -- both were seeded at first, and on a real screen a mark a
  # little off centre reads as misaligned and a grid a few degrees over reads as crooked,
  # because there is nothing else on the canvas for either to be off-balance against.
  #
  # The accents belong here, because the palette's chromatic names live in lattice.theme
  # and the generator only ever sees the nine roles it draws with. There is one entry per
  # chromatic name, all fourteen of them, each pairing its accent with a hue-adjacent
  # second -- the relation blue and lavender have -- so the mark stays two shades of one
  # colour rather than turning into a gradient. Walking the whole palette rather than
  # following lattice.theme.accent is the point: every one of those names is a colour of
  # this theme, and fourteen wallpapers in one hue would differ only in their seeded
  # composition. The first entry is the exception -- no accent and no seed, so it is the
  # live accent drawn plain,
  # which keeps it the image it was before the pool existed and the right one to seed the
  # wallpaper symlinks with before a home has ever picked.
  #
  # An entry names palette entries rather than colours, because the pool is drawn once per
  # flavour in lattice.theme.flavors: "mauve" is a different hex in each, and the runtime
  # theme switch (lattice-theme) swaps the whole pool for that flavour's drawing of it, so
  # the wallpaper's background moves with the rest of the desktop. The seed is its position
  # in the list, which makes appending a wallpaper cheap and reordering the list a redraw of
  # everything that moved.
  #
  # None of them names a density, deliberately: they all take the generator's 1.0. Density
  # divides the node spacing, and everything in the drawing is measured in spacings -- the
  # grid, the dots' radius, the mark -- so varying it across the pool redrew the artwork at
  # a different size on a correctly sized canvas. The entries used to cycle 1.0, 0.7, 1.4,
  # which meant no two neighbours shared one and a step could double the spacing. Cycling
  # wallpapers then read as the image being resized rather than as variety, and the colour
  # is the variety worth having.
  pool = [
    { }
    {
      accent = "mauve";
      accentAlt = "pink";
    }
    {
      accent = "teal";
      accentAlt = "sky";
    }
    {
      accent = "peach";
      accentAlt = "yellow";
    }
    {
      accent = "sapphire";
      accentAlt = "teal";
    }
    {
      accent = "lavender";
      accentAlt = "blue";
    }
    {
      accent = "green";
      accentAlt = "teal";
    }
    {
      accent = "pink";
      accentAlt = "mauve";
    }
    {
      accent = "maroon";
      accentAlt = "peach";
    }
    {
      accent = "sky";
      accentAlt = "sapphire";
    }
    {
      accent = "yellow";
      accentAlt = "peach";
    }
    {
      accent = "red";
      accentAlt = "maroon";
    }
    {
      accent = "flamingo";
      accentAlt = "rosewater";
    }
    {
      accent = "rosewater";
      accentAlt = "flamingo";
    }
  ];

  # Every entry is drawn twice, because no single image is the right size on both screens.
  # hyprpaper scales an image to cover whatever output it lands on, so a fixed image gives
  # the mark a fixed *fraction* of every screen -- and a fraction is the wrong invariant.
  # The Samsung on the desk is about 2.3x the panel's width, so an equal fraction made its
  # mark 2.3x the size, while the criterion that actually matters is the one the greeter
  # already uses (greeter.nix): equal angle at the eye. The desk monitor sits
  # ~28in away against the panel's ~20in, so it should be about 1.4x, not 2.3x.
  #
  # Sizing each canvas near its screen's logical resolution is what delivers that, and it
  # needs no measurement to maintain: `spacing` is fixed, so the mark comes out a constant
  # number of canvas units, and a canvas the size of the logical screen therefore puts the
  # mark in the same relation to the UI drawn in those same units. It lands the two at a
  # ratio of ~1.44 against the 1.43 the greeter derived independently.
  #
  # The aspects are each screen's own, so cover has nothing to crop -- the old single
  # 16:10 image lost a tenth of its height on the 16:9 monitor. The panel figure is 16:10
  # because both laptops here have one; a 16:9 panel would crop that tenth back, which is
  # the cost of not knowing the panel until runtime.
  # Per host, in modules/nixos/display.nix: the numbers are a property of the screens in
  # front of the machine, and a canvas that does not match its screen's logical size is
  # magnified to cover it -- which is the whole of what the paragraph above is about.
  screens = config.lattice.display.canvas;

  # In the picker's order, which is by label so each family's variants sit together.
  flavorNames = lib.sort (a: b: theme.flavors.${a}.label < theme.flavors.${b}.label) (
    lib.attrNames theme.flavors
  );

  # The pool resolved against one flavour: the entries whose accent is one of that flavour's
  # own colours (its `accents`), as that flavour's hexes, plus the palette the rest of the
  # drawing takes. A blend made only to fill a slot would draw a near-twin of a wallpaper
  # already in the pool, so a flavour with seven hues gets seven wallpapers, not fourteen.
  # The seed stays the entry's position in the whole pool, so "red" is the same composition
  # in every flavour and only its colours move.
  #
  # Entry 0 names nothing and so takes lattice.theme.accent's pair, and is always kept: it is
  # the plain drawing, and in the build-time flavour exactly what the artwork module makes by
  # default -- the same store path as before flavours.
  poolFor =
    flavor:
    let
      inherit (theme.flavors.${flavor}) palette accents;
    in
    lib.filter (entry: entry.seed == 0 || accents ? ${entry.slot}) (
      lib.imap0 (
        seed: entry:
        let
          slot = entry.accent or theme.accent;
        in
        {
          inherit seed slot palette;
          label = accents.${slot} or slot;
          accent = palette.${slot};
          accentAlt = palette.${entry.accentAlt or theme.accentAlt};
        }
      ) pool
    );

  wallpapersFor =
    flavor: screen:
    map (
      entry:
      config.lattice.artwork.wallpaper (
        {
          inherit (entry)
            seed
            accent
            accentAlt
            palette
            ;
        }
        // screen
      )
    ) (poolFor flavor);

  panelWallpapers = lib.genAttrs flavorNames (flavor: wallpapersFor flavor screens.panel);

  deskWallpapers = lib.genAttrs flavorNames (flavor: wallpapersFor flavor screens.desk);

  # A bash `case` over the flavours, one arm each, from `arm flavor` -> the arm's body.
  # How the theming scripts carry per-flavour arrays: the pool's hexes and store paths are
  # build-time facts, so they are baked in rather than looked up.
  flavorCase =
    arm:
    ''
      case "$flavor" in
    ''
    + lib.concatMapStrings (flavor: ''
      ${flavor})
      ${arm flavor}
        ;;
    '') flavorNames
    + ''
      esac
    '';

  # Where lattice-theme keeps the flavour, and the shell that reads it back. In ~/.local/state
  # rather than beside the wallpaper's per-boot pick in XDG_RUNTIME_DIR: the flavour is a
  # preference, and should survive a reboot. Anything unreadable or no longer in
  # lattice.theme.flavors falls back to the build-time one rather than failing.
  themeState = "${config.users.users.winston.home}/.local/state/lattice/theme";

  readFlavor = ''
    flavor=$(cat "${themeState}" 2>/dev/null || true)
    case "$flavor" in
    ${lib.concatStringsSep " | " flavorNames}) ;;
    *) flavor=${theme.flavor} ;;
    esac
  '';

  # The run-time palette as a bash associative array `c`, for scripts that draw their own
  # Pango markup: the build-time colours, then theme.sh over them when lattice-palette has
  # written one. Parsed with `read` rather than sourced, so it costs no fork -- the
  # power-profile pill runs it every two seconds -- and shellcheck can see every name used.
  readColours = ''
    declare -A c=(${
      lib.concatStrings (lib.mapAttrsToList (n: hex: " [${n}]='${hex}'") palette)
    } [accent]='${theme.accentHex}' [accentAlt]='${theme.accentAltHex}')
    if [[ -r "${currentDir}/theme.sh" ]]; then
      while IFS='=' read -r key value; do
        value=''${value#\'}
        c[$key]=''${value%\'}
      done <"${currentDir}/theme.sh"
    fi
  '';

  # What the wallpaper symlinks are seeded with: the plain drawing at desk size.
  wallpaper = lib.head deskWallpapers.${theme.flavor};

  # Where the picker records what it set, for the things that cannot be told. hyprlock
  # reads its backgrounds at launch from paths fixed at build time, so pointing it at these
  # is what keeps the lock screen showing the same wallpaper the desktop has; the `color`
  # beside them covers the gap before the first pick, and base is the gradient's own
  # bottom-right stop, so even that reads as the wallpaper's darkest corner. One per screen
  # size, for the same reason there are two of every wallpaper.
  currentDir = "${config.users.users.winston.home}/.cache/lattice";

  currentPanel = "${currentDir}/wallpaper-panel.png";

  currentDesk = "${currentDir}/wallpaper-desk.png";

  # rofi with the calculator mode compiled in. A rofi plugin is a shared object loaded from
  # rofi's own -plugin-path, so `rofi-calc` on its own in systemPackages would be a file
  # nothing ever opens: the nixpkgs wrapper is what joins the plugin into $out/lib/rofi and
  # passes that flag. `rofi -h` lists it under "Detected modes" once it is there, which is
  # the quick check that a nixpkgs bump hasn't broken the plugin ABI -- rofi 2.0 changed it,
  # and a plugin built against the wrong one is silently not loaded.
  #
  # Every menu takes this one rather than pkgs.rofi. Two wrappers differing only in
  # the plugin would otherwise collide in the system profile, and whichever won would decide
  # whether `-show calc` finds anything.
  #
  # The engine is libqalculate, which is what makes this worth a launcher mode rather than a
  # window: bases and units convert in place (`0xff to bin`, `1 GiB to MB`, `0.1+0.2 to
  # double` for the IEEE bits), solve/diff/sum and matrices work, and integers stay exact.
  # nixpkgs patches the plugin's `qalc` lookup to an absolute store path, so nothing needs to
  # be on PATH for the mode itself; libqalculate is in apps.nix's systemPackages only for the
  # `qalc` CLI, and adds no closure of its own because the plugin already pulls it in.
  rofiWithCalc = pkgs.rofi.override { plugins = [ pkgs.rofi-calc ]; };
in
{
  inherit
    theme
    palette
    hex
    mixHex
    pool
    screens
    flavorNames
    poolFor
    wallpapersFor
    panelWallpapers
    deskWallpapers
    flavorCase
    themeState
    readFlavor
    readColours
    wallpaper
    currentDir
    currentPanel
    currentDesk
    rofiWithCalc
    ;
}
