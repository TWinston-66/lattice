{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; })
    theme
    readColours
    rofiWithCalc
    ;

  # The real-time signal each script sends waybar to re-run its pill at once, and the one
  # the pill listens for: SIGRTMIN+n. Shared from here so the two can't drift apart.
  # Other modules hold the rest (waybar.nix asserts no two pills share one).
  #
  # Every script sends it with `pkill -RTMIN+n waybar` and never `-x`: the process is
  # nixpkgs' wrapper's .waybar-wrapped, so an exact match finds nothing and the signal is
  # silently lost -- six pills refreshed only on their intervals that way.
  signal = {
    tailscale = 2;
    weather = 3;
    powerProfile = 6;
    vault = 7;
  };

  # The power-profile pill's sample rate, which its graph needs to know; see `period` in
  # the script.
  powerProfileInterval = 2;

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

        # One jq pass for every field. The status runs to most of a megabyte with Mullvad's
        # exit nodes in the peer list -- 837 KB, 536 peers on 2026-10-06 -- and a jq per field
        # parsed all of it nine times over: about 0.35s of CPU per tick, on each bar. One field
        # per line, health warnings last, with newlines inside a value flattened so nothing can
        # shift the fields after it.
        local -a f
        mapfile -t f < <(jq -r '
          . as $root
          | ((.BackendState // "NoState"),
          (.Self.HostName // "this device"),
          (.Self.TailscaleIPs[0] // ""),
          (.Self.DNSName // "" | sub("\\.$"; "")),
          (.CurrentTailnet.Name // ""),
          (.Self.ExitNode // false),
          ([.Peer[]? | select((.ExitNodeOption | not) and .Online)] | length),
          ([.Peer[]? | select(.ExitNodeOption | not)] | length),
          (.ExitNodeStatus.ID // "" | . as $id
            | if $id == "" then "" else [$root.Peer[]? | select(.ID == $id)][0].HostName // $id end),
          (.AuthURL // ""),
          (.Health // [] | .[]))
          | tostring | gsub("[\n\r]"; " ")
        ' <<<"$json")

        local backend="''${f[0]:-NoState}" text
        local -a classes lines

        case "$backend" in
        Running)
          local host=''${f[1]} ip=''${f[2]} dns=''${f[3]} tailnet=''${f[4]} advertise=''${f[5]}
          local online=''${f[6]} devs=''${f[7]} exit_name=''${f[8]}

          lines=("Tailscale: Connected" "$host  $ip")
          if [ -n "$tailnet" ]; then lines+=("tailnet: $tailnet"); fi
          lines+=("devices: $online/$devs online")

          # Using an exit node is the difference between "the tunnel is up" and "traffic
          # is actually going through Mullvad", so it gets its own class for style.css to
          # colour on: teal with one, red without. ExitNodeStatus is null unless this node
          # is routing through one; its ID names the peer to show in the tooltip.
          local exit_class
          if [ -n "$exit_name" ]; then
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
          if [ "''${#f[@]}" -gt 10 ]; then
            text="$glyph_alert"
            classes=(running warning)
            for line in "''${f[@]:10}"; do lines+=("warning: $line"); done
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
          authurl=''${f[9]}
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

        # After a sign-in this only repaints the pill as "signed out" again -- the browser
        # leg is still in progress at this point -- so the switch to connected arrives with
        # the module's 30s interval.
        pkill -RTMIN+${toString signal.tailscale} waybar 2>/dev/null || true
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
        echo "usage: lattice tailscale [status|toggle|web]" >&2
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
    # With no place set there is nothing to ask for, and an empty line hides the pill.
    text = ''
      ${
        lib.optionalString (config.lattice.weather.latitude == null) "exit 0\n"
      }lat=${toString config.lattice.weather.latitude}
      lon=${toString config.lattice.weather.longitude}
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

        # Just the glyph and the temperature. The apparent temperature used to sit beside
        # it, dimmed, with both right-aligned in three-character fields so the pill kept one
        # width -- eleven characters in all. That is the pill next to the clock, and when
        # the backup pill appeared further along the left group it pushed this one into the
        # clock. So the feels-like reading is in the tooltip now and the padding is gone:
        # five characters. The width still moves by one at -5° or 100°, which is rare
        # enough not to buy back the padding for.
        text=$(printf '%s %s°' "$icon" "$temp")

        tooltip=$(printf '<b>%s</b>\n%s\nFeels like %s°\nH %s°  L %s°\nWind %s mph %s · Humidity %s%%\nSunset %s' \
          "$label" "$desc" "$feels" "$hi" "$lo" "$wind" "$(compass "$wdir")" "$hum" "$sunset")

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
      refresh) pkill -RTMIN+${toString signal.weather} waybar 2>/dev/null || true ;;
      *)
        echo "usage: lattice weather [status|refresh]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # The power-profile pill, as a custom module rather than waybar's own
  # power-profiles-daemon. What the swap buys is the tooltip: four sparklines over a
  # two-minute window -- load, each core cluster's clock and the package's own draw in watts
  # -- under the profile's name, with any cap the profile has put on a cluster's clock. Below
  # them, every readout the machine exposes: the battery (charge limit, wear, cycles), the
  # adapter, the fans, the heatpipe and each named temperature sensor. None of that could
  # hang off the built-in module, whose tooltip-format takes exactly one placeholder,
  # {profile}.
  #
  # What it costs is the D-Bus subscription: the built-in module watched
  # net.hadess.PowerProfiles and repainted the instant anything else set a profile, where
  # this polls. At the pill's 2s interval a press on the deck's profile key, or a
  # `powerprofilesctl set` in a shell, lands within one tick -- close enough not to read as
  # a lag, and the reason the click below goes through lattice-deck rather than at busctl.
  #
  # The sampling has to run whether or not anyone is hovering, because a graph that only
  # started when the tooltip opened would be an empty one. So a tick is built to be cheap:
  # sysfs through bash's `read` rather than $(cat), the slow-moving readouts cached between
  # ticks, and one fork in the whole script -- busctl, for the profile. That measures ~15ms
  # per tick on this Mac, most of it bash's own startup. The window lives in
  # XDG_RUNTIME_DIR, so it is per-boot and never on disk.
  powerProfile = pkgs.writeShellApplication {
    name = "lattice-power-profile";
    runtimeInputs = [
      pkgs.systemd # busctl, for the profile the pill names
      pkgs.procps # pkill, to signal the bar after a click
    ];
    text = ''
      # The tooltip's palette, read from the run-time theme on every tick so a theme switch
      # reaches it too.
      # The three profile colours are the ones style.css gives the pill, so the name in the
      # tooltip and the glyph on the bar are the same colour; the series each get their own.
      ${readColours}
      c_dim=''${c[overlay1]}
      c_text=''${c[text]}
      c_load=''${c[blue]}
      c_pcore=''${c[lavender]}
      c_ecore=''${c[teal]}
      c_watt=''${c[peach]}
      c_saver=''${c[green]}
      c_balanced=''${c[mauve]}
      c_perf=''${c[peach]}
      c_none=''${c[overlay0]}
      c_warn=''${c[red]}
      # The graph is `width` samples of the waybar interval, so these two are the window: 60 at
      # 2s is the last two minutes. `period` is that interval, used only to say how long the
      # window is.
      width=60
      period=${toString powerProfileInterval}
      extras_every=10

      state="''${XDG_RUNTIME_DIR:-/tmp}/lattice-power-profile"
      history="$state/history"
      extras="$state/extras"

      bars=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

      case "''${1:-status}" in
      status) ;;
      cycle)
        # The cycle itself belongs to lattice-deck: it already walks saver -> balanced ->
        # performance through only the profiles this machine's daemon offers, and repaints the
        # deck's key afterwards. Going through it rather than straight at busctl is what keeps the
        # bar and the deck from disagreeing about which profile is on -- the same reason both
        # audio pills mute through lattice-deck.
        lattice-deck profile
        pkill -RTMIN+${toString signal.powerProfile} waybar 2>/dev/null || true
        exit 0
        ;;
      *)
        echo "usage: lattice power profile [status|cycle]" >&2
        exit 2
        ;;
      esac

      # Every reading here is a one-line sysfs file, and $(cat) would fork for each -- twenty-odd
      # of them per tick, every two seconds, all day. `read` into a global is the same thing with
      # no process: `rd path` leaves the value in $val, and a file that is missing, empty or
      # unreadable leaves it empty rather than failing the script.
      val=""
      rd() {
        val=""
        [ -r "$1" ] || return 0
        read -r val < "$1" 2>/dev/null || val=""
      }

      # Guards for everything that reaches arithmetic. sysfs gives unsigned; the state files carry
      # -1 for "this machine has no such sensor", and `sane` is the one test that covers a whole
      # series at once -- a line of digits, spaces and minus signs is safe to do sums on, and
      # anything else (a half-written file from a tick that was killed) starts the window again.
      uint() { case "''${1-}" in "" | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
      sane() { case "''${1-}" in *[!0-9\ -]*) return 1 ;; *) return 0 ;; esac; }

      ### SAMPLE ###

      [ -d "$state" ] || mkdir -p "$state"

      now=''${EPOCHREALTIME/./}

      # CPU busy fraction, as the jiffy counters' delta against the previous sample.
      read -r _ u n s idle iow irq sirq steal _ < /proc/stat
      busy=$((u + n + s + irq + sirq + steal))
      total=$((busy + idle + iow))

      # cpufreq, grouped by the ceiling each policy reports: one group on a machine whose cores
      # are all alike, two where the clusters differ -- this Mac's E- and P-cores, or a hybrid
      # x86 part. A third ceiling, if one ever turns up, folds into the fastest and the slowest.
      # `cap` is scaling_max_freq, the ceiling a power profile has set below the hardware's -- on
      # this Mac the whole difference between the three levels.
      p_max=0 p_min=0 p_sum=0 p_n=0 p_gov="" p_cap=0
      e_max=0 e_min=0 e_sum=0 e_n=0 e_cap=0
      for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        rd "$policy/cpuinfo_max_freq"
        uint "$val" || continue
        hi=$val
        rd "$policy/scaling_cur_freq"
        uint "$val" || continue
        cur=$val
        rd "$policy/cpuinfo_min_freq"
        if uint "$val"; then lo=$val; else lo=0; fi
        rd "$policy/scaling_max_freq"
        if uint "$val"; then cap=$val; else cap=$hi; fi

        if [ "$hi" -gt "$p_max" ]; then
          # A faster group than anything seen so far. What was the fastest becomes the slowest,
          # unless something slower has already claimed that.
          if [ "$p_max" -gt 0 ] && { [ "$e_max" -eq 0 ] || [ "$p_max" -lt "$e_max" ]; }; then
            e_max=$p_max e_min=$p_min e_sum=$p_sum e_n=$p_n e_cap=$p_cap
          fi
          p_max=$hi p_min=$lo p_sum=$cur p_n=1 p_cap=$cap
          rd "$policy/scaling_governor"
          p_gov=$val
        elif [ "$hi" -eq "$p_max" ]; then
          p_sum=$((p_sum + cur)) p_n=$((p_n + 1))
        elif [ "$e_max" -eq 0 ] || [ "$hi" -lt "$e_max" ]; then
          e_max=$hi e_min=$lo e_sum=$cur e_n=1 e_cap=$cap
        elif [ "$hi" -eq "$e_max" ]; then
          e_sum=$((e_sum + cur)) e_n=$((e_n + 1))
        fi
      done
      if [ "$p_n" -gt 0 ]; then p_cur=$((p_sum / p_n)); else p_cur=0; fi
      if [ "$e_n" -gt 0 ]; then e_cur=$((e_sum / e_n)); else e_cur=0; fi

      # Draw, in milliwatts, from whichever of three sources this machine has. macsmc's "Total
      # System Power" is the whole-package figure and the reason this row is worth graphing at
      # all: it is the number a power profile is actually chosen for. The other two are
      # fallbacks for other hardware, and are untested.
      power_mw=-1
      energy_uj=-1
      power_src=""
      for hwmon in /sys/class/hwmon/hwmon*; do
        for lbl in "$hwmon"/power*_label; do
          [ -e "$lbl" ] || continue
          rd "$lbl"
          [ "$val" = "Total System Power" ] || continue
          rd "''${lbl%_label}_input"
          uint "$val" || continue
          power_mw=$((val / 1000))
          power_src=smc
        done
      done
      if [ -z "$power_src" ]; then
        # Intel's RAPL package counter is microjoules since boot, so it needs the previous reading
        # and the interval between the two -- the same delta the jiffies take above.
        rd /sys/class/powercap/intel-rapl:0/energy_uj
        if uint "$val"; then
          energy_uj=$val
          power_src=rapl
        fi
      fi
      if [ -z "$power_src" ]; then
        # Last resort: what the battery is passing. Only true while discharging -- on AC most
        # laptops report the charge rate here, or zero -- so the row it draws is the honest one
        # for a machine on battery and not much otherwise.
        for supply in /sys/class/power_supply/*; do
          rd "$supply/scope"
          [ "$val" = Device ] && continue
          rd "$supply/status"
          [ "$val" = Discharging ] || continue
          rd "$supply/power_now"
          uint "$val" || continue
          power_mw=$((val / 1000))
          power_src=battery
          break
        done
      fi

      ### HISTORY ###

      # Five lines: the counters the next tick differences against, then one line per series. The
      # series are stored across rather than down -- a line of numbers each, trimmed to the
      # graph's width -- so the render below reads its four graphs with four `read -a` and never
      # parses a sample. It lives in XDG_RUNTIME_DIR, so a reboot starts a fresh window.
      hist=()
      [ -r "$history" ] && mapfile -t hist < "$history"

      prev=()
      cpus=() pfreqs=() efreqs=() watts=()
      if [ "''${#hist[@]}" -ge 5 ] && sane "''${hist[0]}" && sane "''${hist[1]}" &&
        sane "''${hist[2]}" && sane "''${hist[3]}" && sane "''${hist[4]}"; then
        read -r -a prev <<<"''${hist[0]}"
        read -r -a cpus <<<"''${hist[1]}"
        read -r -a pfreqs <<<"''${hist[2]}"
        read -r -a efreqs <<<"''${hist[3]}"
        read -r -a watts <<<"''${hist[4]}"
      fi

      prev_ts=0 prev_busy=0 prev_total=0 prev_energy=-1
      uint "''${prev[0]-}" && prev_ts=''${prev[0]}
      uint "''${prev[1]-}" && prev_busy=''${prev[1]}
      uint "''${prev[2]-}" && prev_total=''${prev[2]}
      uint "''${prev[3]-}" && prev_energy=''${prev[3]}

      # Docked, there is a bar on each screen and each runs this on every tick, against the one
      # history file -- so the samples interleaved, one bar's two-second delta beside the other's
      # fraction of a second, and the load graph zig-zagged over half the window it claimed. A
      # tick within 1.5s of the last sample is the other bar's: it draws the window as it stands,
      # with the newest sample as the reading, and leaves the sampling to whichever bar got there
      # first.
      if [ "$prev_ts" -gt 0 ] && [ $((now - prev_ts)) -lt 1500000 ] && [ "''${#cpus[@]}" -gt 0 ]; then
        cpu=''${cpus[-1]} p_cur=''${pfreqs[-1]} e_cur=''${efreqs[-1]} power_mw=''${watts[-1]}
      else
        d_busy=$((busy - prev_busy))
        d_total=$((total - prev_total))
        if [ "$prev_total" -gt 0 ] && [ "$d_total" -gt 0 ] && [ "$d_busy" -ge 0 ]; then
          cpu=$((d_busy * 100 / d_total))
        else
          # First sample after a boot, or after a window that did not survive its sanity check. The
          # counters' lifetime average is not what this pill is for, so the graph starts at the floor
          # and the next tick is the first real reading.
          cpu=0
        fi
        [ "$cpu" -gt 100 ] && cpu=100

        if [ "$power_src" = rapl ] && [ "$prev_energy" -ge 0 ] && [ "$prev_ts" -gt 0 ]; then
          d_us=$((now - prev_ts))
          d_uj=$((energy_uj - prev_energy))
          # The counter wraps at max_energy_range_uj, which shows up as a negative delta. Dropping
          # that one sample is cheaper than carrying the range around to correct it.
          if [ "$d_us" -gt 0 ] && [ "$d_uj" -ge 0 ]; then power_mw=$((d_uj * 1000 / d_us)); fi
        fi

        cpus+=("$cpu")
        pfreqs+=("$p_cur")
        efreqs+=("$e_cur")
        watts+=("$power_mw")
        [ "''${#cpus[@]}" -gt "$width" ] && cpus=("''${cpus[@]: -$width}")
        [ "''${#pfreqs[@]}" -gt "$width" ] && pfreqs=("''${pfreqs[@]: -$width}")
        [ "''${#efreqs[@]}" -gt "$width" ] && efreqs=("''${efreqs[@]: -$width}")
        [ "''${#watts[@]}" -gt "$width" ] && watts=("''${watts[@]: -$width}")

        printf '%s\n' \
          "$now $busy $total $energy_uj" \
          "''${cpus[*]}" \
          "''${pfreqs[*]}" \
          "''${efreqs[*]}" \
          "''${watts[*]}" > "$history"
      fi

      ### EXTRAS ###

      # Fans, temperatures and the battery are readouts rather than series, and on this Mac every
      # one of them is an SMC round trip. They also move slowly, so they are re-read on their own
      # cadence and cached in between; the sampling above is the part that has to happen on every
      # tick. Line 1 is the stamp that says when this last ran, and a sensor the machine does not
      # have writes an empty line rather than a number -- so the render tests for emptiness and
      # never does arithmetic on a guess.
      ex=()
      [ -r "$extras" ] && mapfile -t ex < "$extras"
      stamp=0
      [ "''${#ex[@]}" -eq 17 ] && uint "''${ex[0]-}" && stamp=''${ex[0]}

      if [ $((now / 1000000 - stamp)) -ge "$extras_every" ]; then
        fan_rpm=() heat_mw="" ac_mw="" ac_mv="" temps=()
        for hwmon in /sys/class/hwmon/hwmon*; do
          rd "$hwmon/name"
          chip=$val

          for f in "$hwmon"/fan*_input; do
            [ -e "$f" ] || continue
            rd "$f"
            # A zero is kept: on this Mac the fans are off most of the time, and "off" is a
            # reading. The row goes missing only on a machine with no tachometer at all, rather
            # than appearing and disappearing under the other rows as the fans come and go.
            uint "$val" && fan_rpm+=("$val")
          done

          # The SMC's other rails. "3.8 V Rail Power" is left out: it reads 0 on this Mac.
          for lbl in "$hwmon"/power*_label "$hwmon"/in*_label; do
            [ -e "$lbl" ] || continue
            rd "$lbl"
            label=$val
            rd "''${lbl%_label}_input"
            uint "$val" || continue
            case "$label" in
            "Heatpipe Power") heat_mw=$((val / 1000)) ;;
            "AC Input Power") ac_mw=$((val / 1000)) ;;
            "Charger Input Voltage") ac_mv=$val ;;
            esac
          done

          # Every temperature sensor that names itself, hottest first. Unlabelled ones are skipped:
          # on this Mac they are the six speaker amplifiers. The battery's own sensor is left to
          # the Health row. There is no die temperature among them -- Asahi's SMC does not expose
          # one -- which is why the row names each sensor rather than claiming a CPU reading.
          [ "$chip" = macsmc_battery ] && continue
          for lbl in "$hwmon"/temp*_label; do
            [ -e "$lbl" ] || continue
            rd "$lbl"
            [ -n "$val" ] || continue
            label=''${val% Temperature}
            label=''${label% Temp}
            # nvme's only label is "Composite", which says nothing without the chip's name.
            [ "$chip" = nvme ] && label="NVMe ''${label,,}"
            rd "''${lbl%_label}_input"
            uint "$val" || continue
            temps+=("$((val / 1000))|$label")
          done
        done

        # Insertion sort on the leading number: there are a handful, and sort(1) is a fork.
        sorted=()
        for t in "''${temps[@]}"; do
          i=''${#sorted[@]}
          while [ "$i" -gt 0 ] && [ "''${sorted[i - 1]%%|*}" -lt "''${t%%|*}" ]; do
            sorted[i]=''${sorted[i - 1]}
            i=$((i - 1))
          done
          sorted[i]=$t
        done
        temps_line=""
        [ "''${#sorted[@]}" -gt 0 ] && printf -v temps_line '%s;' "''${sorted[@]}"

        batt_state="" batt_mw="" batt_pct="" batt_min=""
        batt_end="" batt_start="" batt_health="" batt_cycles="" batt_dc=""
        for supply in /sys/class/power_supply/*; do
          rd "$supply/type"
          [ "$val" = Battery ] || continue
          # The Logitech mouse is a power supply too, and says so with scope=Device.
          rd "$supply/scope"
          [ "$val" = Device ] && continue
          rd "$supply/status"
          batt_state=$val
          rd "$supply/capacity"
          uint "$val" && batt_pct=$val
          rd "$supply/power_now"
          uint "$val" && batt_mw=$((val / 1000))
          rd "$supply/energy_now"
          if uint "$val" && [ -n "$batt_mw" ] && [ "$batt_mw" -gt 0 ]; then
            # Microwatt-hours over milliwatts, in minutes.
            batt_min=$((val * 60 / 1000 / batt_mw))
          fi
          # The charge limit: without it, "not charging" at 80% on AC reads like a fault.
          rd "$supply/charge_control_end_threshold"
          uint "$val" && batt_end=$val
          rd "$supply/charge_control_start_threshold"
          uint "$val" && batt_start=$val
          # Wear, as what a full charge holds now against what it held new. Energy where the
          # driver has it, charge where it does not; the ratio is the same either way.
          rd "$supply/energy_full"
          full=$val
          rd "$supply/energy_full_design"
          design=$val
          if ! uint "$full" || ! uint "$design"; then
            rd "$supply/charge_full"
            full=$val
            rd "$supply/charge_full_design"
            design=$val
          fi
          uint "$full" && uint "$design" && [ "$design" -gt 0 ] &&
            batt_health=$(((full * 200 / design + 1) / 2))
          rd "$supply/cycle_count"
          uint "$val" && batt_cycles=$val
          # Tenths of a degree.
          rd "$supply/temp"
          uint "$val" && batt_dc=$val
          break
        done

        ac_online="" ac_limit_mw=""
        for supply in /sys/class/power_supply/*; do
          rd "$supply/type"
          [ "$val" = Mains ] || continue
          rd "$supply/online"
          [ "$val" = 1 ] || continue
          ac_online=1
          # What the adapter negotiated, which is the most the machine may draw from it.
          rd "$supply/input_power_limit"
          uint "$val" && ac_limit_mw=$((val / 1000))
          break
        done

        ex=(
          "$((now / 1000000))"
          "''${fan_rpm[*]-}"
          "$heat_mw"
          "$temps_line"
          "$batt_state"
          "$batt_mw"
          "$batt_pct"
          "$batt_min"
          "$batt_end"
          "$batt_start"
          "$batt_health"
          "$batt_cycles"
          "$batt_dc"
          "$ac_online"
          "$ac_mw"
          "$ac_mv"
          "$ac_limit_mw"
        )
        printf '%s\n' "''${ex[@]}" > "$extras"
      fi

      ### RENDER ###

      # The active profile, off the same interface the deck's key reads: net.hadess.PowerProfiles,
      # which power-profiles-daemon and tuned-ppd both serve, so neither end
      # has to know which daemon is behind it. GetAll rather than the one property, for the same
      # single busctl: it also carries PerformanceDegraded and the holds apps have placed. Trims
      # rather than jq take the reply apart -- this runs every two seconds, and the busctl is
      # already the one fork it cannot do without.
      profile="" degraded="" holders=""
      reply=$(busctl --json=short call net.hadess.PowerProfiles /net/hadess/PowerProfiles \
        org.freedesktop.DBus.Properties GetAll s net.hadess.PowerProfiles 2>/dev/null) || reply=""
      key='"ActiveProfile":{"type":"s","data":"'
      if [[ $reply == *"$key"* ]]; then
        rest=''${reply#*"$key"}
        profile=''${rest%%'"'*}
      fi
      key='"PerformanceDegraded":{"type":"s","data":"'
      if [[ $reply == *"$key"* ]]; then
        rest=''${reply#*"$key"}
        degraded=''${rest%%'"'*}
      fi
      key='"ApplicationId":{"type":"s","data":"'
      rest=$reply
      while [[ $rest == *"$key"* ]]; do
        rest=''${rest#*"$key"}
        holders+="''${holders:+, }''${rest%%'"'*}"
      done

      case "$profile" in
      power-saver) glyph=󰾆 name="Power saver" colour=$c_saver ;;
      balanced) glyph=󰾅 name="Balanced" colour=$c_balanced ;;
      performance) glyph=󰓅 name="Performance" colour=$c_perf ;;
      *)
        # No daemon on the bus, or a profile none of the three names matches. The graphs are still
        # worth drawing -- they come from sysfs, not from the daemon -- so the pill greys out and
        # says what is missing instead of going blank.
        glyph=󰾉 name="No power profile daemon" colour=$c_none profile=unknown
        ;;
      esac

      # Scale a series into the block glyphs. A zero draws the shortest bar rather than a gap, so
      # an idle stretch reads as a flat line along the bottom instead of a hole in the graph.
      spark=""
      sparkline() {
        local max=$1 v i pad
        shift
        spark=""
        # Until the window has filled -- the first two minutes after a boot, and again after any
        # tick that had to start it over -- there are fewer than `width` samples to draw. Blanking
        # the ones that are missing is what makes the graph scroll rather than grow: the newest
        # sample sits at the right edge from the very first tick, so the reading beside it holds
        # its column instead of being pushed right once every two seconds. A space is the same
        # advance as a block glyph in a monospaced font, and printf's `*` width pads without a
        # fork -- the same reason the rows are built with printf -v rather than echoed.
        pad=$((width - $#))
        [ "$pad" -gt 0 ] && printf -v spark '%*s' "$pad" ""
        [ "$max" -gt 0 ] || max=1
        for v in "$@"; do
          i=$((v * 8 / max))
          [ "$i" -gt 7 ] && i=7
          [ "$i" -lt 0 ] && i=0
          spark+=''${bars[$i]}
        done
      }

      # bash has no floats, and printf cannot round one it never had: fixed point by hand, to the
      # one decimal most readings on this tooltip are quoted at. Clock ceilings get two, since
      # 1.97 and 2.40 GHz are the numbers the profiles are set by.
      dec=""
      tenths() {
        dec=$((($1 * 10 + $2 / 2) / $2))
        dec="''${dec%?}.''${dec: -1}"
        [ "''${dec:0:1}" = . ] && dec="0$dec"
        return 0
      }
      hundredths() {
        dec=$((($1 * 100 + $2 / 2) / $2))
        [ "''${#dec}" -lt 3 ] && printf -v dec '%03d' "$dec"
        dec="''${dec%??}.''${dec: -2}"
        return 0
      }

      # One row of the tooltip, appended in place. A function that echoed instead would be a
      # subshell per row, and the point of the reading loops above is that a tick costs one fork.
      # The label column is eight wide, so every graph starts on the same column.
      tip=""
      row() { # label, graph colour, graph, reading, trailing dim note
        local line=""
        printf -v line "<span foreground='%s'>%-8s</span>" "$c_dim" "$1"
        # A readout row has no graph, and an empty span in its place is markup for nothing.
        [ -n "$3" ] && printf -v line "%s<span foreground='%s'>%s</span>" "$line" "$2" "$3"
        printf -v line "%s  <span foreground='%s'>%s</span>" "$line" "$c_text" "$4"
        [ -n "''${5-}" ] && printf -v line "%s<span foreground='%s'>   %s</span>" "$line" "$c_dim" "$5"
        tip+="$line"'\n'
        return 0
      }

      tip="<span foreground='$colour'>$glyph  $name</span>"
      # The tuned profile behind the level, on the Mac; power-profiles-daemon has no such file.
      rd /etc/tuned/active_profile
      [ -n "$val" ] && tip+="<span foreground='$c_dim'>  ·  tuned $val</span>"
      # An app holding a profile (powerprofilesctl launch, a game launcher) pins it until it lets go.
      [ -n "$holders" ] && tip+="<span foreground='$c_dim'>  ·  held by $holders</span>"
      # The daemon's own word that performance is being throttled, e.g. lap-detected on a laptop.
      [ -n "$degraded" ] && tip+="\n<span foreground='$c_warn'>degraded: $degraded</span>"

      # What the level is doing, read back from the kernel rather than restated from the config,
      # so it is true whichever daemon set it. These are the settings that differ between the
      # Mac's three levels (2026-10-04); boost, laptop_mode and audio power-save read the same
      # under all of them or do not exist here, so they are left out.
      doing=()
      [ -n "$p_gov" ] && doing+=("$p_gov governor")
      caps=""
      if [ "$p_cap" -gt 0 ] && [ "$p_cap" -lt "$p_max" ]; then
        hundredths "$p_cap" 1000000
        if [ "$e_max" -gt 0 ]; then caps="P-cores"; else caps="clocks"; fi
        caps+=" capped at $dec GHz"
      fi
      if [ "$e_cap" -gt 0 ] && [ "$e_cap" -lt "$e_max" ]; then
        hundredths "$e_cap" 1000000
        caps+="''${caps:+, }E-cores capped at $dec GHz"
      fi
      doing+=("''${caps:-clocks uncapped}")
      # How long dirty pages may sit before the flusher writes them; longer means the disk wakes
      # less often, at the risk of losing more on a crash.
      rd /proc/sys/vm/dirty_writeback_centisecs
      if uint "$val" && [ "$val" -gt 0 ]; then
        tenths "$val" 100
        doing+=("disk writeback every ''${dec%.0} s")
      fi
      # The hard-lockup detector's periodic perf interrupt, which powersave turns off.
      rd /proc/sys/kernel/nmi_watchdog
      case "$val" in
      0) doing+=("lockup watchdog off") ;;
      1) doing+=("lockup watchdog on") ;;
      esac
      # Two to a line, under the name.
      for ((i = 0; i < ''${#doing[@]}; i += 2)); do
        tip+="\n<span foreground='$c_dim'>''${doing[i]}''${doing[i + 1]:+  ·  ''${doing[i + 1]}}</span>"
      done
      tip+='\n\n'

      sparkline 100 "''${cpus[@]}"
      row "CPU" "$c_load" "$spark" "$cpu%"

      # Both frequency rows are scaled to their own cluster's floor and ceiling rather than to a
      # shared axis. What a frequency graph is asked is "how much of what this core can do is it
      # doing", and on this Mac the E-cores' ceiling is barely above the P-cores' idle.
      # The axis stays the hardware's floor and ceiling even under a profile's cap, so a capped
      # cluster shows as a graph that never reaches the top -- and the note says where it stops.
      freqrow() { # label, colour, floor, ceiling, cap, current, series...
        local label=$1 colour=$2 lo=$3 hi=$4 cap=$5 cur=$6 span f note=""
        local scaled=()
        shift 6
        span=$((hi - lo))
        [ "$span" -gt 0 ] || span=1
        for f in "$@"; do scaled+=("$(((f - lo) * 100 / span))"); done
        sparkline 100 "''${scaled[@]}"
        if [ "$cap" -gt 0 ] && [ "$cap" -lt "$hi" ]; then
          hundredths "$cap" 1000000
          note="capped at $dec of "
          hundredths "$hi" 1000000
          note+="$dec"
        fi
        tenths "$cur" 1000000
        row "$label" "$colour" "$spark" "$dec GHz" "$note"
      }

      if [ "$p_max" -gt 0 ]; then
        # "Freq" rather than "P-core" on a machine with only the one kind of core.
        if [ "$e_max" -gt 0 ]; then p_label=P-core; else p_label=Freq; fi
        freqrow "$p_label" "$c_pcore" "$p_min" "$p_max" "$p_cap" "$p_cur" "''${pfreqs[@]}"
      fi
      if [ "$e_max" -gt 0 ]; then
        freqrow E-core "$c_ecore" "$e_min" "$e_max" "$e_cap" "$e_cur" "''${efreqs[@]}"
      fi

      if [ "$power_mw" -ge 0 ]; then
        peak_mw=0
        drawn=()
        for mw in "''${watts[@]}"; do
          # A -1 is a tick that had no power source; it plots as the floor rather than breaking the
          # run of the graph.
          if [ "$mw" -lt 0 ]; then mw=0; fi
          drawn+=("$mw")
          [ "$mw" -gt "$peak_mw" ] && peak_mw=$mw
        done
        # A 10 W floor under the scale: an idle machine's draw wanders by a few hundred milliwatts,
        # and a graph scaled to its own noise reads as though something is happening.
        scale=$peak_mw
        [ "$scale" -lt 10000 ] && scale=10000
        sparkline "$scale" "''${drawn[@]}"
        tenths "$power_mw" 1000
        reading="$dec W"
        tenths "$peak_mw" 1000
        row "Power" "$c_watt" "$spark" "$reading" "peak $dec W"
      fi

      # The readouts, from the cached block. Each is drawn only if this machine has the sensor.
      fans=''${ex[1]-} heat_mw=''${ex[2]-} temps_line=''${ex[3]-}
      batt_state=''${ex[4]-} batt_mw=''${ex[5]-} batt_pct=''${ex[6]-} batt_min=''${ex[7]-}
      batt_end=''${ex[8]-} batt_start=''${ex[9]-} batt_health=''${ex[10]-}
      batt_cycles=''${ex[11]-} batt_dc=''${ex[12]-}
      ac_online=''${ex[13]-} ac_mw=''${ex[14]-} ac_mv=''${ex[15]-} ac_limit_mw=''${ex[16]-}

      # Readout pieces are joined with the same dot the header uses.
      acc=""
      add() {
        [ -n "$acc" ] && acc+="  ·  "
        acc+=$1
        return 0
      }

      tip+='\n'

      if [ -n "$batt_state" ]; then
        acc="''${batt_pct:-?}%"
        limited=""
        uint "$batt_end" && [ "$batt_end" -lt 100 ] && limited=1
        case "$batt_state" in
        Discharging)
          if uint "$batt_mw"; then
            tenths "$batt_mw" 1000
            add "$dec W out"
          fi
          if uint "$batt_min" && [ "$batt_min" -gt 0 ]; then
            add "$((batt_min / 60))h $((batt_min % 60))m left"
          fi
          ;;
        Charging)
          piece="charging"
          if uint "$batt_mw" && [ "$batt_mw" -gt 0 ]; then
            tenths "$batt_mw" 1000
            piece+=" at $dec W"
          fi
          [ -n "$limited" ] && piece+=" to $batt_end%"
          add "$piece"
          ;;
        "Not charging")
          # On AC with a charge limit, this is the limit doing its job rather than a fault.
          if [ -n "$limited" ]; then
            piece="held at the $batt_end% limit"
            uint "$batt_start" && piece+=", recharges below $batt_start%"
            add "$piece"
          else
            add "not charging"
          fi
          ;;
        *) add "''${batt_state,,}" ;;
        esac
        row Battery "$c_text" "" "$acc"

        acc=""
        uint "$batt_health" && add "$batt_health% of design capacity"
        uint "$batt_cycles" && add "$batt_cycles cycles"
        if uint "$batt_dc"; then
          tenths "$batt_dc" 10
          add "$dec°C"
        fi
        [ -n "$acc" ] && row Health "$c_text" "" "$acc"
      fi

      if [ -n "$ac_online" ]; then
        acc=""
        if uint "$ac_mw"; then
          tenths "$ac_mw" 1000
          add "$dec W in"
        fi
        if uint "$ac_mv"; then
          tenths "$ac_mv" 1000
          add "$dec V"
        fi
        uint "$ac_limit_mw" && [ "$ac_limit_mw" -gt 0 ] && add "$((ac_limit_mw / 1000)) W adapter"
        [ -n "$acc" ] || acc="plugged in"
        row AC "$c_text" "" "$acc"
      fi

      if [ -n "$fans" ]; then
        case "$fans" in
        *[1-9]*) row Fans "$c_text" "" "''${fans// / \/ } rpm" ;;
        *) row Fans "$c_text" "" "off" ;;
        esac
      fi

      # The SoC's share of the system figure above, as the SMC splits it out.
      if uint "$heat_mw"; then
        tenths "$heat_mw" 1000
        row Heatpipe "$c_text" "" "$dec W"
      fi

      # Three sensors to a line, the label only on the first.
      if [ -n "$temps_line" ]; then
        IFS=';' read -r -a temps <<<"$temps_line"
        acc="" n=0 label=Temps
        for t in "''${temps[@]}"; do
          [ -n "$t" ] || continue
          add "''${t%%|*}°C ''${t#*|}"
          n=$((n + 1))
          if [ $((n % 3)) -eq 0 ]; then
            row "$label" "$c_text" "" "$acc"
            acc="" label=""
          fi
        done
        [ -n "$acc" ] && row "$label" "$c_text" "" "$acc"
      fi

      tip+="\n<span foreground='$c_dim'>last $((width * period / 60)) min  ·  click to cycle</span>"

      # waybar reads one JSON object per run of the exec. The tooltip is pango markup -- single
      # quotes on the attributes, because a double one would end the JSON string -- the class is
      # what style.css colours the pill by, and the \n are JSON escapes rather than real newlines:
      # %s passes them through, and waybar's parser turns them into line breaks.
      printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$glyph" "$tip" "$profile"
    '';
  };

  # The bar's clock and calendar, replacing waybar's built-in clock module, whose calendar
  # colours could only be literals in config.jsonc -- and waybar re-reads its config only on
  # a full reload, the one that was crashing it (see lattice-palette). These draw from the
  # run-time theme instead.
  #
  # `markup [offset]` is one month as Pango markup, the month `offset` away from this one:
  # a title, the weekday row and the grid, every line padded to the same 20 columns so a
  # centred box keeps the columns straight. Today is in the accent. Sunday first, as the
  # en_US locale and the old module had it.
  #
  # With no argument it is the calendar menu behind a click on the clock: the month as the
  # menu's message and three buttons under it, previous, today and next, each a rofi row
  # laid out as columns. A button reopens the menu on the new month -- rofi has no way to
  # rewrite its message in place -- and keeps that button selected, so paging is repeated
  # clicks on one spot. Anchored north, under the clock, for the reason lattice-wifi gives.
  calendar = pkgs.writeShellApplication {
    name = "lattice-calendar";
    runtimeInputs = [
      pkgs.coreutils
      rofiWithCalc
    ];
    text = ''
      ${readColours}

      month() {
        local offset=$1 first title start days today="" pad line d cell col
        first=$(date -d "$(date +%Y-%m-01) $offset month" +%F)
        title=$(date -d "$first" '+%B %Y')
        start=$(date -d "$first" +%w)
        days=$(date -d "$first +1 month -1 day" +%-d)
        if ((offset == 0)); then
          today=$(date +%-d)
        fi

        pad=$(((20 - ''${#title}) / 2))
        printf '%*s<span foreground="%s"><b>%s</b></span>%*s\n' "$pad" "" "''${c[text]}" "$title" \
          $((20 - pad - ''${#title})) ""
        printf '<span foreground="%s">Su Mo Tu We Th Fr Sa</span>\n' "''${c[subtext0]}"

        printf -v line '%*s' $((start * 3)) ""
        col=$start
        for ((d = 1; d <= days; d++)); do
          printf -v cell '%2d' "$d"
          if [[ $d == "$today" ]]; then
            line+="<span foreground=\"''${c[accent]}\"><b><u>$cell</u></b></span>"
          else
            line+="<span foreground=\"''${c[subtext1]}\">$cell</span>"
          fi
          col=$((col + 1))
          if ((col == 7)); then
            printf '%s\n' "$line"
            line="" col=0
          else
            line+=" "
          fi
        done
        if ((col > 0)); then
          printf '%s%*s\n' "$line" $(((7 - col) * 3 - 1)) ""
        fi
      }

      if [[ ''${1:-} == markup ]]; then
        month "''${2:-0}"
        exit 0
      fi

      theme='
        window { location: north; anchor: north; y-offset: 5px; width: 250px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { enabled: false; }
        message { padding: 8px 10px 4px; border: 0; }
        textbox { horizontal-align: 0.5; }
        listview { columns: 3; lines: 1; padding: 4px 6px 6px; }
        element { padding: 5px 0; }
        element-text { horizontal-align: 0.5; }
      '
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      offset=0
      selected=1
      while true; do
        choice=$(printf '%s\n' "󰅁" "Today" "󰅂" |
          rofi -dmenu -no-custom -format i -p Calendar -markup \
            -mesg "<tt>$(month "$offset")</tt>" -selected-row "$selected" \
            -theme-str "$theme" "''${click[@]}" || true)
        case "$choice" in
        0) offset=$((offset - 1)) ;;
        1) offset=0 ;;
        2) offset=$((offset + 1)) ;;
        *) exit 0 ;;
        esac
        selected=$choice
      done
    '';
  };

  # The clock pill: the time, and this month's calendar as its tooltip. A long-running exec
  # rather than an interval, so the minute turns over on the minute: it sleeps to the next
  # one, and a USR1 -- from lattice-palette when the theme changes -- cuts the sleep short
  # and redraws at once. Its pid is kept in XDG_RUNTIME_DIR for that.
  clock = pkgs.writeShellApplication {
    name = "lattice-clock";
    runtimeInputs = [
      pkgs.coreutils
      calendar
    ];
    text = ''
      pidfile="''${XDG_RUNTIME_DIR:-/tmp}/lattice-clock.pid"
      echo $$ >"$pidfile"
      trap ':' USR1

      while true; do
        # As one JSON string: newlines escaped, and the markup's double-quoted attributes
        # turned single so they do not end it.
        tip=$(lattice-calendar markup 0)
        tip=''${tip//$'\n'/\\n}
        tip=''${tip//\"/\'}
        printf '{"text": "%s", "tooltip": "<tt>%s</tt>"}\n' "$(date '+%a %b %d  %H:%M')" "$tip"

        sleep $((60 - 10#$(date +%S))) &
        sleeper=$!
        wait "$sleeper" || true
        kill "$sleeper" 2>/dev/null || true
      done
    '';
  };

  # The caps-lock pill, which is only on the bar while caps lock is: the Mac's keyboard has
  # an LED for it and the NuPhy does not. Read from the keyboards' LED nodes in sysfs, which
  # are world-readable, rather than waybar's keyboard-state module -- that one opens
  # /dev/input itself and so wants the input group, which is every keystroke on the seat
  # handed to anything running as this user. Hyprland drives every keyboard's LED from the
  # one shared lock state, so any of them being lit is the answer.
  #
  # sysfs attributes do not raise inotify events, so it polls; five reads of a few bytes a
  # second is nothing, and it only prints when the state flips. The glob is expanded on
  # every pass so a keyboard plugged in later is picked up. Empty text hides the pill.
  #
  # The wait between passes is a `read -t` on a pipe nothing ever writes to, not `sleep`:
  # the same pause without forking a process five times a second, on each bar, all day.
  capsLock = pkgs.writeShellApplication {
    name = "lattice-capslock";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec {tick}<> <(:)
      last=
      while true; do
        state=off
        for led in /sys/class/leds/*::capslock/brightness; do
          [[ -r $led ]] || continue
          read -r v <"$led" || continue
          if [[ $v != 0 ]]; then
            state=on
            break
          fi
        done

        if [[ $state != "$last" ]]; then
          if [[ $state == on ]]; then
            # The glyph alone: the yellow border already says it, and on the Mac's bar the
            # word was what pushed a full left group into the clock.
            printf '{"text": "󰘲", "class": "on", "tooltip": "Caps lock is on"}\n'
          else
            printf '{"text": ""}\n'
          fi
          last=$state
        fi
        read -rt 0.2 -u "$tick" _ || true
      done
    '';
  };

  # The battery pill, replacing waybar's built-in battery module. That module never reads
  # the kernel's `capacity` attribute: it works the percentage out itself from
  # energy_now / energy_full. On the Mac those disagree -- macsmc-battery's capacity is the
  # SMC's own state of charge, the number macOS shows, and it read 80% while the energy
  # ratio read 77% (47.2 / 61.4 Wh) -- and neither `bat` nor `weighted-average` changes
  # which one the module uses. upower reports `capacity`, and so do fastfetch, the
  # power-profile tooltip, lattice-battery-notify's ladder and the 80% charge cap, so the
  # bar was the one reading out of step with everything else.
  #
  # The battery is picked by role the way lattice-battery-notify picks it, so the mouse
  # and headphones are skipped. `upower --monitor` prints a line whenever any device
  # changes, which is the redraw trigger; the read timeout is a backstop for the minutes
  # where upower publishes nothing. Empty text hides the pill on a host with no battery.
  batteryPill = pkgs.writeShellApplication {
    name = "lattice-battery-pill";
    runtimeInputs = [
      pkgs.upower
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      device=""
      for candidate in $(upower -e | grep /battery_); do
        if upower -i "$candidate" | grep 'power supply: *yes' >/dev/null; then
          device=$candidate
          break
        fi
      done
      if [[ -z $device ]]; then
        printf '{"text": ""}\n'
        exec sleep infinity
      fi

      # The same ten glyphs, empty to full, that the built-in module's format-icons held.
      icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)

      render() {
        local info state level time icon class tooltip
        info=$(upower -i "$device")
        state=$(awk '/^ *state:/ { print $2; exit }' <<<"$info")
        level=$(awk '/^ *percentage:/ { gsub(/%/, "", $2); print int($2 + 0.5); exit }' <<<"$info")
        [[ -n $level ]] || return 0

        case $state in
        charging)
          icon=󰂄
          class='"charging"'
          time=$(awk -F'time to full: *' 'NF > 1 { print $2; exit }' <<<"$info")
          tooltip="Charging''${time:+, $time to full}"
          ;;
        discharging)
          icon=''${icons[level * 9 / 100]}
          class='"discharging"'
          time=$(awk -F'time to empty: *' 'NF > 1 { print $2; exit }' <<<"$info")
          tooltip="On battery''${time:+, $time left}"
          ;;
        fully-charged)
          icon=󰚥
          class='"plugged"'
          tooltip="Fully charged"
          ;;
        *)
          # pending-charge: on the charger but held, which on the Mac is the charge cap.
          icon=󰚥
          class='"plugged"'
          tooltip="Plugged in, not charging"
          ;;
        esac

        # The thresholds the built-in module's `states` had; the stylesheet only colours
        # them while not charging.
        if ((level <= 10)); then
          class+=', "critical"'
        elif ((level <= 25)); then
          class+=', "warning"'
        fi

        printf '{"text": "%s %s%%", "tooltip": "%s", "class": [%s]}\n' \
          "$icon" "$level" "$tooltip" "$class"
      }

      coproc MONITOR { upower --monitor; }
      # Its first line is a "Monitoring activity" banner, not a change.
      read -r -t 5 -u "''${MONITOR[0]:-}" _ || true
      while true; do
        render
        # A timeout is a status over 128. Anything else means upower --monitor has gone
        # away, and without the sleep the loop would spin.
        read -r -t 60 -u "''${MONITOR[0]:-}" _ || { (($? > 128)) || sleep 60; }
      done
    '';
  };

  # The Obsidian vault's git state, as one pill: what is uncommitted, what is committed but
  # not pushed, and what is on GitHub but not here. Only that one repo -- it is the one
  # edited all day outside a terminal, so it is the one that drifts unnoticed.
  #
  # The local half is `git status`, run on waybar's interval. GIT_OPTIONAL_LOCKS=0 stops it
  # refreshing the index on the way, which takes index.lock and would make a commit typed
  # at the same moment fail. The remote half needs a fetch, which is a round trip to
  # GitHub through Bitwarden's SSH agent, so `status` never waits on it: once the last
  # attempt is five minutes old it starts `fetch` detached, and that signals the bar when
  # it lands. BatchMode keeps a locked agent from turning into a prompt -- the fetch just
  # fails, and the tooltip says how long ago the remote was last seen.
  #
  vault = pkgs.writeShellApplication {
    name = "lattice-vault";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.jq
      pkgs.coreutils
      pkgs.util-linux
      pkgs.procps
      pkgs.gnused
      pkgs.systemd
      config.programs.uwsm.package
    ];
    text = ''
      repo=$HOME/Documents/vault
      state=''${XDG_RUNTIME_DIR:-/tmp}/lattice
      attempted=$state/vault-fetch-attempted
      fetched=$state/vault-fetched
      failure=$state/vault-fetch-error
      every=300

      ago() {
        local s=$1
        if ((s < 60)); then
          echo "just now"
        elif ((s < 3600)); then
          echo "$((s / 60))m ago"
        elif ((s < 86400)); then
          echo "$((s / 3600))h ago"
        else
          echo "$((s / 86400))d ago"
        fi
      }

      fetch() {
        mkdir -p "$state"
        exec 9>"$state/vault-fetch.lock"
        flock -n 9 || return 0
        touch "$attempted"
        if out=$(GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
          timeout 60 git -C "$repo" fetch --quiet --prune 2>&1); then
          touch "$fetched"
          rm -f "$failure"
        else
          printf '%s\n' "''${out:-timed out}" | tail -n 1 >"$failure"
        fi
        pkill -RTMIN+${toString signal.vault} waybar || true
      }

      status() {
        if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
          printf '{"text": ""}\n'
          return
        fi

        local now age
        now=$(date +%s)
        age=$((now - $(stat -c %Y "$attempted" 2>/dev/null || echo 0)))
        if ((age >= every)); then
          setsid -f "$0" fetch >/dev/null 2>&1 </dev/null
        fi

        local branch="" upstream="" ahead=0 behind=0 changed=0 untracked=0 conflicts=0
        local -a files=()
        while IFS= read -r line; do
          case $line in
          "# branch.head "*) branch=''${line#\# branch.head } ;;
          "# branch.upstream "*) upstream=''${line#\# branch.upstream } ;;
          "# branch.ab "*)
            read -r _ _ a b <<<"$line"
            ahead=''${a#+}
            behind=''${b#-}
            ;;
          "? "*)
            untracked=$((untracked + 1))
            files+=("?  ''${line#? }")
            ;;
          "u "*)
            conflicts=$((conflicts + 1))
            files+=("!  ''${line#* * * * * * * * * * }")
            ;;
          [12]" "*)
            changed=$((changed + 1))
            local xy=''${line:2:2}
            local path=''${line#* * * * * * * * }
            [[ $line == 2* ]] && path=''${line#* * * * * * * * * }
            files+=("''${xy//./ } ''${path%%$'\t'*}")
            ;;
          esac
        done < <(GIT_OPTIONAL_LOCKS=0 git -C "$repo" status --porcelain=v2 --branch)

        local gitdir operation=""
        gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)
        if [[ -d $gitdir/rebase-merge || -d $gitdir/rebase-apply ]]; then
          operation="rebase"
        elif [[ -f $gitdir/MERGE_HEAD ]]; then
          operation="merge"
        fi

        local dirty=$((changed + untracked + conflicts))
        local text="󰊢" class tip
        ((dirty > 0)) && text+=" $dirty"
        ((ahead > 0)) && text+=" ↑$ahead"
        ((behind > 0)) && text+=" ↓$behind"

        if ((conflicts > 0)) || [[ -n $operation ]]; then
          class=conflict
        elif ((ahead > 0 && behind > 0)); then
          class=diverged
        elif ((dirty > 0)); then
          class=dirty
        elif ((ahead > 0)); then
          class=ahead
        elif ((behind > 0)); then
          class=behind
        else
          class=clean
        fi

        tip="Vault: $branch"
        [[ -n $upstream ]] && tip+=" → $upstream"
        [[ -n $operation ]] && tip+=$'\n'"A $operation is in progress"
        if ((dirty == 0)); then
          tip+=$'\n'"Nothing uncommitted"
        else
          tip+=$'\n'"$dirty uncommitted"
          ((changed > 0)) && tip+=", $changed changed"
          ((untracked > 0)) && tip+=", $untracked new"
          ((conflicts > 0)) && tip+=", $conflicts conflicted"
        fi
        if [[ -z $upstream ]]; then
          tip+=$'\n'"No upstream branch"
        elif ((ahead == 0 && behind == 0)); then
          tip+=$'\n'"In step with $upstream"
        else
          ((ahead > 0)) && tip+=$'\n'"$ahead commit$( ((ahead == 1)) || echo s) not pushed"
          ((behind > 0)) && tip+=$'\n'"$behind commit$( ((behind == 1)) || echo s) on $upstream not pulled"
        fi

        # How fresh the remote half is. Stale means the last good fetch is more than three
        # attempts old, so the arrows can no longer be trusted to be complete.
        local seen
        seen=$(stat -c %Y "$fetched" 2>/dev/null || echo 0)
        if ((seen == 0)); then
          tip+=$'\n'"Remote not checked yet"
        else
          tip+=$'\n'"Remote checked $(ago $((now - seen)))"
        fi
        if [[ -s $failure ]]; then
          tip+=$'\n'"Last fetch failed: $(<"$failure")"
        fi
        if ((now - seen > 3 * every + 60)); then
          class+=" stale"
        fi

        if ((''${#files[@]} > 0)); then
          tip+=$'\n'
          local f
          for f in "''${files[@]:0:12}"; do
            tip+=$'\n'"$f"
          done
          ((''${#files[@]} > 12)) && tip+=$'\n'"… and $((''${#files[@]} - 12)) more"
        fi
        tip+=$'\n\n'"Click to fetch now, right-click for lazygit"

        jq -nc --arg text "$text" --arg tip "$tip" --arg class "$class" \
          '{text: $text, tooltip: $tip, class: ($class | split(" "))}'
      }

      case ''${1:-status} in
      status) status ;;
      fetch) fetch ;;
      # Waybar's PATH is only the store paths in waybar.path below, and uwsm app hands the
      # caller's environment on: a bare terminal failed with a critical "Command not found"
      # notification, and lazygit inside it -- and git and nvim inside that -- would not be
      # found either. So the terminal gets the session's PATH, the one uwsm exported to the
      # user manager at login.
      open)
        PATH=$(systemctl --user show-environment | sed -n 's/^PATH=//p')
        export PATH
        exec uwsm app -- foot --working-directory="$repo" lazygit
        ;;
      *)
        echo "usage: lattice-vault [status|fetch|open]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [
    tailscale
    powerProfile
  ];

  systemd.user.services = {
    # systemd user services get a bare default PATH -- coreutils, findutils, grep, sed,
    # systemd -- and notably *not* /run/current-system/sw/bin. Waybar runs its module
    # commands through `sh -c` with that environment, so anything they call has to be
    # named here or it fails with "command not found" and the module silently renders
    # empty. Keep this in step with the exec and on-click commands of the pills below and
    # in waybar.nix.
    #
    # Each desktop module appends the scripts it owns (theming.nix the wallpaper and theme
    # pills, menus.nix the menus, and so on); what is here is the bar's own share.
    #
    # That reaches one step further than the commands themselves. The lattice scripts are
    # writeShellApplications, so each prepends its own runtimeInputs and finds its own
    # tools regardless of this list -- but a tool that in turn execs something by *name*
    # is back to this PATH. xdg-open is the one that does: it resolves
    # x-scheme-handler/https to firefox.desktop from the assignment in apps.nix and then
    # runs `firefox`, so without the browser here lattice-tailscale's sign-in click and
    # its right-click to the admin console both resolved a URL and then opened nothing.
    # xdg-open does say so -- it walks its whole fallback list of browser names, reports
    # "no method available", and exits 3 -- but both call it with output on /dev/null
    # (they must: it is detached), so the complaint went nowhere and the pill just sat
    # there.
    waybar.path = [
      tailscale
      weather
      # Both ends of the power-profile pill: waybar runs `status` on the interval and
      # `cycle` on a click, and the script's own runtimeInputs cover everything it calls
      # except lattice-deck, which streamdeck.nix puts on this same PATH.
      powerProfile
      # The clock, and the calendar menu a click on it opens.
      clock
      calendar
      # The caps-lock pill's exec.
      capsLock
      # The battery pill's.
      batteryPill
      # The vault pill's status, its click-to-fetch and its right-click into lazygit.
      vault
      pkgs.wireplumber
      config.programs.firefox.finalPackage
    ];
  };

  lattice.bar.modules = {
    # Caps lock, for the keyboards without an LED for it. Only on the bar while it is on --
    # lattice-capslock prints empty text otherwise.
    "custom/capslock" = {
      section = "left";
      order = 20;
      settings = {
        exec = "lattice-capslock";
        return-type = "json";
        tooltip = true;
      };
    };

    # The clock, from lattice-clock rather than waybar's built-in module: that one's
    # calendar colours could only be literals in the config, which is only re-read on a
    # full reload. lattice-clock draws the hover calendar from the run-time theme and
    # redraws it when the theme changes. A click opens lattice-calendar, the month with
    # previous / today / next buttons under it.
    "custom/clock" = {
      section = "center";
      order = 10;
      settings = {
        exec = "lattice-clock";
        return-type = "json";
        tooltip = true;
        on-click = "lattice-calendar";
      };
    };

    # Weather, from Open-Meteo via lattice-weather, for the place in lattice.weather -- and
    # only with one: no coordinates, no pill. The exec emits the glyph, both temperatures
    # and a class per temperature band; nothing here spells the conditions out, because the
    # glyph and the colour in style.css already carry them.
    #
    # First on the right, so it is still the pill the clock is read next to: "what time is
    # it" and "what is it doing outside" get answered in the same glance. Kept to the glyph
    # and the temperature, with the feels-like reading in the tooltip.
    #
    # interval 900 is the API's own cadence, not a guess: Open-Meteo stamps its `current`
    # block "interval":900, so a faster poll returns the same numbers. A click doesn't have
    # to wait it out -- `lattice-weather refresh` signals the bar and waybar re-runs the exec.
    "custom/weather" = lib.mkIf (config.lattice.weather.latitude != null) {
      section = "right";
      order = 10;
      settings = {
        exec = "lattice-weather status";
        return-type = "json";
        signal = signal.weather;
        interval = 900;
        on-click = "lattice-weather refresh";
      };
    };

    # The Obsidian vault's git state: uncommitted files as a count, then ↑ for commits not
    # pushed and ↓ for commits on GitHub not pulled, coloured by the worst of them. A
    # readout rather than a toggle, so it sits after them. The script checks GitHub on its
    # own every five minutes and signals the bar when it has; the interval only re-reads the
    # working tree. Click fetches now, right-click opens lazygit in the vault. Empty, and so
    # hidden, where there is no vault.
    "custom/vault" = {
      section = "group/toggles";
      order = 60;
      settings = {
        exec = "lattice-vault status";
        return-type = "json";
        signal = signal.vault;
        interval = 10;
        on-click = "lattice-vault fetch";
        on-click-right = "lattice-vault open";
      };
    };

    # Tailscale has no Linux GUI, so the pill is the interface: hover for the connection
    # report, click to bring the tunnel up or down, right-click for the admin console. The
    # glyph and colour are chosen by lattice-tailscale per state, so nothing here spells the
    # state out -- the script emits `text` and the class style.css keys off. It signals the
    # bar itself after a toggle, so the interval is only a safety net for changes made from
    # a shell. Icon-only, and just right of network. Only on a host that runs Tailscale.
    "custom/tailscale" = lib.mkIf config.services.tailscale.enable {
      section = "group/links";
      order = 20;
      settings = {
        exec = "lattice-tailscale status";
        return-type = "json";
        signal = signal.tailscale;
        interval = 30;
        on-click = "lattice-tailscale toggle";
        on-click-right = "lattice-tailscale web";
      };
    };

    # The power profile, and -- on hover -- what the machine is doing with it: four
    # sparklines over the last two minutes (load, each core cluster's clock, and the
    # package's own draw in watts), then the fans, the hottest sensor that names itself and
    # the battery. lattice-power-profile, above, emits the lot as one JSON object.
    #
    # Waybar's own power-profiles-daemon module was here and drew the same three glyphs. It
    # could not grow this tooltip: its tooltip-format takes exactly one placeholder,
    # {profile}, and nothing that reaches sysfs.
    #
    # Icon-only, as that one was: the three glyphs are distinct enough to read at a glance,
    # and dropping the labels frees ~42px of bar. The profile's name is still one hover
    # away, at the head of the graphs.
    #
    # The interval is the graph's sample rate rather than a refresh rate. The script keeps
    # a 60-sample window in XDG_RUNTIME_DIR and each tick is one column of it, so a hover
    # shows the two minutes that have already happened instead of starting a graph when the
    # pointer arrives -- which is also why the sampling cannot be made lazy.
    #
    # The signal is what makes a click land at once; the click itself cycles through
    # lattice-deck, so a deck's profile key and this pill cannot disagree.
    "custom/power-profile" = {
      section = "group/energy";
      order = 10;
      settings = {
        exec = "lattice-power-profile status";
        return-type = "json";
        signal = signal.powerProfile;
        interval = powerProfileInterval;
        on-click = "lattice-power-profile cycle";
      };
    };

    # The battery, from lattice-battery-pill rather than waybar's built-in module: that one
    # works the percentage out from energy_now / energy_full and never reads the kernel's
    # capacity, so on the Mac it read 77% while upower, fastfetch and the power-profile
    # tooltip all read 80%. The script sets the charging / plugged / warning / critical
    # classes the stylesheet colours.
    "custom/battery" = {
      section = "group/energy";
      order = 20;
      settings = {
        exec = "lattice-battery-pill";
        return-type = "json";
        tooltip = true;
      };
    };
  };

  lattice.cli.commands = {
    tailscale = {
      exec = lib.getExe tailscale;
      args = "[status|toggle|web]";
      summary = "Tailscale: bring it up or down, or open the admin console";
      group = "session";
      launch = [
        {
          label = "Tailscale: toggle";
          args = "toggle";
          icon = "network-vpn";
        }
        {
          label = "Tailscale admin console";
          args = "web";
          icon = "network-vpn";
        }
      ];
    };
    weather = {
      exec = lib.getExe weather;
      args = "[status|refresh]";
      summary = "The bar's weather; refresh drops the cache";
      group = "session";
    };
    "power profile" = {
      exec = lib.getExe powerProfile;
      args = "[status|cycle]";
      summary = "Cycle the power profile; status is the bar's JSON";
      group = "session";
      launch = [
        {
          label = "Next power profile";
          args = "cycle";
          icon = "preferences-system-power";
        }
      ];
    };
    calendar = {
      exec = lib.getExe calendar;
      summary = "A month calendar in a menu";
      group = "session";
      launch = [
        {
          label = "Calendar";
          icon = "office-calendar";
        }
      ];
    };
    "bar clock" = {
      exec = lib.getExe clock;
      summary = "The clock pill's output";
      group = "session";
      hidden = true;
    };
    "bar capslock" = {
      exec = lib.getExe capsLock;
      summary = "The caps-lock pill's output";
      group = "session";
      hidden = true;
    };
    "bar battery" = {
      exec = lib.getExe batteryPill;
      summary = "The battery pill's output";
      group = "session";
      hidden = true;
    };
    vault = {
      exec = lib.getExe vault;
      args = "[status|fetch|open]";
      summary = "The Obsidian vault's git state; fetch checks GitHub, open starts lazygit";
      group = "session";
      launch = [
        {
          label = "Obsidian vault in lazygit";
          args = "open";
          icon = "obsidian";
        }
      ];
    };
  };
}
