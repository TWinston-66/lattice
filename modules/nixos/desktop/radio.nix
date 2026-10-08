{
  config,
  lib,
  pkgs,
  ...
}:
# SomaFM, without a web app: the channels are a tab in the launcher (lattice-launch's
# `radio` mode), the stream is mpv in a user service, and while it plays there is a bar
# pill whose click is a small player with the cover art. A banner says each new track.
#
# mpv carries mpv-mpris, so playerctl -- and with it the Stream Deck's media keys and the
# keyboard's -- reaches the radio like any other player. It is loaded into this service
# only, not into the system mpv.
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) rofiWithCalc;

  # Tells lattice-radio about each new track and each pause, so it can raise the banner
  # and redraw the pill. SomaFM sends the track as the ICY title, "Artist - Title".
  # The script's path comes in as a script-opt, since this file can't name the script
  # that names it.
  notifier = pkgs.writeText "lattice-radio.lua" ''
    local bin = mp.get_opt("lattice_radio-bin")
    local function tell(...)
      mp.command_native_async({ name = "subprocess", args = { bin, ... }, playback_only = false },
        function() end)
    end
    local last
    mp.observe_property("metadata/by-key/icy-title", "string", function(_, title)
      if title and title ~= "" and title ~= last then
        last = title
        tell("track", title)
      end
    end)
    mp.observe_property("pause", "bool", function() tell("signal") end)
  '';

  radio = pkgs.writeShellApplication {
    name = "lattice-radio";
    runtimeInputs = [
      rofiWithCalc
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.jq
      pkgs.libnotify
      pkgs.mpv
      pkgs.procps
      pkgs.socat
      pkgs.systemd
      pkgs.util-linux
      pkgs.wl-clipboard
    ];
    text = ''
      # The channel list and logos, refetched a day after the last fetch; the channels
      # played, most recent first, which is also the launcher's order and the one that
      # plays next; and the player's socket and the current track's cover.
      cache=''${XDG_CACHE_HOME:-$HOME/.cache}/lattice/radio
      recent=''${XDG_STATE_HOME:-$HOME/.local/state}/lattice/radio/recent
      run=''${XDG_RUNTIME_DIR:-/tmp}/lattice-radio
      sock=$run/mpv.sock
      unit=lattice-radio.service

      # RTMIN+10 matches the "signal" of custom/radio in ~/.dotfiles/waybar. 1 to 9 are taken.
      signal() { pkill -RTMIN+10 -x waybar || true; }

      # channels.tsv: id, title, description, genre, stream, logo URL -- most listeners
      # first. The stream is the 128k AAC playlist; every channel has one (2026-10-08).
      fetch() {
        local json
        mkdir -p "$cache/logos"
        json=$(curl -fsS --max-time 10 https://somafm.com/channels.json) || return 1
        jq -r '
          def flat: gsub("[\t\n]"; " ");
          .channels | sort_by(-(.listeners | tonumber))[]
          | [.id, (.title | flat), (.description | flat), (.genre | gsub("\\|"; ", ")),
             (((.playlists | map(select(.format == "aac" and .quality == "highest")))
               + .playlists)[0].url),
             .largeimage]
          | @tsv' <<<"$json" >"$cache/channels.tsv.$$" || { rm -f "$cache/channels.tsv.$$"; return 1; }
        mv -f "$cache/channels.tsv.$$" "$cache/channels.tsv"
        local id logo
        while IFS=$'\t' read -r id _ _ _ _ logo; do
          [[ -s $cache/logos/$id.png ]] && continue
          curl -fsS --max-time 10 -o "$cache/logos/$id.png.part" "$logo" \
            && mv -f "$cache/logos/$id.png.part" "$cache/logos/$id.png" &
        done <"$cache/channels.tsv"
        wait
        rm -f "$cache"/logos/*.part
      }

      # The list as of the last fetch, fetching behind it once it is a day old. Only the
      # very first use waits on SomaFM.
      channels() {
        if [[ ! -s $cache/channels.tsv ]]; then
          fetch || { echo "lattice-radio: could not fetch the channel list" >&2; exit 1; }
        elif [[ -n $(find "$cache/channels.tsv" -mmin +1440) ]]; then
          setsid -f "$0" fetch >/dev/null 2>&1 </dev/null
        fi
      }

      # One channel's row into the globals id title desc genre stream.
      channel() {
        IFS=$'\t' read -r id title desc genre stream _ \
          < <(awk -F'\t' -v id="$1" '$1 == id' "$cache/channels.tsv") || return 1
      }
      current() { head -n 1 "$recent" 2>/dev/null; }
      playing() { systemctl --user -q is-active "$unit"; }

      # A property from the running mpv, or nothing.
      get() {
        printf '{"command":["get_property","%s"]}\n' "$1" \
          | socat -t 1 - "UNIX-CONNECT:$sock" 2>/dev/null \
          | jq -r 'select(.error == "success") | .data' | head -n 1
      }

      esc() {
        REPLY=''${1//&/"&amp;"}
        REPLY=''${REPLY//</"&lt;"}
        REPLY=''${REPLY//>/"&gt;"}
      }

      play() {
        channels
        local want=''${1:-$(current)}
        [[ -n $want ]] || { echo "lattice-radio: nothing played yet; name a channel" >&2; exit 2; }
        channel "$want" || { echo "lattice-radio: no channel '$want' (lattice radio channels)" >&2; exit 2; }
        mkdir -p "$(dirname "$recent")"
        { printf '%s\n' "$want"; grep -vx -- "$want" "$recent" 2>/dev/null || true; } >"$recent.$$"
        mv -f "$recent.$$" "$recent"
        systemctl --user restart "$unit"
      }

      # The service's ExecStart. reconnect rides out a dropped connection; a stream that
      # is gone for good fails the unit, and Restart= has another go.
      serve() {
        channels
        channel "$(current)"
        mkdir -p "$run"
        rm -f "$run"/art*
        exec mpv --no-video --no-terminal --idle=no --audio-client-name=SomaFM \
          --input-ipc-server="$sock" \
          --stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=30 \
          --script=${pkgs.mpvScripts.mpris}/share/mpv/scripts/mpris.so \
          --script=${notifier} --script-opts=lattice_radio-bin="$0" \
          "$stream"
      }

      # A new track: find its cover, say so, redraw the pill. SomaFM's own song list has
      # an albumArt field but leaves it empty on every channel, so the cover comes from
      # the iTunes Search API, and only when both the title and the artist agree --
      # the channel's logo is better than somebody else's album.
      track() {
        local t=$1 artist="" song=$1 url f art
        channel "$(current)" || exit 0
        art=$cache/logos/$id.png
        if [[ $t == *' - '* ]]; then
          artist=''${t%% - *} song=''${t#* - }
          url=$(curl -fsS --max-time 4 -G https://itunes.apple.com/search \
            --data-urlencode "term=$artist $song" -d entity=song -d limit=5 2>/dev/null \
            | jq -r --arg a "$artist" --arg s "$song" '
              def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
              ($a | norm) as $a | ($s | norm) as $s
              | if ($a == "" or $s == "") then empty else
                  [.results[]
                   | select((.trackName | norm) as $t | ($t | startswith($s)) or ($s | startswith($t)))
                   | select(.artistName | norm | contains($a[0:8]))][0].artworkUrl100 // empty
                end' 2>/dev/null) || true
          if [[ -n $url ]]; then
            mkdir -p "$run"
            f=$run/art-$(md5sum <<<"$t" | cut -c 1-12).jpg
            if curl -fsS --max-time 5 -o "$f.part" "''${url/100x100bb/600x600bb}"; then
              mv -f "$f.part" "$f"
              art=$f
            fi
            rm -f "$f.part"
          fi
        fi
        # The menu shows whichever is newest; the rest of the old covers go.
        ln -sfn "$art" "$run/art"
        find "$run" -maxdepth 1 -name 'art-*' ! -samefile "$art" -delete 2>/dev/null || true
        notify-send -a SomaFM -i "$art" -h string:x-canonical-private-synchronous:lattice-radio \
          "$song" "''${artist:+$artist · }$title"
        signal
      }

      # The pill: hidden while nothing plays, otherwise the channel, with the track in the
      # tooltip.
      bar() {
        if ! playing || ! channel "$(current)"; then
          printf '{"text":""}\n'
          return
        fi
        local paused now
        paused=$(get pause)
        now=$(get media-title)
        [[ $now == "$stream" || $now == *.pls ]] && now=""
        jq -nc --arg c "$title" --arg n "$now" --arg d "$desc" --arg p "$paused" '{
          text: ((if $p == "true" then "󰏤" else "󰐹" end) + "  " + $c),
          tooltip: ((if $n != "" then $n + "\n" else "" end) + $c + " · " + $d),
          class: (if $p == "true" then "paused" else "playing" end)
        }'
      }

      toggle() {
        if playing; then
          printf '{"command":["cycle","pause"]}\n' | socat -t 1 - "UNIX-CONNECT:$sock" >/dev/null
        else
          play
        fi
      }

      stop() {
        systemctl --user stop "$unit"
      }

      # The launcher's radio tab, as a rofi script mode: the channels played before, most
      # recent first, then the rest by listeners. The one playing is highlighted.
      mode() {
        case ''${ROFI_RETV-0} in
        0)
          channels
          printf '\0prompt\x1fradio\n\0markup-rows\x1ftrue\n\0no-custom\x1ftrue\n'
          if playing; then printf '\0active\x1f0\n'; fi
          local id title desc genre label
          while IFS=$'\t' read -r id title desc genre _ _; do
            esc "$title"
            label=$REPLY
            esc "$desc"
            printf '%s\0display\x1f%s  <span alpha="55%%">%s</span>\x1ficon\x1f%s\x1finfo\x1f%s\n' \
              "$title $desc $genre" "$label" "$REPLY" "$cache/logos/$id.png" "$id"
          done < <(awk -F'\t' 'FILENAME == ARGV[1] { rank[$1] = FNR; next }
                               { print ($1 in rank ? rank[$1] : 1000 + FNR) "\t" $0 }' \
                     <(cat "$recent" 2>/dev/null || true) "$cache/channels.tsv" \
                   | sort -n -k 1,1 | cut -f 2-)
          ;;
        1) [[ -z ''${ROFI_INFO-} ]] || play "$ROFI_INFO" ;;
        esac
      }

      # Behind a click on the pill: the cover beside what is playing, and what can be done
      # about it. Hung north west like the backup menu; see lattice-wifi in menus.nix for
      # the offsets.
      menu() {
        playing && channel "$(current)" || exit 0
        local paused now art msg choice
        paused=$(get pause)
        now=$(get media-title)
        [[ $now == "$stream" || $now == *.pls ]] && now=""
        art=$(readlink -f "$run/art" 2>/dev/null || true)
        [[ -s $art ]] || art=$cache/logos/$id.png

        msg=""
        if [[ -n $now ]]; then
          if [[ $now == *' - '* ]]; then
            esc "''${now#* - }"
            msg+="<b>$REPLY</b>"$'\n'
            esc "''${now%% - *}"
            msg+="$REPLY"$'\n\n'
          else
            esc "$now"
            msg+="<b>$REPLY</b>"$'\n\n'
          fi
        fi
        # The channel alone: its description wraps past the cover and gets cut off, and
        # the pill's tooltip has it.
        esc "$title"
        msg+="<span alpha=\"55%\">$REPLY</span>"

        local theme='
          window { location: north west; anchor: north west; x-offset: 10px; y-offset: 5px; width: 560px; }
          * { font: "JetBrains Mono 10"; }
          mainbox { orientation: horizontal; children: [ icon-art, box-side ]; spacing: 14px; }
          icon-art { filename: "'"$art"'"; size: 164px; expand: false; vertical-align: 0; }
          box-side { orientation: vertical; children: [ message, listview ]; spacing: 8px; expand: true; }
          inputbar { enabled: false; }
          element { padding: 5px 10px; }
          textbox { padding: 7px 10px; }
        '
        local -a rows=() acts=()
        if [[ $paused == true ]]; then rows+=("󰐊  Resume"); else rows+=("󰏤  Pause"); fi
        acts+=(toggle)
        rows+=("󰐹  Change channel")
        acts+=(change)
        if [[ -n $now ]]; then rows+=("󰆏  Copy the track"); acts+=(copy); fi
        rows+=("󰓛  Stop")
        acts+=(stop)

        choice=$(printf '%s\n' "''${rows[@]}" |
          rofi -dmenu -i -no-custom -format i -p radio -markup -mesg "$msg" \
            -l "''${#rows[@]}" -theme-str "$theme" \
            -me-select-entry "" -me-accept-entry MousePrimary || true)
        [[ -n $choice ]] || exit 0
        case ''${acts[$choice]} in
        toggle) toggle ;;
        # The launcher's radio tab on its own, without the other tabs around it.
        change) exec rofi -show radio -modi "radio:$0 rofi" ;;
        copy) printf '%s' "$now" | wl-copy ;;
        stop) stop ;;
        esac
      }

      case ''${1-} in
      play) play "''${2-}" ;;
      toggle) toggle ;;
      stop) stop ;;
      menu) menu ;;
      channels)
        channels
        cut -f 1,2 "$cache/channels.tsv" | column -t -s $'\t'
        ;;
      bar) bar ;;
      rofi) mode ;;
      serve) serve ;;
      fetch) fetch ;;
      track) track "$2" ;;
      signal) signal ;;
      *)
        echo "usage: lattice-radio [play [<channel>]|toggle|stop|menu|channels]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ radio ];

  # The pill's exec and its clicks; see the PATH note on waybar.path in bar.nix.
  systemd.user.services.waybar.path = [ radio ];

  systemd.user.services.lattice-radio = {
    description = "SomaFM radio";
    after = [ "pipewire.service" ];
    onFailure = [ "lattice-notify-failure@%n.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe radio} serve";
      ExecStartPost = "-${lib.getExe radio} signal";
      ExecStopPost = "-${lib.getExe radio} signal";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  lattice.cli.commands.radio = {
    exec = lib.getExe radio;
    args = "[play [<channel>]|toggle|stop|menu|channels]";
    summary = "SomaFM: play a channel, pause, stop";
    group = "session";
  };
}
