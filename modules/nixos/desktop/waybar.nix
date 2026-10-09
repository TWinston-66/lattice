{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lattice.bar;
  json = pkgs.formats.json { };

  sections = [
    "left"
    "center"
    "right"
  ];

  # A section's or a group's members, in their order. A group with nothing in it is left
  # out of wherever it sits, so a host whose features leave a segment empty doesn't draw an
  # empty frame.
  membersOf =
    section:
    lib.filter (name: !(isGroup name) || membersOf name != [ ]) (
      map (m: m.name) (
        lib.sort (
          a: b: if a.value.order == b.value.order then a.name < b.name else a.value.order < b.value.order
        ) (lib.filter (m: m.value.section == section) (lib.attrsToList cfg.modules))
      )
    );

  isGroup = lib.hasPrefix "group/";

  placed = lib.concatMap membersOf (sections ++ lib.filter isGroup (lib.attrNames cfg.modules));

  barConfig =
    cfg.settings
    // lib.listToAttrs (
      map (section: lib.nameValuePair "modules-${section}" (membersOf section)) sections
    )
    // lib.genAttrs placed (
      name: cfg.modules.${name}.settings // lib.optionalAttrs (isGroup name) { modules = membersOf name; }
    );

  signals = lib.concatMap (m: lib.optional (m.value.settings ? signal) m.value.settings.signal) (
    lib.attrsToList cfg.modules
  );
