{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) rofiWithCalc;

  # The `>` list's own rows: every `launch` row a lattice command declares, next to the
  # command (cli.nix), in route order so a family like `restart` stays together. Tab
  # separated, and no field is ever empty -- tab is IFS whitespace to `read`, so an empty
  # field would collapse and shift the rest along.
  actions = pkgs.writeText "lattice-launch-actions.tsv" (
    lib.concatStrings (
      lib.concatLists (
        lib.mapAttrsToList (
          route: c:
          map (
            row:
            lib.concatStringsSep "\t" [
              row.label
              row.icon
              route
              (if row.terminal then "1" else "0")
              (c.exec + lib.optionalString (row.args != "") " ${row.args}")
            ]
            + "\n"
          ) c.launch
        ) config.lattice.cli.commands
      )
    )
  );

  # What `?` asks for. The answer lands in a rofi message box: pango text, no scrolling,
  # about 560px wide, so markdown would show as literal asterisks and fences.
  askPrompt = ''
    You are answering a question typed into the app launcher on the user's own Linux
    desktop (NixOS, Hyprland). Your answer is shown in a small popup that renders plain
    text only. No markdown: no headings, bold, bullets with asterisks, tables or code
    fences. Answer first, no preamble, in at most about twelve short lines. Put a shell
    command on a line of its own so it can be copied. If the question needs current
    information, search the web.
  '';

  # Home Assistant and Tailscale are optional modules; their rows only appear where they are.
  ha = config.lattice.cli.commands.ha.exec or "";
  radio = config.lattice.cli.commands.radio.exec;
  tailnet = config.services.tailscale;

  # The tab bar: rofi's own mode-switcher widget, one button per mode, the current one
  # drawn like a selected row. It sits under the search field rather than at the bottom,
  # because the window is as tall as its list -- ask, chat and web have none -- and a bar
  # at the bottom jumped up and down as you stepped through the modes. Only the launcher has it -- the other rofi
  # menus have one mode and no use for it -- so it comes in on the command line rather
  # than in config.rasi.
  tabBar = ''
    mainbox { children: [ inputbar, mode-switcher, message, listview ]; }
    mode-switcher { spacing: 6px; }
    button {
      padding: 6px 0px;
      border-radius: 8px;
      text-color: @subtext0;
      cursor: pointer;
    }
    button selected {
      background-color: @surface0;
      text-color: @accent;
    }
  '';

  # The launcher on ALT + SPACE: apps, as `drun` always showed them, and these instead:
  #
  #   > / <    the next or previous mode: apps, actions, radio, ask, chat, web (the tab bar)
  #   ? text   a short answer from Claude, in rofi
  #   ?? text  a conversation with Claude, in a foot window
  #   @ text   a DuckDuckGo search; its !bangs work too (`@!w nixos`)
  #
  # `>` and `<` are rofi's mode switch (kb-mode-next/-previous), so the actions list
  # filters as you type like the apps do; ask, chat and web are modes too, for anyone who
  # would rather tab to them. The prefixes take free text, and rofi 2.0 has no hook on the
  # text as it is typed, so they are routed on Enter: in combi mode a query that matches no row is
  # "handled by the first combined mode" (rofi(1), COMBI), and the first one here is this
  # script, which lists no rows of its own and so adds nothing to the apps. It hands the
  # query to a copy of itself that outlives the launcher -- rofi runs one instance at a
  # time (the lock on $XDG_RUNTIME_DIR/rofi.pid), so the next menu can only open once this
  # one has closed. The script's parent is not rofi (rofi double-forks it), hence the pid
  # file rather than $PPID. Neither `?` nor `@` appears in a desktop entry's searchable
  # fields glued to a word, so `?how` never matches an app and steals the Enter.
  #
  # The actions list, in order: lattice's own (each command's `launch` rows, cli.nix), the
  # open windows, Home Assistant's lights, switches and scenes, the tailnet's devices (not
  # Mullvad's exit nodes), and every running or failed systemd service, user then system.
  # Each row is filtered on its plain text and drawn from `display`, so the grey suffix
  # (route, window class, entity id, unit scope) is searchable without being in the way.
  launch = pkgs.writeShellApplication {
    name = "lattice-launch";
    runtimeInputs = [
      rofiWithCalc
      pkgs.claude-code
      pkgs.coreutils
      pkgs.foot
      pkgs.gnused
      pkgs.hyprland
      pkgs.jq
      pkgs.libnotify
      pkgs.systemd
      pkgs.util-linux
      pkgs.wl-clipboard
      pkgs.xdg-utils
    ]
    ++ lib.optional tailnet.enable tailnet.package;
    text = ''
      # Where `?` and `??` run claude. Its sessions are kept per directory, so a quick
      # answer can be picked up again as a conversation from here, and no project's
      # CLAUDE.md comes along.
      state=''${XDG_STATE_HOME:-$HOME/.local/state}/lattice/ask

      # Pango-escape $1 into REPLY, without a fork: the actions list does this a few hundred
      # times, and a sed apiece made it take a second to come up. The replacements are
      # quoted so patsub_replacement doesn't read their & as the match.
      esc() {
        REPLY=''${1//&/"&amp;"}
        REPLY=''${REPLY//</"&lt;"}
        REPLY=''${REPLY//>/"&gt;"}
      }
      pango() {
        esc "$1"
        printf '%s' "$REPLY"
      }

      # Wait out the launcher, at most two seconds, so the next rofi can take the lock.
      after() {
        [[ -n $1 ]] || return 0
        for _ in $(seq 100); do
          kill -0 "$1" 2>/dev/null || return 0
          sleep 0.02
        done
      }

      # Hand $@ to a copy of this script that waits for the launcher to close.
      detach() {
        local pid
        pid=$(cat "$XDG_RUNTIME_DIR/rofi.pid" 2>/dev/null || true)
        setsid -f "$0" "$@" "$pid" >/dev/null 2>&1 </dev/null
      }

      # Run a command where a failure says so instead of vanishing with nobody watching --
      # `backup now` with the drive out, say. $1 names it in the banner.
      quiet() {
        local label=$1 err
        shift
        err=$(mktemp)
        if ! "$@" >/dev/null 2>"$err"; then
          notify-send -a lattice-launch -i dialog-error "$label failed" "$(tail -n 3 "$err")"
        fi
        rm -f "$err"
      }

      terminal() { exec uwsm app -- foot --app-id lattice-launch "$@"; }

      # A conversation is Opus; one carried on from a quick answer is Sonnet, a step up from
      # the Haiku that answered it.
      chat() {
        local model=$1
        shift
        mkdir -p "$state"
        exec uwsm app -- foot --app-id lattice-ask --working-directory="$state" \
          claude --model "$model" "$@"
      }

      ask() {
        local q=$1 claude wait answer sid pick
        [[ -n $q ]] || chat opus
        mkdir -p "$state"
        # Not local: the trap runs at exit, after this function's locals are gone.
        out=$(mktemp -d)
        trap 'rm -rf "$out"' EXIT

        # exec, so the pid is claude's own and Esc can stop it.
        (cd "$state" && exec claude -p --model haiku --output-format json \
          --tools WebSearch,WebFetch --allowedTools WebSearch,WebFetch --strict-mcp-config \
          --append-system-prompt ${lib.escapeShellArg askPrompt} \
          -- "$q" >"$out/json" 2>"$out/err") &
        claude=$!

        # Something to look at while it thinks, and Esc to give up. rofi -dmenu quits
        # straight away on an empty list, hence the one row nothing can select.
        printf 'Thinking…\0nonselectable\x1ftrue\n' \
          | rofi -dmenu -p ask -no-custom -mesg "<b>$(pango "$q")</b>" &
        wait=$!
        wait -n "$claude" "$wait" || true
        if ! kill -0 "$wait" 2>/dev/null; then
          kill "$claude" 2>/dev/null || true
          exit 0
        fi
        kill "$wait" 2>/dev/null || true
        wait "$wait" 2>/dev/null || true

        answer=$(jq -r 'select(.is_error | not) | .result // empty' "$out/json" 2>/dev/null || true)
        sid=$(jq -r '.session_id // empty' "$out/json" 2>/dev/null || true)
        if [[ -z $answer ]]; then
          answer="No answer: $(jq -r '.result // empty' "$out/json" 2>/dev/null || true)$(tail -n 3 "$out/err")"
        fi

        # The message box doesn't scroll, so a long answer is cut where the terminal
        # can carry on with it.
        local shown
        shown=$(head -n 24 <<<"$answer")
        [[ $shown == "$answer" ]] || shown+=$'\n…'
        pick=$(printf 'Copy the answer\0icon\x1fedit-copy\nContinue in a terminal\0icon\x1futilities-terminal\n' \
          | rofi -dmenu -i -no-custom -format i -p ask \
            -theme-str 'window { width: 720px; }' \
            -mesg "<b>$(pango "$q")</b>"$'\n\n'"$(pango "$shown")") || exit 0
        case $pick in
        0) printf '%s' "$answer" | wl-copy ;;
        1)
          # chat execs, so the trap never gets its turn.
          rm -rf "$out"
          if [[ -n $sid ]]; then chat sonnet --resume "$sid"; else chat sonnet "$q"; fi
          ;;
        esac
      }

      web() {
        local url=https://duckduckgo.com/
        [[ -z $1 ]] || url+="?q=$(jq -rn --arg q "$1" '$q | @uri')"
        exec uwsm app -- xdg-open "$url"
      }

      # Home Assistant's entities and the tailnet's devices, as of the last launch. Asking
      # for them took about a hundred milliseconds -- Tailscale's status is most of a
      # megabyte with the exit nodes in it -- and rofi sets up every mode before it draws
      # anything, so the launcher came up that much later than plain drun did. They
      # hardly change, so the list reads what the previous launch fetched and fetches
      # again behind it: a new device or entity shows from the launch after. Only the
      # very first launch of a session waits for them. A fetch that fails (the house
      # unreachable) leaves the last good copy in place.
      cache=''${XDG_RUNTIME_DIR:-/tmp}/lattice-launch
      refresh() {
        mkdir -p "$cache"
        ${lib.optionalString (ha != "") ''
          if timeout 2 ${ha} entities >"$cache/ha.$$" 2>/dev/null && [[ -s $cache/ha.$$ ]]; then
            mv -f "$cache/ha.$$" "$cache/ha"
          fi &
        ''}
        ${lib.optionalString tailnet.enable ''
          # With Mullvad on, all but a handful of the peers are its exit nodes, which
          # ExitNodeOption marks.
          if tailscale status --json 2>/dev/null | jq -r '
            .Peer // {} | .[] | select(.ExitNodeOption | not)
            | [(.DNSName | split(".")[0]), .HostName, .OS, .Online, .TailscaleIPs[0]] | @tsv
          ' >"$cache/tailscale.$$"; then
            mv -f "$cache/tailscale.$$" "$cache/tailscale"
          fi &
        ''}
        wait
        rm -f "$cache"/*."$$"
      }

      # One row of the actions list: filter text, label, grey suffix, icon, info for `run`,
      # and any further row options. info is tab separated with no empty field, since tab
      # is IFS whitespace to `read` and an empty field would shift the rest.
      row() {
        local label
        esc "$2"
        label=$REPLY
        esc "$3"
        printf '%s\0display\x1f%s  <span alpha="55%%">%s</span>\x1ficon\x1f%s\x1finfo\x1f%s%s\n' \
          "$1" "$label" "$REPLY" "$4" "$5" "''${6-}"
      }
      tab=$'\t'

      list() {
        printf '\0prompt\x1factions\n\0markup-rows\x1ftrue\n\0no-custom\x1ftrue\n'
        # The live sources, all started at once rather than one after another.
        local windows units_user units_system
        exec {windows}< <(hyprctl clients -j | jq -r '
          map(select(.mapped and .workspace.id > 0))
          | sort_by(if .focusHistoryID == 0 then 1e9 else .focusHistoryID end)[]
          | [(.class | ascii_downcase), (.title | gsub("\t"; " ")), .address] | @tsv')
        exec {units_user}< <(systemctl --user list-units --type=service --state=active,failed \
          --no-legend --plain)
        exec {units_system}< <(systemctl --system list-units --type=service \
          --state=active,failed --no-legend --plain)

        if [[ -d $cache ]]; then
          setsid -f "$0" refresh >/dev/null 2>&1 </dev/null
        else
          refresh
        fi

        local label icon route term cmd
        while IFS=$'\t' read -r label icon route term cmd; do
          row "$label $route" "$label" "$route" "$icon" "cmd$tab$term$tab$cmd$tab$label"
        done <${actions}

        # The windows, the one in use last. Special workspaces (the Bitwarden scratchpad)
        # have negative ids.
        local class title address
        while IFS=$'\t' read -r class title address; do
          row "$title $class window" "$title" "$class" "$class" "window$tab$address"
        done <&"$windows"

      ${lib.optionalString (ha != "") ''
        local entity name text verb
        while IFS=$'\t' read -r entity name; do
          case $entity in
          light.* | switch.* | fan.*) verb=toggle text="Toggle $name" icon=brightness ;;
          scene.* | script.*) verb=activate text="Scene: $name" icon=media-playback-start ;;
          *) continue ;;
          esac
          row "$text $entity home assistant" "$text" "$entity" "$icon" "ha$tab$verb$tab$entity$tab$text"
        done < <(cat "$cache/ha" 2>/dev/null || true)
      ''}
      ${lib.optionalString tailnet.enable ''
        # The tailnet's own devices.
        local dns host os online ip seen
        while IFS=$'\t' read -r dns host os online ip; do
          case $os in
          iOS | android) icon=smartphone ;;
          macOS | windows) icon=laptop ;;
          *) icon=network-server ;;
          esac
          if [[ $online == true && $os != iOS && $os != android ]]; then
            row "SSH to $host $dns tailscale" "SSH to $host" tailscale "$icon" "ssh$tab$dns"
          fi
          seen=$ip
          [[ $online == true ]] || seen+=" · offline"
          row "Copy $host's address $dns $ip tailscale" "Copy $host's address" "$seen" edit-copy \
            "copy$tab$ip$tab$host"
        done < <(cat "$cache/tailscale" 2>/dev/null || true)
      ''}
        # Services that are running or failed; a failed one is drawn urgent.
        local scope unit active desc urgent fd
        for scope in user system; do
          fd=$units_user
          [[ $scope == system ]] && fd=$units_system
          while read -r unit _ active _ desc; do
            urgent=""
            [[ $active == failed ]] && urgent=$'\x1furgent\x1ftrue'
            row "$unit $desc $scope systemd $active" "$unit" "$scope · $desc" applications-system \
              "unit$tab$scope$tab$unit" "$urgent"
          done <&"$fd"
        done
      }

      # A service picked from the list: what to do with it.
      unit() {
        local scope=$1 name=$2 state pick
        local -a journal=()
        [[ $scope == user ]] && journal=(--user)
        state=$(systemctl "--$scope" is-active "$name" || true)
        local -a verbs=(restart) labels=(Restart) icons=(view-refresh)
        if [[ $state == active ]]; then
          verbs+=(stop) labels+=(Stop) icons+=(media-playback-stop)
        else
          verbs+=(start) labels+=(Start) icons+=(media-playback-start)
        fi
        verbs+=(log status) labels+=("Follow its log" "Status")
        icons+=(utilities-terminal dialog-information)
        pick=$(for i in "''${!labels[@]}"; do
          printf '%s\0icon\x1f%s\n' "''${labels[i]}" "''${icons[i]}"
        done | rofi -dmenu -i -no-custom -format i -p "$name" -mesg "$(pango "$scope service, $state")") || exit 0
        case ''${verbs[pick]} in
        log) terminal journalctl "''${journal[@]}" -u "$name" -n 200 -f ;;
        status) terminal --hold systemctl "--$scope" status --no-pager -n 40 "$name" ;;
        # A system service goes through polkit, which asks for the password itself.
        *) quiet "''${labels[pick]} $name" systemctl "--$scope" "''${verbs[pick]}" "$name" ;;
        esac
      }

      run() {
        local -a f arg
        IFS=$'\t' read -ra f <<<"$1"
        case ''${f[0]} in
        cmd)
          read -ra arg <<<"''${f[2]}"
          if [[ ''${f[1]} == 1 ]]; then terminal --hold "''${arg[@]}"; fi
          quiet "''${f[3]}" "''${arg[@]}"
          ;;
        window) hyprctl dispatch "hl.dsp.focus({ window = \"address:''${f[1]}\" })" >/dev/null ;;
        ${lib.optionalString (ha != "") ''ha) quiet "''${f[3]}" ${ha} "''${f[1]}" "''${f[2]}" ;;''}
        ssh) terminal ssh "''${f[1]}" ;;
        copy)
          printf '%s' "''${f[1]}" | wl-copy
          notify-send -a lattice-launch -i edit-copy "Copied ''${f[2]}'s address" "''${f[1]}"
          ;;
        unit) unit "''${f[1]}" "''${f[2]}" ;;
        esac
      }

      # The launcher's modes, in the order the tab bar shows them and `>` / `<` step through
      # them. ask, chat and web list nothing: they are a prompt for Enter to send. radio is
      # SomaFM's channels, from lattice-radio (radio.nix).
      launcher() {
        exec rofi -show "$1" \
          -modi "combi,actions:$0 actions,radio:${radio} rofi,ask:$0 mode ask,chat:$0 mode chat,web:$0 mode web" \
          -combi-modes "lattice:$0 route,drun" -combi-hide-mode-prefix -display-combi apps \
          -kb-mode-next "greater,Shift+Right,Control+Tab" \
          -kb-mode-previous "less,Shift+Left,Control+ISO_Left_Tab" \
          -theme-str ${lib.escapeShellArg tabBar}
      }

      case ''${1-} in
      "") launcher combi ;;
      radio) launcher radio ;;
      actions)
        # rofi's script mode for the actions list (ROFI_RETV 0 lists it, 1 is a pick). Run
        # by hand, it opens the launcher on that list.
        case ''${ROFI_RETV-} in
        "") launcher actions ;;
        0) list ;;
        1) detach run "''${ROFI_INFO-}" ;;
        esac
        ;;
      mode)
        # ask, chat and web as modes: a prompt and a line saying what Enter does (0), then
        # the text (2). Enter on nothing still does something -- a blank chat, DuckDuckGo's
        # front page -- the same as `??` or `@` alone.
        case ''${ROFI_RETV-0} in
        0)
          case $2 in
          ask) hint="Ask Claude. The answer comes up right here." ;;
          chat) hint="Start a conversation with Claude in a terminal." ;;
          web) hint="Search DuckDuckGo. !bangs work: !w, !yt, !gh…" ;;
          esac
          printf '\0prompt\x1f%s\n\0message\x1f%s\n' "$2" "$hint"
          ;;
        2)
          q=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"''${3-}")
          case $2 in
          chat) detach chat-new "$q" ;;
          *) detach "$2" "$q" ;;
          esac
          ;;
        esac
        ;;
      route)
        # The free-text prefixes, in the combi's first mode: listed once with nothing to
        # say (ROFI_RETV 0), then called again with the query when nothing matched it (2).
        [[ ''${ROFI_RETV-0} == 2 ]] || exit 0
        q=''${2-}
        case $q in
        '??'*) verb=chat-new q=''${q#"??"} ;;
        '?'*) verb=ask q=''${q#"?"} ;;
        '@'*) verb=web q=''${q#"@"} ;;
        *) exit 0 ;;
        esac
        q=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$q")
        detach "$verb" "$q"
        ;;
      refresh) refresh ;;
      ask | web | chat-new | run)
        after "''${3-}"
        case $1 in
        chat-new) if [[ -n $2 ]]; then chat opus "$2"; else chat opus; fi ;;
        *) "$1" "$2" ;;
        esac
        ;;
      *)
        echo "usage: lattice-launch [actions|radio]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ launch ];
}
