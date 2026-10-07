{
  config,
  lib,
  pkgs,
  ...
}:
# The desktop end of ../backup.nix: the bar pill's menu and the daily reminder. The pill's
# JSON is `lattice-backup bar`, from there, since `lattice backup status` and the doctor
# read the same state.
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) rofiWithCalc;
  inherit (config.lattice.backup.internal)
    cli
    mountPoint
    browseDir
    ;

  # Behind a right-click on the pill. The status is the message at the top; the rows are
  # what can be done from here, so they change with what is going on.
  menu = pkgs.writeShellApplication {
    name = "lattice-backup-menu";
    runtimeInputs = [
      rofiWithCalc
      cli
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gnused
      pkgs.systemd
      config.programs.uwsm.package
    ];
    text = ''
      # North west, under the left group, as the wallpaper and theme menus hang; see
      # lattice-wallpaper-menu in theming.nix for the offsets.
      theme='
        window { location: north west; anchor: north west; x-offset: 10px; y-offset: 5px; width: 440px; }
        * { font: "JetBrains Mono 10"; }
        inputbar { enabled: false; }
        element { padding: 5px 10px; }
        textbox { padding: 7px 10px; }
      '
      # One click accepts, as on every other bar surface; see lattice-wifi.
      click=(-me-select-entry "" -me-accept-entry MousePrimary)

      # The file manager needs the session's PATH rather than waybar's; see lattice-vault.
      open() {
        PATH=$(systemctl --user show-environment | sed -n 's/^PATH=//p')
        export PATH
        exec uwsm app -- xdg-open "$1"
      }

      mesg=$(lattice-backup status | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' || true)

      rows=() actions=()
      if mountpoint -q ${mountPoint}; then
        if systemctl -q is-active 'lattice-backup@*.service'; then
          rows+=("󰓛  Stop the backup") actions+=(stop)
        else
          rows+=("󰁯  Back up now") actions+=(now)
        fi
        if mountpoint -q ${browseDir}; then
          rows+=("󰉋  Open the backups" "󰅖  Stop browsing") actions+=(open unbrowse)
        else
          rows+=("󰉋  Browse the backups") actions+=(browse)
        fi
        rows+=("󰄬  Check every backup" "󰕓  Eject the drive") actions+=(check eject)
      fi

      choice=$(printf '%s\n' "''${rows[@]}" |
        rofi -dmenu -i -no-custom -format i -p Backups -mesg "$mesg" \
          -l "''${#rows[@]}" -theme-str "$theme" "''${click[@]}" || true)
      [[ -n ''${choice:-} ]] || exit 0

      case ''${actions[$choice]} in
      browse) open "$(lattice-backup browse)" ;;
      open) open "${browseDir}/hosts/$(hostname)" ;;
      *) lattice-backup "''${actions[$choice]}" ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ menu ];

  # The pill's exec and both its clicks; see the PATH note on waybar.path in bar.nix.
  systemd.user.services.waybar.path = [
    cli
    menu
  ];

  # The reminder for a drive that has stayed away a week: the pill turns too, but a pill
  # is easy not to look at. Ten minutes into a login and then daily, rather than at a fixed
  # time the laptop might well be asleep through. Quiet while the drive is in.
  systemd.user.services.lattice-backup-nag = {
    description = "Remind about a backup drive that has been away too long";
    wants = [ "mako.service" ];
    after = [ "mako.service" ];
    onFailure = [ "lattice-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe cli} nag";
    };
  };
  systemd.user.timers.lattice-backup-nag = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "10min";
      OnUnitActiveSec = "1d";
    };
  };

  lattice.cli.commands."backup menu" = {
    exec = lib.getExe menu;
    summary = "The backup pill's menu";
    group = "system";
    hidden = true;
  };
}
