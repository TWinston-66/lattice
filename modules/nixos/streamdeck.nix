{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lattice.streamdeck;
  theme = config.lattice.theme;

  # Glyphs by the name Material Design Icons gives them, written as the characters rather
  # than as escapes because Nix has no \u. The comment is the searchable half: these are
  # the names to look up, and lattice-tailscale declares its own the same way.
  g = {
    console = "󰆍"; # md-console
    firefox = "󰈹"; # md-firefox
    folder = "󰉋"; # md-folder
    magnify = "󰍉"; # md-magnify
    clipboard = "󰅍"; # md-clipboard_text
    screenshot = "󰹑"; # md-monitor_screenshot
    wallpaper = "󰸉"; # md-wallpaper
    layers = "󰌨"; # md-layers

    previous = "󰒮"; # md-skip_previous
    play = "󰐊"; # md-play
    pause = "󰏤"; # md-pause
    next = "󰒭"; # md-skip_next
    # The +/- pair rather than the loud/quiet speakers: three speaker glyphs in a row read
    # as mush at arm's length, and the mute key below is the one that should wear a speaker.
    volumeDown = "󰝞"; # md-volume_minus
    volumeUp = "󰝝"; # md-volume_plus
    awake = "󰅶"; # md-coffee
    idle = "󰾪"; # md-coffee_off
    sound = "󰖀"; # md-volume_medium
    muted = "󰝟"; # md-volume_mute
    mic = "󰍬"; # md-microphone
    micOff = "󰍭"; # md-microphone_off
    apple = "󰀵"; # md-apple
    youtube = "󰗃"; # md-youtube
    # Not md-apple, which the Apple Music key already wears one row over -- and there is no
    # md-apple_tv to have instead. A plain set reads better at arm's length than the same
    # mark twice.
    television = "󰔂"; # md-television
    mail = "󰇮"; # md-email
    calendar = "󰸗"; # md-calendar_month
    checklist = "󰝖"; # md-format_list_checks

    bell = "󰂚"; # md-bell
    bellOff = "󰂛"; # md-bell_off
    history = "󰋚"; # md-history
    clearAll = "󰎟"; # md-notification_clear_all
    sunny = "󰖙"; # md-weather_sunny
    night = "󰖔"; # md-weather_night
    cloudy = "󰖕"; # md-weather_partly_cloudy
    wifi = "󰖩"; # md-wifi
    vpn = "󰖂"; # md-vpn
    vpnOff = "󰌙"; # md-lan_disconnect
    speaker = "󰓃"; # md-speaker
    battery = "󰁹"; # md-battery
    perf = "󰓅"; # md-speedometer
    balanced = "󰾅"; # md-speedometer_medium
    saver = "󰾆"; # md-speedometer_slow
    lock = "󰌾"; # md-lock
    rebuild = "󰜉"; # md-restart
    refresh = "󰑐"; # md-refresh
    power = "󰐥"; # md-power

    dashboard = "󰕮"; # md-view_dashboard
    headphones = "󰋋"; # md-headphones
    home = "󰋜"; # md-home

    bulb = "󰹏"; # md-lightbulb_off
    bulbOn = "󰛨"; # md-lightbulb_on
    fan = "󰠝"; # md-fan_off
    fanOn = "󰈐"; # md-fan
    bed = "󰋣"; # md-bed
    meditation = "󱅻"; # md-meditation
    target = "󰓾"; # md-target
    dusk = "󰖚"; # md-weather_sunset
  };

  # The seven entities the home page presses, by the names modules/nixos/homeassistant.nix
  # gives them. Read through here rather than written out again, so correcting an id after
  # `lattice-ha entities` is one edit in the module that owns it.
  entities = config.lattice.homeassistant.entities;

  # The one path in the repo that already knows where the repo is.
  flake = config.programs.nh.flake;

  # The whole argv for a web app, from the list webapps.nix publishes: the ids stay written
  # down once, and a key cannot drift from the launcher entry for the same app.
  webapp =
    name:
    let
      matches = lib.filter (app: app.name == name) config.lattice.webapps.apps;
    in
    if matches == [ ] then
      throw "lattice.streamdeck: no web app named ${name} in lattice.webapps.apps"
    else
      (lib.head matches).launch;

  bin = package: name: "${package}/bin/${name}";

  # streamdeck-ui puts an icon in the tray and offers no way not to: create_tray runs
  # unconditionally, `-n` only suppresses the window, and waybar 0.15's tray module has no
  # ignore-list to filter it out at the other end. So it comes out here, in the one line
  # that shows it.
  #
  # What that costs is the GUI, and here it costs nothing: the layout is generated, and
  # anything edited in that window is overwritten by the seed at the next generation. If it
  # is ever wanted for a look, the service has to come down first -- a second instance exits
  # on the semaphore rather than raising the first:
  #
  #   systemctl --user stop streamdeck && streamdeck
  #
  streamdeckUi = pkgs.streamdeck-ui.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace streamdeck_ui/gui.py \
        --replace-fail "main_window.tray.show()" "pass  # lattice: no tray icon"

      # The SIGTERM handler only runs once the interpreter gets a turn, which is what this
      # timer is for -- but upstream keeps it in a local, so it is collected as soon as
      # configure_signals returns and the handler never runs while Qt idles. A stop then
      # sits out the whole stop timeout and gets SIGKILLed, which is a failed unit and a
      # rebuild stalled behind it. Parenting it to the app keeps it alive.
      substituteInPlace streamdeck_ui/gui.py \
        --replace-fail "timer = QTimer()" "timer = QTimer(app)"
    '';
  });

  # Pages, as names, in the order the rail shows them. The index into this list is the page
  # index in the config, and the name is what the rail's own key is called.
  pages = [
    "desktop"
    "media"
    "home"
  ];

  # The rail: three keys down the right-hand edge, the same on every page, each switching to
  # one page and lit when that page is the one showing. Its art depends only on the key
  # index -- which is what decides a key's slice of the deck-wide lattice -- so the six faces
  # are shared across all three pages rather than drawn once per page.
  railKeys = [
    {
      index = 4;
      glyph = g.dashboard;
    }
    {
      index = 9;
      glyph = g.headphones;
    }
    {
      index = 14;
      glyph = g.home;
    }
  ];

  # A button: one key on one page, its faces, and the argv one press runs.
  #
  # `cmd` is argv and never a shell line -- streamdeck-ui runs it through shlex.split with no
  # shell at all, so a pipeline, a `&&` or a `$()` in here is not a command, it is arguments.
  # Anything that needs one of those is a verb on lattice-deck below.
  #
  # Two faces make a toggle: the press flips the face at once (`switch_state` in the config
  # it generates) and `lattice-deck sync` corrects it from the real state a moment later, so
  # a command that failed does not leave the key lying. `sync` names which reading does that.
  #
  # `text` is the only thing drawn at runtime rather than baked into the PNG, for the two
  # keys that show a number.
  # A key with nothing on it yet: the lattice ground, no glyph and no command. Kept in the
  # layout rather than dropped from it, so the face stays part of the surface instead of
  # leaving an unlit hole in the middle of it.
  blank = index: {
    inherit index;
    faces = [ { icon = "blank-${toString index}"; } ];
  };

  desktopPage = [
    {
      index = 0;
      cmd = "lattice-power";
      faces = [
        {
          icon = "power";
          glyph = g.power;
          label = "power";
        }
      ];
    }
    {
      # Two presses, because one brush past a key should not start a rebuild: the first arms
      # the key and lattice-deck disarms it again after a few seconds, the second runs it.
      index = 1;
      # What `rebuildAt` finds it by, so that moving this key between pages does not have to
      # be remembered in two places.
      arm = true;
      faces = [
        {
          icon = "rebuild";
          glyph = g.rebuild;
          label = "rebuild";
          cmd = "lattice-deck arm";
        }
        {
          icon = "rebuild-armed";
          glyph = g.rebuild;
          label = "confirm";
          tone = "warn";
          bar = "bottom";
          # In a terminal: a rebuild is the one thing on the deck with output worth reading,
          # and scripts/rebuild.sh asks for a password.
          #
          # In a transient unit of its own, and not as a child of this service, because
          # scripts/rebuild.sh restarts the units a switch changed -- this one among them.
          # A window started straight from here lives in streamdeck.service's cgroup, so
          # that restart would kill the terminal, and with it the rebuild running in it,
          # somewhere in the middle of the switch. setsid is no help: it changes the
          # session, not the cgroup.
          cmd = "systemd-run --user --quiet --collect --unit=lattice-deck-rebuild ghostty -e lattice-deck rebuild";
        }
      ];
    }
    {
      # The bar's power-profile bubble, as a key: the same daemon, the same cycle, and the
      # same three glyphs waybar draws. Three faces rather than two, so the key says which
      # profile is on rather than only that it changed.
      index = 2;
      cmd = "lattice-deck profile";
      sync = "profile";
      faces = [
        {
          icon = "profile-saver";
          glyph = g.saver;
          label = "saver";
          tone = "dim";
        }
        {
          icon = "profile-balanced";
          glyph = g.balanced;
          label = "balanced";
        }
        {
          icon = "profile-performance";
          glyph = g.perf;
          label = "perf";
          tone = "accent";
          bar = "bottom";
        }
      ];
    }
    {
      # Straight at lattice-idle, which is also what the bar's pill runs: one mechanism, two
      # surfaces, and the script pushes the repaint back here the way lattice-dnd does.
      index = 3;
      cmd = "lattice-idle toggle";
      sync = "awake";
      faces = [
        {
          icon = "idle-on";
          glyph = g.idle;
          label = "idle";
        }
        {
          icon = "awake";
          glyph = g.awake;
          label = "awake";
          tone = "accent";
          bar = "bottom";
        }
      ];
    }
    {
      index = 5;
      cmd = webapp "Claude";
      faces = [
        {
          icon = "claude";
          embed = ../../.github/assets/claude.svg;
          label = "claude";
        }
      ];
    }
    {
      # Thunderbird rather than a web app: programs.thunderbird is on in
      # profiles/graphical.nix, so the same bare name works on either host.
      index = 6;
      cmd = "thunderbird";
      faces = [
        {
          icon = "mail";
          glyph = g.mail;
          label = "mail";
        }
      ];
    }
    {
      index = 7;
      cmd = webapp "Calendar";
      faces = [
        {
          icon = "calendar";
          glyph = g.calendar;
          label = "cal";
        }
      ];
    }
    {
      index = 8;
      cmd = webapp "Reminders";
      faces = [
        {
          icon = "reminders";
          glyph = g.checklist;
          label = "todo";
        }
      ];
    }
    {
      index = 10;
      cmd = "lattice-sunset toggle";
      sync = "sunset";
      faces = [
        {
          icon = "day";
          glyph = g.sunny;
          label = "day";
        }
        {
          icon = "night";
          glyph = g.night;
          label = "night";
          tone = "accent";
          bar = "bottom";
        }
      ];
    }
    {
      index = 11;
      cmd = "lattice-dnd toggle";
      sync = "dnd";
      faces = [
        {
          icon = "notify";
          glyph = g.bell;
          label = "notify";
        }
        {
          icon = "dnd";
          glyph = g.bellOff;
          label = "dnd";
          tone = "accent";
          bar = "bottom";
        }
      ];
    }
    {
      index = 12;
      cmd = "lattice-screenshot";
      faces = [
        {
          icon = "screenshot";
          glyph = g.screenshot;
          label = "shot";
        }
      ];
    }
    {
      index = 13;
      cmd = "lattice-wallpaper next";
      faces = [
        {
          icon = "wallpaper";
          glyph = g.wallpaper;
          label = "paper";
        }
      ];
    }
  ];

  mediaPage = [
    {
      index = 0;
      cmd = "${bin pkgs.playerctl "playerctl"} previous";
      faces = [
        {
          icon = "previous";
          glyph = g.previous;
          label = "prev";
        }
      ];
    }
    {
      index = 1;
      cmd = "lattice-deck play";
      sync = "media";
      faces = [
        {
          icon = "play";
          glyph = g.play;
          label = "play";
        }
        {
          icon = "pause";
          glyph = g.pause;
          label = "pause";
          tone = "accent";
          bar = "bottom";
        }
      ];
    }
    {
      index = 2;
      cmd = "${bin pkgs.playerctl "playerctl"} next";
      faces = [
        {
          icon = "next";
          glyph = g.next;
          label = "next";
        }
      ];
    }
    {
      # The media page's one free key, and the right page for it: everything this mends is
      # on this page. Dim rather than plain because it is not part of the transport row it
      # sits in -- it is the key you only reach for when something has gone wrong, and it
      # cuts whatever is playing on the way to fixing it.
      #
      # One press, not armed. The arm mechanism is a single key's (see the throw in this
      # module), it belongs to the rebuild, and a recovery key that wants confirming is a
      # recovery key you are fighting while the audio is already broken.
      index = 3;
      cmd = "lattice-deck audio-restart";
      faces = [
        {
          icon = "audio-restart";
          glyph = g.refresh;
          label = "restart";
          tone = "dim";
        }
      ];
    }
    {
      # Through swayosd rather than straight at wireplumber, so a volume change from the deck
      # puts the same OSD on screen as the one from the keyboard.
      index = 5;
      cmd = "${bin pkgs.swayosd "swayosd-client"} --output-volume lower";
      faces = [
        {
          icon = "volume-down";
          glyph = g.volumeDown;
          label = "vol -";
        }
      ];
    }
    {
      index = 6;
      cmd = "${bin pkgs.swayosd "swayosd-client"} --output-volume raise --max-volume 100";
      faces = [
        {
          icon = "volume-up";
          glyph = g.volumeUp;
          label = "vol +";
        }
      ];
    }
    {
      index = 7;
      cmd = "lattice-deck mute";
      sync = "mute";
      faces = [
        {
          icon = "sound";
          glyph = g.sound;
          label = "sound";
        }
        {
          icon = "muted";
          glyph = g.muted;
          label = "muted";
          tone = "warn";
          bar = "bottom";
        }
      ];
    }
    {
      index = 8;
      cmd = "lattice-deck mic";
      sync = "mic";
      faces = [
        {
          icon = "mic";
          glyph = g.mic;
          label = "mic";
        }
        {
          icon = "mic-off";
          glyph = g.micOff;
          label = "mic off";
          tone = "warn";
          bar = "bottom";
        }
      ];
    }
    {
      index = 10;
      cmd = webapp "Apple Music";
      faces = [
        {
          icon = "music";
          glyph = g.apple;
          label = "music";
        }
      ];
    }
    {
      index = 11;
      cmd = webapp "YouTube";
      faces = [
        {
          icon = "youtube";
          glyph = g.youtube;
          label = "youtube";
        }
      ];
    }
    {
      # Beside YouTube because the three of them are the same kind of key: a window onto a
      # service, not a control over whatever is already playing.
      index = 12;
      cmd = webapp "Apple TV";
      faces = [
        {
          icon = "apple-tv";
          glyph = g.television;
          label = "apple tv";
        }
      ];
    }
    # What the second seek key left behind. Blank rather than dropped, so the corner keeps
    # its slice of the lattice instead of going dark -- see `blank` above.
    (blank 13)
  ];

  # A Home Assistant device, as a toggle key: the same two-face shape as the local toggles
  # above, and `haEntity` is what makes `lattice-deck sync home` able to find it and read
  # the house back onto it. The two faces are the same thing lit and unlit, so the label is
  # what says which room -- a bulb is a bulb.
  #
  # Written as a function because the three of them differ only in their entity and their
  # reading, and three copies of the same eight lines would be three places to get one of
  # those wrong.
  haToggle =
    {
      index,
      name,
      entity,
      label,
      off,
      on,
    }:
    {
      inherit index;
      cmd = "lattice-ha toggle ${entity}";
      # Not `sync`, which names the one key a reading belongs to and is looked up with `at`.
      # These three share a reading -- `home` repaints all of them in one pass -- so the
      # entity is the marker, and sync_home below is built by filtering on it.
      haEntity = entity;
      faces = [
        {
          icon = name;
          glyph = off;
          inherit label;
        }
        {
          icon = "${name}-on";
          glyph = on;
          inherit label;
          tone = "accent";
          bar = "bottom";
        }
      ];
    };

  # A scene, a script or an automation: one face, because there is no state to come back and
  # report. `lattice-ha activate` reads the domain off the entity id and picks the service
  # for it, so a mood that starts as a scene and later becomes a script is a changed id here
  # and nothing else. The banner it raises is what says the press landed.
  haScene =
    {
      index,
      name,
      entity,
      glyph,
      label,
    }:
    {
      inherit index;
      cmd = "lattice-ha activate ${entity}";
      faces = [
        {
          icon = name;
          inherit glyph label;
        }
      ];
    };

  # Devices along the top, moods along the middle, and the bottom row left as the lattice
  # ground for whatever the house grows next. Two rows rather than one long run, because the
  # two halves are pressed for different reasons: the top three are switches that are on or
  # off and say so, the four below are a whole room set at once and are over the moment they
  # are pressed.
  homePage = [
    (haToggle {
      index = 0;
      name = "bedroom-lights";
      entity = entities.bedroomLights;
      label = "bedroom";
      off = g.bulb;
      on = g.bulbOn;
    })
    (haToggle {
      index = 1;
      name = "bathroom-lights";
      entity = entities.bathroomLights;
      label = "bathroom";
      off = g.bulb;
      on = g.bulbOn;
    })
    (haToggle {
      index = 2;
      name = "bedroom-fan";
      entity = entities.bedroomFan;
      label = "fan";
      off = g.fan;
      on = g.fanOn;
    })
    (blank 3)
    (haScene {
      index = 5;
      name = "bed-time";
      entity = entities.bedTime;
      glyph = g.bed;
      label = "bed time";
    })
    (haScene {
      index = 6;
      name = "calm";
      entity = entities.calm;
      glyph = g.meditation;
      label = "calm";
    })
    (haScene {
      index = 7;
      name = "focus";
      entity = entities.focus;
      glyph = g.target;
      label = "focus";
    })
    (haScene {
      index = 8;
      name = "wind-down";
      entity = entities.windDown;
      glyph = g.dusk;
      label = "wind down";
    })
  ]
  ++ map blank [
    10
    11
    12
    13
  ];

  # The rail on each page, and then every button with its page index attached.
  railFor =
    page:
    lib.imap0 (target: rail: {
      inherit page;
      inherit (rail) index;
      cmd = "lattice-deck page ${toString target}";
      # 1-based in the config: switch_page 0 is what means "this key does not switch pages".
      switchPage = target + 1;
      # The rail's faces are not flipped by the press. `lattice-deck page` sets all three
      # from the page that ended up showing, which is the only thing that knows.
      flip = false;
      state = if target == page then 1 else 0;
      faces = [
        {
          icon = "rail-${lib.elemAt pages target}";
          inherit (rail) glyph;
          tone = "dim";
        }
        {
          icon = "rail-${lib.elemAt pages target}-on";
          inherit (rail) glyph;
          tone = "accent";
          bar = "left";
        }
      ];
    }) railKeys;

  buttons = lib.concatMap (
    page: map (button: button // { inherit page; }) (lib.elemAt pageButtons page) ++ railFor page
  ) (lib.range 0 (lib.length pages - 1));

  pageButtons = [
    desktopPage
    mediaPage
    homePage
  ];

  # Every distinct face, as the artwork module wants them: `index` is what gives a face its
  # slice of the lattice, so it comes from the button rather than from the face. The rail
  # contributes the same six faces on all three pages, which is what `unique` is here for.
  faceArt = lib.unique (
    lib.concatMap (
      button:
      map (face: {
        name = face.icon;
        inherit (button) index;
        glyph = face.glyph or "";
        glyphFont = face.glyphFont or "";
        glyphSize = face.glyphSize or "";
        embed = face.embed or null;
        label = face.label or "";
        tone = face.tone or "plain";
        bar = face.bar or "none";
      }) button.faces
    ) buttons
  );

  # One set of faces per flavour, so the deck can follow lattice-theme: each drawn in that
  # flavour's palette and its default accent pair -- lattice.theme.accent's names, which is
  # what the plain wallpaper wears in it. Deliberately not the wallpaper's accent: that one
  # moves on every click of the wallpaper pill, and every change costs the deck a restart
  # (the config below is read once, at start), where a theme switch is rare enough to pay
  # for one.
  coloursFor =
    flavor:
    let
      p = theme.flavors.${flavor}.palette;
    in
    {
      palette = p;
      accent = p.${theme.accent};
      accentAlt = p.${theme.accentAlt};
    };

  iconsFor = flavor: config.lattice.artwork.deckKeysWith (coloursFor flavor) faceArt;

  # JetBrains Mono by path, not by family: the reading on a key is drawn by streamdeck-ui
  # with Pillow, which takes a font file and has no fontconfig to ask.
  readingFont = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";

  stateFor = flavor: button: index: face: {
    icon = "${iconsFor flavor}/${face.icon}.png";
    # Empty for every key whose label is baked into its PNG. The two that carry a reading get
    # theirs from `lattice-deck sync`, and where the label would be.
    text = face.text or "";
    keys = "";
    write = "";
    command = face.cmd or button.cmd or "";
    switch_page = button.switchPage or 0;
    # 1-based, and 0 means "do not switch": a key with faces to cycle points at the next one
    # round, and anything else stays where it is. Three faces cycle as readily as two -- the
    # power-profile key is the one that does.
    switch_state =
      let
        count = lib.length button.faces;
      in
      if (button.flip or true) && count > 1 then lib.mod (index + 1) count + 1 else 0;
    brightness_change = 0;
    text_vertical_align = "bottom";
    text_horizontal_align = "";
    font = readingFont;
    font_color = theme.flavors.${flavor}.palette.text;
    font_size = 15;
    background_color = "";
  };

  # The config file, in the shape streamdeck_ui/config.py reads: keyed by the deck's serial,
  # then page, then key, then state. The five deck-level fields are all required -- that
  # reader takes them with [] and not .get() -- so none of them can be left out here.
  #
  # One per flavour, like the faces; the seed below picks the one lattice-theme names.
  generatedFor =
    flavor:
    pkgs.writeText "lattice-streamdeck-${flavor}.json" (
      builtins.toJSON {
        streamdeck_ui_version = 2;
        state.${cfg.serial} = {
          brightness = cfg.brightness;
          brightness_dimmed = 0;
          # 0 disables streamdeck-ui's own dimmer, on purpose. With it on, the first press
          # after the deck has dimmed is swallowed to wake it and does nothing else -- and the
          # deck should go dark with the screen anyway, which is hypridle's business and not a
          # timer of its own. See the listener in profiles/graphical.nix.
          display_timeout = 0;
          rotation = 0;
          page = 0;
          buttons = lib.listToAttrs (
            lib.imap0 (page: _: {
              name = toString page;
              value = lib.listToAttrs (
                map (button: {
                  name = toString button.index;
                  value = {
                    state = button.state or 0;
                    states = lib.listToAttrs (
                      lib.imap0 (index: face: {
                        name = toString index;
                        value = stateFor flavor button index face;
                      }) button.faces
                    );
                  };
                }) (lib.filter (button: button.page == page) buttons)
              );
            }) pages
          );
        };
      }
    );

  # Where a live key is, for the sync below: the coordinates live in the button list and are
  # interpolated into the script rather than written out a second time.
  at =
    tag:
    let
      tagged = lib.filter (button: (button.sync or null) == tag) buttons;
    in
    if lib.length tagged != 1 then
      throw "lattice.streamdeck: ${toString (lib.length tagged)} buttons tagged sync = ${tag}"
    else
      "${toString (lib.head tagged).page} ${toString (lib.head tagged).index}";

  rebuildAt =
    let
      tagged = lib.filter (button: button.arm or false) buttons;
    in
    if lib.length tagged != 1 then
      throw "lattice.streamdeck: ${toString (lib.length tagged)} keys marked arm = true"
    else
      "${toString (lib.head tagged).page} ${toString (lib.head tagged).index}";

  # Every key whose face is a Home Assistant device: what sync_home repaints, and -- through
  # the page they all sit on -- what makes switching to that page re-read them.
  haButtons = lib.filter (button: button ? haEntity) buttons;

  # The page those keys are on. Unlike a toggle pressed here, a light switched from a phone,
  # a motion automation or the dial tells this machine nothing at all, so a key can sit wrong
  # for as long as five minutes -- the sync timer is the only thing that would catch it.
  # Re-reading on the way in costs three GETs and makes the keys right whenever they are
  # actually being looked at, which is the only time it matters.
  haPage =
    let
      pagesWith = lib.unique (map (button: button.page) haButtons);
    in
    if lib.length pagesWith != 1 then
      throw "lattice.streamdeck: Home Assistant keys are spread over ${toString (lib.length pagesWith)} pages; sync_home assumes one."
    else
      toString (lib.head pagesWith);

  # What both units below run their children with. A launcher's PATH is the session's, and
  # that is the whole difference between this and waybar.path in profiles/graphical.nix:
  # waybar calls a fixed handful of commands that can be listed, while the deck's keys open
  # apps -- ghostty, thunar, rofi, the lattice-* scripts -- and listing the system profile's
  # contents here would be a second copy of the app list, drifting from the first. Anything
  # that is a package rather than a session app is named by store path in a button command
  # instead. lattice-deck is found this way too, and has to be: its script carries the
  # coordinates of the keys that call it, so naming it by store path would be a cycle.
  #
  # Directories rather than packages, which is unusual for this option and is the point of
  # it: `path` is joined with makeBinPath and merged with the default list (coreutils,
  # findutils, grep, sed, systemd), so this adds the session's profile to that rather than
  # replacing it. Setting environment.PATH directly instead collides with the definition the
  # systemd module derives from this very option.
  #
  # The sync unit needs it every bit as much as the deck does, and for a reason that hides
  # itself: a status script that cannot be found reads, through a command substitution inside
  # a test, as an empty class -- so the key is painted off rather than the sync failing. The
  # deck spent a login wrong about the tailscale tunnel that way, before this was split out.
  sessionPath = [
    "/run/wrappers"
    "/run/current-system/sw"
  ];

  deck = pkgs.writeShellApplication {
    name = "lattice-deck";

    # The session's own programs are deliberately not in here: they are found on the PATH the
    # unit runs with, which is where the deck's bare-name button commands find them too.
    runtimeInputs = [
      streamdeckUi # streamdeckc, the client for the running instance
      pkgs.jq
      pkgs.systemd # busctl, for the power-profile key
      pkgs.playerctl
      pkgs.swayosd # swayosd-client, so a change from the deck raises the same OSD
      pkgs.wireplumber # wpctl, for reading whether a stream is muted
      pkgs.pulseaudio # pactl, for moving the default sink; wpctl has no equivalent
      pkgs.libnotify
      pkgs.coreutils
      pkgs.gnugrep
    ];

    text = ''
      brightness=${toString cfg.brightness}
      # How long an armed rebuild key stays armed.
      arm_seconds=10
      page_file="''${XDG_RUNTIME_DIR:-/tmp}/lattice-deck.page"

      # streamdeckc talks to the running streamdeck-ui over a unix socket in TMPDIR. Every
      # call through here repaints something that is already true elsewhere, so a deck that
      # is unplugged, or a session whose service is not up, is not an error worth reporting:
      # the face simply goes uncorrected until the next sync.
      deck() { streamdeckc "$@" >/dev/null 2>&1 || true; }

      # page button state. SET_TEXT is the other half of this and has no caller now that no
      # key carries a reading -- the config still has the font and the empty string for one,
      # so a key that shows a number again is a face away.
      face() { deck -a SET_STATE -p "$1" -b "$2" -s "$3"; }

      # The deck reads the same status contract waybar does -- one JSON object per script,
      # with a `class` naming the state. It is a string in some of them and an array in
      # others, so it is flattened before it is matched.
      class() { jq -r '[.class] | flatten | .[0] // ""'; }

      sync_dnd() {
        if [ "$(lattice-dnd status | class)" = on ]; then
          face ${at "dnd"} 1
        else
          face ${at "dnd"} 0
        fi
      }

      sync_sunset() {
        if [ "$(lattice-sunset status | class)" = warm ]; then
          face ${at "sunset"} 1
        else
          face ${at "sunset"} 0
        fi
      }

      # Read from lattice-idle rather than from systemctl, so the key and the bar's pill
      # cannot disagree about what "awake" means: both ask the one script, and it is the one
      # that knows stopping hypridle is how this is done.
      sync_awake() {
        if [ "$(lattice-idle status | class)" = awake ]; then
          face ${at "awake"} 1
        else
          face ${at "awake"} 0
        fi
      }

      sync_media() {
        case "$(playerctl status 2>/dev/null || echo Stopped)" in
        Playing) face ${at "media"} 1 ;;
        *) face ${at "media"} 0 ;;
        esac
      }

      # A sink's description rather than its node name, for the banners: "MacBook Pro J414
      # Speakers" is what the key changed, `audio_effect.j414-convolver` is only how it is
      # spelled. `pactl list` is the listing that carries both, and the pairing is
      # positional -- Description follows the Name it belongs to -- so the name is held
      # until its description arrives. Falls back to the node name, which is better than an
      # empty banner if the sink went away between the switch and the read.
      sink_label() {
        pactl list sinks | awk -v want="$1" '
          /^\tName: /        { name = $2 }
          /^\tDescription: / { sub(/^\tDescription: /, ""); if (name == want) { print; exit } }
        ' | grep . || printf '%s' "$1"
      }

      sync_mute() {
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED; then
          face ${at "mute"} 1
        else
          face ${at "mute"} 0
        fi
      }

      sync_mic() {
        if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then
          face ${at "mic"} 1
        else
          face ${at "mic"} 0
        fi
      }

      # The bar's power-profile bubble reads net.hadess.PowerProfiles, and so does this:
      # that is the interface both power-profiles-daemon (the Dell's) and tuned-ppd (this
      # Mac's, see hosts/mac/default.nix) serve, so neither end has to know which daemon is
      # behind it. busctl rather than powerprofilesctl, which belongs to one of the two.
      profile_now() {
        busctl --json=short get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles ActiveProfile 2>/dev/null | jq -r '.data // empty'
      }

      profile_offered() {
        busctl --json=short get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles Profiles 2>/dev/null | jq -r '.data[].Profile.data'
      }

      sync_profile() {
        # No daemon, no repaint: the key keeps whichever face it had rather than claiming a
        # profile that nothing is serving.
        case "$(profile_now)" in
        power-saver) face ${at "profile"} 0 ;;
        balanced) face ${at "profile"} 1 ;;
        performance) face ${at "profile"} 2 ;;
        esac
      }

      # The home page's device keys, read back off the house. One pass over all of them
      # rather than a reading each, because they go stale together and the cost is the round
      # trip, not the key.
      #
      # `unknown` -- no answer from Home Assistant, or an entity id that is not there -- is
      # the case with no branch: the key keeps whichever face it had rather than claiming
      # the lights are off because the network is. sync_profile does the same thing for the
      # same reason.
      home_face() {
        case "$(lattice-ha state "$1" 2>/dev/null)" in
        on) face "$2" "$3" 1 ;;
        off) face "$2" "$3" 0 ;;
        esac
      }

      sync_home() {
        ${
          # The separator carries the indentation of the generated lines: interpolated text
          # is not touched by the ''-string's own dedent, so it has to arrive already at the
          # indent the line above it ends up at.
          lib.concatMapStringsSep "\n  " (
            button: "home_face ${button.haEntity} ${toString button.page} ${toString button.index}"
          ) haButtons
        }
      }

      # The three rail keys, lit for whichever page is showing. Only that page's rail is
      # repainted: the other two are not on screen, and each switch lights its own.
      sync_rail() {
        local shown target=0 index
        shown="$(cat "$page_file" 2>/dev/null || echo 0)"
        for index in ${lib.concatMapStringsSep " " (rail: toString rail.index) railKeys}; do
          if [ "$target" = "$shown" ]; then
            face "$shown" "$index" 1
          else
            face "$shown" "$index" 0
          fi
          target=$((target + 1))
        done
      }

      # The socket exists from the moment streamdeck-ui binds it, which is a second or two
      # after the service starts. Only the sync at login needs to wait for that.
      wait_for_deck() {
        local i
        for i in $(seq 40); do
          [ -S "''${TMPDIR:-/tmp}/streamdeck_ui.sock" ] && return 0
          sleep 0.5
        done
        return 1
      }

      sync() {
        local topic
        if [ "$#" -eq 0 ]; then
          set -- dnd sunset media mute mic profile awake home rail
        fi
        for topic in "$@"; do
          case "$topic" in
          dnd | sunset | media | mute | mic | profile | awake | home | rail) "sync_$topic" ;;
          *)
            echo "lattice-deck: no such reading: $topic" >&2
            exit 2
            ;;
          esac
        done
      }

      case "''${1:-}" in
      sync)
        shift
        if [ "''${1:-}" = --wait ]; then
          shift
          # Nothing to sync to, and nothing wrong either: no deck is plugged in.
          wait_for_deck || exit 0
        fi
        sync "$@"
        ;;

      page)
        target="''${2:?usage: lattice-deck page <index>}"
        printf '%s' "$target" > "$page_file"
        # The key that ran this also carries switch_page, so the page has already changed by
        # now; this is here for a page switch from anywhere else.
        deck -a SET_PAGE -p "$target"
        sync_rail
        # See the note on haPage in modules/nixos/streamdeck.nix: the house is the one
        # subject here that changes without telling us, so its page is re-read on the way in
        # rather than only every five minutes.
        if [ "$target" = ${haPage} ]; then
          sync_home
        fi
        ;;

      play)
        # No player at all is not a failure: the key is just idle.
        playerctl play-pause 2>/dev/null || true
        sleep 0.2
        sync_media
        ;;

      mute)
        swayosd-client --output-volume mute-toggle
        sleep 0.2
        sync_mute
        ;;

      mic)
        swayosd-client --input-volume mute-toggle
        sleep 0.2
        sync_mic
        ;;

      audio)
        # Round-robin through the sinks pipewire-pulse knows about, moving what is already
        # playing over with it -- a default sink that only applies to the next stream to
        # start is not what pressing this means.
        current="$(pactl get-default-sink)"
        mapfile -t sinks < <(pactl list short sinks | cut -f2)
        if [ "''${#sinks[@]}" -lt 2 ]; then
          notify-send -a lattice-deck -i audio-card "Audio output" "Only one output available"
          exit 0
        fi
        next="''${sinks[0]}"
        for i in "''${!sinks[@]}"; do
          if [ "''${sinks[$i]}" = "$current" ]; then
            next="''${sinks[$(((i + 1) % ''${#sinks[@]}))]}"
            break
          fi
        done
        pactl set-default-sink "$next"
        while read -r stream; do
          [ -n "$stream" ] || continue
          pactl move-sink-input "$stream" "$next" 2>/dev/null || true
        done < <(pactl list short sink-inputs | cut -f1)
        notify-send -a lattice-deck -i audio-card "Audio output" "$(sink_label "$next")"
        ;;

      # The recovery for the one way the audio stack here gets wedged. Moving a live stream
      # off the MacBook's speakers -- which the `audio` key above does, and so does the
      # bar's output picker -- takes the speakers with it: the ALSA node behind
      # asahi-audio's convolver hangs up ("poll fd error/hangup (card removed?)" in
      # wireplumber's journal), the software-dsp filter in front of it goes too, and the
      # speakers stop being a device anything can switch back to.
      #
      # Restarting wireplumber is not enough. The node that died belongs to the pipewire
      # daemon, so that is what has to come back; wireplumber and pipewire-pulse follow it
      # because they are its clients and hold handles that the restart invalidates.
      #
      # swayosd is collateral and easy to miss: swayosd-server resolves the default sink
      # once and holds it, so a pipewire that came back underneath leaves every
      # --output-volume call a silent no-op. Separate, and tolerated, because it is not
      # part of the fix -- a host without the OSD should still be able to mend its audio.
      audio-restart)
        notify-send -a lattice-deck -i audio-card \
          -h string:x-canonical-private-synchronous:lattice-deck-audio \
          "Audio" "Restarting PipeWire"

        systemctl --user restart pipewire pipewire-pulse wireplumber
        systemctl --user restart swayosd || true

        # The units are back as soon as they have started, which is a good deal before
        # PipeWire has re-enumerated the hardware and WirePlumber has picked what to route
        # to -- so without this the banner names nothing and the two key faces below sync
        # off a device list that is still empty.
        #
        # What it waits for is a *named* default, not merely a sink existing: in the gap
        # between the two, `pactl get-default-sink` answers "@DEFAULT_SINK@", which is the
        # placeholder for "whatever the server picks" and not a node at all. It reads
        # straight through sink_label, which finds no Name to match and falls back to
        # printing what it was given -- so the first version of this put the literal string
        # @DEFAULT_SINK@ on screen as the name of the speakers.
        #
        # Ten seconds is a ceiling rather than a wait; it breaks in well under one.
        default=""
        for _ in $(seq 40); do
          default="$(pactl get-default-sink 2>/dev/null || true)"
          case "$default" in
          "" | "@DEFAULT_SINK@") default=""; sleep 0.25 ;;
          *) break ;;
          esac
        done

        if [ -n "$default" ]; then
          body="$(sink_label "$default")"
        else
          body="restarted, with nothing to play through yet"
        fi
        notify-send -a lattice-deck -i audio-card \
          -h string:x-canonical-private-synchronous:lattice-deck-audio \
          "Audio" "$body"

        # Whatever came back brings its own mute state, and both faces draw one.
        sync mute mic
        ;;

      profile)
        # Cycled in the key's own order -- saver, balanced, performance -- and through only
        # what this machine's daemon offers, so the face the press flipped to is the one that
        # ends up set. PPD's placeholder driver advertises two of the three; the note in
        # hosts/mac/default.nix is about exactly that.
        mapfile -t offered < <(profile_offered)
        ring=()
        for name in power-saver balanced performance; do
          for have in ''${offered[@]+"''${offered[@]}"}; do
            if [ "$name" = "$have" ]; then ring+=("$name"); fi
          done
        done
        if [ "''${#ring[@]}" -lt 2 ]; then
          notify-send -a lattice-deck -i battery "Power profile" "No profiles to switch between"
          exit 0
        fi
        current="$(profile_now)"
        next="''${ring[0]}"
        for i in "''${!ring[@]}"; do
          if [ "''${ring[$i]}" = "$current" ]; then
            next="''${ring[$(((i + 1) % ''${#ring[@]}))]}"
            break
          fi
        done
        busctl set-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles ActiveProfile s "$next" >/dev/null
        sync_profile
        ;;

      arm)
        # The press that ran this has already flipped the key to its armed face. All that is
        # left is to put it back if the second press does not come.
        (
          sleep "$arm_seconds"
          face ${rebuildAt} 0
        ) &
        ;;

      rebuild)
        face ${rebuildAt} 0
        # The repo's own entry point, which does the sops recipient check and the hyprctl
        # reload that a bare nixos-rebuild would skip.
        set +e
        ${flake}/scripts/rebuild.sh
        status=$?
        set -e
        if [ "$status" -eq 0 ]; then
          printf '\nrebuild finished -- press enter to close '
        else
          printf '\nrebuild failed (%s) -- press enter to close ' "$status"
        fi
        read -r _ || true
        ;;

      dim) deck -a SET_BRIGHTNESS --brightness 0 ;;
      wake) deck -a SET_BRIGHTNESS --brightness "$brightness" ;;

      *)
        cat >&2 <<USAGE
      usage: lattice-deck <verb>

        sync [--wait] [reading...]   repaint the live keys; everything, by default
        page <index>                 switch page and light its rail key
        play | mute | mic | audio    media and audio, with the key repainted after
        audio-restart                restart PipeWire when the speakers vanish
        profile                      cycle the power profile, as the bar's bubble does
        dim | wake                   the deck's own backlight
        arm | rebuild                the two halves of the rebuild key
      USAGE
        exit 2
        ;;
      esac
    '';
  };

  # streamdeck-ui owns this file while it runs: the current page and every toggle's state are
  # written back into it as keys are pressed. So the generated config is copied in rather
  # than symlinked -- it saves with os.replace(tmp, os.path.realpath(path)), which for a
  # symlink into the store means writing *through* it, at a path that is read-only.
  #
  # The copy is refreshed only when the generation it came from changes, and the store path
  # is the stamp that says which one that was. A refresh does drop the runtime half of the
  # file -- which page was showing, which way each toggle was flipped -- and that is the
  # right way round: the generated config is the source of truth, and the sync at login puts
  # the toggles back to what is actually true a second later.
  #
  # Which generation is the flavour lattice-theme last picked (lattice.theme.runtimeState),
  # so a theme switch is a restart of this unit -- lattice-theme does that -- and lands the
  # deck on that flavour's faces. Anything unreadable is the build-time flavour.
  seed = pkgs.writeShellApplication {
    name = "lattice-streamdeck-seed";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      config="''${STREAMDECK_UI_CONFIG:?}"
      stamp="$(dirname "$config")/generation"

      flavor=${
        if theme.runtimeState == null then
          theme.flavor
        else
          "$(cat ${lib.escapeShellArg theme.runtimeState} 2>/dev/null || true)"
      }
      case "$flavor" in
      ${
        lib.concatStrings (
          lib.mapAttrsToList (flavor: _: ''
            ${flavor}) generated=${generatedFor flavor} ;;
          '') theme.flavors
        )
      }*) generated=${generatedFor theme.flavor} ;;
      esac

      if [ "$(cat "$stamp" 2>/dev/null || true)" = "$generated" ]; then
        exit 0
      fi

      install -Dm600 "$generated" "$config"
      printf '%s' "$generated" > "$stamp"
      echo "seeded $config from $generated"
    '';
  };
