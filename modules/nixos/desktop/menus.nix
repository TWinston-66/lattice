{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    theme
    rofiWithCalc
    ;

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

  # The output and input pickers, behind the volume and microphone pills. Same shape as
  # lattice-wifi above and for the same reason: what a bar pill wants is the short list of
  # devices to switch between, and rofi is already themed, already the launcher, and lets
  # one be found by typing rather than hunted down a list.
  #
  # One script for both. The two menus differ only in which nodes they list and which pactl
  # verbs move them; the theme, the rendering and the loop are the same, and two copies of
  # that would drift.
  #
  # Picking a device moves what is already playing over with the default rather than only
  # redirecting the next stream to start -- `pactl set-default-sink` on its own leaves the
  # current song on the old speakers, which is not what picking speakers from a menu means.
  # That is the pairing `lattice-deck audio` already makes for the deck's round-robin key.
  audioMenu = pkgs.writeShellApplication {
    name = "lattice-audio";
    runtimeInputs = [
      rofiWithCalc
      # pactl, for the listing, the default and moving live streams. wpctl can set a
      # default but has no equivalent of move-sink-input, and `pactl -f json` is a document
      # to query rather than a table to scrape -- the same reason lattice-deck takes it.
      pkgs.pulseaudio
      pkgs.jq
      # swayosd-client for the mute row, so muting from the menu raises the same pill the
      # mute key does. Nothing here calls wpctl.
      pkgs.swayosd
      pkgs.libnotify
    ];
    text = ''
            case "''${1:-}" in
            output)
              noun=Output; nodes=sinks; streams=sink-inputs; get_default="get-default-sink"
              set_default="set-default-sink"; move="move-sink-input"
              osd=--output-volume; topic=mute; fallback=󰓃
              ;;
            input)
              noun=Input; nodes=sources; streams=source-outputs; get_default="get-default-source"
              set_default="set-default-source"; move="move-source-output"
              osd=--input-volume; topic=mic; fallback=󰍬
              ;;
            *)
              echo "usage: lattice audio output|input" >&2
              exit 2
              ;;
            esac

            # Anchored and sized exactly like lattice-wifi's menu -- the long note on the theme
            # there says what each offset is counted from. It is not hung under the pill that
            # opened it for the reason that one isn't either: everything to the right of both is
            # variable width, so no fixed offset stays under them.
            #
            # Wider than that menu's 340px, because these labels are longer than an SSID:
            # "Built-in Audio Headset Microphone" is 33 characters, and a device list that
            # truncates the word saying which device it is has lost the plot. A glyph, a
            # 34-column description and a right-aligned reading come to 43 columns of JetBrains
            # Mono 10 -- ~345px, against the ~412px this leaves once config.rasi's 12px window
            # padding, its 2px border and the element padding above are taken off. 400px was not
            # enough and rofi answered by ellipsising the reading off the end of every row.
            theme='
              window { location: north east; anchor: north east; x-offset: -10px; y-offset: 5px; width: 460px; }
              * { font: "JetBrains Mono 10"; }
              inputbar { padding: 7px 10px; }
              element { padding: 5px 10px; }
              listview { lines: 12; }

              /* The device in use, marked with rofi -a, in the same green lattice-wifi gives the
                 network in use -- config.rasi draws an active row in lavender, which reads as a
                 shade of the ordinary text rather than as a state. */
              element normal.active, element alternate.active { text-color: @green; }
              element selected.active { background-color: @green; text-color: @crust; }
            '

            # One click accepts, as on every other bar surface; see lattice-wifi.
            click=(-me-select-entry "" -me-accept-entry MousePrimary)

            # -mesg is the one string rofi renders as pango markup, and a device description is
            # free text -- "Family & Friends Dock" would take the whole message down otherwise.
            pango() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g'; }

            # PipeWire names the hardware, not the shape of it, so the glyph is guessed from what
            # the device says about itself: device.icon_name first, since that is the field meant
            # for this, then the form factor, then the node name for what neither covers. Order
            # matters -- a Bluetooth headset is both, and the bus is the more useful of the two
            # to draw.
            #
            # Anything unrecognised keeps the per-menu fallback rather than drawing nothing:
            # speakers for an output, a microphone for an input. Also a guess, but the right one
            # more often than not, and a blank column would take the row out of line.
            glyph_for() {
              case "$1|$2|$3" in
              *bluez* | *luetooth*)   printf '󰂯' ;;
              *headset*)              printf '󰋎' ;;
              *headphone*)            printf '󰋋' ;;
              *hdmi* | *isplayport*)  printf '󰡁' ;;
              *speaker*)              printf '󰓃' ;;
              *)                      printf '%s' "$fallback" ;;
              esac
            }

            # A monitor is the loopback of a sink and is a source only as an accident of the
            # PulseAudio model: there is nothing to record from, and listing them would fill the
            # input menu with a second copy of the output one. device.class marks them, and the
            # name suffix is checked as well because a node that sets neither is still a monitor
            # if it is called one. Both are no-ops on the sink side, which has none.
            #
            # value_percent arrives as "100%" and the row builds its own reading, so it is
            # stripped to digits here and the parsing stays in one place. Channels can differ and
            # the first is taken -- a balance that is not centred is not what this menu is for.
            #
            # Every column is emitted non-empty, "-" standing in for a property the node does not
            # set. That is load-bearing rather than tidiness: the reader below splits on tab, tab
            # is IFS whitespace, and `read` collapses a run of IFS whitespace into one delimiter
            # -- so one empty field in the middle silently shifts every column after it left by
            # one. A device with no icon name read its form factor as its mute state, and every
            # output in the menu drew as muted. "-" matches none of the glyph patterns, so an
            # unknown lands on the fallback, which is where it belongs anyway.
            read_nodes() {
              pactl -f json list "$nodes" | jq -r --arg default "$default" '
                def dash: if (. // "") == "" then "-" else . end;

                # An ALSA jack is a node whether or not anything is in it, and its active port is
                # what says which. Listing the ones that are empty is worse than not listing them:
                # picking the headphone socket with nothing plugged into it sets the default,
                # WirePlumber sees an unavailable port and puts it straight back, and the menu
                # looks broken rather than honest. Ports that report "unknown" -- which is most
                # of them, and every USB device -- are kept; only an explicit no is a no.
                #
                # A node with no ports at all is kept too. The MacBook speakers are one: they are
                # a virtual node in front of the convolver, not a jack, so there is nothing to
                # ask. And the device in use is always listed whatever it claims, because a menu
                # that hides what you are listening through is not one worth opening.
                def available:
                  (.active_port // "") as $port
                  | .name == $default
                    or $port == ""
                    or (([.ports[]? | select(.name == $port) | .availability] | first) // "unknown")
                       != "not available";

                .[]
                | select((.properties["device.class"] // "") != "monitor")
                | select(.name | endswith(".monitor") | not)
                | select(available)
                | [ .name,
                    .description,
                    (.volume | to_entries | .[0].value.value_percent | gsub("[^0-9]"; "")),
                    (if .mute then "muted" else "live" end),
                    (.properties["device.icon_name"] | dash),
                    (.properties["device.form_factor"] | dash)
                  ] | @tsv'
            }

            while true; do
              default=$(pactl "$get_default" 2>/dev/null || true)

              names=(); rows=(); selected=(); mesg=""; default_muted=""; gone_desc=""
              while IFS=$'\t' read -r name desc vol muted icon ff; do
                [ -n "$name" ] || continue

                # The per-row reading is the level, or the muted glyph in its place -- a device
                # that is muted at 60% is muted, and the number would read as the live state.
                if [ "$muted" = muted ]; then reading=󰝟; else reading="$vol%"; fi

                if [ "$name" = "$default" ]; then
                  selected=(-a "''${#rows[@]}")
                  default_muted=$muted
                  # Kept for the note below, which has to name a device that no longer exists.
                  gone_desc=$desc
                  if [ "$muted" = muted ]; then
                    mesg="$(pango "$desc")  ·  muted at $vol%"
                  else
                    mesg="$(pango "$desc")  ·  $vol%"
                  fi
                fi

                names+=("$name")
                rows+=("$(printf '%s  %-34.34s %5s' "$(glyph_for "$icon" "$ff" "$name")" "$desc" "$reading")")
              done < <(read_nodes)

              if [ "''${#names[@]}" -eq 0 ]; then
                notify-send -a lattice-audio -i audio-card \
                  -h string:x-canonical-private-synchronous:lattice-audio \
                  "No $noun device" "PipeWire is reporting nothing to switch to"
                exit 0
              fi

              if [ "$default_muted" = muted ]; then action="󰕾  Unmute"; else action="󰝟  Mute"; fi

              # -a indexes the rendered list, so the mark moves down by the action row about to be
              # put above it.
              [ "''${#selected[@]}" -eq 2 ] && selected=(-a "$((selected[1] + 1))")

              # The cursor starts on the first device rather than on the action, the way
              # lattice-wifi starts below its own: Enter should act on a device, and mute is
              # reached by scrolling up or by typing it.
              choice=$(printf '%s\n' "$action" "''${rows[@]}" |
                rofi -dmenu -i -no-cycle -format i -p "$noun" -mesg "''${mesg:-no default device}" \
                  -theme-str "$theme" "''${click[@]}" "''${selected[@]}" -selected-row 1 || true)
              [ -n "''${choice:-}" ] || exit 0

              if [ "$choice" -eq 0 ]; then
                swayosd-client "$osd" mute-toggle
                # The deck's key draws this device's mute state and only knows what it is told.
                # `|| true` for the reason lattice-sunset gives: an unplugged deck, or a
                # lattice-deck that is not on this caller's PATH, must not fail a mute that has
                # already happened.
                lattice-deck sync "$topic" || true
                continue
              fi

              target=''${names[$((choice - 1))]}
              # Picking the device already in use should do nothing, rather than set a default it
              # already has and walk every live stream across to where it already is.
              [ "$target" = "$default" ] && exit 0

              pactl "$set_default" "$target"
              while read -r stream; do
                [ -n "$stream" ] || continue
                pactl "$move" "$stream" "$target" 2>/dev/null || true
              done < <(pactl list short "$streams" | cut -f1)

              # Moving a live stream off the MacBook's speakers takes the speakers away with it:
              # the ALSA node behind asahi-audio's convolver hangs up ("poll fd error/hangup
              # (card removed?)" in wireplumber's journal), the software-dsp filter in front of it
              # goes with it, and neither comes back until pipewire is restarted -- restarting
              # wireplumber alone is not enough, because the node that died belongs to the daemon.
              # Nothing here causes it: `lattice-deck audio` has always done the same two steps
              # and has always had the same effect. Setting the default alone does not do it, and
              # ordinary playback stopping does not either; it takes the unlink.
              #
              # swayosd is in the restart because it is collateral: swayosd-server resolves the
              # default sink once and holds it, so a pipewire that came back underneath it leaves
              # every --output-volume call a silent no-op until it is restarted too.
              #
              # So the menu says so rather than leaving someone to find the speakers missing from
              # it later and conclude the picker is broken. Only when it actually happens: the
              # node list is read back, and this is silent unless what was just switched away from
              # has genuinely gone. The second is for the teardown, which is not instant.
              #
              # The fix is a verb rather than the four-unit systemctl line it wraps, because the
              # Stream Deck's media page has a key for it and a banner that names the same command
              # the key runs is one thing to remember instead of two. See modules/nixos/
              # streamdeck.nix, which is also where the why is written down.
              sleep 1
              if [ -n "$default" ] && ! read_nodes | cut -f1 | grep -qxF "$default"; then
                notify-send -a lattice-audio -i audio-card \
                  -h string:x-canonical-private-synchronous:lattice-audio \
                  "$noun switched" \
                  "$gone_desc is gone from the list -- an Asahi quirk. \
      The deck's restart key, or <tt>lattice-deck audio-restart</tt>, brings it back."
              fi

              # The new device brings its own mute state with it, which is what the deck draws.
              lattice-deck sync "$topic" || true
              exit 0
            done
    '';
  };

  # The SUPER + / cheatsheet: every bind that says what it does, in one rofi list. Nothing
  # is written down twice -- the rows come live from the configs themselves, Hyprland binds
  # with a description, tmux binds with a note and nvim maps with a desc, so a key goes on
  # the sheet by being described where it is bound, and a rebind can't leave it stale.
  # ~/.config/hypr/keys.tsv (the hypr stow package) adds what no config can report -- the
  # trackpad gesture, the mouse's Solaar rules -- and hides rows not worth the space.
  #
  # tmux and nvim come from PATH rather than runtimeInputs: tmux has to be the build the
  # server is running, and nvim has to be the one the config and its plugins were set up for.
  hyprKeys = pkgs.writeText "lattice-keys-hypr.jq" ''
    # hyprctl binds -j -> "<keys>\t<description>", for the described binds only. Binds that
    # share a description, modifiers and submap fold into one row ("SUPER + 0-9"), in the
    # order the config makes them.
    def mods:
      . as $m
      | [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
      | map(select(($m / .[0] | floor) % 2 == 1) | .[1]);
    def pretty:
      {
        left: "←", right: "→", up: "↑", down: "↓",
        mouse_down: "Scroll", mouse_up: "Scroll",
        "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB",
        slash: "/", escape: "Esc", return: "Enter", SPACE: "Space",
        XF86AudioRaiseVolume: "Vol+", XF86AudioLowerVolume: "Vol-",
        XF86AudioMute: "Mute", XF86AudioMicMute: "MicMute",
        XF86MonBrightnessUp: "Bright+", XF86MonBrightnessDown: "Bright-",
        XF86AudioPlay: "Play", XF86AudioPause: "Pause",
        XF86AudioNext: "Next", XF86AudioPrev: "Prev"
      }[.] // .;
    def keylist:
      if length == 10 and all(test("^[0-9]$")) then "0-9"
      elif (sort == ["down", "left", "right", "up"]) then "Arrows"
      else map(pretty) | reduce .[] as $k ([]; if index([$k]) then . else . + [$k] end) | join("/")
      end;

    reduce (.[] | select(.has_description)) as $b ({order: [], groups: {}};
      ([$b.submap, ($b.modmask | tostring), $b.description] | join("\u0001")) as $id
      | if .groups[$id] == null then
          .order += [$id]
          | .groups[$id] = {submap: $b.submap, modmask: $b.modmask, desc: $b.description, keys: [$b.key]}
        elif (.groups[$id].keys | index([$b.key])) then .
        else .groups[$id].keys += [$b.key]
        end)
    | .groups as $g
    | .order[]
    | $g[.]
    | ((.modmask | mods) + [.keys | keylist] | join(" + ")) as $keys
    | [(if .submap == "" then $keys else .submap + ": " + $keys end), .desc]
    | @tsv
  '';

  nvimKeys = pkgs.writeText "lattice-keys-nvim.lua" ''
    -- Every map the user's config describes, as "<keys>\t<description>" lines on stdout.
    -- LSP maps are buffer-local and only made on LspAttach, which a headless nvim with no
    -- server never sees, so it is fired by hand on the empty buffer first.
    pcall(vim.api.nvim_exec_autocmds, "LspAttach", { buffer = 0, data = {} })

    local leader = vim.g.mapleader or "\\"
    local modes = { n = "n", x = "v", o = "o", i = "i", t = "t", c = "c" }
    local order, rows = {}, {}

    local function add(map, mode)
      -- sid < 0 is nvim's own runtime: its default maps carry descs too, and are not ours.
      if not map.desc or map.desc == "" or map.sid < 0 then
        return
      end
      local lhs = map.lhs
      if lhs:sub(1, #leader) == leader then
        lhs = "<leader>" .. lhs:sub(#leader + 1)
      end
      lhs = lhs:gsub(" ", "<Space>")
      local id = lhs .. "\t" .. map.desc
      if not rows[id] then
        rows[id] = { lhs = lhs, desc = map.desc, modes = {} }
        table.insert(order, id)
      end
      if not vim.tbl_contains(rows[id].modes, mode) then
        table.insert(rows[id].modes, mode)
      end
    end

    for query, mode in pairs(modes) do
      for _, map in ipairs(vim.api.nvim_get_keymap(query)) do
        add(map, mode)
      end
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, query)) do
        add(map, mode)
      end
    end

    table.sort(order)
    for _, id in ipairs(order) do
      local row = rows[id]
      table.sort(row.modes)
      local desc = row.desc
      -- Normal mode goes without saying; anything else is spelled out.
      if not (#row.modes == 1 and row.modes[1] == "n") then
        desc = desc .. "  [" .. table.concat(row.modes, ",") .. "]"
      end
      io.stdout:write(row.lhs, "\t", desc, "\n")
    end
  '';

  keybindings = pkgs.writeShellApplication {
    name = "lattice-keys";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      rofiWithCalc
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    text = ''
      extras="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/keys.tsv"

      # What is in front of you decides which section leads: nvim if the tmux pane last typed
      # into is running it, tmux if a terminal has focus, the desktop otherwise. Everything is
      # still listed and searchable; this only saves scrolling past the rest.
      focus=hypr
      if [[ $(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""') == com.mitchellh.ghostty ]]; then
        focus=tmux
        pane=$(tmux list-clients -F '#{client_activity} #{pane_current_command}' 2>/dev/null \
          | sort -rn | head -n1 | cut -d' ' -f2-) || true
        [[ $pane == nvim ]] && focus=nvim
      fi
      case $focus in
        nvim) order=(nvim tmux hypr mouse) ;;
        tmux) order=(tmux nvim hypr mouse) ;;
        *) order=(hypr mouse tmux nvim) ;;
      esac

      live() {
        hyprctl binds -j | jq -r -f ${hyprKeys} | sed 's/^/hypr\t/'

        # Only binds the config itself notes: tmux notes every default too, so those are listed
        # by a throwaway server that has read no config and taken out. The prefix is set on it
        # first so its rows read the same as the live ones. No server, no tmux section --
        # starting one with the real config would set tmux-continuum restoring sessions.
        if prefix=$(tmux show -gv prefix 2>/dev/null); then
          tmux list-keys -N \
            | grep -vxFf <(tmux -L "lattice-keys-$$" -f /dev/null start-server \; \
                set -g prefix "$prefix" \; list-keys -N \; kill-server 2>/dev/null) \
            | sed -E 's/^([^ ]+ [^ ]+) +/tmux\t\1\t/' || true
        fi

        # The real config, headless, against an empty buffer. timeout so a plugin that wants
        # an answer at startup costs a missing section rather than a picker that never opens.
        if command -v nvim >/dev/null; then
          (cd "''${XDG_RUNTIME_DIR:-/tmp}" && timeout 5 nvim --headless \
            -c "luafile ${nvimKeys}" -c 'qa!' 2>/dev/null) | sed 's/^/nvim\t/' || true
        fi
      }

      # keys.tsv rows are added, and a "-" description takes the matching live row out. awk
      # reads the extras first so it knows what to drop by the time the live rows arrive. By
      # name rather than FNR == NR, which an empty or missing keys.tsv would turn true for both.
      rows=$(
        awk -F '\t' -v OFS='\t' -v order="''${order[*]}" '
          BEGIN { n = split(order, o, " "); for (i = 1; i <= n; i++) rank[o[i]] = i }
          FILENAME == ARGV[1] {
            if ($0 ~ /^#/ || NF < 3) next
            if ($3 == "-") hide[$1 FS $2] = 1
            else extra[++e] = $0
            next
          }
          !(($1 FS $2) in hide) && !seen[$0]++ { print rank[$1] + 0, ++i, $0 }
          END { for (j = 1; j <= e; j++) { split(extra[j], f, FS); print rank[f[1]] + 0, ++i, extra[j] } }
        ' <(cat "$extras" 2>/dev/null || true) <(live) \
          | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
      )

      # Read-only: picking a row does nothing, it is the search that is the point.
      # Padded into columns rather than rofi's -display-columns, which joins but never aligns.
      # The font is monospace (config.rasi), so spaces line up.
      printf '%s\n' "$rows" \
        | awk -F '\t' '
            { s[NR] = $1; k[NR] = $2; d[NR] = $3; if (length($2) > w) w = length($2) }
            END { for (i = 1; i <= NR; i++) printf "%-5s  %-*s  %s\n", s[i], w, k[i], d[i] }
          ' \
        | rofi -dmenu -i -no-custom -p "keys" \
            -theme-str 'window { width: 960px; } listview { lines: 14; }' \
        >/dev/null || true
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
      pkgs.jq # the focused screen's height, for the margin below
    ];
    text = ''
      # Clicking the bar pill a second time should close the menu, not stack another
      # copy of it behind the first.
      if pgrep -x wlogout >/dev/null; then
        pkill -x wlogout
        exit 0
      fi

      # How tall a button comes out, and the only lever there is for it. wlogout gives every
      # button vexpand, so a button is exactly its share of the grid's height -- no padding,
      # min-height or margin in style.css can make it shorter than that, they only ever raise
      # the floor. What the grid gets is the screen minus wlogout's own margin, so the margin
      # is the thing to set: take the height the buttons should have out of the middle of the
      # screen and give the rest away.
      #
      # It is measured rather than written down because one number is a different button on
      # every screen -- this menu is a single row of five here and two rows of three on a host
      # that hibernates, and the Mac's 840 logical rows are not the Dell's.
      #
      # The measurement is the *shortest* screen attached, not the focused one. wlogout draws
      # the grid on every output and has only one set of margins for all of them, so a margin
      # taken from a tall docked screen is more than a laptop panel has to give -- the band it
      # asks to keep clear is taller than the panel, and the menu lands off the bottom of it.
      # The shortest screen is the one that fits everywhere.
      rows=${toString (if canHibernate then 2 else 1)}
      height=140
      # The button's own margin in /etc/xdg/wlogout/style.css, which is outside the height
      # above -- so a change there wants the same change here.
      gap=14

      margin=()
      if screen=$(hyprctl monitors -j 2>/dev/null |
        jq -e -r '[.[] | .height / .scale] | min | floor'); then
        v=$(((screen - rows * (height + 2 * gap)) / 2))
        # A screen too short to seat the menu at that height keeps a thin band top and bottom
        # rather than a negative margin, and the buttons come out shorter than asked for.
        [ "$v" -lt 40 ] && v=40
        margin=(--margin-top "$v" --margin-bottom "$v")
      fi

      # No margin flags if the query failed, which leaves wlogout's own 230 on every side --
      # the full-height buttons this replaced, rather than no menu at all.
      exec wlogout \
        --layout /etc/xdg/wlogout/layout \
        --css /etc/xdg/wlogout/style.css \
        "''${margin[@]}" \
        --buttons-per-row ${toString (if canHibernate then 3 else lib.length powerButtons)}
    '';
  };
in
{
  environment.systemPackages = [
    rofiWithCalc
    wifiMenu
    audioMenu
    powerMenu
    keybindings
  ];

  systemd.user.services.waybar.path = [
    wifiMenu
    audioMenu
    powerMenu
  ];

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
  # over a scrim that dims the desktop behind it. Every colour comes in through the bar's
  # palette by name rather than as a literal, so the menu follows lattice-palette's flavour
  # and accent like the bar does.
  environment.etc."xdg/wlogout/style.css".text = ''
    @import url("file:///etc/xdg/waybar/lattice.css");

    * {
      background-image: none;
      box-shadow: none;
      font-family: "${theme.fonts.monospace}", "Symbols Nerd Font";
      font-size: 17px;
    }

    window {
      background-color: alpha(@crust, 0.72);
    }

    button {
      color: @text;
      background-color: alpha(@base, ${toString theme.opacity});
      border: 2px solid @surface0;
      border-radius: 14px;
      /* Outside the height lattice-power sizes the grid to -- keep `gap` there in step. */
      margin: 14px;
      padding: 28px;
      outline-style: none;
      /* GTK animates between the two states, so hover and focus fade rather than snap. */
      transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease;
    }

    button:focus,
    button:hover {
      color: @accent;
      background-color: alpha(@surface0, ${toString theme.opacity});
      border-color: @accent;
    }

    /* The two that can't be taken back warn in their own colour on the way past. */
    #reboot:focus,
    #reboot:hover {
      color: @peach;
      border-color: @peach;
    }

    #shutdown:focus,
    #shutdown:hover {
      color: @red;
      border-color: @red;
    }
  '';

  lattice.cli.commands = {
    wifi = {
      exec = lib.getExe wifiMenu;
      summary = "Join, rescan, disconnect or switch off Wi-Fi";
      group = "session";
    };
    audio = {
      exec = lib.getExe audioMenu;
      args = "<output|input>";
      summary = "Pick an output or input; what is playing moves with it";
      group = "session";
    };
    "power menu" = {
      exec = lib.getExe powerMenu;
      summary = "Lock, suspend, log out, reboot or shut down";
      group = "session";
    };
    keys = {
      exec = lib.getExe keybindings;
      summary = "Search every Hyprland, tmux and Neovim binding";
      group = "session";
    };
  };
}
