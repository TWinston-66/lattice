{
  config,
  lib,
  pkgs,
  ...
}:
# Time Machine-style backups to an external drive. Any host backs up whenever the drive
# labelled `lattice-backup` is plugged into it: once shortly after it attaches, then hourly
# while it stays. Every host shares one restic repository on the drive, so data common to
# them is stored once and each host's tooltip can say when the others last backed up.
#
# What gets backed up is the whole machine less what is rebuilt or thrown away, so that a
# reinstall plus a restore puts it back as it was -- see "Restoring from a backup" in the
# README. Rather than a list of paths to keep, it is everything on the `sources` mount
# points with `exclude` taken out, so state nobody thought to list still comes back.
#
# The pieces:
#   - udev hides the drive from udisks, or udiskie would automount it as the user;
#   - the drive's by-label device unit pulls in the mount, the mount pulls in
#     lattice-backup-drive (the plugged/unplugged notifications), and that starts the timer;
#   - lattice-backup@auto.service is what the timer runs, @now is a click on the pill, @check
#     reads every pack back. All three are the same runner;
#   - the runner keeps its results in a world-readable state file that the pill, `lattice
#     backup status` and `lattice doctor` read, so none of them needs the password or root.
#
# Restic encrypts everything it writes with a key derived from the password, file names
# included, so the drive itself is plain btrfs: a lost or stolen drive gives up nothing
# without the password, and LUKS on top would only add an unlock step on every host. The
# password is read from lattice.backup.passwordFile, and should also live somewhere that
# survives the host, such as a password manager.
let
  # SIGRTMIN+9, the signal the bar pill below listens for (waybar.nix checks that no two pills share one).
  barSignal = 9;

  cfg = config.lattice.backup;

  label = "lattice-backup";
  mountPoint = "/mnt/lattice-backup";
  repo = "${mountPoint}/restic";
  # The device's and the mount's unit names, \x2d being systemd's escape for the dashes.
  deviceUnit = "dev-disk-by\\x2dlabel-lattice\\x2dbackup.device";
  mountUnit = "mnt-lattice\\x2dbackup.mount";
  stateFile = "/var/lib/lattice-backup/state.json";
  runDir = "/run/lattice-backup";
  browseDir = "${runDir}/browse";
  # Read-only btrfs snapshots of the sources live here for the length of a run.
  snapshotDir = "/.lattice-backup";
  cacheDir = "/var/cache/restic";
  user = config.lattice.user.name;
  host = config.networking.hostName;
  inherit (cfg) passwordFile;

  # A pill whose drive has been away this long turns to a warning, and twice as long to an
  # error. The daily reminder starts at the first.
  staleDays = 7;

  # Time Machine's ladder, more or less: every hour for a day, every day for a month, then
  # weekly and monthly, and one a year forever. At under 10 GB a host, a 1 TB drive holds
  # years of this.
  keep = [
    "--keep-hourly 24"
    "--keep-daily 30"
    "--keep-weekly 26"
    "--keep-monthly 24"
    "--keep-yearly unlimited"
  ];

  # Paths as they sit on the running system. A pattern with a * in it matches one path
  # component.
  defaultExclude = [
    # Rebuilt from the flake at the revision the manifest records.
    "/nix"
    # Recreated by the Asahi installer and nixos-install.
    "/boot"
    # Kernel and runtime file systems. They are not in a snapshot anyway, but the live
    # fallback for a source that is not btrfs would see them.
    "/dev"
    "/proc"
    "/sys"
    "/run"
    "/tmp"
    "/var/tmp"
    "/var/cache"
    "/mnt"
    snapshotDir
    # snapper's own history. restic's replaces it, and it cannot survive a reinstall anyway.
    "/home/.snapshots"
    # Containers rebuild from configs kept on GitHub. VMs (/var/lib/libvirt) are kept.
    "/var/lib/docker"
    "/var/lib/containers"
    "/var/lib/machines"
    "/var/lib/portables"
    "/home/*/.local/share/containers"
    # Flatpak runtimes and apps, which lattice-flatpaks reinstalls. Their data, in
    # ~/.var/app, is kept.
    "/var/lib/flatpak"
    "/home/*/.local/share/flatpak"
    "/var/lib/systemd/coredump"
    # Caches and the trash.
    "/root/.cache"
    "/home/*/.cache"
    "/home/*/.local/share/Trash"
    "/home/*/.cargo/registry"
    "/home/*/.cargo/git"
    "/home/*/.npm"
    "/home/*/go/pkg/mod"
  ];

  excludeFile = pkgs.writeText "lattice-backup-exclude" (
    lib.concatLines (defaultExclude ++ cfg.exclude)
  );

  # A nested subvolume shows up in a snapshot as an empty directory, so its contents would
  # silently go missing. The runner looks for those and reports any that are neither a
  # source of their own nor excluded; these are the excluded ones it can match exactly.
  skipSubvolumes = lib.filter (p: !lib.hasInfix "*" p) (defaultExclude ++ cfg.exclude);

  # Shared by the scripts below: where things are, and how to say how long ago.
  common = ''
    state=${stateFile}
    run=${runDir}

    # The state file, or an empty object before the first run.
    state_json() { cat "$state" 2>/dev/null || echo '{}'; }

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

    duration() {
      local s=$1
      if ((s < 60)); then
        echo "''${s}s"
      elif ((s < 3600)); then
        echo "$((s / 60))m $((s % 60))s"
      else
        echo "$((s / 3600))h $((s % 3600 / 60))m"
      fi
    }

    human() { numfmt --to=iec --suffix=B --format=%.1f "$1"; }

    signal() { pkill -RTMIN+${toString barSignal} waybar || true; }
  '';

  # Root's way onto the user's screen: a transient unit in the user manager, which already
  # has the session bus in its environment. With nobody logged in it fails, and the line
  # this echoes to the journal is all that is left. Every banner shares one synchronous
  # tag, so "Backing up" turns into "Backup complete" in place rather than stacking, and
  # an hourly run while docked is one banner, not two.
  rootNotify = ''
    notify() {
      local urgency=$1 icon=$2 title=$3 body=$4
      echo "$title: $body"
      systemd-run --quiet --collect --user --machine=${user}@.host \
        ${pkgs.libnotify}/bin/notify-send -a lattice-backup -u "$urgency" -i "$icon" \
        -h string:x-canonical-private-synchronous:lattice-backup "$title" "$body" \
        >/dev/null 2>&1 || true
    }
  '';

  runner = pkgs.writeShellApplication {
    name = "lattice-backup-run";
    # jq programs passed through save(), which shellcheck takes for shell.
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = [
      pkgs.restic
      pkgs.btrfs-progs
      pkgs.util-linux
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      ${common}
      ${rootNotify}

      export RESTIC_REPOSITORY=${repo}
      export RESTIC_PASSWORD_FILE=${passwordFile}
      export RESTIC_CACHE_DIR=${cacheDir}
      # restic's --json progress comes at this rate; each line rewrites the pill.
      export RESTIC_PROGRESS_FPS=0.5

      host=${lib.escapeShellArg host}
      sources=(${lib.escapeShellArgs cfg.sources})
      skip=(${lib.escapeShellArgs skipSubvolumes})

      now() { date +%s; }

      # The state file is replaced whole, so a reader never sees half of it.
      save() {
        local tmp
        tmp=$(mktemp "$state.XXXXXX")
        state_json | jq "$@" >"$tmp"
        chmod 644 "$tmp"
        mv -f "$tmp" "$state"
      }

      # What the pill shows while a run is going. Removed when the run ends.
      phase() {
        jq -nc --arg p "$1" --argjson s "$started" '{phase: $p, started: $s}' >"$run/progress.json.tmp"
        mv -f "$run/progress.json.tmp" "$run/progress.json"
        signal
      }

      # Every restic call but the backup itself goes through here, so a failure has its
      # reason to hand.
      r() { restic "$@" 2>"$run/stderr"; }

      # What is on the drive, as the state file carries it: this host's snapshot count, the
      # newest snapshot of every host, and the space used and left. Needs the password, so
      # only a run can find it out; everything else reads it back from the state file.
      drive_facts() {
        local snapshots hosts count repo_bytes free size
        snapshots=$(r snapshots --json)
        count=$(jq --arg h "$host" '[.[] | select(.hostname == $h)] | length' <<<"$snapshots")
        # The newest snapshot of every host, timed in epoch seconds for the pill's sake.
        hosts=$(jq -r 'group_by(.hostname) | map(max_by(.time)) | .[] | "\(.hostname)\t\(.time)"' <<<"$snapshots" |
          while IFS=$'\t' read -r h t; do
            jq -nc --arg h "$h" --argjson t "$(date -d "$t" +%s)" '{host: $h, time: $t}'
          done | jq -sc .)
        repo_bytes=$(du -sb ${repo} | cut -f1)
        read -r free size < <(df -B1 --output=avail,size ${mountPoint} | tail -n 1)
        save --argjson hosts "$hosts" --argjson count "$count" \
          --argjson repo "$repo_bytes" --argjson free "$free" --argjson size "$size" \
          '.snapshots = $count | .hosts = $hosts
           | .repo_bytes = $repo | .free_bytes = $free | .size_bytes = $size'
        signal
      }

      drop_snapshots() {
        local s
        for s in ${snapshotDir}/*; do
          [[ -e $s ]] && btrfs subvolume delete "$s" >/dev/null
        done
        return 0
      }

      covered() {
        local p=$1 s
        for s in "''${sources[@]}"; do
          [[ $p == "$s" ]] && return 0
        done
        for s in "''${skip[@]}"; do
          [[ $p == "$s" || $p == "$s"/* ]] && return 0
        done
        return 1
      }

      # Runs inside `unshare --mount`, so none of these mounts are seen outside it and
      # all of them go when it exits. The snapshots are mounted where they came from inside
      # a chroot, so restic records /home/<user> and not /.lattice-backup/_home/<user>,
      # and a restore lands where it should. The repo and the password come in under a
      # private tmpfs on /run.
      capture() {
        local tree=$run/tree pair mp src
        mkdir -p "$tree"
        for pair in "$@"; do
          mp=''${pair%%=*}
          src=''${pair#*=}
          mount -o bind,ro "$src" "$tree''${mp%/}"
        done
        mount -o bind,ro /nix "$tree/nix"
        mount -t tmpfs -o mode=0700 tmpfs "$tree/run"
        mkdir "$tree/run/repo" "$tree/run/secrets" "$tree/run/tmp"
        mount --bind ${mountPoint} "$tree/run/repo"
        install -m 400 "$RESTIC_PASSWORD_FILE" "$tree/run/secrets/restic"
        mount --rbind /dev "$tree/dev"
        mount -t proc proc "$tree/proc"
        mount --bind ${cacheDir} "$tree${cacheDir}"

        # errexit off for the pipeline: restic's own status is the answer, and 3 is not a
        # failure.
        set +e
        chroot "$tree" env \
          RESTIC_REPOSITORY=/run/repo/restic \
          RESTIC_PASSWORD_FILE=/run/secrets/restic \
          RESTIC_CACHE_DIR=${cacheDir} \
          RESTIC_PROGRESS_FPS="$RESTIC_PROGRESS_FPS" \
          TMPDIR=/run/tmp \
          restic backup --json --host "$host" --exclude-file=${excludeFile} --exclude-caches / \
          2>"$run/stderr" |
          while IFS= read -r line; do
            case $line in
            *'"message_type":"status"'*)
              jq -c --argjson s "$started" \
                '{phase: "backup", started: $s, percent: ((.percent_done // 0) * 100 | floor), remaining: .seconds_remaining}' \
                <<<"$line" >"$run/progress.json.tmp" &&
                mv -f "$run/progress.json.tmp" "$run/progress.json" && signal
              ;;
            *'"message_type":"summary"'*) printf '%s\n' "$line" >"$run/summary.json" ;;
            *'"message_type":"error"'*) printf '%s\n' "$line" >>"$run/errors" ;;
            esac
          done
        local rc=''${PIPESTATUS[0]}
        set -e
        return "$rc"
      }

      # Why the run died, for the banner: restic's last word if a restic call is what
      # failed, otherwise the command itself. The ERR trap below records which it was.
      reason() {
        local msg=""
        case ''${failed:-} in
        "r "* | restic* | unshare*) msg=$(tail -n 1 "$run/stderr" 2>/dev/null || true) ;;
        esac
        echo "''${msg:-''${failed:+$failed: }exited with status $1}"
      }

      fail() {
        reported=1
        save --arg e "$1" --argjson t "$(now)" '.last_run = $t | .last_result = "failed" | .last_error = $e'
        notify critical dialog-error "Backup failed" "$1"
        exit 1
      }

      # Whatever ends the run: the snapshots go, the progress file goes, and an exit nobody
      # reported yet gets reported. A stop (the drive pulled, `lattice backup stop`, an
      # eject) is not a failure -- restic leaves nothing broken and the next run picks up.
      cleanup() {
        local status=$?
        drop_snapshots || true
        rm -f "$run/progress.json"
        if ((status != 0)) && [[ -z ''${reported:-} ]]; then
          if [[ -n ''${stopping:-} ]]; then
            reported=1
            save --argjson t "$(now)" '.last_run = $t | .last_result = "interrupted"'
            # Pulled out: lattice-backup-drive says so, ordered after this. Still there:
            # stopped from the pill or the CLI, or by an eject, which says so itself after.
            if [[ -e /dev/disk/by-label/${label} ]]; then
              notify normal dialog-information "Backup stopped" "Nothing was lost; the next run carries on."
            fi
          else
            fail "$(reason "$status")"
          fi
        fi
        signal
      }

      backup() {
        if [[ $mode == auto ]]; then
          local last
          last=$(state_json | jq -r '.last_success // 0')
          if (($(now) - last < 50 * 60)); then
            echo "backed up $(ago $(($(now) - last))); skipping"
            exit 0
          fi
        fi

        started=$(now)
        export started host
        # A fresh install has the drive's repository but not its password, and restic's own
        # words for that ("Resolving password failed") don't say what to do.
        [[ -s ${passwordFile} ]] ||
          fail "No backup password on this machine. Put the drive's (it's in your password manager) in ${passwordFile}, readable by root only."
        phase starting
        notify normal document-save "Backing up" "$host to the backup drive"

        if [[ ! -e ${repo}/config ]]; then
          if [[ -n $(ls -A ${repo} 2>/dev/null) ]]; then
            fail "${repo} is not empty and is not a restic repository"
          fi
          mkdir -p ${repo}
          r init >/dev/null
        fi
        # Only locks whose process is gone: one left by a run cut off by an unplug.
        r unlock >/dev/null
        # Read the drive up front too, so the pill and the menu describe what is on it for
        # the length of the run rather than what was there when this host last finished one
        # -- which, before its first, is nothing at all, other hosts' backups included.
        drive_facts

        phase snapshot
        drop_snapshots
        mkdir -p ${snapshotDir} ${cacheDir}
        local -a binds=() uncovered=()
        local src name p
        local subvolume
        for src in "''${sources[@]}"; do
          [[ -d $src ]] || continue
          # inode 256 is the root of a btrfs subvolume, the top level included.
          subvolume=""
          [[ $(stat -f -c %T "$src") == btrfs && $(stat -c %i "$src") == 256 ]] && subvolume=1
          # A plain directory is already inside its parent's snapshot.
          [[ -n $subvolume ]] || mountpoint -q "$src" || continue
          if [[ -n $subvolume ]]; then
            name=''${src//\//_}
            btrfs subvolume snapshot -r "$src" "${snapshotDir}/$name" >/dev/null
            binds+=("$src=${snapshotDir}/$name")
            while IFS= read -r -d "" p; do
              p=''${src%/}/''${p#"${snapshotDir}/$name/"}
              covered "$p" || uncovered+=("$p")
            done < <(find "${snapshotDir}/$name" -type d -inum 2 -print0)
          else
            # Not btrfs: back up the live tree, which is what any other tool would do.
            binds+=("$src=$src")
          fi
        done

        phase backup
        rm -f "$run/summary.json" "$run/errors"
        local rc=0
        unshare --mount --propagation private -- "$0" _capture "''${binds[@]}" || rc=$?
        # 3 is a snapshot saved with some files unreadable; it is a backup, with a warning.
        if ((rc != 0 && rc != 3)); then
          failed="restic backup"
          fail "$(reason "$rc")"
        fi
        drop_snapshots
        local unreadable=0
        [[ -s $run/errors ]] && unreadable=$(wc -l <"$run/errors")

        # forget and prune want the repository to themselves, which `lattice backup
        # browse` holds a lock on. They wait for a run when nobody is browsing.
        local checked=""
        if ! systemctl -q is-active lattice-backup-browse.service; then
          phase forget
          r forget --host "$host" --group-by host ${lib.concatStringsSep " " keep} >/dev/null
          if (($(now) - $(state_json | jq -r '.last_prune // 0') > 7 * 86400)); then
            phase prune
            r prune >/dev/null
            save --argjson t "$(now)" '.last_prune = $t'
          fi
          # A tenth of the data read back every month, which over a year touches most of
          # it. `lattice backup check` reads all of it.
          if (($(now) - $(state_json | jq -r '.last_check // 0') > 30 * 86400)); then
            phase check
            if r check --read-data-subset=10% >"$run/check.log"; then
              save --argjson t "$(now)" '.last_check = $t | .last_check_result = "ok"'
              checked="ok"
            else
              save --argjson t "$(now)" --arg e "$(tail -n 1 "$run/stderr")" \
                '.last_check = $t | .last_check_result = "errors" | .last_check_error = $e'
              checked="errors"
            fi
          fi
        fi

        phase finishing
        [[ -s $run/summary.json ]] || echo '{}' >"$run/summary.json"
        drive_facts
        local ended
        ended=$(now)

        save --argjson t "$ended" --argjson d "$((ended - started))" \
          --slurpfile s "$run/summary.json" --argjson unreadable "$unreadable" \
          --argjson uncovered "$(printf '%s\n' "''${uncovered[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
          '.last_run = $t | .last_success = $t | .last_result = "ok" | .last_error = null
           | .last_duration = $d | .last_added = ($s[0].data_added // 0)
           | .last_files_new = ($s[0].files_new // 0) | .last_files_changed = ($s[0].files_changed // 0)
           | .last_unreadable = $unreadable | .uncovered = $uncovered'
        rm -f "$run/progress.json"

        local body urgency=normal icon=document-save
        body="Added $(human "$(jq -r '.data_added // 0' "$run/summary.json")") in $(duration $((ended - started)))"
        if ((unreadable > 0)); then
          body+=$'\n'"$unreadable file(s) could not be read; lattice backup status lists them"
        fi
        if ((''${#uncovered[@]} > 0)); then
          body+=$'\n'"Not backed up (nested subvolume): ''${uncovered[*]}"
          urgency=critical icon=dialog-warning
        fi
        if [[ $checked == errors ]]; then
          body+=$'\n'"The monthly check found problems: lattice backup check"
          urgency=critical icon=dialog-warning
        fi
        notify "$urgency" "$icon" "Backup complete" "$body"
      }

      check() {
        started=$(now)
        phase check
        notify normal document-save "Checking backups" "Reading every backup on the drive back"
        r unlock >/dev/null
        if r check --read-data >"$run/check.log"; then
          save --argjson t "$(now)" '.last_check = $t | .last_check_result = "ok" | .last_check_error = null'
          notify normal document-save "Backups verified" "Read everything back in $(duration $(($(now) - started))); no problems"
        else
          reported=1
          save --argjson t "$(now)" --arg e "$(tail -n 1 "$run/stderr")" \
            '.last_check = $t | .last_check_result = "errors" | .last_check_error = $e'
          notify critical dialog-error "Backup check found problems" "$(tail -n 1 "$run/stderr")"
          exit 1
        fi
      }

      mode=''${1:-now}
      if [[ $mode == _capture ]]; then
        shift
        capture "$@"
        exit $?
      fi

      mkdir -p "$run" "$(dirname "$state")"
      exec 9>"$run/lock"
      if ! flock -n 9; then
        echo "a run is already going"
        exit 0
      fi
      # errtrace, so the ERR trap also fires inside functions.
      set -E
      trap 'failed=$BASH_COMMAND' ERR
      trap cleanup EXIT
      trap 'stopping=1; exit 143' TERM INT

      case $mode in
      auto | now) backup ;;
      check) check ;;
      *)
        echo "usage: lattice-backup-run [auto|now|check]" >&2
        exit 2
        ;;
      esac
    '';
  };

  # Its start is the drive arriving, its stop the drive going: it is PartOf the mount, and
  # the mount is bound to the device. A stop with the drive still there is a shutdown or a
  # restart of this unit by a switch, and says nothing; the attached flag keeps a restart's
  # start from announcing the drive again.
  drive = pkgs.writeShellApplication {
    name = "lattice-backup-drive";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      ${common}
      ${rootNotify}

      mkdir -p "$run"
      case ''${1:-} in
      start)
        if [[ ! -e $run/attached ]]; then
          touch "$run/attached"
          last=$(state_json | jq -r '.last_success // 0')
          if ((last == 0)); then
            body="This machine has not been backed up yet; starting now"
          elif (($(date +%s) - last < 50 * 60)); then
            body="Last backup $(ago $(($(date +%s) - last))); the next is within the hour"
          else
            body="Last backup $(ago $(($(date +%s) - last))); backing up now"
          fi
          notify normal drive-removable-media "Backup drive connected" "$body"
        fi
        signal
        ;;
      stop)
        [[ -e /dev/disk/by-label/${label} ]] && exit 0
        rm -f "$run/attached"
        result=$(state_json | jq -r 'if .last_result == "interrupted" and (now - (.last_run // 0)) < 120 then "interrupted" else "" end')
        if [[ $result == interrupted ]]; then
          notify normal drive-removable-media "Backup drive removed" \
            "It came out mid-backup. Nothing was lost; the backup runs again next time it is plugged in."
        else
          notify normal drive-removable-media "Backup drive removed" ""
        fi
        signal
        ;;
      *)
        echo "usage: lattice-backup-drive start|stop" >&2
        exit 2
        ;;
      esac
    '';
  };

  eject = pkgs.writeShellApplication {
    name = "lattice-backup-eject";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.udisks
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      ${common}
      ${rootNotify}

      dev=$(readlink -f /dev/disk/by-label/${label} 2>/dev/null || true)
      if [[ -z $dev || ! -b $dev ]]; then
        echo "the backup drive is not plugged in"
        exit 0
      fi
      disk=$(lsblk -no PKNAME "$dev")
      # A running backup is stopped, not waited for: restic leaves nothing half-written.
      systemctl stop lattice-backup.timer lattice-backup-browse.service 'lattice-backup@*.service'
      # The drive service stops with the mount and sees the drive still there, so it stays
      # quiet. The next plug-in should announce itself, hence the flag goes here.
      systemctl stop ${lib.escapeShellArg mountUnit}
      rm -f "$run/attached"
      sync
      udisksctl power-off -b "/dev/$disk" --no-user-interaction >/dev/null 2>&1 || true
      notify normal drive-removable-media "Backup drive ejected" "Safe to unplug"
      signal
    '';
  };

  # The human end: `lattice backup ...`, the pill's JSON and the menu's actions. Everything
  # it starts is a system unit polkit lets the user start (see the rule below), so none of
  # it needs sudo.
  cli = pkgs.writeShellApplication {
    name = "lattice-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.jq
      pkgs.procps
      pkgs.systemd
      pkgs.libnotify
    ];
    text = ''
      ${common}

      host=${lib.escapeShellArg host}
      stale=$((${toString staleDays} * 86400))

      # Everything the status and the pill read, in shell variables.
      load() {
        attached=0 running=0 browsing=0
        mountpoint -q ${mountPoint} && attached=1
        # The progress file alone could outlive a run that was killed outright; the
        # runner's lock cannot.
        if [[ -s $run/progress.json ]] && ! flock -n -s "$run/lock" true 2>/dev/null; then
          running=1
        fi
        mountpoint -q ${browseDir} 2>/dev/null && browsing=1
        nowt=$(date +%s)
        last_success=0 last_result="" last_error="" last_run=0 last_duration=0 last_added=0
        last_unreadable=0 snapshots=0 repo_bytes=0 free_bytes=0 last_check=0
        last_check_result="" last_check_error="" uncovered="" others=""
        eval "$(state_json | jq -r --arg h "$host" '@sh "
          last_success=\(.last_success // 0) last_result=\(.last_result // "")
          last_error=\(.last_error // "") last_run=\(.last_run // 0)
          last_duration=\(.last_duration // 0) last_added=\(.last_added // 0)
          last_unreadable=\(.last_unreadable // 0) snapshots=\(.snapshots // 0)
          repo_bytes=\(.repo_bytes // 0) free_bytes=\(.free_bytes // 0)
          last_check=\(.last_check // 0) last_check_result=\(.last_check_result // "")
          last_check_error=\(.last_check_error // "")
          uncovered=\(.uncovered // [] | join(" "))
          others=\([.hosts // [] | .[] | select(.host != $h) | "\(.host)\t\(.time)"] | join("\n"))"')"
        phase="" percent="" remaining=""
        if ((running)); then
          eval "$(jq -r '@sh "phase=\(.phase // "") percent=\(.percent // "") remaining=\(.remaining // "")"' "$run/progress.json" 2>/dev/null || true)"
        fi
        age=$((nowt - last_success))
      }

      # One line each, plain text: `status` prints them, the pill's tooltip escapes them.
      lines() {
        if ((running)); then
          case $phase in
          backup) echo "Backing up: ''${percent:-0}%''${remaining:+, about $(duration "$remaining") left}" ;;
          prune) echo "Clearing out old backups" ;;
          check) echo "Reading backups back to check them" ;;
          *) echo "Backing up" ;;
          esac
        fi
        if ((last_success == 0)); then
          echo "This machine has never been backed up"
        else
          echo "Last backup $(ago "$age") ($(date -d "@$last_success" '+%a %b %-d %H:%M')), $(human "$last_added") added in $(duration "$last_duration")"
        fi
        if [[ $last_result == failed ]]; then
          echo "The last attempt failed $(ago $((nowt - last_run))): $last_error"
        elif [[ $last_result == interrupted ]]; then
          echo "The last attempt was cut short $(ago $((nowt - last_run)))"
        fi
        if ((last_success > 0 && age >= stale)); then
          echo "No backup for $((age / 86400)) days; plug in the backup drive"
        fi
        ((last_unreadable > 0)) && echo "$last_unreadable file(s) could not be read last time"
        [[ -n $uncovered ]] && echo "Not backed up (nested subvolume): $uncovered"
        if ((attached && !running)); then
          next=$(systemctl show lattice-backup.timer -p NextElapseUSecRealtime --value --timestamp=unix 2>/dev/null || true)
          next=''${next#@}
          if [[ -n $next && $next != 0 ]]; then
            echo "Next backup in $(duration $((next > nowt ? next - nowt : 0)))"
          fi
        fi
        ((snapshots > 0)) && echo "$snapshots backups of $host"
        if [[ -n $others ]]; then
          while IFS=$'\t' read -r h t; do
            echo "$h last backed up $(ago $((nowt - t)))"
          done <<<"$others"
        fi
        if ((attached)); then
          echo "Drive: $(human "$repo_bytes") of backups, $(human "$free_bytes") free"
        else
          echo "Backup drive not connected"
        fi
        if ((last_check > 0)); then
          if [[ $last_check_result == ok ]]; then
            echo "Last check $(ago $((nowt - last_check))): no problems"
          else
            echo "Last check $(ago $((nowt - last_check))) found problems: $last_check_error"
          fi
        fi
        ((browsing)) && echo "Browsing at ${browseDir}/hosts/$host"
        return 0
      }

      status() {
        load
        lines
        # For `lattice doctor`: a failed run, a stale or missing backup, or a gap in what is
        # covered is a problem.
        if [[ $last_result == failed ]] || ((last_success == 0 || age >= stale)) || [[ -n $uncovered ]] ||
          [[ $last_check_result == errors ]]; then
          return 1
        fi
      }

      # Hidden unless there is something to see: the drive is in, the last run failed, or
      # the last backup is a week old.
      bar() {
        load
        local text class
        if ((running)); then
          case $phase in
          backup) text="󰓦 ''${percent:-0}%" ;;
          prune) text="󰓦 pruning" ;;
          check) text="󰓦 checking" ;;
          *) text="󰓦" ;;
          esac
          class=running
        elif [[ $last_result == failed || $last_check_result == errors ]]; then
          text="󰀦 failed" class=failed
        elif ((last_success == 0)); then
          text="󰁯 never" class=warning
        elif ((age >= 2 * stale)); then
          text="󰁯 $((age / 86400))d" class=critical
        elif ((age >= stale)); then
          text="󰁯 $((age / 86400))d" class=warning
        elif ((attached)); then
          text="󰁯 $(ago "$age" | sed 's/ ago//; s/just now/now/')" class=ok
        else
          printf '{"text": ""}\n'
          return
        fi
        ((browsing)) && class+=" browsing"
        ((attached)) || class+=" detached"

        local tip
        tip="<b>Backups</b>"$'\n'$(lines | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        if ((attached)); then
          tip+=$'\n\n'"Click to back up now, right-click to eject or browse"
        fi
        jq -nc --arg text "$text" --arg tip "$tip" --arg class "$class" \
          '{text: $text, tooltip: $tip, class: ($class | split(" "))}'
      }

      # The daily reminder, from the user timer in desktop/backup.nix. Quiet while the
      # drive is in: the pill and the hourly runs have that covered.
      nag() {
        load
        ((attached)) && return 0
        if ((last_success == 0)); then
          notify-send -a lattice-backup -u critical -i dialog-warning \
            -h string:x-canonical-private-synchronous:lattice-backup \
            "$host has never been backed up" "Plug in the backup drive to back it up"
        elif ((age >= stale)); then
          notify-send -a lattice-backup -u critical -i dialog-warning \
            -h string:x-canonical-private-synchronous:lattice-backup \
            "No backup in $((age / 86400)) days" "Plug in the backup drive to back up $host"
        fi
      }

      unit() {
        systemctl --no-ask-password "$@"
      }

      need_drive() {
        if ! mountpoint -q ${mountPoint}; then
          echo "the backup drive is not plugged in" >&2
          exit 1
        fi
      }

      case ''${1:-status} in
      status) status ;;
      bar) bar ;;
      nag) nag ;;
      now)
        need_drive
        unit start --no-block lattice-backup@now.service
        signal
        ;;
      check)
        need_drive
        unit start --no-block lattice-backup@check.service
        ;;
      stop) unit stop 'lattice-backup@*.service' ;;
      browse)
        need_drive
        unit start lattice-backup-browse.service
        for _ in $(seq 50); do
          mountpoint -q ${browseDir} && break
          sleep 0.2
        done
        signal
        mountpoint -q ${browseDir} || {
          echo "the backups did not mount; systemctl status lattice-backup-browse" >&2
          exit 1
        }
        echo "${browseDir}/hosts/$host"
        ;;
      unbrowse)
        unit stop lattice-backup-browse.service
        signal
        ;;
      eject) unit start lattice-backup-eject.service ;;
      *)
        echo "usage: lattice backup [status|now|check|stop|browse|unbrowse|eject]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  options.lattice.backup = {
    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/lattice-backup/password";
      description = ''
        A root-readable file holding the restic password. The drive is unreadable without
        it, so keep a copy off the machine.
      '';
    };
    sources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # /srv is a subvolume of its own wherever systemd-tmpfiles made it on btrfs, which
      # leaves it out of the snapshot of /.
      default = [
        "/"
        "/home"
        "/srv"
      ];
      description = ''
        Mount points and nested btrfs subvolumes to back up, parents before children. Each
        one that is a btrfs subvolume is snapshotted for the run; anything else is read
        live. A source that is neither on this host is skipped, since its parent already
        covers it.
      '';
    };
    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic exclude patterns on top of the defaults in backup.nix.";
    };
    internal = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "What desktop/backup.nix needs from here.";
      default = {
        inherit
          cli
          staleDays
          mountPoint
          browseDir
          ;
      };
    };
  };

  config = {
    # Hidden unless there is something to see: the drive is plugged in, the last run
    # failed, or the last backup is a week old. The text is the age of the last backup, or
    # progress while one runs; the tooltip has the rest. The runner signals the bar on every
    # change, so the interval is only for the age ticking over. Click backs up now,
    # right-click is the menu (browse, check, eject; desktop/backup.nix).
    lattice.bar.modules."custom/backup" = {
      section = "group/toggles";
      order = 70;
      settings = {
        exec = "lattice-backup bar";
        return-type = "json";
        signal = barSignal;
        interval = 30;
        on-click = "lattice-backup now";
        on-click-right = "lattice-backup-menu";
      };
    };

    environment.systemPackages = [
      cli
      pkgs.restic
    ];

    # udiskie would otherwise mount it under /run/media as the user the moment it appears.
    services.udev.extraRules = ''
      SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${label}", ENV{UDISKS_IGNORE}="1"
    '';

    systemd.tmpfiles.rules = [
      "d ${runDir} 0755 root root -"
      "d ${snapshotDir} 0700 root root -"
      "d ${cacheDir} 0700 root root -"
      "d /var/lib/lattice-backup 0755 root root -"
    ];

    # The device unit exists while the drive is plugged in, and wanting the mount from it
    # is what mounts it. The mount is bound to the device, so pulling the drive unmounts.
    # Restic packs are already compressed, so btrfs is left not to try.
    systemd.mounts = [
      {
        what = "/dev/disk/by-label/${label}";
        where = mountPoint;
        type = "btrfs";
        options = "noatime";
        wantedBy = [ deviceUnit ];
      }
    ];

    systemd.services = {
      lattice-backup-drive = {
        description = "Backup drive attached";
        wantedBy = [ mountUnit ];
        after = [ mountUnit ];
        requisite = [ mountUnit ];
        partOf = [ mountUnit ];
        wants = [ "lattice-backup.timer" ];
        onFailure = [ "lattice-notify-failure@%n.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe drive} start";
          ExecStop = "${lib.getExe drive} stop";
        };
      };

      # The runner reports its own failures, so no OnFailure= here: it would only say the
      # same thing twice. After the drive service so that on an unplug this stops first and
      # records the interruption before the drive service reads it.
      "lattice-backup@" = {
        description = "Back up to the backup drive (%i)";
        after = [
          mountUnit
          "lattice-backup-drive.service"
        ];
        requisite = [ mountUnit ];
        partOf = [ mountUnit ];
        # A switch mid-backup should not restart it from the top.
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe runner} %i";
          TimeoutStartSec = "infinity";
          TimeoutStopSec = "30s";
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
          CPUSchedulingPolicy = "batch";
        };
      };

      # Every backup as a folder, for `lattice backup browse`. FUSE with allow_other, so
      # the user can read it, and with the default permission checks, so only what was
      # already theirs. It holds a lock that keeps forget and prune waiting.
      lattice-backup-browse = {
        description = "Mount the backups for browsing";
        after = [ mountUnit ];
        requisite = [ mountUnit ];
        partOf = [ mountUnit ];
        restartIfChanged = false;
        path = [ "/run/wrappers" ];
        environment = {
          RESTIC_REPOSITORY = repo;
          RESTIC_PASSWORD_FILE = passwordFile;
          RESTIC_CACHE_DIR = cacheDir;
        };
        serviceConfig = {
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${browseDir}";
          ExecStart = "${lib.getExe pkgs.restic} mount --allow-other ${browseDir}";
        };
      };

      lattice-backup-eject = {
        description = "Eject the backup drive";
        onFailure = [ "lattice-notify-failure@%n.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe eject;
        };
      };
    };

    # Hourly while the drive is in, counted from the end of the last run. The first fires
    # ten seconds after the drive arrives; the runner skips it if the last backup is under
    # 50 minutes old, so a quick unplug and replug does not back up twice.
    systemd.timers.lattice-backup = {
      description = "Back up hourly while the backup drive is attached";
      after = [ mountUnit ];
      partOf = [ mountUnit ];
      timerConfig = {
        Unit = "lattice-backup@auto.service";
        OnActiveSec = "10s";
        OnUnitInactiveSec = "1h";
        AccuracySec = "1min";
      };
    };

    # Lets the pill and `lattice backup` start what they start without sudo. Named units
    # only: anything else still asks.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "${user}") {
          var unit = action.lookup("unit");
          var verb = action.lookup("verb");
          var units = [
            "lattice-backup@now.service",
            "lattice-backup@auto.service",
            "lattice-backup@check.service",
            "lattice-backup-browse.service",
            "lattice-backup-eject.service",
          ];
          if (units.indexOf(unit) >= 0 && (verb == "start" || verb == "stop")) {
            return polkit.Result.YES;
          }
        }
      });
    '';

    lattice.cli.commands = {
      "backup status" = {
        exec = "${lib.getExe cli} status";
        summary = "When this machine last backed up, and the drive's state";
        group = "system";
        launch = [
          {
            label = "Backup status";
            icon = "document-save";
            terminal = true;
          }
        ];
      };
      "backup now" = {
        exec = "${lib.getExe cli} now";
        summary = "Back up to the backup drive now";
        group = "system";
        launch = [
          {
            label = "Back up now";
            icon = "document-save";
          }
        ];
      };
      "backup check" = {
        exec = "${lib.getExe cli} check";
        summary = "Read every backup back to verify it";
        group = "system";
      };
      "backup stop" = {
        exec = "${lib.getExe cli} stop";
        summary = "Stop a running backup; the next one carries on";
        group = "system";
      };
      "backup browse" = {
        exec = "${lib.getExe cli} browse";
        summary = "Mount every backup as folders; prints where";
        group = "system";
      };
      "backup unbrowse" = {
        exec = "${lib.getExe cli} unbrowse";
        summary = "Unmount the browsable backups";
        group = "system";
      };
      "backup eject" = {
        exec = "${lib.getExe cli} eject";
        summary = "Stop everything, unmount and power off the backup drive";
        group = "system";
        launch = [
          {
            label = "Eject the backup drive";
            icon = "media-eject";
          }
        ];
      };
    };
  };
}
