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

  # The same drawing at three zoom levels: the mark stays the anchor, the grid around it
  # gets finer or coarser. The first is the one hyprpaper starts on and hyprlock dims.
  wallpapers = map (density: config.lattice.artwork.wallpaper { inherit density; }) [
    "1.0"
    "0.7"
    "1.4"
  ];
  wallpaper = lib.head wallpapers;

  # Switching between them, for a bind in ~/.dotfiles. hyprpaper 0.8 loads an image when it
  # is asked for -- `preload` is gone -- so the variants only have to exist in the store.
  # hyprpaper can also rotate a directory by itself, with `timeout` and `order` in the
  # wallpaper block below; this stays manual so the desktop only changes when asked.
  cycleWallpaper = pkgs.writeShellApplication {
    name = "lattice-wallpaper";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      wallpapers=(${lib.concatStringsSep " " wallpapers})
      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-wallpaper"
      index=$(cat "$state" 2>/dev/null || echo 0)
      count=''${#wallpapers[@]}

      case "''${1:-next}" in
      next) index=$(((index + 1) % count)) ;;
      prev) index=$(((index - 1 + count) % count)) ;;
      list)
        printf '%s\n' "''${wallpapers[@]}"
        exit 0
        ;;
      *[!0-9]*)
        echo "usage: lattice-wallpaper [next|prev|list|<index>]" >&2
        exit 2
        ;;
      *) index=$(($1 % count)) ;;
      esac

      hyprctl hyprpaper wallpaper ",''${wallpapers[index]}"
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
      pkgs.rofi
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
  # Launched from rofi rather than a key. The Dell has a dedicated Print key, but the Mac's
  # internal keyboard (hid-apple, 05AC:0352) lands on the magic_keyboard_2021_and_2024 fn
  # table, which has no KEY_SYSRQ on either fn layer -- so a Print bind was silently dead
  # on one of the two hosts. One launcher entry behaves the same on both. (evtest-style
  # dumps do show KEY_SYSRQ here; that comes from the generic HID boot-keyboard descriptor,
  # not from a key that exists. Same trap as the backlight keys in profiles/laptop.nix.)
  #
  # Note that HyprQuickFrame spawns satty itself, with its own flags, so the only settings
  # of ours it honours are the ones in ~/.dotfiles/satty/.config/satty/config.toml that it
  # does not override -- `fullscreen` among them, which is why that moved out of the CLI
  # and into the config file. It passes its own --output-filename, --early-exit,
  # --init-tool and --copy-command.
  hqf = inputs.hyprquickframe.packages.${pkgs.system}.default;

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
    animations = true;
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
in
{
  # Everything below reads config.lattice.theme, so don't rely on branding.nix pulling it in.
  imports = [
    ../artwork.nix
    ../theme.nix
    ../plymouth.nix
    ../display.nix
    ../webapps.nix
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
    rofi
    # hyprsunset ships only as a systemd.packages unit above, so its CLI -- which is how
    # the running daemon is driven -- wasn't on PATH for lattice-sunset or a shell.
    hyprsunset
    # notify-send: without it every script that tries to raise a notification fails
    # silently, mako itself was fine all along.
    libnotify
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
    firefoxpwa
    bitwarden-desktop
    wf-recorder

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
    tailscale
    wifiMenu
    powerMenu
    screenshot
    screenshotItem
    # The drawing tool itself, for trying a density or a phase before wiring it in.
    config.lattice.artwork.draw
  ];

  programs = {
    firefox = {
      enable = true;
      nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
    };
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
    udev.packages = [ pkgs.swayosd ];
  };
  users.users.winston.extraGroups = [ "video" ];

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
    hyprpaper.wantedBy = [ "graphical-session.target" ];
    mako.wantedBy = [ "graphical-session.target" ];
    hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
    hyprsunset.wantedBy = [ "graphical-session.target" ];

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
      tailscale
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
    useTextGreeter = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet";
  };

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

    # tuigreet takes ANSI colour names, not hex, so the accent maps to its nearest name.
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
    '';

    "xdg/hypr/hyprlock.conf".text = ''
      general {
        hide_cursor = true
      }

      background {
        monitor =
        path = ${wallpaper}
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
