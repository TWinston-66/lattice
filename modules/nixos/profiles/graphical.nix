{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };

  theme = config.lattice.theme;
  inherit (theme) palette;

  # hyprlang writes colours bare, without the leading '#'.
  hex = lib.removePrefix "#";

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
  # which keeps it the image it was before the pool existed and the right one for
  # hyprpaper.conf to name for the moment before the pick lands.
  #
  # An entry is the generator's own argument set, so one only has to name what it changes;
  # the seed is its position in the list, which makes appending a wallpaper cheap and
  # reordering the list a redraw of everything that moved.
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
      accent = palette.mauve;
      accentAlt = palette.pink;
    }
    {
      accent = palette.teal;
      accentAlt = palette.sky;
    }
    {
      accent = palette.peach;
      accentAlt = palette.yellow;
    }
    {
      accent = palette.sapphire;
      accentAlt = palette.teal;
    }
    {
      accent = palette.lavender;
      accentAlt = palette.blue;
    }
    {
      accent = palette.green;
      accentAlt = palette.teal;
    }
    {
      accent = palette.pink;
      accentAlt = palette.mauve;
    }
    {
      accent = palette.maroon;
      accentAlt = palette.peach;
    }
    {
      accent = palette.sky;
      accentAlt = palette.sapphire;
    }
    {
      accent = palette.yellow;
      accentAlt = palette.peach;
    }
    {
      accent = palette.red;
      accentAlt = palette.maroon;
    }
    {
      accent = palette.flamingo;
      accentAlt = palette.rosewater;
    }
    {
      accent = palette.rosewater;
      accentAlt = palette.flamingo;
    }
  ];

  # Every entry is drawn twice, because no single image is the right size on both screens.
  # hyprpaper scales an image to cover whatever output it lands on, so a fixed image gives
  # the mark a fixed *fraction* of every screen -- and a fraction is the wrong invariant.
  # The Samsung on the desk is about 2.3x the panel's width, so an equal fraction made its
  # mark 2.3x the size, while the criterion that actually matters is the one the greeter
  # already uses a few hundred lines up: equal angle at the eye. The desk monitor sits
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

  wallpapersFor =
    screen:
    lib.imap0 (
      seed: entry: config.lattice.artwork.wallpaper (entry // screen // { inherit seed; })
    ) pool;

  panelWallpapers = wallpapersFor screens.panel;
  deskWallpapers = wallpapersFor screens.desk;

  # What hyprpaper.conf and the boot-time default name: the plain drawing at desk size.
  wallpaper = lib.head deskWallpapers;

  # Where the picker records what it set, for the things that cannot be told. hyprlock
  # reads its backgrounds at launch from paths fixed at build time, so pointing it at these
  # is what keeps the lock screen showing the same wallpaper the desktop has; the `color`
  # beside them covers the gap before the first pick, and base is the gradient's own
  # bottom-right stop, so even that reads as the wallpaper's darkest corner. One per screen
  # size, for the same reason there are two of every wallpaper.
  currentDir = "${config.users.users.winston.home}/.cache/lattice";
  currentPanel = "${currentDir}/wallpaper-panel.png";
  currentDesk = "${currentDir}/wallpaper-desk.png";

  # Switching between them, for a bind in ~/.dotfiles and for the login pick below.
  # hyprpaper 0.8 loads an image when it is asked for -- `preload` is gone -- so the pool
  # only has to exist in the store. hyprpaper can also rotate a directory by itself, with
  # `timeout` and `order` in the wallpaper block further down; this stays a command so that
  # the desktop changes once at login and then only when asked.
  #
  # Which size goes where is decided here, at run time, rather than written into
  # hyprpaper.conf: hyprpaper's IPC takes an output *name* and rejects a `desc:` selector
  # (tested -- "Invalid monitor"), and a name is the one thing about a monitor that is not
  # knowable until it is plugged in. Reading the live output list also means the pick is
  # right whether this laptop is docked, undocked, or on a screen it has never seen.
  cycleWallpaper = pkgs.writeShellApplication {
    name = "lattice-wallpaper";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.jq
    ];
    text = ''
      panel=(${lib.concatStringsSep " " panelWallpapers})
      desk=(${lib.concatStringsSep " " deskWallpapers})
      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-wallpaper"
      count=''${#desk[@]}

      # -1 when nothing has been picked yet: the state lives in XDG_RUNTIME_DIR, so each
      # boot starts out with no wallpaper of its own rather than with the first one.
      current=$(cat "$state" 2>/dev/null || echo -1)
      index=$((current < 0 ? 0 : current))

      case "''${1:-next}" in
      next) index=$(((index + 1) % count)) ;;
      prev) index=$(((index - 1 + count) % count)) ;;
      # Drawn from the whole pool when nothing has been picked yet, which is the login
      # case: any of them is a fair wallpaper for the session, the plain one included.
      # A re-roll from a bind is a different question -- it is a request for a change, and
      # landing back on the one already up would read as the pick having silently failed --
      # so that one is drawn from the others.
      random)
        if ((current < 0)); then
          index=$((RANDOM % count))
        else
          index=$(((index + 1 + RANDOM % (count - 1)) % count))
        fi
        ;;
      list)
        for i in $(seq 0 $((count - 1))); do
          printf '%s\t%s\t%s\n' "$i" "''${desk[i]}" "''${panel[i]}"
        done
        exit 0
        ;;
      *[!0-9]*)
        echo "usage: lattice-wallpaper [next|prev|random|list|<index>]" >&2
        exit 2
        ;;
      *) index=$(($1 % count)) ;;
      esac

      # Before hyprpaper is told, and recorded after it is: the lock screen reads these
      # rather than being sent anything, so they should be right even on the login pick,
      # where this races hyprpaper's own start and may have to be retried to get through.
      install -d "${currentDir}"
      ln -sfn "''${panel[index]}" "${currentPanel}"
      ln -sfn "''${desk[index]}" "${currentDesk}"

      # An internal panel is a small screen a forearm away and gets the drawing sized for
      # one; anything else is taken for a monitor across a desk. Matching on the connector
      # name is what hyprland and the kernel both call these, and it covers the Dell's
      # eDP-1 as well as this Mac's.
      apply() {
        local output file
        for output in $(hyprctl monitors -j | jq -r '.[].name'); do
          case "$output" in
          eDP-* | LVDS-* | DSI-*) file="''${panel[index]}" ;;
          *) file="''${desk[index]}" ;;
          esac
          hyprctl hyprpaper wallpaper "$output,$file" || return 1
        done
      }

      # hyprpaper binds its IPC socket a moment after its process starts, so the login pick
      # can arrive before there is anything to answer it -- hyprctl does not wait, it exits
      # nonzero. Retrying here rather than letting the unit fail and restart is what keeps
      # the failure notification worth having: it now means hyprpaper is not coming, not
      # that the pick was a second early. Five seconds is many times the gap ever measured.
      for attempt in {1..10}; do
        if reply=$(apply 2>&1); then
          break
        fi
        if ((attempt == 10)); then
          echo "hyprpaper did not answer after $attempt tries: $reply" >&2
          exit 1
        fi
        sleep 0.5
      done

      echo "$index" >"$state"
    '';
  };

  # hyprsunset runs from session start but idles at its 6000K default, which is no filter
  # at all -- the daemon is only useful once something sets a temperature.
  #
  # Two things about driving it, both found by testing: the `hyprsunset` CLI flags spawn a
  # *new* daemon rather than talking to the running one (it then dies with "A CTM manager
  # is already running"), so control goes through `hyprctl hyprsunset`; and `identity`
  # leaves the reported temperature at its last set value, so it can't be used to detect
  # state. Toggling between 6000K and warm keeps the daemon's own reading authoritative,
  # which means the bar can't desync from the screen and no state file is needed.
  #
  # The warm end is per-host -- lattice.display.sunsetTemperature -- because how strong a
  # given temperature looks depends on the panel; see modules/nixos/display.nix.
  sunset = pkgs.writeShellApplication {
    name = "lattice-sunset";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.procps
    ];
    text = ''
      warm=${toString config.lattice.display.sunsetTemperature}
      neutral=6000

      current() { hyprctl hyprsunset temperature; }

      case "''${1:-toggle}" in
      on)     hyprctl hyprsunset temperature "$warm" >/dev/null ;;
      off)    hyprctl hyprsunset temperature "$neutral" >/dev/null ;;
      toggle)
        if [ "$(current)" -lt "$neutral" ]; then
          hyprctl hyprsunset temperature "$neutral" >/dev/null
        else
          hyprctl hyprsunset temperature "$warm" >/dev/null
        fi
        ;;
      status)
        temp=$(current)
        if [ "$temp" -lt "$neutral" ]; then
          printf '{"text":"󰖔","tooltip":"Night light on - %sK","class":"warm"}\n' "$temp"
        else
          printf '{"text":"󰖙","tooltip":"Night light off - %sK","class":"cool"}\n' "$temp"
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-sunset [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+1 matches the "signal" of the custom/sunset module in ~/.dotfiles/waybar.
      pkill -RTMIN+1 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync sunset || true
    '';
  };

  # Do not disturb, as a mako mode rather than anything of our own: `[mode=dnd] invisible=1`
  # in ~/.dotfiles/mako is the whole implementation, and this only flips the mode and tells
  # the bar. mako owns the state, so the pill cannot desync from the daemon -- the same
  # reason lattice-sunset reads hyprsunset instead of keeping a state file.
  #
  # What `invisible` does and does not do, measured rather than read off the man page:
  # a hidden notification is still *live*, so nothing is dropped -- leaving the mode shows
  # whatever is still up, which for critical means everything, since urgency=critical carries
  # default-timeout=0. A normal notification instead times out unseen while the mode is on
  # and lands in the history, recoverable on SUPER+ALT+N. So the count below is the number
  # that will appear the moment the mode goes off, not the number missed.
  dnd = pkgs.writeShellApplication {
    name = "lattice-dnd";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      pkgs.gnugrep
      pkgs.procps
    ];
    text = ''
      # -x, because `makoctl mode` prints one mode per line and a substring match would
      # answer yes to any mode with dnd in the name.
      enabled() { makoctl mode | grep -qx dnd; }

      case "''${1:-toggle}" in
      on)  makoctl mode -a dnd >/dev/null ;;
      off) makoctl mode -r dnd >/dev/null ;;
      toggle)
        if enabled; then
          makoctl mode -r dnd >/dev/null
        else
          makoctl mode -a dnd >/dev/null
        fi
        ;;
      status)
        if enabled; then
          waiting=$(makoctl list -j | jq length)
          if [ "$waiting" -gt 0 ]; then
            printf '{"text":"󰂛","tooltip":"Do not disturb - %s waiting","class":"on"}\n' "$waiting"
          else
            printf '{"text":"󰂛","tooltip":"Do not disturb","class":"on"}\n'
          fi
        else
          printf '{"text":"󰂚","tooltip":"Notifications on","class":"off"}\n'
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-dnd [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+4 matches the "signal" of the custom/dnd module in ~/.dotfiles/waybar. 1, 2
      # and 3 are sunset, tailscale and weather.
      pkill -RTMIN+4 waybar || true

      # And the Stream Deck's key for it, the other consumer of the `status` above. `|| true`
      # for the same reason as the signal: a deck that is unplugged, or a lattice-deck that
      # is not on this caller's PATH, must not fail the toggle that has already happened.
      lattice-deck sync dnd || true
    '';
  };

  # The keep-awake switch, and the one mechanism behind both surfaces that offer it.
  #
  # waybar's built-in idle_inhibitor was the obvious thing and is the wrong shape here: it
  # holds a zwp_idle_inhibit_manager_v1 lock on waybar's *own* surface, which nothing
  # outside waybar can read or release. So a Stream Deck key could only ever have been a
  # second switch disagreeing with the first -- press one and the other still shows the
  # opposite, both of them telling the truth about their own lock.
  #
  # hypridle is what actually locks the session, blanks the screens and dims the deck, so
  # stopping it is the honest way to say "stay awake" -- and it stops all three rather than
  # only the blank, which is what the inhibit lock did too. `systemctl is-active` is then a
  # state both surfaces can read, and neither owns.
  #
  # `on` means staying awake, matching the bar's old activated/deactivated. That it stops a
  # unit to do so is the sort of inversion worth saying out loud.
  idleInhibit = pkgs.writeShellApplication {
    name = "lattice-idle";
    runtimeInputs = [
      pkgs.systemd
      pkgs.procps
    ];
    text = ''
      unit=hypridle.service

      awake() { ! systemctl --user is-active --quiet "$unit"; }

      case "''${1:-toggle}" in
      on)  systemctl --user stop "$unit" ;;
      off) systemctl --user start "$unit" ;;
      toggle)
        if awake; then
          systemctl --user start "$unit"
        else
          systemctl --user stop "$unit"
        fi
        ;;
      status)
        if awake; then
          printf '{"text":"󰅶","tooltip":"Staying awake","class":"awake"}\n'
        else
          printf '{"text":"󰾪","tooltip":"Idle timers active","class":"idle"}\n'
        fi
        exit 0
        ;;
      *)
        echo "usage: lattice-idle [toggle|on|off|status]" >&2
        exit 2
        ;;
      esac

      # RTMIN+5 matches the "signal" of custom/idle in ~/.dotfiles/waybar. 1 to 4 are
      # sunset, tailscale, weather and dnd.
      pkill -RTMIN+5 waybar || true

      # And the deck's key for it, as the other three do.
      lattice-deck sync awake || true
    '';
  };

  # Tailscale has no Linux GUI, so the bar pill is the interface: the tooltip carries the
  # connection report and a click brings the tunnel up or down. `tailscale status --json`
  # exposes the daemon's own view, so there is no separate session state to keep in step --
  # the same reason lattice-sunset asks hyprsunset rather than tracking the temperature.
  #
  # Peer counts skip exit nodes: this tailnet has the Mullvad integration on, so 533 of its
  # 539 peers are exit nodes and counting them would hide the six real devices. Health is
  # reported as a second CSS class, so a running-but-warning node doesn't read as a
  # healthy green pill. The glyphs are Material Design Icons from Nerd Fonts 3.5.0;
  # there is no Tailscale mark in the set, and these are recoloured by style.css anyway.
  tailscale = pkgs.writeShellApplication {
    name = "lattice-tailscale";
    runtimeInputs = [
      pkgs.tailscale
      pkgs.jq
      pkgs.procps
      pkgs.xdg-utils
      pkgs.coreutils # sleep, while waiting on the sign-in URL
    ];
    text = ''
      glyph_connected=$'\U000F0582' # md-vpn
      glyph_stopped=$'\U000F0319'   # md-lan_disconnect
      glyph_login=$'\U000F08EE'     # md-lock_alert
      glyph_alert=$'\U000F0ECC'     # md-shield_alert

      # Waybar's custom-module JSON. `class` is an array, so a state and a warning can both
      # apply; style.css keys off the names. Built through jq rather than printf so newlines
      # and any awkward character in a hostname or health line are escaped, not trusted.
      emit() {
        local text="$1" tooltip="$2"
        shift 2
        jq -cn \
          --arg text "$text" \
          --arg tooltip "$tooltip" \
          --argjson class "$(jq -cn --args '$ARGS.positional' "$@")" \
          '{text: $text, tooltip: $tooltip, class: $class}'
      }

      status() {
        local json
        if ! json="$(tailscale status --json 2>/dev/null)" || [ -z "$json" ]; then
          emit "$glyph_stopped" $'Tailscale is not responding\ntailscaled may be stopped' stopped
          return 0
        fi

        local backend text
        local -a classes lines

        backend="$(jq -r '.BackendState // "NoState"' <<<"$json")"

        case "$backend" in
        Running)
          local host ip tailnet dns advertise online devs exit_id exit_name health
          host="$(jq -r '.Self.HostName // "this device"' <<<"$json")"
          ip="$(jq -r '.Self.TailscaleIPs[0] // ""' <<<"$json")"
          dns="$(jq -r '.Self.DNSName // "" | sub("\\.$"; "")' <<<"$json")"
          tailnet="$(jq -r '.CurrentTailnet.Name // ""' <<<"$json")"
          advertise="$(jq -r '.Self.ExitNode // false' <<<"$json")"

          read -r online devs <<<"$(jq -r '[([.Peer[] | select((.ExitNodeOption | not) and .Online)] | length), ([.Peer[] | select(.ExitNodeOption | not)] | length)] | @tsv' <<<"$json")"

          lines=("Tailscale: Connected" "$host  $ip")
          if [ -n "$tailnet" ]; then lines+=("tailnet: $tailnet"); fi
          lines+=("devices: $online/$devs online")

          # Using an exit node is the difference between "the tunnel is up" and "traffic
          # is actually going through Mullvad", so it gets its own class for style.css to
          # colour on: teal with one, red without. ExitNodeStatus is null unless this node
          # is routing through one; its ID names the peer to show in the tooltip.
          exit_id="$(jq -r '.ExitNodeStatus.ID // empty' <<<"$json")"
          local exit_class
          if [ -n "$exit_id" ]; then
            exit_name="$(jq -r --arg id "$exit_id" '[.Peer[] | select(.ID == $id)][0].HostName // $id' <<<"$json")"
            lines+=("exit node: $exit_name")
            exit_class=exit-node
          else
            lines+=("exit node: none")
            exit_class=no-exit-node
          fi
          if [ "$advertise" = true ]; then
            lines+=("advertising as an exit node")
          fi
          if [ -n "$dns" ]; then lines+=("$dns"); fi

          # Health is where tailscaled reports route conflicts and the like. Showing it as
          # a second class is the whole reason the running state isn't just the vpn glyph.
          health="$(jq -r '.Health // [] | .[]' <<<"$json")"
          if [ -n "$health" ]; then
            text="$glyph_alert"
            classes=(running warning)
            while IFS= read -r line; do lines+=("warning: $line"); done <<<"$health"
          else
            text="$glyph_connected"
            classes=(running "$exit_class")
          fi
          ;;

        Starting)
          text="$glyph_connected"
          classes=(starting)
          lines=("Tailscale: starting")
          ;;

        NeedsLogin | NeedsMachineAuth)
          local authurl
          text="$glyph_login"
          classes=(needs-login)
          authurl="$(jq -r '.AuthURL // empty' <<<"$json")"
          if [ "$backend" = NeedsMachineAuth ]; then
            lines=("Tailscale: waiting for approval")
          else
            lines=("Tailscale: signed out" "click to sign in")
          fi
          if [ -n "$authurl" ]; then lines+=("$authurl"); fi
          ;;

        *)
          text="$glyph_stopped"
          classes=(stopped)
          lines=("Tailscale: disconnected" "click to connect")
          ;;
        esac

        local tooltip
        printf -v tooltip '%s\n' "''${lines[@]}"
        emit "$text" "''${tooltip%$'\n'}" "''${classes[@]}"
      }

      toggle() {
        local json backend
        json="$(tailscale status --json 2>/dev/null || true)"
        backend="$(jq -r '.BackendState // "NoState"' <<<"$json" 2>/dev/null || echo NoState)"

        case "$backend" in
        Running)
          tailscale down
          ;;

        # Signed out, so there is no tunnel to raise -- there is a sign-in to finish, and
        # that needs a browser. `tailscale up` cannot be the whole answer here: it prints
        # the sign-in URL on its own stdout and then blocks until the browser leg
        # completes, and it has to be detached or the click would hang forever, which
        # threw the URL away and left the pill sitting at "signed out" with nothing on
        # screen. tailscaled publishes the same URL in its status once a flow exists --
        # the copy the tooltip already shows -- so take it from there and open it.
        NeedsLogin | NeedsMachineAuth)
          local authurl n=0
          authurl="$(jq -r '.AuthURL // empty' <<<"$json" 2>/dev/null || true)"

          # No flow yet: ask for one. The URL is minted by the control plane, so it lands
          # a beat after the request rather than with it. 10s is a generous round trip and
          # still short enough that an unreachable control plane doesn't leave this
          # spinning behind the bar.
          if [ -z "$authurl" ]; then
            tailscale up >/dev/null 2>&1 &
            disown || true

            while [ -z "$authurl" ] && [ "$n" -lt 40 ]; do
              sleep 0.25
              n=$((n + 1))
              authurl="$(tailscale status --json 2>/dev/null | jq -r '.AuthURL // empty' 2>/dev/null || true)"
            done
          fi

          if [ -n "$authurl" ]; then
            xdg-open "$authurl" >/dev/null 2>&1 &
            disown || true
          fi
          ;;

        *)
          # Authenticated and merely down, or the daemon has no opinion yet: `up` returns
          # at once, so the signal below lands on the new state.
          tailscale up >/dev/null 2>&1 &
          disown || true
          ;;
        esac

        # RTMIN+2 matches the "signal" of custom/tailscale in ~/.dotfiles/waybar. After a
        # sign-in it only repaints the pill as "signed out" again -- the browser leg is
        # still in progress at this point -- so the switch to connected arrives with the
        # module's 30s interval.
        pkill -RTMIN+2 waybar 2>/dev/null || true
      }

      web() {
        xdg-open "https://login.tailscale.com/admin/machines" >/dev/null 2>&1 &
        disown || true
      }

      case "''${1:-status}" in
      status) status ;;
      toggle) toggle ;;
      web) web ;;
      *)
        echo "usage: lattice-tailscale [status|toggle|web]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # Weather, from Open-Meteo: no API key, no account, and -- the reason it is this rather
  # than the usual wttr.in one-liner -- it takes explicit coordinates. Anything that
  # geolocates by IP reads the Tailscale exit node instead of the laptop, and this tailnet
  # has the Mullvad integration on (see lattice-tailscale above), so the pill would quietly
  # report another country's weather most of the time. The coordinates are
  # lattice.weather.* in modules/nixos/weather.nix.
  #
  # The pill is glyph + temperature + apparent temperature, the last dimmed with Pango
  # markup rather than split into a second module, so the whole reading stays one bubble on
  # a bar whose right side is already full. Conditions are carried by the glyph and the
  # colour, which is why the text spells out neither: the script emits a class per
  # temperature band and style.css colours it, the same contract lattice-sunset and
  # lattice-tailscale use.
  #
  # The last good payload is cached in XDG_RUNTIME_DIR, so a resume with the Wi-Fi still
  # associating re-renders the previous reading greyed (.stale) instead of blanking the
  # pill. Runtime dir rather than /var/lib: a reading that survived a reboot would be too
  # old to show anyway.
  weather = pkgs.writeShellApplication {
    name = "lattice-weather";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.procps
      pkgs.coreutils # mktemp
    ];
    text = ''
      lat=${config.lattice.weather.latitude}
      lon=${config.lattice.weather.longitude}
      label=${lib.escapeShellArg config.lattice.weather.label}

      cache="''${XDG_RUNTIME_DIR:-/tmp}/lattice-weather.json"

      # forecast_days=1 because the tooltip only shows today's high, low and sunset; the
      # hourly block is left off for the same reason. `timezone=auto` resolves from the
      # coordinates, so the sunset timestamp is already local and needs no conversion.
      api="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day&daily=temperature_2m_max,temperature_2m_min,sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=1"

      # Written to a temp file and moved into place only once jq confirms the body parses,
      # so a captive portal's login page or a truncated response can't overwrite a good
      # cache with something that renders as an empty pill.
      fetch() {
        local tmp
        tmp=$(mktemp)
        if curl -fsS --max-time 10 "$api" -o "$tmp" && jq -e '.current.temperature_2m' "$tmp" >/dev/null 2>&1; then
          mv "$tmp" "$cache"
          return 0
        fi
        rm -f "$tmp"
        return 1
      }

      # 16 points of 22.5 degrees each. Integer arithmetic, so the half-degree is carried by
      # scaling both sides by 10: index = (deg * 10 + 112) / 225, which rounds to the
      # nearest point rather than truncating toward N.
      compass() {
        local points=(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW)
        echo "''${points[$((($1 * 10 + 112) / 225 % 16))]}"
      }

      # WMO 4677, as Open-Meteo documents it. Codes are grouped to the glyphs the Material
      # Design range actually has -- there is no "slight vs moderate drizzle" mark -- and
      # the day/night split only exists for the three clear-ish codes, which are the only
      # ones that look wrong with a sun in them at midnight.
      icon_for() {
        case "$1" in
        0)        if [ "$2" = 1 ]; then echo "󰖙 Clear"; else echo "󰖔 Clear"; fi ;;
        1)        if [ "$2" = 1 ]; then echo "󰖙 Mainly clear"; else echo "󰖔 Mainly clear"; fi ;;
        2)        if [ "$2" = 1 ]; then echo "󰖕 Partly cloudy"; else echo "󰼱 Partly cloudy"; fi ;;
        3)        echo "󰖐 Overcast" ;;
        45 | 48)  echo "󰖑 Fog" ;;
        51 | 53 | 55) echo "󰼳 Drizzle" ;;
        56 | 57)  echo "󰙿 Freezing drizzle" ;;
        61 | 63)  echo "󰖖 Rain" ;;
        65)       echo "󰖗 Heavy rain" ;;
        66 | 67)  echo "󰙿 Freezing rain" ;;
        71 | 73)  echo "󰖘 Snow" ;;
        75)       echo "󰼶 Heavy snow" ;;
        77)       echo "󰖘 Snow grains" ;;
        80 | 81)  echo "󰖖 Rain showers" ;;
        82)       echo "󰖗 Violent rain showers" ;;
        85 | 86)  echo "󰖘 Snow showers" ;;
        95)       echo "󰖓 Thunderstorm" ;;
        96 | 99)  echo "󰼯 Thunderstorm with hail" ;;
        *)        echo "󰼮 WMO $1" ;;
        esac
      }

      # Fahrenheit bands. The glyph says what is falling out of the sky; the colour says
      # whether to put a coat on, which is the part a forecast usually gets consulted for.
      band_for() {
        if   [ "$1" -lt 32 ]; then echo freezing
        elif [ "$1" -lt 50 ]; then echo cold
        elif [ "$1" -lt 75 ]; then echo mild
        elif [ "$1" -lt 90 ]; then echo warm
        else echo hot
        fi
      }

      render() {
        local stale="$1"
        local code isday temp feels hum wind wdir hi lo sunset
        local icon desc band classes text tooltip

        # One jq pass into positional fields rather than ten invocations. round() gives
        # integers, which is what the [ -lt ] comparisons in band_for need and what the
        # pill should show -- a tenth of a degree is noise at this size.
        IFS=$'\t' read -r code isday temp feels hum wind wdir hi lo sunset < <(
          jq -r '[
            .current.weather_code,
            .current.is_day,
            (.current.temperature_2m | round),
            (.current.apparent_temperature | round),
            .current.relative_humidity_2m,
            (.current.wind_speed_10m | round),
            (.current.wind_direction_10m | round),
            (.daily.temperature_2m_max[0] | round),
            (.daily.temperature_2m_min[0] | round),
            (.daily.sunset[0] | split("T")[1])
          ] | @tsv' "$cache"
        )

        read -r icon desc <<<"$(icon_for "$code" "$isday")"
        band=$(band_for "$temp")

        classes=$(jq -cn --arg b "$band" --argjson s "$stale" \
          'if $s then [$b, "stale"] else [$b] end')

        # Pango markup: the apparent temperature is the same size but dimmed, so it reads
        # as a qualifier on the number beside it rather than as a second reading competing
        # with it. waybar runs a custom module's text through set_markup, so this is parsed
        # rather than shown literally.
        #
        # Both temperatures are right-aligned in a three-character field. The bar font is
        # JetBrains Mono, so that makes the pill a fixed width whatever the reading is --
        # which is what lets the centre group's counterweight be a constant. Without it the
        # pill would be two characters narrower at 73° than at -5°, and the clock beside it
        # would wander off centre as the temperature changed. Three characters covers
        # -99..999; a reading outside that widens the pill, and the clock drifts by half the
        # difference until it comes back.
        text=$(printf '%s %3s° <span alpha="55%%">%3s°</span>' "$icon" "$temp" "$feels")

        tooltip=$(printf '<b>%s</b>\n%s\nH %s°  L %s°\nWind %s mph %s · Humidity %s%%\nSunset %s' \
          "$label" "$desc" "$hi" "$lo" "$wind" "$(compass "$wdir")" "$hum" "$sunset")

        if [ "$stale" = true ]; then
          tooltip=$(printf '%s\n<i>Offline - last known reading</i>' "$tooltip")
        fi

        jq -cn --arg text "$text" --arg tooltip "$tooltip" --argjson class "$classes" \
          '{text: $text, tooltip: $tooltip, class: $class}'
      }

      status() {
        local stale=false
        fetch || stale=true

        # Nothing cached and nothing fetched -- a cold boot with no network yet. A muted
        # glyph rather than an empty module, which waybar would collapse to a bare pill.
        if [ ! -s "$cache" ]; then
          printf '{"text":"󰅤","tooltip":"Weather unavailable","class":["unavailable"]}\n'
          return
        fi

        render "$stale"
      }

      case "''${1:-status}" in
      status) status ;;
      # The signal is the whole of it: waybar re-runs `status` on receipt, and that is what
      # re-fetches. Doing the fetch here as well would make every click two round trips.
      # RTMIN+3 matches the "signal" of custom/weather in ~/.dotfiles/waybar.
      refresh) pkill -RTMIN+3 waybar 2>/dev/null || true ;;
      *)
        echo "usage: lattice-weather [status|refresh]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # rofi with the calculator mode compiled in. A rofi plugin is a shared object loaded from
  # rofi's own -plugin-path, so `rofi-calc` on its own in systemPackages would be a file
  # nothing ever opens: the nixpkgs wrapper is what joins the plugin into $out/lib/rofi and
  # passes that flag. `rofi -h` lists it under "Detected modes" once it is there, which is
  # the quick check that a nixpkgs bump hasn't broken the plugin ABI -- rofi 2.0 changed it,
  # and a plugin built against the wrong one is silently not loaded.
  #
  # Every caller below takes this one rather than pkgs.rofi. Two wrappers differing only in
  # the plugin would otherwise collide in the system profile, and whichever won would decide
  # whether `-show calc` finds anything.
  #
  # The engine is libqalculate, which is what makes this worth a launcher mode rather than a
  # window: bases and units convert in place (`0xff to bin`, `1 GiB to MB`, `0.1+0.2 to
  # double` for the IEEE bits), solve/diff/sum and matrices work, and integers stay exact.
  # nixpkgs patches the plugin's `qalc` lookup to an absolute store path, so nothing needs to
  # be on PATH for the mode itself; libqalculate is in systemPackages below only for the
  # `qalc` CLI, and adds no closure of its own because the plugin already pulls it in.
  rofiWithCalc = pkgs.rofi.override { plugins = [ pkgs.rofi-calc ]; };

  # The Wi-Fi picker behind the network pill. NetworkManager's own front ends are either a
  # tray applet that would duplicate the pill (nm-applet, already turned down in
  # profiles/laptop.nix) or a window (nm-connection-editor); what is actually wanted from
  # the bar is the short list of networks in range. So this is rofi -- already themed from
  # /etc/xdg/rofi/lattice.rasi, already the launcher, and it lets an SSID be found by
  # typing rather than by hunting down a list.
  #
  # It raises no notifications of its own for joining or leaving: lattice-network-notify
  # (profiles/laptop.nix) is already watching `nmcli monitor` and reports connecting,
  # connected and failed for every interface, so anything said here would arrive as a
  # second pill saying the same thing. The two it does raise are for the cases the monitor
  # cannot describe, because no connection is attempted at all.
  wifiMenu = pkgs.writeShellApplication {
    name = "lattice-wifi";
    runtimeInputs = [
      pkgs.networkmanager
      rofiWithCalc
      pkgs.gawk
      pkgs.libnotify
      # makoctl, to take the scan banner back down; see scanning() below.
      pkgs.mako
    ];
    text = ''
      # Anchored under the right end of the bar rather than centred like the launcher.
      # The offsets are counted from the *usable* area, not from the screen: waybar holds
      # a layer-shell exclusive zone, so a north-east anchor already starts below it, at
      # the bar's bottom edge. y-offset is therefore the gap itself -- 5px, the same
      # spacing the pills use between themselves -- and not the 37 it would take to clear
      # a bar that had to be measured (margin-top 4 plus height 28), which double-counts
      # it and hangs the menu 37px low. Measured with `hyprctl layers`: waybar sits at
      # xywh 10 4 1324 28, and the menu lands at y 32 with an offset of 0, y 37 with 5.
      #
      # x-offset has no exclusive zone to account for, so -10 is waybar's own margin-right
      # and lines the menu's right edge up with the last pill.
      #
      # It is not put under the network pill itself -- every pill to its right is variable
      # width (the battery percentage, the tailscale state), so there is no fixed offset
      # that would stay under it.
      #
      # The rest is what makes this read as a bar dropdown rather than as the launcher
      # wearing a different position. The launcher is a full-attention surface and sized
      # for it; this is a glance, so the type is two points down from the 12 in
      # ~/.dotfiles/rofi/config.rasi and the rows are tightened to match. Overriding it
      # here rather than in config.rasi is deliberate: config.rasi still dresses `rofi
      # -show drun` at its own size.
      theme='
        window { location: north east; anchor: north east; x-offset: -10px; y-offset: 5px; width: 340px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { padding: 7px 10px; }
        element { padding: 5px 10px; }
        listview { lines: 12; }

        /* The connected network, marked with rofi -a. config.rasi draws an active row in
           lavender, which reads as a shade of the ordinary text rather than as a state --
           the launcher has nothing to mark, so the colour was never chosen for this.
           Green instead, the same "this is up" green the battery pill uses, and the
           accent block inverts to dark-on-green when the cursor is on it, the way
           selected.urgent already does. */
        element normal.active, element alternate.active { text-color: @green; }
        element selected.active { background-color: @green; text-color: @crust; }
      '

      # rofi ships the convention for a list you browse: one click highlights a row, two
      # accept it. This is a menu you pick from, and every other surface on the bar acts
      # on the first click, so accept moves onto the single primary click. Select has to
      # be unbound in the same breath -- leave it and both bindings want the same button.
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      # -mesg is the one string rofi renders as pango markup, so an SSID with an ampersand
      # in it would otherwise take the whole message down with a parse error.
      pango() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g'; }

      notice() {
        notify-send -a lattice-wifi -i "$1" \
          -h string:x-canonical-private-synchronous:lattice-wifi "$2" "''${3:-}"
      }

      # The profile whose stored SSID matches, if there is one. `connection show` reports the
      # profile *name*, which is usually the SSID but does not have to be, so the ssid
      # property is what gets compared. UUIDs are listed rather than names because a UUID
      # cannot contain a colon, which keeps the terse output trivially splittable.
      profile_for() {
        local uuid ssid
        while IFS= read -r uuid; do
          ssid=$(nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null || true)
          if [ "$ssid" = "$1" ]; then printf '%s' "$uuid"; return 0; fi
        done < <(nmcli -g UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')
        return 1
      }

      connect() {
        local ssid=$1 uuid password

        case "''${security["$ssid"]}" in
        *802.1X*)
          # Enterprise wants an EAP method, an identity and usually a CA certificate. That
          # is more than one prompt can collect, and a half-filled profile fails in ways
          # that are harder to unpick than never having made one.
          notice network-wireless-symbolic "Enterprise network" \
            "$ssid needs 802.1X settings -- join it once with nmtui"
          return 0
          ;;
        esac

        # A known network is brought up from its saved profile, which is also what holds the
        # stored key; only a genuinely new secured network reaches the prompt.
        if uuid=$(profile_for "$ssid"); then
          nmcli connection up uuid "$uuid" >/dev/null 2>&1 || true
        elif [ -z "''${security["$ssid"]}" ]; then
          nmcli device wifi connect "$ssid" >/dev/null 2>&1 || true
        else
          password=$(
            rofi -dmenu -password -p "Password" -mesg "Password for $(pango "$ssid")" \
              -theme-str "$theme" \
              -theme-str 'mainbox { children: [ inputbar, message ]; }' </dev/null
          ) || return 0
          [ -n "$password" ] || return 0
          nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1 || true
        fi
      }

      device=$(nmcli -g DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1; exit }')
      if [ -z "$device" ]; then
        notice network-wireless-offline-symbolic "No Wi-Fi device" "NetworkManager reports no wifi interface"
        exit 0
      fi

      # Nothing to list while the radio is off, and the only useful thing to offer is
      # turning it back on -- so that is the whole menu.
      if [ "$(nmcli radio wifi)" != enabled ]; then
        choice=$(printf '󰖩  Turn Wi-Fi on\n' |
          rofi -dmenu -i -no-cycle -format i -p "Wi-Fi" -mesg "Wi-Fi is off" \
            -theme-str "$theme" "''${click[@]}" || true)
        [ "''${choice:-}" = 0 ] && nmcli radio wifi on
        exit 0
      fi

      # A sweep of the band takes ~6s on this radio and NetworkManager ages its results
      # out, so a menu that insisted on a current list would routinely leave the click
      # unanswered for six seconds. It never waits: the menu is always drawn from the
      # cache nmcli returns instantly (--rescan no), and when that cache holds nothing but
      # the network already joined a sweep is asked for in the background, so the list is
      # there the next time rather than this time. Rescan is the row that waits on
      # purpose, and --rescan yes is what blocks until the sweep finishes.
      #
      # SSID is last in -f on purpose. nmcli's terse output escapes a colon inside a value
      # as '\:', which would shift every field after it -- with the SSID last, the first
      # three splits happen before any of that and the rest of the line is the SSID,
      # whatever it contains.
      scan() {
        nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "$1"
      }

      # The blocking sweep needs to say why the menu has not come back, but mako's
      # default-timeout is 15s -- more than twice the scan -- so a fire-and-forget banner
      # outlives the thing it was explaining and sits on top of the menu that replaced it.
      # `notify-send -p` hands back the id it was given, which makoctl closes the moment
      # the scan returns, so the banner lasts exactly as long as the wait does.
      scanning() {
        local id
        id=$(notify-send -p -a lattice-wifi -i network-wireless-acquiring-symbolic \
          -h string:x-canonical-private-synchronous:lattice-wifi "Scanning for networks")
        lines=$(scan yes)
        [ -n "$id" ] && makoctl dismiss -n "$id" >/dev/null 2>&1 || true
      }

      rescan=no
      while true; do
        if [ "$rescan" = yes ]; then
          scanning
          rescan=no
        else
          lines=$(scan no)
          if [ "$(printf '%s\n' "$lines" | awk 'NF' | wc -l)" -le 1 ]; then
            nmcli device wifi rescan >/dev/null 2>&1 &
          fi
        fi

        unset best security
        declare -A best security
        active=""

        while IFS= read -r line; do
          inuse=''${line%%:*}; rest=''${line#*:}
          signal=''${rest%%:*}; rest=''${rest#*:}
          sec=''${rest%%:*}; ssid=''${rest#*:}
          ssid=''${ssid//\\:/:}

          # A hidden network reports an empty SSID and there is nothing to click on.
          [ -n "$ssid" ] || continue

          # One network is usually several APs, and both bands of each; keep the strongest
          # reading rather than listing the same SSID once per radio.
          if [ -z "''${best["$ssid"]:-}" ] || [ "$signal" -gt "''${best["$ssid"]}" ]; then
            best["$ssid"]=$signal
            security["$ssid"]=$sec
          fi
          [ "$inuse" = "*" ] && active=$ssid
        done <<<"$lines"

        # The actions come first, and not as a matter of taste: the network list is the
        # part that may be a stale cache or empty, and Rescan is what fixes that -- so the
        # row that answers a disappointing list has to be above it, not below however many
        # networks did turn up. They are a parallel array of verbs, because the choice
        # comes back as an index and nothing should have to parse a rendered row apart.
        rows=()
        actions=()
        if [ -n "$active" ]; then
          actions+=(disconnect)
          rows+=("󰅖  Disconnect")
        fi
        actions+=(rescan)
        rows+=("󰑓  Rescan")
        actions+=(radio-off)
        rows+=("󰖪  Turn Wi-Fi off")
        offset=''${#actions[@]}

        mapfile -t ordered < <(
          for ssid in "''${!best[@]}"; do printf '%s\t%s\n' "''${best["$ssid"]}" "$ssid"; done |
            sort -rn -k1,1 | cut -f2-
        )

        selected=()
        for ssid in "''${ordered[@]}"; do
          signal=''${best["$ssid"]}
          if [ "$signal" -ge 75 ]; then icon=󰤨
          elif [ "$signal" -ge 50 ]; then icon=󰤥
          elif [ "$signal" -ge 25 ]; then icon=󰤢
          else icon=󰤟
          fi

          lock=" "
          [ -n "''${security["$ssid"]}" ] && lock=󰌾

          # rofi's -a marks a row "active", which the theme already draws in lavender --
          # so the network in use is coloured rather than carrying a marker glyph that
          # would push the columns out of line.
          [ "$ssid" = "$active" ] && selected=(-a "''${#rows[@]}")

          rows+=("$(printf '%s  %-20.20s %3s%%  %s' "$icon" "$ssid" "$signal" "$lock")")
        done

        # Enter should join the strongest network, not fire whichever action happens to
        # sit in the first row -- so the cursor starts below them, and the actions are
        # reached by scrolling up or by typing their name.
        start=()
        [ "''${#ordered[@]}" -gt 0 ] && start=(-selected-row "$offset")

        if [ -n "$active" ]; then
          mesg="Connected to $(pango "$active")"
        else
          mesg="$device  not connected"
        fi

        choice=$(printf '%s\n' "''${rows[@]}" |
          rofi -dmenu -i -no-cycle -format i -p "Wi-Fi" -mesg "$mesg" \
            -theme-str "$theme" "''${click[@]}" "''${selected[@]}" "''${start[@]}" || true)
        [ -n "''${choice:-}" ] || exit 0

        if [ "$choice" -ge "$offset" ]; then
          # Selecting the network already in use should do nothing rather than tear the
          # connection down and put it straight back up.
          ssid=''${ordered[$((choice - offset))]}
          [ "$ssid" = "$active" ] || connect "$ssid"
          exit 0
        fi

        case "''${actions[$choice]}" in
        disconnect)
          nmcli device disconnect "$device" >/dev/null 2>&1 || true
          exit 0
          ;;
        rescan) rescan=yes ;;
        radio-off)
          nmcli radio wifi off
          exit 0
          ;;
        esac
      done
    '';
  };

  # Resuming needs somewhere to resume from, so a host without a resume device has no
  # business offering hibernation.
  canHibernate = config.boot.resumeDevice != "";

  powerButton = label: action: text: keybind: {
    inherit
      label
      action
      text
      keybind
      ;
  };
  lock = powerButton "lock" "pidof hyprlock || hyprlock" "󰌾  Lock" "l";
  logout = powerButton "logout" "hyprctl dispatch 'hl.dsp.exit()'" "󰗽  Log out" "e";
  suspend = powerButton "suspend" "systemctl suspend" "󰒲  Suspend" "u";
  reboot = powerButton "reboot" "systemctl reboot" "󰜉  Reboot" "r";
  hibernate = powerButton "hibernate" "systemctl hibernate" "󰋊  Hibernate" "h";
  shutdown = powerButton "shutdown" "systemctl poweroff" "󰐥  Shut down" "s";

  powerButtons =
    if canHibernate then
      [
        lock
        logout
        suspend
        reboot
        hibernate
        shutdown
      ]
    else
      [
        lock
        suspend
        logout
        reboot
        shutdown
      ];

  # Screenshots. HyprQuickFrame draws the selection overlay -- shader dimming, spring
  # animations on the selection, snap-to-window -- then hands the capture to satty for
  # annotation. It replaces the grim+slurp pair that used to be inlined here; grim is still
  # what actually takes the pixels, but HyprQuickFrame builds the geometry and the pipeline.
  #
  # Reachable two ways, because neither one covers both hosts on its own. Print is bound in
  # ~/.dotfiles/hypr/.config/hypr/hyprland.lua, and the key comes from the external keyboard
  # (NuPhy Halo65 V2), which is remapped in firmware and so emits a real KEY_SYSRQ wherever
  # it is plugged in. The Dell's built-in keyboard has a Print key too, but the Mac's
  # (hid-apple, 05AC:0352) lands on the magic_keyboard_2021_and_2024 fn table, which has no
  # KEY_SYSRQ on either fn layer -- so on the Mac with nothing plugged in, the launcher
  # entry below is the only way in. (evtest-style dumps do show KEY_SYSRQ on the internal
  # keyboard; that comes from the generic HID boot-keyboard descriptor, not from a key that
  # exists. Same trap as the backlight keys in profiles/laptop.nix.)
  #
  # Temp is the default action: HQF_ACTION below starts the overlay with the bar's "Temp"
  # toggle already on, so a capture goes to the clipboard and nowhere else -- no file in
  # ~/Pictures/Screenshots to go back and delete. Upstream reads that variable once at
  # startup (shell.qml, `tempActive`), and the toggle stays live, so the floating Temp
  # button still turns it back off mid-selection and Edit still hands off to satty. The
  # three actions are mutually exclusive, so HQF_ACTION=edit or =share picks those instead,
  # and any other value -- HQF_ACTION=save, say -- leaves all three off, which is upstream's
  # save-and-notify default.
  #
  # Note that HyprQuickFrame spawns satty itself, with its own flags, so the only settings
  # of ours it honours are the ones in ~/.dotfiles/satty/.config/satty/config.toml that it
  # does not override -- `fullscreen` among them, which is why that moved out of the CLI
  # and into the config file. It passes its own --output-filename, --early-exit,
  # --init-tool and --copy-command.
  hqf = inputs.hyprquickframe.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Upstream reads theme.toml from, in order, ~/.config/hyprquickframe, then
  # ~/.config/quickshell/HyprQuickFrame, then its own install directory. XDG_CONFIG_DIRS is
  # never consulted, so the /etc/xdg drop-in that dresses waybar and mako cannot reach it.
  # Restacking the QML tree with our file as the install-directory copy themes it without
  # putting anything in $HOME, and leaves both user paths free for a by-hand override that
  # needs no rebuild.
  #
  # The parser on the other end is a hand-rolled line matcher, not a TOML library: it takes
  # `[section]` headers and `key = value`, folding the two into one camelCase name, and
  # understands bare true/false and numbers. Colours are read as #RRGGBBAA -- note that
  # upstream's own defaults look like Qt's #AARRGGBB and are simply wrong about their own
  # alpha, so every colour here is written the way the parser reads it.
  hqfTheme = toml.generate "theme.toml" {
    accent = theme.accentHex;
    accentText = palette.crust;
    dimOpacity = 0.6;
    borderRadius = 10;
    outlineThickness = 2;
    bottomMargin = 60;

    # Off. This gates only the two selectors (shell.qml wires it to RegionSelector's
    # globalAnimations and WindowSelector's animateSelection), where it puts a spring --
    # 5/0.7, underdamped and slack -- between the pointer and the rectangle, so the region
    # visibly trails the cursor while you drag. The bar and the toggles animate from
    # hardcoded springs of their own and keep their movement either way.
    animations = false;
    annotationTool = "satty";

    bar = {
      background = "${palette.surface0}cc";
      border = "${palette.overlay0}40";
      text = "${palette.subtext0}ff";
      shadow = "${palette.crust}80";
    };

    toggle = {
      shadow = "${palette.crust}80";
      edit = palette.green;
      temp = theme.accentAltHex;
    };

    # kdeconnect is not installed on either host, so the share toggle can only ever report
    # failure. Coloured anyway rather than left on upstream's stock palette, which is the
    # one thing on screen that would not be Catppuccin.
    share = {
      connected = palette.sapphire;
      pending = palette.overlay0;
      errorIcon = palette.crust;
      errorBackground = palette.red;
    };
  };

  hqfShell = pkgs.runCommand "hyprquickframe-shell" { } ''
    cp -r ${hqf}/share/hyprquickframe $out
    chmod -R u+w $out
    cp ${hqfTheme} $out/theme.toml

    # Each bar item is one Text holding "<glyph>  Region", the glyph coming from the
    # Material Design range of Nerd Fonts that waybar also draws from. Upstream names no
    # family, so the item takes the default UI font and every glyph comes out as tofu:
    # Qt's fontconfig backend builds its fallback list from the family alone and then
    # keeps only the fonts whose writing system it recognises, which no amount of
    # installing nerd-fonts.symbols-only changes -- that is a plain-PUA font and fc-match
    # finding it for :charset=f0489 is not something Qt ever asks. Naming the symbol font
    # outright is what works. Qt's fallback does run in the other direction, so the Latin
    # half of the string still lands on fontconfig's sans default, which is
    # theme.fonts.ui. font.families, Qt 6's real fallback list, is not reachable: the QML
    # font value type here exposes family and not families.
    #
    # Only the bar needs this. The floating toggles used to carry glyphs too -- the dead
    # `icon:` properties in shell.qml still hold them -- and upstream moved those to
    # bundled SVGs, presumably over the same thing.
    substituteInPlace $out/components/ControlBar.qml \
      --replace-fail 'font.pixelSize: 15' \
        'font.pixelSize: 15
                    font.family: "Symbols Nerd Font"'
  '';

  # --path rather than upstream's --config: -c takes a *name* to look up under the
  # quickshell config directories, and only incidentally accepts a path. runtimeInputs is
  # load-bearing -- the QML shells out to every one of these by bare name.
  screenshot = pkgs.writeShellApplication {
    name = "lattice-screenshot";
    runtimeInputs = [
      pkgs.quickshell
      pkgs.grim
      pkgs.imagemagick
      pkgs.wl-clipboard
      pkgs.satty
      pkgs.libnotify
    ];
    text = ''
      export HQF_ACTION="''${HQF_ACTION-temp}"
      exec quickshell --path ${hqfShell} -n "$@"
    '';
  };

  # What puts it in `rofi -show drun`. Papirus has accessories-screenshot; neither
  # HyprQuickFrame nor satty ships an icon of its own.
  screenshotItem = pkgs.makeDesktopItem {
    name = "lattice-screenshot";
    desktopName = "Screenshot";
    comment = "Select a region and annotate it";
    exec = "${screenshot}/bin/lattice-screenshot";
    icon = "accessories-screenshot";
    categories = [ "Graphics" ];
    # rofi matches these too, so the tool names find it even when "screenshot" isn't the
    # word that comes to mind.
    keywords = [
      "screenshot"
      "screen"
      "capture"
      "region"
      "snip"
      "grim"
      "satty"
      "hyprquickframe"
    ];
  };

  # Everything mako has already shown and timed out on, as a browsable list -- the whole of
  # what a "notification centre" would otherwise be a daemon for. Bound to SUPER+ALT+N; see
  # the mako binds in ~/.dotfiles/hypr/.config/hypr/hyprland.lua.
  #
  # jq, not a format string: `makoctl history` grew -f only after 1.11, which is what this
  # nixpkgs carries, so -j and a filter is the version-proof way to read it. The JSON is a
  # plain array of objects, newest first, with the fields below spelled exactly as mako
  # spells them (app_name, not app-name -- these are not the DBus hint names).
  notifyHistory = pkgs.writeShellApplication {
    name = "lattice-notifications";
    runtimeInputs = [
      pkgs.mako
      pkgs.jq
      rofiWithCalc
      pkgs.wl-clipboard
      pkgs.libnotify
      pkgs.coreutils # cut
    ];
    text = ''
      # Captured once, and both passes read this copy. Reading it twice would race a
      # notification arriving mid-prompt, and the id picked from the first list would then
      # mean a different entry in the second.
      history="$(makoctl history -j)"

      # An empty prompt is indistinguishable from a bind that did nothing, and the answer
      # -- that nothing has arrived -- is worth saying out loud.
      if [ "$(printf '%s' "$history" | jq 'length')" -eq 0 ]; then
        notify-send -a lattice-notifications -u low \
          "No notification history" "Nothing has expired since mako started."
        exit 0
      fi

      # The id rides in a hidden first column, the way the cliphist bind does it, because
      # the summary alone is not unique -- a unit that fails twice has two identical lines.
      # Bodies are multi-line and rofi is not, so newlines collapse to spaces; @tsv would
      # escape them rather than break the row, but a literal \n mid-line reads badly.
      selection=$(
        printf '%s' "$history" \
          | jq -r '.[] | [
              (.id | tostring),
              ((.app_name // "?") + ": " + (.summary // "")
                + " | " + ((.body // "") | split("\n") | join(" ")))
            ] | @tsv' \
          | rofi -dmenu -i -p notifications -display-columns 2
      ) || exit 0
      [ -n "$selection" ] || exit 0
      # That `|| exit 0` is for rofi answering 1 on a dismissed prompt, which is a normal
      # outcome and must not take the script down under pipefail. It cannot tell a cancel
      # from rofi failing to reach the compositor at all, and deliberately: both end with
      # no selection and nothing to copy.

      # The body, not the summary. Going back to a notification that has already gone is
      # nearly always about something inside it -- a code, a path, a link -- and mako keeps
      # no action registry for an expired notification, so there is nothing to invoke.
      printf '%s' "$history" \
        | jq -r --argjson id "$(printf '%s' "$selection" | cut -f1)" \
            '.[] | select(.id == $id) | .body' \
        | wl-copy
    '';
  };

  # wlogout reads $XDG_CONFIG_HOME/wlogout/{layout,style.css} and then falls straight back
  # to its own store path -- it never consults XDG_CONFIG_DIRS, so the /etc/xdg drop-in
  # trick the other shell surfaces use doesn't reach it. The paths are passed explicitly
  # instead, which is why the menu is only ever opened through this wrapper.
  #
  # wlogout runs each action through `sh -c`, inheriting this script's environment, so
  # runtimeInputs is also what puts hyprctl within reach of the logout button when the
  # menu is launched from waybar's systemd unit (see waybar.path below).
  powerMenu = pkgs.writeShellApplication {
    name = "lattice-power";
    runtimeInputs = [
      pkgs.wlogout
      pkgs.hyprland
      config.programs.hyprlock.package
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      # Clicking the bar pill a second time should close the menu, not stack another
      # copy of it behind the first.
      if pgrep -x wlogout >/dev/null; then
        pkill -x wlogout
        exit 0
      fi

      exec wlogout \
        --layout /etc/xdg/wlogout/layout \
        --css /etc/xdg/wlogout/style.css \
        --buttons-per-row ${toString (if canHibernate then 3 else lib.length powerButtons)}
    '';
  };

  # The reporter behind the OnFailure= lines on the session's own units. A unit that dies
  # is otherwise indistinguishable from a unit with nothing to say: lattice-battery-notify
  # failed on every boot for four days over one missing `awk`, and the only symptom was a
  # battery that never warned.
  notifyFailure = pkgs.writeShellApplication {
    name = "lattice-notify-failure";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.systemd
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      unit="$1"

      # Which manager owns the failing unit, because one reporter serves both. A session
      # unit's OnFailure= reaches this directly; a system unit's goes through the root
      # bridge in systemd.services below and arrives here as `system`. Only the flag
      # differs -- winston is in wheel, so the system manager and its journal are readable
      # from the session without privilege, and nothing has to be handed across.
      case "''${2:-user}" in
        user) manager=(--user) ;;
        system) manager=() ;;
        *)
          echo "usage: lattice-notify-failure <unit> [user|system]" >&2
          exit 1
          ;;
      esac

      # Two different answers, and the banner wants both. Result is systemd's own verdict
      # -- exit-code, start-limit-hit, timeout -- while the journal tail is where the
      # reason actually lives; the outage this was written for was one line of it.
      result="$(systemctl "''${manager[@]}" show -P Result -- "$unit" 2>/dev/null || true)"
      # `|| true` for grep exiting 1 on an empty capture, which pipefail would otherwise
      # turn into a failed reporter.
      log="$(journalctl "''${manager[@]}" --no-pager -o cat -n 5 -u "$unit" 2>/dev/null | grep -v '^$' || true)"

      body="''${result:-failed}"
      # An `if`, not `[ -n "$log" ] && body=...`: that list returns 1 when the tail is
      # empty and errexit takes the whole script down with it.
      if [ -n "$log" ]; then
        body="$(printf '%s\n\n%s' "$body" "$log")"
      fi

      # Onto the journal as well as the screen. If nothing owns org.freedesktop.Notifications
      # -- the one failure this cannot raise a banner for -- the attempt is still on record.
      printf '%s failed: %s\n' "$unit" "''${result:-unknown}"

      # Critical, so the default-timeout=0 in ~/.dotfiles/mako leaves it up until it is
      # dismissed: a unit breaking while nobody is looking is the case that must not time
      # out. Keyed synchronous per unit, so a unit that fails, gets fixed and fails again
      # replaces its own banner rather than stacking, while two units still get one each.
      notify-send -a lattice-systemd -u critical -i dialog-error \
        -h "string:x-canonical-private-synchronous:lattice-failure-''${2:-user}-$unit" \
        "$unit failed" "$body"
    '';
  };

  # Opens the NuPhy Halo65 V2's raw-HID node to whoever holds the seat, so the keyboard can
  # be remapped from nuphy.io in the Chromium below. The board is QMK underneath: its
  # interface 1 reports usage page 0xFF60, QMK's raw-HID endpoint and the transport both
  # NuPhy Console and VIA speak. That node is root-only by default, and the resulting
  # failure is badly disguised -- the WebHID chooser comes up empty and reads as "no
  # compatible devices found", which looks like the site not supporting the keyboard
  # rather than like a permission problem.
  #
  # This is a udev *package* rather than services.udev.extraRules, and that is the whole
  # point of it. uaccess is not applied by the rule that sets the tag; systemd's
  # 73-seat-late.rules is what turns TAG+="uaccess" into an ACL. extraRules is hardcoded
  # into 99-local.rules, which udev reaches long after 73, so the tag is set after the
  # only rule that would consume it and nothing happens -- silently, with the rule
  # present and correct in the file. Numbering this below 73 is what makes it fire, and
  # is why the MX Master's own rule ships at 42. udev.packages takes the filename from
  # the destination, so the 60- prefix here is load-bearing.
  #
  # pkgs.qmk-udev-rules is no substitute: all 89 of its lines are bootloader VID/PIDs for
  # flashing, and none touch hidraw on a running board.
  #
  # Scoped to the one product and to hidraw only. The evdev nodes stay shut -- remapping
  # happens in the keyboard's own firmware, so nothing here needs to read keystrokes.
  nuphyHidAccess = pkgs.writeTextFile {
    name = "nuphy-halo65-udev-rules";
    destination = "/lib/udev/rules.d/60-nuphy-halo65.rules";
    text = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="19f5", ATTRS{idProduct}=="3315", TAG+="uaccess"
    '';
  };

  # Catppuccin, matching ~/.dotfiles. Theme names follow lattice.theme.
  gtkTheme = "catppuccin-${theme.flavor}-${theme.accent}-standard";
  iconTheme = "Papirus-Dark";
  cursorTheme = "catppuccin-${theme.flavor}-dark-cursors";
  # 9pt (12px) keeps UI text close to Ghostty and waybar; qt6ct in ~/.dotfiles uses the same fonts.
  uiFont = "${theme.fonts.ui} ${toString theme.fonts.size}";
  monospaceFont = "${theme.fonts.monospace} ${toString theme.fonts.size}";

  gtkSettings = ''
    [Settings]
    gtk-theme-name=${gtkTheme}
    gtk-icon-theme-name=${iconTheme}
    gtk-cursor-theme-name=${cursorTheme}
    gtk-cursor-theme-size=16
    gtk-application-prefer-dark-theme=true
    gtk-font-name=${uiFont}
  '';

  # regular0-7 then bright0-7, read straight off the list ../theme.nix hands the kernel as
  # vt.default_red/grn/blu, so the greeter's sixteen colours and the console's are one
  # source. console.colors is already '#'-less, which is also foot's format.
  greeterAnsi = lib.concatStringsSep "\n" (
    lib.imap0 (
      i: colour: "${if i < 8 then "regular" else "bright"}${toString (lib.mod i 8)}=${colour}"
    ) config.console.colors
  );

  # The greeter's terminal. tuigreet is untouched by this -- same binary, same config, same
  # theme block below -- it just draws into foot under cage now rather than into fbcon on
  # VT1.
  #
  # Sizing is the whole reason. fbcon has one framebuffer and one bitmap font for every
  # output it takes over, so a docked boot shares a single 16x32 cell between the Mac's
  # 254 dpi panel and the 140 dpi Samsung: 0.13" of glyph on one and 0.26" on the other, the
  # same image mirrored. No console font setting fixes both at once -- shrinking it for the
  # monitor shrinks the panel by the same factor, because the font is pixels and the screens
  # differ in pixel size. A Wayland terminal can size type from each output's own physical
  # DPI instead, which is what dpi-aware does below.
  greeterTerminal = ''
    # foot, as the greeter's terminal: greetd runs cage -> foot -> tuigreet, wired up in the
    # LOGIN block of this profile. Written from lattice.theme, so it is not the place to keep
    # an edit -- change it there.

    # 7pt is measured, not picked. fbcon's TER16x32 cell is 32px tall; foot reads the panel
    # as `eDP-1: 3024x1890+0x0@120Hz 14.03" scale=3, DPI=254.24/338.99 (physical/scaled)`;
    # and JetBrains Mono's cell comes out 1.345x its pixel size (28.25px of font -> 38px of
    # cell). So 32px of cell is 23.8px of font is 6.74pt, and 7pt rounds up rather than down.
    # Measured back, it lands a 15x34 cell against fbcon's 16x32 -- 0.134" a row against
    # 0.126", so the panel ends a shade larger than the console was, never smaller. dpi-aware
    # is what makes that a physical figure rather than a pixel one, so the Samsung renders the
    # same 0.134" from its own ~140 dpi and halves what it shows today.
    #
    # dpi-aware has to be `yes` rather than the default `no`, and not because of HiDPI as
    # such: cage has no scale of its own -- its entire option set is -d -D -h -m -s -v -- so
    # every output reports scale 1, and sizing by scale would land 7pt at 96 dpi on a 254 dpi
    # panel. `yes` ignores the scale and reads the output's millimetres, which appledrm does
    # report for both outputs even though it publishes no EDID for either.
    #
    # 7pt is the undocked size, i.e. the panel's. greeterSession overrides it when the greeter
    # is going to land on an external screen instead, because equal inches is the wrong target
    # across a desk -- see there.
    font=${theme.fonts.monospace}:size=7
    dpi-aware=yes

    # cage maximises its one client and asks it not to draw decorations, so padding is all
    # the geometry there is to set -- and none of it, because tuigreet centres its own box
    # inside whatever grid it is handed.
    pad=0x0

    # foot's own terminfo is not in the system profile, only ncurses' entries are, and the
    # greeter is the worst place to find that out. tuigreet drives the screen through
    # crossterm, which writes plain ANSI and never opens terminfo, so the entry only has to
    # exist for anything else that looks; xterm-256color always does.
    term=xterm-256color

    # tuigreet is themed by ANSI colour name, so this block is where those names get their
    # values: `blue` in its theme is the palette's blue, exactly as it was on the console,
    # which gets these same sixteen through vt.default_red/grn/blu.
    [colors-dark]
    background=${hex palette.base}
    foreground=${hex palette.text}
    ${greeterAnsi}
  '';

  # cage's client, and the reason there is a script here at all: the size the greeter wants
  # depends on which screen cage is about to put it on, and that is knowable before foot
  # starts but not from inside foot's config.
  #
  # dpi-aware sizes type in inches, which made the two screens agree physically and then read
  # wrong anyway: 7pt is 0.134" a row on the panel at arm's length and the same 0.134" on a
  # 32" monitor most of a desk away, where it is roughly a third too small. Angle is what the
  # eye measures, so the monitor wants that 0.134" scaled by the ratio of the viewing
  # distances -- ~28" against ~20" -- which is 0.19" and, at 1.345 cells per pixel of font,
  # 10pt. That also lands between the two sizes already ruled out by eye: fbcon's 0.26" on
  # this monitor was too big, physical parity's 0.13" too small.
  #
  # The check is any connected output that is not an internal panel, rather than this Mac's
  # HDMI-A-1 by name, so the Dell's DP outputs pick the same branch. It reads the same sysfs
  # the greeter's compositor is about to read; nothing is cached between the two.
  greeterSession = pkgs.writeShellApplication {
    name = "lattice-greeter";
    runtimeInputs = [
      pkgs.foot
      pkgs.tuigreet
    ];
    text = ''
      size=7
      for status in /sys/class/drm/card*-*/status; do
        case "$status" in *-eDP-*) continue ;; esac
        if [ "$(cat "$status")" = connected ]; then
          size=10
          break
        fi
      done

      # -o rather than a second config file: everything else about the two cases is identical,
      # and a font line is the one thing that differs.
      exec foot \
        --config=/etc/greetd/foot.ini \
        --override="font=${theme.fonts.monospace}:size=$size" \
        tuigreet
    '';
  };
in
{
  # Everything below reads config.lattice.theme, so don't rely on branding.nix pulling it in.
  imports = [
    ../artwork.nix
    ../theme.nix
    ../plymouth.nix
    ../display.nix
    ../weather.nix
    ../streamdeck.nix
    ../webapps.nix
    ../widevine.nix
    ../phone.nix
  ];

  ### SESSION ###
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # GTK file-chooser portal; xdg-desktop-portal-hyprland doesn't implement it.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  ### APPS ###
  environment.systemPackages = with pkgs; [
    ghostty
    rofiWithCalc
    # The same libqalculate engine at its other two surfaces: `qalc` in a terminal, and a
    # real window for the times a calculation is worth keeping on screen and editing --
    # qalculate-gtk carries the history, stored variables, user functions and the plot
    # button that a one-line launcher prompt has nowhere to put. It is GTK3, so the
    # catppuccin-gtk theme below dresses it; it lands in `rofi -show drun` as "Qalculate!".
    # libqalculate is free here (rofi-calc already put it in the closure) and qalculate-gtk
    # adds ~8 MiB on top of it.
    libqalculate
    qalculate-gtk
    # hyprsunset ships only as a systemd.packages unit above, so its CLI -- which is how
    # the running daemon is driven -- wasn't on PATH for lattice-sunset or a shell.
    hyprsunset
    # notify-send: without it every script that tries to raise a notification fails
    # silently, mako itself was fine all along.
    libnotify
    # The same story as hyprsunset above, and for the same reason: mako ships as a
    # systemd.packages unit, which installs the service and nothing else. makoctl is how a
    # running mako is driven -- every bind in hyprland.lua goes through it, and Hyprland
    # execs those with the session PATH, not a wrapper's runtimeInputs.
    mako
    brightnessctl
    playerctl
    wl-clipboard
    cliphist
    grim
    satty
    swayosd
    xdg-user-dirs

    mpv
    imv
    xarchiver
    libreoffice-qt
    hunspellDicts.en_US
    hyphenDicts.en_US
    drawio
    telegram-desktop
    zathura
    bitwarden-desktop
    wf-recorder

    # Not a browser: Firefox keeps http/https under DEFAULT APPS below, and nothing here
    # changes that. This is on the machine for WebHID (navigator.hid) alone, which is the
    # only way to reach the NuPhy Halo65 V2's QMK raw-HID interface from this host. The
    # native clients cannot: pkgs.via and pkgs.vial are both x86_64-only AppImages in
    # nixpkgs, so on aarch64 the configurator is nuphy.io (or usevia.app) in a Chromium
    # tab. Firefox is not an option either -- Mozilla lists WebHID as harmful and ships no
    # implementation -- which is the whole reason a second browser exists here.
    #
    # Ungoogled rather than pkgs.chromium, and it costs nothing to prefer: both are cached
    # for aarch64 at ~200 MiB, and NIXOS_OZONE_WL below already makes either a native
    # Wayland client. The keyboard's hidraw node still needs the udev rule below before
    # the page can open the device.
    ungoogled-chromium

    # Everything below was once picked per host, because the obvious client is x86-only
    # in nixpkgs and the Mac needed a stand-in. Running the stand-in on both is simpler
    # than keeping two app sets: each is cross-arch, cached for aarch64, and close
    # enough to what it replaces that having one of them in muscle memory is worth more
    # than the nicer x86 build.
    #
    # Vesktop, for Discord: an Electron shell around the web client, so it is the same
    # app the official build wraps, plus Vencord and working Wayland screen share.
    #
    # cryptomator-cli, for Cryptomator: same vaults, same format -- `cryptomator-cli
    # unlock` mounts one over FUSE and it is a normal directory from there. The GUI is
    # x86-only because nixpkgs pins `platforms = [ "x86_64-linux" ]`; that looks like an
    # untested restriction rather than a real one (zulu25 has an aarch64 JDK with
    # JavaFX, and the derivation evaluates fine on aarch64 with the meta relaxed), so an
    # overlay is the way back to the GUI on both if the CLI ever grates.
    #
    # Popsicle, for Impression: Impression is not merely unbuilt on ARM, it depends on
    # syslinux, which is genuinely x86-only, so this one has no way back.
    vesktop
    cryptomator-cli
    popsicle

    # Tor Browser used to sit here, on the Dell alone. It is dropped rather than gated:
    # the Tor Project ships no ARM Linux build (only tor-browser-linux-x86_64), and
    # Mullvad Browser is x86-only for the same reason, so there is nothing to make the
    # two hosts agree on. `nix run nixpkgs#tor-browser` on the Dell for the rare need.

    (catppuccin-gtk.override {
      variant = theme.flavor;
      accents = [ theme.accent ];
    })
    (catppuccin-papirus-folders.override {
      inherit (theme) flavor accent;
    })
    catppuccin-cursors."${theme.flavor}Dark"

    cycleWallpaper
    sunset
    idleInhibit
    tailscale
    wifiMenu
    powerMenu
    notifyHistory
    dnd
    screenshot
    screenshotItem
    # The drawing tool itself, for trying a density or a phase before wiring it in.
    config.lattice.artwork.draw
  ];

  programs = {
    # No nativeMessagingHosts: firefoxpwa was the one entry here, and its host is only
    # reachable by the PWAsForFirefox extension, which isn't installed. Web apps are
    # Firefox's own Taskbar Tabs instead -- see modules/nixos/webapps.nix for why.
    firefox.enable = true;
    thunderbird.enable = true;
    thunar = {
      enable = true;
      plugins = [
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
      ];
    };
    waybar.enable = true;

    # Logitech HID++ control, for the MX Master 3. Its sensor ships at 4000 DPI, which is
    # what makes the pointer read as fast however far down Hyprland's per-device
    # `sensitivity` goes -- libinput can only discard motion counts after the fact, so it
    # buys slowness at the cost of precision. `solaar config <device> dpi <n>` moves it at
    # the source instead, which is why the device block in ~/.dotfiles/hypr/.config/hypr/
    # hyprland.lua now sits at sensitivity 0 with accel_profile flat: DPI is the only
    # speed knob, and pointer travel is proportional to hand travel so it means one thing.
    #
    # DPI is volatile: the mouse forgets it whenever it power-cycles or the Bluetooth link
    # drops, which on the Dell includes every hibernate -- see the btintel_pcie unload
    # in hosts/dell. The CLI alone would hold only until the next reconnect; the
    # user service is what makes it stick, reapplying ~/.config/solaar/config.yaml each
    # time the device comes back. It starts hidden, to the waybar tray.
    #
    # That config.yaml is a symlink into the dotfiles repo (the solaar stow package), so
    # the DPI is shared rather than re-set per machine. Solaar rewrites it with a plain
    # open(path, "w"), which writes through the symlink instead of replacing it.
    #
    # enable also turns on hardware.logitech.wireless, which is what installs the udev
    # rules that let a non-root user talk to the device at all.
    #
    # The buttons are mapped in ~/.config/solaar/rules.yaml, the other half of the same
    # stow package: config.yaml diverts Back, Forward, Smart Shift and the gesture button
    # away from their built-in meanings, and rules.yaml says what they do instead (volume
    # on back/forward, the launcher on Smart Shift, and Hyprland navigation on the gesture
    # button). Rules are read once at start-up, so editing that file means
    # `systemctl --user restart solaar`.
    #
    # Most of those rules run commands rather than synthesising keystrokes. Execute needs
    # no privilege, and the uwsm-populated user environment already carries
    # HYPRLAND_INSTANCE_SIGNATURE into the service, which is what makes hyprctl work from
    # there. Its PATH does not carry /run/current-system/sw/bin, though, so the rules name
    # every binary absolutely.
    #
    # The exception is the gesture button, which holds SUPER down for as long as it is
    # held. That one needs KeyPress, which writes to /dev/uinput -- hence the
    # hardware.uinput block below. It buys the thing Solaar cannot do on its own: its
    # mouse-gesture mode only reports the direction once the button is released (the
    # notification is pushed from release_action, with no mid-gesture hook), so a gesture
    # can move one workspace per press and no more. Held as a modifier instead, the button
    # feeds the SUPER+scroll and SUPER+drag binds already in hyprland.lua, and workspaces
    # cycle continuously under the wheel. The cost is that a button is diverted as Mouse
    # Gestures or as a plain key, never both, so the four directional gestures are gone.
    solaar = {
      enable = true;
      userService.enable = true;
    };

    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  services = {
    gvfs.enable = true;
    tumbler.enable = true;
    blueman.enable = config.hardware.bluetooth.enable;
    flatpak.enable = true;

    # swayosd writes backlight brightness through sysfs, which its udev rule opens to the video group.
    #
    # nuphyHidAccess opens the Halo65 V2's raw-HID node so the configurator can reach it;
    # see the note on the package itself for why it is a package here and not extraRules.
    udev.packages = [
      pkgs.swayosd
      nuphyHidAccess
    ];
  };
  # /dev/uinput, for the Solaar rule that holds SUPER while the mouse's gesture button is
  # down. The NixOS module loads the module, makes the group and writes the udev rule; the
  # group membership is what the solaar user service actually needs. Supplementary groups
  # are fixed when the session starts, so this only reaches a running Solaar after a
  # re-login -- until then KeyPress fails silently, which is its only failure mode.
  hardware.uinput.enable = true;

  users.users.winston.extraGroups = [
    "video"
    "uinput"
  ];

  ### AUDIO ###
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;

      # Every bluez5 codec nixpkgs ships (AAC, aptX, LDAC, LC3, Opus, mSBC) is already built in
      # and enabled by default, and bluetooth.profile-preference is already "quality", so codec
      # selection needs no help. Autoswitching does.
      #
      # With it on, anything that opens a capture stream -- a browser tab checking for a mic,
      # a meeting joining -- drags headphones from A2DP down to HFP, which is 8kHz mono, and
      # music sounds broken until they are power-cycled. Off means the headset mic is no longer
      # offered automatically; the laptop's own mic gets used instead, which is the better
      # trade here. Switch profiles by hand in blueman on the rare call that needs the headset.
      extraConfig."51-bluetooth-no-autoswitch" = {
        "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
  };

  ### SECRETS ###
  services.gnome = {
    gnome-keyring.enable = true;
    # SSH keys stay with programs.ssh.startAgent.
    gcr-ssh-agent.enable = false;
  };
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Run Electron apps natively on Wayland so they aren't blurry under fractional scaling.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  # LibreOffice picks its GTK3 backend outside KDE, which can't do fractional scaling and oversizes its icons.
  environment.sessionVariables.SAL_USE_VCLPLUGIN = "qt6";
  # LibreOffice finds spelling/hyphenation dictionaries under share/{hunspell,hyphen} in the system profile.
  environment.pathsToLink = [ "/share/hyphen" ];

  ### SESSION SERVICES ###
  systemd.packages = with pkgs; [
    hyprpaper
    mako
    hyprpolkitagent
    hyprsunset
  ];

  systemd.user.services = {
    # The OnFailure= target for the session's own units, so a unit that gives up says so
    # on screen instead of in the journal nobody reads. %i is the failing unit's full
    # name, handed over by `OnFailure=lattice-notify-failure@%n.service` at each use site.
    #
    # It fires once per failure, not once per restart attempt: OnFailure= triggers on
    # entry to the failed state, and an automatic restart is not that -- a unit with
    # Restart=on-failure reports when it exhausts its start limit and gives up, not five
    # times on the way there.
    #
    # Nothing sets OnFailure= on this unit, deliberately. A reporter that cannot report
    # has nothing left to report with, and a self-reference would only spin.
    "lattice-notify-failure@" = {
      description = "Report %i as a desktop notification";

      # The banner needs something to receive it, and mako is Type=dbus on
      # org.freedesktop.Notifications -- so ordering after it already means the name is
      # owned, with nothing to poll for. Wants and not Requires: when mako itself is the
      # broken thing, this should still run and leave its line in the journal. The only
      # place that names the daemon, so a swap away from mako would edit here.
      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i";
      };
    };

    # Where the system half lands. The bridge in systemd.services below starts this, and the
    # only difference from the template above is the scope the reporter is told to look in:
    # a system unit's Result and journal tail live in the system manager, and asking the
    # user manager for them yields an empty banner that says nothing but "failed".
    "lattice-notify-failure-system@" = {
      description = "Report system unit %i as a desktop notification";

      wants = [ "mako.service" ];
      after = [ "mako.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailure} %i system";
      };
    };

    hyprpaper.wantedBy = [ "graphical-session.target" ];
    mako.wantedBy = [ "graphical-session.target" ];
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

    # One wallpaper out of the pool per login.
    #
    # It hangs off hyprpaper rather than off graphical-session.target, which is not a
    # stylistic choice: hyprpaper's own unit is `After=graphical-session.target`, so a unit
    # that the target wants *and* that waits for hyprpaper closes a loop -- the target waits
    # for the pick, the pick waits for hyprpaper, hyprpaper waits for the target. systemd
    # spots that at activation and breaks it by deleting a job from the cycle, which is a
    # warning in the journal and a wallpaper that never changes, not a failure anyone is
    # told about. Being wanted by hyprpaper instead says the same thing -- pick once the
    # wallpaper daemon is up -- with no edge back to the target. It also means a hyprpaper
    # that died and restarted gets a fresh pick rather than coming back on whatever
    # hyprpaper.conf names, which is the better answer anyway.
    #
    # There is no Restart= here on purpose. hyprpaper is Type=simple, so ordering after it
    # only means its process has been forked and its IPC socket may not be bound yet -- but
    # riding that out with a restart makes systemd enter the failed state first, and
    # OnFailure= fires on entry, not on giving up, so every login would raise a banner that
    # the retry then quietly disproved. The waiting belongs in the command instead, which is
    # where it is; reaching this unit's OnFailure= now means hyprpaper never arrived at all.
    lattice-wallpaper-pick = {
      description = "Pick this session's wallpaper";

      after = [ "hyprpaper.service" ];
      wantedBy = [ "hyprpaper.service" ];
      # Stop-propagation only -- PartOf implies no ordering, so it adds no edge back to the
      # target. It is here so a pick still retrying cannot outlive the session it is for.
      partOf = [ "graphical-session.target" ];
      onFailure = [ "lattice-notify-failure@%n.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cycleWallpaper} random";
      };
    };

    # systemd user services get a bare default PATH -- coreutils, findutils, grep, sed,
    # systemd -- and notably *not* /run/current-system/sw/bin. Waybar runs its module
    # commands through `sh -c` with that environment, so anything they call has to be
    # named here or it fails with "command not found" and the module silently renders
    # empty. Keep this in step with the on-click/on-scroll/exec commands in
    # ~/.dotfiles/waybar/config.jsonc.
    #
    # That reaches one step further than the commands themselves. The scripts below are
    # writeShellApplications, so each prepends its own runtimeInputs and finds its own
    # tools regardless of this list -- but a tool that in turn execs something by *name*
    # is back to this PATH. xdg-open is the one that does: it resolves
    # x-scheme-handler/https to firefox.desktop from the assignment further down and then
    # runs `firefox`, so without the browser here lattice-tailscale's sign-in click and
    # its right-click to the admin console both resolved a URL and then opened nothing.
    # xdg-open does say so -- it walks its whole fallback list of browser names, reports
    # "no method available", and exits 3 -- but both call it with output on /dev/null
    # (they must: it is detached), so the complaint went nowhere and the pill just sat
    # there.
    waybar.path = [
      sunset
      dnd
      idleInhibit
      tailscale
      weather
      wifiMenu
      powerMenu
      pkgs.wireplumber
      config.programs.firefox.finalPackage
    ];

    swayosd = {
      description = "Volume and brightness OSD";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
      };
    };

    cliphist = {
      description = "Clipboard history";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
      };
    };

    # Starting with the session rather than at login gives tmux panes WAYLAND_DISPLAY, so GTK apps
    # launched from them don't fall back to XWayland and get upscaled blurry. Replaces continuum's boot unit.
    tmux = {
      description = "tmux default session (detached)";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # Inherit the session PATH instead of NixOS's minimal one; plugins and panes need the full system.
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.tmux}/bin/tmux new-session -d";
        ExecStop = [
          "%h/.local/share/tmux/plugins/tmux-resurrect/scripts/save.sh"
          "${pkgs.tmux}/bin/tmux kill-server"
        ];
      };
    };
  };

  # The same reporter, reached from the system manager. A unit's OnFailure= resolves in the
  # manager that owns it, so `lattice-notify-failure@%n.service` spelled in a host file's
  # systemd.services lands here rather than on the user template above -- one spelling for
  # both scopes, and a unit that moves between them needs no edit at its use site.
  #
  # `--machine=winston@.host` is the whole of it: root opens the user manager's own bus by
  # name and starts the unit there, so neither a uid nor a DBUS_SESSION_BUS_ADDRESS has to
  # be reconstructed the way the Mac's sleep guard still does for its own banner. Reaching
  # the session becomes the reporter's problem instead of the failing unit's.
  #
  # With nobody logged in there is no bus to open and this fails, leaving only its journal
  # line -- the same outcome as a banner with no one in front of it. So a boot-time oneshot
  # gets less out of this than it looks: the case it does cover is that unit failing during
  # a `nixos-rebuild switch`, where a session is up by definition.
  #
  # No OnFailure= of its own, for the same reason the user template has none.
  systemd.services."lattice-notify-failure@" = {
    description = "Report system unit %i as a desktop notification";

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user --machine=winston@.host start lattice-notify-failure-system@%i.service";
    };
  };

  ### DEFAULT APPS ###
  xdg.mime.defaultApplications =
    let
      assign = app: types: lib.genAttrs types (_: app);
    in
    assign "firefox.desktop" [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ]
    // assign "thunderbird.desktop" [ "x-scheme-handler/mailto" ]
    // assign "thunar.desktop" [ "inode/directory" ]
    // assign "org.pwmt.zathura.desktop" [ "application/pdf" ]
    // assign "imv.desktop" [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/avif"
      "image/bmp"
      "image/tiff"
    ]
    // assign "mpv.desktop" [
      "video/mp4"
      "video/webm"
      "video/x-matroska"
      "video/quicktime"
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/wav"
    ]
    // assign "xarchiver.desktop" [
      "application/zip"
      "application/x-tar"
      "application/gzip"
      "application/x-xz"
      "application/zstd"
      "application/x-7z-compressed"
      "application/vnd.rar"
    ];

  ### THEME ###
  xdg.icons.fallbackCursorThemes = [ cursorTheme ];

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = gtkTheme;
        icon-theme = iconTheme;
        cursor-theme = cursorTheme;
        cursor-size = lib.gvariant.mkInt32 16;
        font-name = uiFont;
        monospace-font-name = monospaceFont;
      };
    }
  ];

  # Qt apps (hyprpolkitagent, LibreOffice) take their palette and fonts from qt6ct, configured in ~/.dotfiles.
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      jetbrains-mono
      nerd-fonts.symbols-only
      # Microsoft core fonts (Times New Roman, Arial, Courier New, ...) so documents render as their authors saw them.
      corefonts
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans" ];
      monospace = [ "JetBrains Mono" ];
    };
  };

  environment.etc."xdg/gtk-3.0/settings.ini".text = gtkSettings;
  environment.etc."xdg/gtk-4.0/settings.ini".text = gtkSettings;

  ### WALLPAPER ###
  environment.etc."xdg/hypr/hyprpaper.conf".text = ''
    wallpaper {
      monitor =
      path = ${wallpaper}
      fit_mode = cover
    }

    splash = false
  '';

  ### LOGIN ###
  services.greetd = {
    enable = true;

    # cage -> foot -> tuigreet, for the per-screen sizing the console cannot do; see
    # greeterTerminal above for the arithmetic. cage is a kiosk compositor -- one client,
    # maximised, no decorations -- and it exits when that client does, so greetd starts the
    # session on exactly the same signal it did when tuigreet owned the VT. The cost over the
    # console path is 6.9 MB of store (cage brings wlroots and xwayland; foot brings 976 KB
    # and nothing that was not already here) and ~50 MB of RSS that is gone before the
    # desktop starts.
    #
    # `-m last` rather than letting cage extend across both outputs, which is what decides
    # where the greeter appears. Extending puts the window on the first output, eDP-1, and that
    # is the one output which might be a closed lid -- a greeter nobody can see. `last` follows
    # whichever output came up last instead, and a docked boot confirms that is the HDMI one:
    # the panel is already live out of simpledrm while dcp debounces its HPD for 500ms. The
    # panel then stays dark while docked, which is the other half of why greeterSession sizes
    # for the external screen when one is attached -- the greeter is on exactly one screen,
    # never both, so there is one right size rather than a compromise between two.
    #
    # `-s` keeps VT switching, which is the way out if the greeter ever comes up blank; `-d`
    # stops cage asking foot for decorations it would then have to draw.
    #
    # No useTextGreeter: that option only adjusts greetd's own TTY plumbing so systemd cannot
    # scribble over a TUI sharing VT1 with it. The TUI is inside a compositor now, and there
    # is nothing left on the VT to protect.
    settings.default_session.command = lib.concatStringsSep " " [
      "${pkgs.cage}/bin/cage"
      "-s"
      "-d"
      "-m"
      "last"
      "--"
      (lib.getExe greeterSession)
    ];
  };

  # Beside tuigreet's own config below rather than in the store path of the command above, so
  # a size can be tried with `foot --config=/etc/greetd/foot.ini -o font=...` from a terminal
  # before it is committed to a boot -- and because dpi-aware sizes in inches, a window opened
  # that way on a screen renders at exactly the size the greeter will on that same screen.
  environment.etc."greetd/foot.ini".text = greeterTerminal;

  environment.etc."tuigreet/config.toml".source = toml.generate "tuigreet.toml" {
    display = {
      greeting = "Welcome to lattice";
      show_time = true;
    };
    session = {
      command = "uwsm start -e -D Hyprland hyprland.desktop";
      sessions_dirs = [ "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions" ];
    };
    remember.username = true;
    secret = {
      mode = "characters";
      characters = "*";
    };
    power = {
      shutdown = "systemctl poweroff";
      reboot = "systemctl reboot";
    };

    # tuigreet takes ANSI colour names, not hex, so the accent maps to its nearest name. What
    # those names resolve to is foot's [colors-dark] block above, which is ../theme.nix's
    # palette -- so `blue` is the palette's blue rather than a terminal's idea of blue, and a
    # re-accent carries through here without touching this block.
    theme = {
      container = "black";
      border = theme.accentAnsi;
      title = theme.accentAnsi;
      greet = "white";
      time = "white";
      text = "gray";
      prompt = theme.accentAnsi;
      input = "gray";
      action = theme.accentAnsi;
      button = "magenta";
    };
  };

  ### POWER MENU ###
  # Replaces the rofi -dmenu confirmation the logout bind used to shell out to, which is
  # gone from ~/.dotfiles/hypr/hyprland.lua entirely -- CTRL + SUPER + Q opens this instead.
  # Lock runs hyprlock directly, matching the SUPER + L bind rather than going through
  # `loginctl lock-session`, which does nothing if hypridle isn't there to answer it. The
  # layout is a sequence of bare JSON objects, not an array -- that is the format
  # wlogout's parser wants. `label` is also the CSS id of the button it makes.
  #
  # Icons are Nerd Font glyphs in the label rather than wlogout's shipped PNGs, which
  # are a fixed white and would stay that colour through a re-accent. They have to sit
  # on one line with the word: wlogout's JSON reader doesn't decode escapes, so a "\n"
  # in `text` reaches the button as a literal backslash-n.
  #
  # wlogout fills its grid *down the columns*, so with --buttons-per-row 3 the order of
  # powerButtons lays out as
  #     Lock      Suspend   Hibernate
  #     Log out   Reboot    Shut down
  # which puts the three that end the session along the bottom row. A host that can't
  # hibernate gets one row of five instead: wlogout reads a button for every cell of its
  # grid, so five buttons in a three-wide grid would run off the end of the list.
  environment.etc."xdg/wlogout/layout".text = lib.concatMapStrings (button: ''
    {
      "label": "${button.label}",
      "action": "${button.action}",
      "text": "${button.text}",
      "keybind": "${button.keybind}"
    }
  '') powerButtons;

  # GTK CSS, like waybar's and swayosd's, but written here rather than imported from
  # ~/.dotfiles: wlogout is Wayland-only, so there is no macOS half to keep in step.
  # The pill treatment carries over -- translucent @base, @surface0 border -- scaled up,
  # over a scrim that dims the desktop behind it.
  environment.etc."xdg/wlogout/style.css".text = ''
    * {
      background-image: none;
      box-shadow: none;
      font-family: "${theme.fonts.monospace}", "Symbols Nerd Font";
      font-size: 17px;
    }

    window {
      background-color: alpha(${palette.crust}, 0.72);
    }

    button {
      color: ${palette.text};
      background-color: alpha(${palette.base}, ${toString theme.opacity});
      border: 2px solid ${palette.surface0};
      border-radius: 14px;
      margin: 14px;
      padding: 28px;
      outline-style: none;
      /* GTK animates between the two states, so hover and focus fade rather than snap. */
      transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease;
    }

    button:focus,
    button:hover {
      color: ${theme.accentHex};
      background-color: alpha(${palette.surface0}, ${toString theme.opacity});
      border-color: ${theme.accentHex};
    }

    /* The two that can't be taken back warn in their own colour on the way past. */
    #reboot:focus,
    #reboot:hover {
      color: ${palette.peach};
      border-color: ${palette.peach};
    }

    #shutdown:focus,
    #shutdown:hover {
      color: ${palette.red};
      border-color: ${palette.red};
    }
  '';

  ### IDLE/LOCK ###
  programs.hyprlock.enable = true;

  environment.etc = {
    "xdg/hypr/hypridle.conf".text = ''
      general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
      }

      listener {
        timeout = 300
        on-timeout = loginctl lock-session
      }

      listener {
        timeout = 330
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
      }

      # The Stream Deck's backlight, on the same timeout as the lock above so the two go
      # dark together. It is only the backlight: streamdeck-ui knows nothing about the lock
      # screen, so its keys still work while the session is locked -- behind hyprlock's
      # input grab, where the windows they open cannot be seen or typed into.
      #
      # This rather than streamdeck-ui's own display_timeout, which is off in
      # modules/nixos/streamdeck.nix: its dimmer eats the first press after it dims, and a
      # key that does nothing the first time is worse than a lit deck.
      listener {
        timeout = 300
        on-timeout = lattice-deck dim
        on-resume = lattice-deck wake
      }
    '';

    "xdg/hypr/hyprlock.conf".text = ''
      general {
        hide_cursor = true
      }

      # Two blocks for the same reason there are two of every wallpaper: an image sized for
      # the desk monitor has too small a mark on the panel. The generic one comes first and
      # the panel's second, so on eDP-1 the later block is the one left showing.
      background {
        monitor =
        path = ${currentDesk}
        color = rgb(${hex palette.base})
      }

      background {
        monitor = eDP-1
        path = ${currentPanel}
        color = rgb(${hex palette.base})
      }

      label {
        monitor =
        text = $TIME
        color = rgb(${hex palette.text})
        font_size = 96
        font_family = ${theme.fonts.monospace} ExtraBold
        position = 0, 360
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:60000] date +"%A, %B %-d"
        color = rgb(${hex palette.subtext0})
        font_size = 22
        font_family = ${theme.fonts.monospace}
        position = 0, 260
        halign = center
        valign = center
      }

      input-field {
        monitor =
        size = 320, 56
        position = 0, -320
        halign = center
        valign = center
        rounding = 14
        outline_thickness = 2
        outer_color = rgb(${hex theme.accentHex})
        inner_color = rgb(${hex palette.mantle})
        font_color = rgb(${hex palette.text})
        font_family = ${theme.fonts.monospace}
        check_color = rgb(${hex theme.accentAltHex})
        fail_color = rgb(${hex palette.red})
        capslock_color = rgb(${hex palette.yellow})
        placeholder_text = <span foreground="#${palette.overlay0}">password</span>
        fail_text = $FAIL
        fade_on_empty = false
        dots_size = 0.25
        dots_spacing = 0.3
      }
    '';
  };
}