in
{
  ### BAR ###
  # waybar's config, put together from the modules that own each pill: a pill is declared
  # next to the script that feeds it, so its exec, its click handlers and the signal its
  # script sends are all in one place, and a feature that is off takes its pill with it.
  # Written to /etc/xdg/waybar/config.jsonc with the stylesheet beside it; a
  # ~/.config/waybar of the user's own replaces both.
  options.lattice.bar = {
    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "The bar's own top-level settings: position, margins, spacing.";
    };

    modules = lib.mkOption {
      default = { };
      description = ''
        The bar's modules, by waybar's name for each -- `custom/weather`, `wireplumber#mic`,
        `group/toggles`. A group's members are the modules whose section names it.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            section = lib.mkOption {
              type = lib.types.str;
              example = "group/toggles";
              description = "Where the module sits: left, center, right, or a group's name.";
            };
            order = lib.mkOption {
              type = lib.types.int;
              description = "Its place in that section, lowest first.";
            };
            settings = lib.mkOption {
              inherit (json) type;
              default = { };
              description = "waybar's settings for the module, as they would be written in its config.";
            };
          };
        }
      );
    };
  };

  config = {
    programs.waybar.enable = true;

    environment.etc = {
      "xdg/waybar/config.jsonc".source = json.generate "waybar-config.jsonc" barConfig;
      "xdg/waybar/style.css".source = ./configs/waybar.css;
    };

    assertions = [
      {
        assertion = lib.length (lib.unique signals) == lib.length signals;
        message = "lattice.bar: two modules share a signal, so a refresh for one would re-run the other.";
      }
      {
        assertion = lib.all (m: lib.elem m.value.section sections || cfg.modules ? ${m.value.section}) (
          lib.attrsToList cfg.modules
        );
        message = "lattice.bar: a module sits in a section that is neither left, center, right nor a group.";
      }
    ];

    lattice.bar.settings = {
      layer = "top";
      position = "top";
      # No "height": the bar takes its height from style.css (window > box), where a
      # host's /etc/xdg/waybar drop-in can shrink it. A height set here is a floor CSS can't
      # go under.
      margin-top = 4;
      margin-left = 10;
      margin-right = 10;
      spacing = 5;
      # Restyles in place when style.css or anything it @imports changes -- which is how the
      # runtime theme (lattice-palette) reaches the bar without a SIGUSR2 rebuilding it.
      reload_style_on_change = true;
    };

    # The centre holds the clock and nothing else, which is what pays for the right side.
    # waybar centres modules-center as a group, so a module put beside the clock has to be
    # balanced by the same width on the clock's other side to keep the clock on the bar's
    # centre line -- every pill in there costs its width twice, and half of that is spent
    # pushing the group's right edge towards the right-hand group. Alone, the clock reaches
    # only 71px either side of centre and the right side gets ~130px back.
    #
    # Each side gets half the bar less half the clock, and on the Mac's 1324px the left ran
    # out first: the toggles, the radio and a pomodoro countdown don't fit beside the
    # workspaces. So the weather sits first on the right instead -- still the pill next to
    # the clock, so "what time is it" and "what is it doing outside" are one glance apart --
    # and the right side pays for it by segmenting its readouts: the levels (volume, mic,
    # brightness) share one frame, the connection another, the power profile and battery a
    # third. A pill's border, padding and the bar's spacing cost ~25px a seam, which is what
    # makes room.
    #
    # Privacy went right with the weather: a call or a screen share holds it up for as long
    # as the pomodoro or the backup, and the left has room for only one of those at a time.
    # Caps lock is up for seconds, so it stays left and the radio shrinks for it.
    #
    # The orders, so a pill declared elsewhere can find its place:
    #   left    workspaces 10, capslock 20, group/toggles 30, radio 40
    #   center  clock 10
    #   right   weather 10, privacy 20, tray 30, group/levels 40, group/links 50,
    #           group/energy 60, power 70
    #   toggles sunset 10, dnd 20, idle 30, wallpaper 40, theme 50, vault 60, backup 70,
    #           bitwarden 80, reading 90, pomodoro 100
    #   levels  volume 10, mic 20, backlight 30
    #   links   network 10, tailscale 20
    #   energy  power profile 10, battery 20
    #
    # The pills below are the ones that are waybar's own modules, fed by no script of
    # lattice's; the rest are declared with their scripts.
    lattice.bar.modules = {
      # The number alone says where a window is but not what it is, which stops being
      # enough as soon as three or four workspaces are in use at once. {windows} appends one
      # glyph per open window, so a pill reads "2 󰈹" -- number first, so the SUPER+[1-5]
      # target is still the thing the eye lands on. Empty persistent pills render the id
      # and nothing else, and keep their .empty styling.
      #
      # Rules are matched against the Wayland app_id, not the X11 WM_CLASS, and the two
      # differ for some apps -- the classes below are the ones `hyprctl clients` reports.
      # Anything unmatched draws window-rewrite-default rather than disappearing, which is
      # the signal to come back here and add it. The patterns are ECMAScript regex wrapped
      # in .* so they hold whether waybar searches or anchors them.
      #
      # A rule naming both class and title outranks a class-only rule whatever the order
      # here, so the three Firefox web apps (webapps.nix -- they are Taskbar Tabs and report
      # app_id "firefox" like any other window) win over the plain Firefox rule. They match
      # on title, so an ordinary tab titled "... Calendar ..." wears the calendar mark too;
      # harmless, and the alternative is no mark for the web apps at all.
      "hyprland/workspaces" = {
        section = "left";
        order = 10;
        settings = {
          format = "{id} {windows}";
          format-window-separator = " ";
          window-rewrite-default = "";
          window-rewrite = {
            "class<foot>" = "";
            "class<firefox> title<.*Gemini.*>" = "󰚩";
            "class<firefox> title<.*Reminders.*>" = "󰄹";
            "class<firefox> title<.*Calendar.*>" = "󰸗";
            "class<firefox>" = "󰈹";
            "class<thunderbird>" = "󰇮";
            "class<thunar>" = "󰉋";
            "class<.*zathura>" = "󰈦";
            "class<mpv>" = "󰎁";
            "class<imv>" = "󰋩";
            "class<coda-qt>" = "󰈙";
            "class<draw.io>" = "";
            "class<.*[Tt]elegram.*>" = "";
            "class<.*[Vv]esktop.*>" = "󰙯";
            "class<.*[Bb]itwarden.*>" = "󰌾";
            "class<qalculate-gtk>" = "󰂽";
            "class<xarchiver>" = "󰗄";
            "class<.*[Cc]ode.*>" = "󰨞";
          };
        };
      };

      # The click-toggles and the two wallpaper/theme actions share one segmented pill: one
      # frame, no gaps, each icon still its own module and click target. As separate pills
      # each one paid for a border, padding and the bar's spacing around a single glyph, and
      # on the Mac's 1344px the left group overflowed into the clock and ellipsised the
      # radio. Styled as #toggles in style.css.
      "group/toggles" = {
        section = "left";
        order = 30;
        settings.orientation = "horizontal";
      };

      # Next to the weather rather than on the left, which is full. Takes zero width while
      # nothing is capturing, so it costs nothing at rest and simply appears when something
      # starts.
      #
      # Default modules are screenshare + audio-in, which is what is wanted: audio-out would
      # light up for any music playing. icon-size 15 to sit on a 28px bar -- the default 20
      # is sized for a taller one.
      privacy = {
        section = "right";
        order = 20;
        settings = {
          icon-size = 15;
          icon-spacing = 6;
          transition-duration = 200;
        };
      };

      # 14px rather than the stock 16: at 16 the tray's icon rendered visibly larger than the
      # Nerd Font glyphs in the pills beside it. It also has to stay small -- the tray is the
      # leftmost pill of an already-full right group, and a wider icon squeezes the network
      # label until waybar ellipsizes the SSID to make room.
      tray = {
        section = "right";
        order = 30;
        settings = {
          icon-size = 14;
          spacing = 8;
        };
      };

      # The right side's segmented pills; see the note on the sections above.
      "group/levels" = {
        section = "right";
        order = 40;
        settings.orientation = "horizontal";
      };
      "group/links" = {
        section = "right";
        order = 50;
        settings.orientation = "horizontal";
      };
      "group/energy" = {
        section = "right";
        order = 60;
        settings.orientation = "horizontal";
      };

      # Muted keeps only the glyph: the word made this the widest state the pill can be in,
      # and dropping it is what buys the room on the right for custom/tailscale.
      # The glyph is still greyed by the .muted class in style.css.
      #
      # Click for the output picker: lattice-audio (menus.nix) lists the sinks PipeWire
      # knows about through rofi, marks the one in use and moves what is already playing
      # over when another is chosen -- the same shape as the Wi-Fi pill, which is the other
      # bar surface whose job is "switch this to something else". Mute moves to the right
      # button and to the menu's first row; the keyboard still has XF86AudioMute for it.
      #
      # Scroll does nothing, for the same reason backlight has no scroll handlers -- a stray
      # wheel tick on the way past the bar shouldn't move the volume. Unlike backlight, this
      # module changes volume in C++ whether or not anything is configured, so the mechanic
      # can't just be left unconfigured: the only thing that displaces it is a scroll
      # handler of our own, which is what these two are. They are empty on purpose and cost
      # nothing -- waybar's forkExec returns early on an empty command, so no shell is
      # spawned per tick -- and with them present scroll-step has nothing left to scale, so
      # it's gone.
      #
      # The right-click mute goes through lattice-deck rather than straight at wpctl so a
      # Stream Deck's mute key follows it; see the microphone pill below.
      wireplumber = {
        section = "group/levels";
        order = 10;
        settings = {
          format = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
          on-click = "lattice-audio output";
          on-click-right = "lattice-deck mute";
          on-scroll-up = "";
          on-scroll-down = "";
        };
      };

      # The microphone, as the same module pointed at the default source instead of the
      # default sink -- node-type is the whole difference, and the "#mic" suffix is what
      # lets wireplumber appear twice. Deliberately the sink pill's pair: same shape, same
      # glyph-only muted state, so the two are read together rather than as two unrelated
      # readouts that happen to be adjacent.
      #
      # Click for the input picker, right-click to mute -- the same pair as the sink pill,
      # and `lattice-audio input` is the same script with node-type's counterpart on the
      # pactl side. It drops the monitor sources, which are the loopback of each sink and
      # would otherwise fill the list with a copy of the output menu.
      #
      # Both pills mute through lattice-deck rather than wpctl. A Stream Deck has a key for
      # each and only knows what it is told, so a mute from the bar would otherwise leave it
      # showing the old state until its five-minute sync came round -- the same reason
      # XF86AudioMute and XF86AudioMicMute go through lattice-deck in the Hyprland binds.
      # Without a deck, lattice-deck still mutes; see streamdeck.nix.
      #
      # Icon-only, unlike the sink beside it. The level is not the question this pill
      # answers -- input gain is set once and left, where output volume moves all day -- and
      # "󰍬 100%" is 64px against the glyph's 35. SHIFT+XF86AudioRaiseVolume raises
      # swayosd's own pill with the number on it, which is where a level belongs -- at the
      # moment it changes.
      #
      # Scroll is stubbed for the reason the sink's is.
      "wireplumber#mic" = {
        section = "group/levels";
        order = 20;
        settings = {
          node-type = "Audio/Source";
          format = "󰍬";
          format-muted = "󰍭";
          on-click = "lattice-audio input";
          on-click-right = "lattice-deck mic";
          on-scroll-up = "";
          on-scroll-down = "";
        };
      };

      # Readout only. Brightness is changed with XF86MonBrightness{Up,Down}, bound in
      # Hyprland, which raise the same swayosd popup a volume key does.
      #
      # The two empty scroll handlers are what make it readout-only, and leaving them out is
      # not the same thing: this module dims the screen in C++ whether or not anything is
      # configured (Backlight::handleScroll goes straight to logind's SetBrightness), and
      # the only thing that displaces it is a handler of our own -- its guard is
      # `config_["on-scroll-up"].isString()`, and "" is a string. Exactly the pair the
      # wireplumber pills carry, and for exactly that reason.
      #
      # Worth having because the bar is a 28px strip along the top edge of the screen,
      # which is where a pointer travels on its way to anything at the top of a window -- so
      # a wheel tick on the way past is an accident rather than a request, and "the screen
      # just dimmed and I don't know why" is a poor thing for a readout to be able to do.
      backlight = {
        section = "group/levels";
        order = 30;
        settings = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
          on-scroll-up = "";
          on-scroll-down = "";
        };
      };

      # 16, up from 13. The cap used to be the tightest thing on the bar -- the right group
      # cleared the clock by ~19px with volume and backlight both at 100%, so the SSID was
      # what gave. Emptying the centre group down to the clock handed ~130px back, and after
      # the microphone pill took its share this is where the rest went. Longer names still
      # ellipsize; the full name and the address stay in the tooltip.
      #
      # Measured on the Mac's panel, at the cap, with volume and backlight at 100%: the pill
      # runs 6.5px per unit of max-length, and the right group clears the clock by ~42px.
      # When it runs out, GTK squeezes the centre child -- the clock visibly narrows rather
      # than the SSID giving way. Re-measure before raising it.
      #
      # Click for the picker: lattice-wifi (menus.nix) lists what is in range through rofi,
      # which is themed and lets an SSID be found by typing.
      network = {
        section = "group/links";
        order = 10;
        settings = {
          on-click = "lattice-wifi";
          max-length = 16;
          format-wifi = "{icon} {essid}";
          format-ethernet = "󰈀 wired";
          format-disconnected = "󰤮 offline";
          format-icons = [
            "󰤟"
            "󰤢"
            "󰤥"
            "󰤨"
          ];
          tooltip-format = "{ifname}  {ipaddr}/{cidr}";
        };
      };
    };
  };
}
