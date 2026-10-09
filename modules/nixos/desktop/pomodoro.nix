{
  config,
  lib,
  pkgs,
  ...
}:
# A pomodoro timer as one more segment of the bar's toggles: 25 minutes of work, then a
# 5-minute break, a 15-minute one after every fourth. Work runs straight into its break;
# a break ends by waiting for a click, so the next pomodoro starts when you sit back down
# rather than while you are still away.
#
# The countdown is the pill, redrawn every second by waybar. The phase change is a
# transient systemd timer on the wall clock, so it still fires on time -- or at once on
# resume -- after a suspend, which a monotonic timer would have slept through.
let
  # SIGRTMIN+11, the signal the bar pill below listens for (waybar.nix checks that no two pills share one).
  barSignal = 11;

  inherit (import ./lib.nix { inherit config lib pkgs; }) rofiWithCalc;

  pomodoro = pkgs.writeShellApplication {
    name = "lattice-pomodoro";
    runtimeInputs = [
      rofiWithCalc
      pkgs.coreutils
      pkgs.libnotify
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      work=$((25 * 60)) short=$((5 * 60)) long=$((15 * 60)) every=4

      # One line, "phase status value count": phase is work, short or long; status is
      # running (value = the epoch it ends), paused (value = seconds left) or ready (a
      # break is over and the next work waits for a click); count is the work phases
      # finished. No file means no timer.
      dir=''${XDG_RUNTIME_DIR:-/tmp}/lattice-pomodoro
      state=$dir/state
      timer=lattice-pomodoro-next

      signal() { pkill -RTMIN+${toString barSignal} waybar || true; }
      now() { printf '%(%s)T' -1; }

      load() {
        phase="" status="" value=0 count=0
        [[ -r $state ]] && read -r phase status value count <"$state"
        return 0
      }
      save() {
        mkdir -p "$dir"
        printf '%s %s %s %s\n' "$phase" "$status" "$value" "$count" >"$state"
      }

      unschedule() { systemctl --user stop "$timer.timer" 2>/dev/null || true; }

      # Run `next` when the current phase ends, by the wall clock.
      schedule() {
        unschedule
        systemctl --user reset-failed "$timer.service" "$timer.timer" 2>/dev/null || true
        systemd-run --user --quiet --collect --unit="$timer" \
          --on-calendar="$(date -d "@$1" '+%F %T')" --timer-property=AccuracySec=1s \
          "$0" next
      }

      start() {
        phase=$1 status=running value=$(($(now) + $2))
        save
        schedule "$value"
      }

      length() {
        case $1 in
        work) echo "$work" ;;
        short) echo "$short" ;;
        long) echo "$long" ;;
        esac
      }

      toggle() {
        load
        case $status in
        "" | ready) start work "$work" ;;
        running)
          unschedule
          status=paused value=$((value - $(now)))
          ((value > 0)) || value=0
          save
          ;;
        paused) start "$phase" "$value" ;;
        esac
        signal
      }

      # The phase is over, by the timer or by a right-click skipping it.
      next() {
        load
        [[ -n $status ]] || exit 0
        unschedule
        if [[ $phase == work ]]; then
          count=$((count + 1))
          if ((count % every == 0)); then
            start long "$long"
            notify-send -a Pomodoro -i alarm-clock "Long break" "$count done. $((long / 60)) minutes."
          else
            start short "$short"
            notify-send -a Pomodoro -i alarm-clock "Break" "$((short / 60)) minutes."
          fi
        else
          phase=work status=ready value=0
          save
          notify-send -a Pomodoro -i alarm-clock "Break's over" "Click the timer to start the next one."
        fi
        signal
      }

      stop() {
        unschedule
        rm -f "$state"
        signal
      }

      # Behind a right-click, since the Mac's trackpad has no middle click: start, pause or
      # resume, skip the phase, stop. Hung north west like the radio's menu.
      menu() {
        load
        local msg choice left
        local -a rows=() acts=()
        case $status in
        "") msg="Off" ;;
        ready) msg="Break over" ;;
        *)
          if [[ $status == running ]]; then left=$((value - $(now))); else left=$value; fi
          ((left > 0)) || left=0
          if [[ $phase == work ]]; then msg="Work"; else msg="Break"; fi
          msg+=", $((left / 60)):$(printf '%02d' $((left % 60))) left"
          [[ $status == paused ]] && msg+=" (paused)"
          ;;
        esac
        msg+=" · $count done"

        case $status in
        "" | ready) rows+=("󰐊  Start") ;;
        running) rows+=("󰏤  Pause") ;;
        paused) rows+=("󰐊  Resume") ;;
        esac
        acts+=(toggle)
        if [[ $status == running || $status == paused ]]; then
          if [[ $phase == work ]]; then rows+=("󰒭  Skip to the break"); else rows+=("󰒭  Skip the break"); fi
          acts+=(next)
        fi
        if [[ -n $status ]]; then rows+=("󰓛  Stop"); acts+=(stop); fi

        choice=$(printf '%s\n' "''${rows[@]}" |
          rofi -dmenu -i -no-custom -format i -p pomodoro -mesg "$msg" \
            -l "''${#rows[@]}" \
            -theme-str 'window { location: north west; anchor: north west; x-offset: 10px; y-offset: 5px; width: 320px; } inputbar { enabled: false; }' \
            -me-select-entry "" -me-accept-entry MousePrimary || true)
        [[ -n $choice ]] || exit 0
        "''${acts[$choice]}"
      }

      bar() {
        load
        local left icon class tip
        case $status in
        "")
          printf '{"text":"󰔛","tooltip":"Pomodoro: click to start","class":"idle"}\n'
          return
          ;;
        ready)
          printf '{"text":"󰔛","tooltip":"Break over (%d done): click to start","class":"ready"}\n' "$count"
          return
          ;;
        running) left=$((value - $(now))) ;;
        paused) left=$value ;;
        esac
        ((left > 0)) || left=0
        case $phase in
        work) icon=󰔟 class='"work"' tip="Work" ;;
        *) icon=󰅶 class='"break"' tip="Break" ;;
        esac
        [[ $status == paused ]] && icon=󰏤 class+=',"paused"' tip="$tip, paused"
        printf '{"text":"%s %d:%02d","tooltip":"%s · %d done\\nclick: pause/resume · right: menu","class":[%s]}\n' \
          "$icon" $((left / 60)) $((left % 60)) "$tip" "$count" "$class"
      }

      case ''${1-} in
      toggle) toggle ;;
      next) next ;;
      stop) stop ;;
      menu) menu ;;
      bar) bar ;;
      status)
        load
        echo "''${status:-off}''${phase:+ $phase}"
        ;;
      *)
        echo "usage: lattice-pomodoro [toggle|next|stop|menu|status]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  # Last in the toggles so the countdown growing and shrinking the segment moves nothing
  # else. A timer icon when off; click starts or pauses, right-click is a menu with skip and
  # stop -- the Mac's trackpad has no middle click. Ticks every second for the countdown,
  # and signals the bar on every change.
  lattice.bar.modules."custom/pomodoro" = {
    section = "group/toggles";
    order = 100;
    settings = {
      exec = "lattice-pomodoro bar";
      return-type = "json";
      signal = barSignal;
      interval = 1;
      on-click = "lattice-pomodoro toggle";
      on-click-right = "lattice-pomodoro menu";
    };
  };

  environment.systemPackages = [ pomodoro ];

  # The pill's exec and its clicks; see the PATH note on waybar.path in bar.nix.
  systemd.user.services.waybar.path = [ pomodoro ];

  lattice.cli.commands.pomodoro = {
    exec = lib.getExe pomodoro;
    args = "[toggle|next|stop|menu|status]";
    summary = "Pomodoro: start or pause, skip the phase, stop";
    group = "session";
  };
}