in
{
  # All three are read here rather than assumed: the keys are drawn by the artwork module,
  # the web-app keys launch what webapps.nix declares, and the home page's keys press the
  # entities homeassistant.nix names.
  imports = [
    ./artwork.nix
    ./homeassistant.nix
    ./webapps.nix
  ];

  options.lattice.streamdeck = {
    serial = lib.mkOption {
      type = lib.types.str;
      default = "AL24J2C03581";
      description = ''
        The deck this layout is for. streamdeck-ui keys its configuration by serial, so this
        is what makes one generated file work on either host -- whichever one the deck is
        plugged into is the one that finds a layout for it. Read it off a connected deck with
        `cat /sys/bus/usb/devices/*/serial` against idVendor 0fd9, or from the title bar of
        `streamdeck` itself.
      '';
    };

    brightness = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 60;
      description = ''
        Backlight, as a percentage. 60 reads well in a lit room; the LCDs wash out in direct
        sun whatever this says. `lattice-deck dim` takes it to 0 and `wake` brings it back
        here, which is how the deck follows the screen going to sleep.
      '';
    };
  };

  config = {
    # Both for the keys, which name lattice-deck bare and find it here through the unit's
    # PATH, and for the shell: `lattice-deck sync` and `lattice-deck audio` are worth having
    # by hand, and `streamdeck` is what opens the GUI once the service is stopped.
    environment.systemPackages = [
      deck
      streamdeckUi
    ];

    # The rules ship with the package: TAG+="uaccess" on Elgato's whole vendor id, at
    # 70-streamdeck.rules. The number is the load-bearing part and it is already right --
    # uaccess is applied by systemd's 73-seat-late.rules, so a tag set after that does
    # nothing at all. See the note on nuphyHidAccess in profiles/graphical.nix, which is the
    # same trap the other way round.
    services.udev.packages = [ streamdeckUi ];

    systemd.user.services = {
      streamdeck = {
        description = "Elgato Stream Deck";

        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        onFailure = [ "lattice-notify-failure@%n.service" ];

        path = sessionPath;

        environment = {
          STREAMDECK_UI_CONFIG = "%S/lattice/streamdeck.json";
          # Otherwise this lands in $HOME as a dotfile.
          STREAMDECK_UI_LOG_FILE = "%S/lattice/streamdeck.log";
        };

        serviceConfig = {
          Type = "simple";
          StateDirectory = "lattice";
          ExecStartPre = lib.getExe seed;
          # -n: no window. With the tray icon patched out above there is no way to raise one
          # either, which is the intended state -- see the note on streamdeckUi.
          ExecStart = "${streamdeckUi}/bin/streamdeck -n";
          Restart = "on-failure";
          # A clean stop takes well under a second (see the QTimer patch on streamdeckUi).
          # Anything longer is a hang, and the default 90s holds up every other unit a
          # switch is restarting.
          TimeoutStopSec = 5;
        };
      };

      # The toggles' faces come from the config file, and the config file is a guess: it was
      # written before the session it is being read into. This is what makes the deck agree
      # with the machine -- at login, and every few minutes after that for the two readings
      # that go stale on their own.
      lattice-deck-sync = {
        description = "Repaint the Stream Deck's live keys";

        after = [ "streamdeck.service" ];
        wantedBy = [ "streamdeck.service" ];
        partOf = [ "graphical-session.target" ];

        # The readings it takes are lattice-dnd and lattice-sunset.
        path = sessionPath;

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe deck} sync --wait";
        };
      };
    };

    # waybar clicks lattice-dnd and lattice-sunset, and both now repaint the deck's key for
    # it as well as signalling the bar. Those scripts find lattice-deck on the PATH of
    # whoever ran them, and waybar's is the fixed list in profiles/graphical.nix -- so it is
    # handed the one command it did not have before.
    systemd.user.services.waybar.path = [ deck ];

    # hypridle's PATH is a fixed list inside its own NixOS module -- hyprland, hyprlock,
    # procps -- so the listener in profiles/graphical.nix that dims the deck with the screen
    # has to be handed the command it names. It goes here rather than there because this is
    # the module that has lattice-deck in scope.
    systemd.user.services.hypridle.path = lib.mkIf config.services.hypridle.enable [ deck ];

    systemd.user.timers.lattice-deck-sync = {
      description = "Re-check what the Stream Deck's toggles are showing";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "5min";
        OnUnitActiveSec = "5min";
        Unit = "lattice-deck-sync.service";
      };
    };

    assertions = [
      {
        assertion = lib.all (button: button.faces != [ ]) buttons;
        message = "lattice.streamdeck: a key with no faces has nothing to draw.";
      }
      {
        # Two faces drawn differently under one name would silently share a PNG -- whichever
        # of them the icon build wrote last.
        assertion = lib.length (lib.unique (map (art: art.name) faceArt)) == lib.length faceArt;
        message = "lattice.streamdeck: two different key faces share an icon name.";
      }
      {
        assertion = flake != null;
        message = "lattice.streamdeck: the rebuild key needs programs.nh.flake, which is where the repo's path is written down.";
      }
    ];
  };
}
