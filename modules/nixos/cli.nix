{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lattice.cli;
  inherit (lib) types;

  # The checkout the repo commands run from. nh already needs it, so it is named once there.
  flake = config.programs.nh.flake;

  # Sections of `lattice --help`, in the order they print.
  groups = [
    {
      id = "look";
      title = "Look";
    }
    {
      id = "session";
      title = "Session";
    }
    {
      id = "devices";
      title = "Devices";
    }
    {
      id = "system";
      title = "System";
    }
  ];

  command = types.submodule (
    { name, config, ... }:
    {
      options = {
        exec = lib.mkOption {
          type = types.str;
          description = ''
            What the route runs, with the caller's arguments appended. A store path rather
            than a bare name, so the route works from any PATH -- waybar's, a unit's, a
            Stream Deck key's.
          '';
        };
        summary = lib.mkOption {
          type = types.str;
          description = "One line for the command list.";
        };
        args = lib.mkOption {
          type = types.str;
          default = "";
          example = "[toggle|on|off|status]";
          description = ''
            The synopsis after the route. A leading `<` means the command does nothing
            useful bare, so `lattice <route>` alone prints its help instead.
          '';
        };
        details = lib.mkOption {
          type = types.lines;
          default = "";
          description = "Printed under the summary by `lattice <route> --help`.";
        };
        complete = lib.mkOption {
          type = types.listOf types.str;
          default = lib.unique (
            lib.concatMap
              (group: lib.filter (w: builtins.match "[a-z0-9-]+" w != null) (lib.splitString "|" group))
              (
                lib.concatMap (m: if builtins.isList m then m else [ ]) (
                  builtins.split "[[<]([^]>]*\\|[^]>]*)[]>]" config.args
                )
              )
          );
          defaultText = lib.literalMD "every plain word in an `a|b|c` alternation in `args`";
          description = "Words zsh offers after the route.";
        };
        group = lib.mkOption {
          type = types.enum (map (g: g.id) groups);
          description = "Which section of `lattice --help` lists it.";
        };
        hidden = lib.mkOption {
          type = types.bool;
          default = false;
          description = ''
            Left out of `lattice --help` and completion: commands only the bar or a unit
            runs. `lattice commands --all` still lists them.
          '';
        };
        launch = lib.mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                label = lib.mkOption {
                  type = types.str;
                  description = "The row's text. A trailing … means it opens a menu of its own.";
                };
                args = lib.mkOption {
                  type = types.str;
                  default = "";
                  description = "Appended to `exec`, split on spaces.";
                };
                icon = lib.mkOption {
                  type = types.str;
                  default = "system-run";
                  description = "An icon name from the icon theme.";
                };
                terminal = lib.mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Run it in a foot window that stays open, for commands whose output is
                    the point or that ask for a password.
                  '';
                };
              };
            }
          );
          default = [ ];
          description = ''
            Rows this command puts in the launcher's `>` list (desktop/launcher.nix). The
            route is searchable on each row too, so `>dnd` finds "Do not disturb".
          '';
        };
        route = lib.mkOption {
          type = types.str;
          default = name;
          readOnly = true;
          internal = true;
        };
      };
    }
  );

  commands = cfg.commands;
  routes = lib.attrNames commands;
  words = lib.splitString " ";
  head = route: lib.head (words route);
  isPair = route: lib.length (words route) == 2;
  pairs = lib.filter isPair routes;
  singles = lib.filter (r: !isPair r) routes;
  # First words that are only a prefix, like `power` or `secrets`.
  bareHeads = lib.filter (h: !(commands ? ${h})) (lib.unique (map head pairs));
  shown = routes: lib.filter (r: !commands.${r}.hidden) routes;
  under = h: lib.filter (r: isPair r && head r == h) routes;

  usage = r: "lattice ${r}${lib.optionalString (commands.${r}.args != "") " ${commands.${r}.args}"}";

  # Two columns, padded at build time so the script only has to cat it.
  table =
    rows:
    let
      width = lib.foldl' lib.max 0 (map (row: lib.stringLength row.left) rows);
      pad = s: s + lib.concatStrings (lib.genList (_: " ") (width - lib.stringLength s));
    in
    lib.concatMapStrings (row: "  ${pad row.left}  ${row.right}\n") rows;
  rowsFor = rowsWith true;
  rowsWith =
    withArgs: routes:
    map (r: {
      left = if withArgs then lib.removePrefix "lattice " (usage r) else r;
      right = commands.${r}.summary;
    }) routes;

  mainHelp = ''
    lattice: one command for this desktop and the system under it.

    Usage:
      lattice <command> [args...]
      lattice <command> --help
      lattice commands [--all|--json]
  ''
  + lib.concatMapStrings (
    g:
    let
      members = lib.filter (r: commands.${r}.group == g.id) (shown routes);
    in
    lib.optionalString (members != [ ]) "\n${g.title}\n${table (rowsWith false members)}"
  ) groups;

  commandHelp =
    r:
    let
      c = commands.${r};
      related = shown (under r);
    in
    ''
      Usage: ${usage r}

      ${c.summary}
    ''
    + lib.optionalString (c.details != "") (
      "\n"
      + lib.concatMapStrings (line: "  ${line}\n") (
        lib.splitString "\n" (lib.removeSuffix "\n" c.details)
      )
    )
    + lib.optionalString (related != [ ]) "\nAlso:\n${table (rowsFor related)}";

  groupHelp = h: "Usage: lattice ${h} <command>\n\n${table (rowsFor (under h))}";

  # Quoted heredocs, so nothing in a summary is expanded; the terminator cannot appear in
  # any of them.
  heredocTo = redirect: text: ''
    cat ${redirect}<<'LATTICE_HELP'
    ${lib.removeSuffix "\n" text}
    LATTICE_HELP
  '';
  heredoc = heredocTo "";

  # A command's branch: --help is the router's, everything else is the command's.
  dispatch =
    r:
    let
      c = commands.${r};
      bareHelp = lib.hasPrefix "<" c.args;
    in
    ''
      case "''${1-}" in
      -h | --help)
      ${heredoc (commandHelp r)}
        exit 0
        ;;
      ${lib.optionalString bareHelp ''
        "")
        ${heredoc (commandHelp r)}
          exit 2
          ;;
      ''}
      esac
      exec ${c.exec} "$@"
    '';

  json = pkgs.writeText "lattice-commands.json" (
    builtins.toJSON (
      map (r: {
        route = r;
        inherit (commands.${r})
          summary
          args
          group
          hidden
          exec
          complete
          ;
      }) routes
    )
  );

  router = pkgs.writeShellApplication {
    name = "lattice";
    text = ''
      case "''${1-}" in
      "" | -h | --help | help)
      ${heredoc mainHelp}
        exit 0
        ;;
      commands)
        case "''${2-}" in
        "")
      ${heredoc (table (rowsFor (shown routes)))}
          ;;
        --all)
      ${heredoc (table (rowsFor routes))}
          ;;
        --json) cat ${json} ;;
        *)
          echo "usage: lattice commands [--all|--json]" >&2
          exit 2
          ;;
        esac
        exit 0
        ;;
      esac

      # Two-word routes first, so `theme menu` is not read as `theme` given `menu`. The
      # assertion in this module keeps that from shadowing a verb of the one-word command.
      case "''${1-} ''${2-}" in
      ${lib.concatMapStrings (r: ''
        "${r}")
          shift 2
        ${dispatch r}
          ;;
      '') pairs}
      esac

      case "$1" in
      ${lib.concatMapStrings (r: ''
        ${r})
          shift
        ${dispatch r}
          ;;
      '') singles}
      ${lib.concatMapStrings (h: ''
        ${h})
          if [[ -n ''${2-} && ''${2-} != -h && ''${2-} != --help ]]; then
            echo "lattice: no such command: $*" >&2
          ${heredocTo ">&2 " (groupHelp h)}
            exit 127
          fi
        ${heredoc (groupHelp h)}
          exit 0
          ;;
      '') bareHeads}
      *)
        echo "lattice: no such command: $1" >&2
        echo "Run 'lattice' for the list." >&2
        exit 127
        ;;
      esac
    '';
  };

  # zsh: the first word from every route head, then the head's verbs and second words.
  zq = s: lib.replaceStrings [ "'" ":" ] [ "'\\''" "\\:" ] s;
  headSummary =
    h:
    if commands ? ${h} then
      commands.${h}.summary
    else
      lib.concatMapStringsSep ", " (r: lib.last (words r)) (under h);
  completion = pkgs.writeTextDir "share/zsh/site-functions/_lattice" ''
    #compdef lattice

    local -a described plain
    if (( CURRENT == 2 )); then
      described=(
    ${
      lib.concatMapStrings (h: "    '${h}:${zq (headSummary h)}'\n") (
        lib.unique (map head (shown routes))
      )
    }    'commands:List every command'
      )
      _describe -t commands 'lattice command' described
      return
    fi

    if (( CURRENT == 4 )); then
      case "''${words[2]} ''${words[3]}" in
    ${
      lib.concatMapStrings (r: ''
        "${r}") plain=(${lib.escapeShellArgs commands.${r}.complete}) ;;
      '') (shown pairs)
    }  esac
      (( $#plain )) && compadd -a plain
      return
    fi

    (( CURRENT == 3 )) || return
    case "''${words[2]}" in
    ${
      lib.concatMapStrings (
        h:
        let
          subs = shown (under h);
        in
        ''
          ${h})
            described=(${
              lib.concatMapStringsSep " " (r: "'${lib.last (words r)}:${zq commands.${r}.summary}'") subs
            })
            plain=(${lib.escapeShellArgs (commands.${h}.complete or [ ])})
            ;;
        ''
      ) (lib.unique (map head (shown routes)))
    }  commands) plain=(--all --json) ;;
    esac
    (( $#described )) && _describe -t subcommands 'subcommand' described
    (( $#plain )) && compadd -a plain
    return 0
  '';

  # For the system group, which belongs to no one module.
  script =
    name: runtimeInputs: text:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "lattice-${name}";
        inherit runtimeInputs text;
      }
    );

  # What /run/current-system was built from, against what the checkout holds now. Shared by
  # `version` and `doctor`.
  revisionCheck = ''
    built=$(nixos-version --configuration-revision 2>/dev/null || true)
    head=$(git -C ${lib.escapeShellArg flake} rev-parse HEAD 2>/dev/null || true)
    dirty=$(git -C ${lib.escapeShellArg flake} status --porcelain 2>/dev/null | head -n1 || true)
    if [[ -z $built || -z $head ]]; then
      drift="unknown"
    elif [[ $built != "$head" && $built != *-dirty && -z $dirty ]] &&
      git -C ${lib.escapeShellArg flake} diff --quiet "''${built%-dirty}" "$head" -- 2>/dev/null; then
      # A PR merged on GitHub lands as a new merge commit over the exact tree that was built
      # from its branch, so commit IDs differ while nothing a rebuild reads has moved. Only
      # with both sides clean: a dirty build or checkout holds files no commit records.
      drift="the checkout is at ''${head:0:7}, a different commit with the same files as the running system"
    elif [[ ''${built%-dirty} != "$head" ]]; then
      drift="the checkout is at ''${head:0:7}, ahead of or apart from the running system"
    elif [[ $built == *-dirty || -n $dirty ]]; then
      drift="same commit, but one side was built or is sitting dirty"
    else
      drift="the running system is the checkout's HEAD"
    fi
    # A `lattice rebuild --test` is running but is not what the machine boots.
    trial=""
    if [[ $(readlink -f /run/current-system) != $(readlink -f /nix/var/nix/profiles/system) ]]; then
      trial="running a trial build (lattice rebuild --test); a reboot goes back to the boot default"
    fi
  '';
in
{
  options.lattice.cli.commands = lib.mkOption {
    type = types.attrsOf command;
    default = { };
    description = ''
      Every route of the `lattice` command, keyed by the words that reach it
      (`"theme"`, `"power menu"`). Modules register the scripts they define here, next
      to the script itself. Routes are one word, or two when the first names a family
      (`power menu`, `power profile`).

      The `lattice-*` binaries stay on PATH as the implementation: scripts, units, the
      bar and the deck call each other by those names. `lattice` is the front door
      for people, with help, completion and one place to find everything.
    '';
  };

  config = {
    assertions = lib.concatMap (
      r:
      let
        h = head r;
        w = lib.last (words r);
      in
      lib.optional (commands ? ${h}) {
        assertion = !(lib.elem w commands.${h}.complete);
        message = "lattice.cli: route `${r}` shadows `lattice ${h} ${w}`, a verb of `${h}`.";
      }
    ) pairs;

    environment.systemPackages = [
      router
      completion
    ];

    lattice.cli.commands = lib.mkIf (flake != null) {
      rebuild = {
        exec = "${flake}/scripts/rebuild.sh";
        args = "[--build|--test] [host]";
        summary = "Build this machine from the checkout and switch to it";
        details = ''
          --build  build only, and list what a switch would change; no sudo, nothing activated
          --test   switch until the next reboot, which goes back to the boot default
        '';
        group = "system";
        launch = [
          {
            label = "Rebuild this machine";
            icon = "system-software-update";
            terminal = true;
          }
        ];
      };
      update = {
        exec = "${flake}/scripts/update.sh";
        args = "[input...]";
        summary = "Move flake.lock forward, then offer a rebuild";
        group = "system";
        launch = [
          {
            label = "Update flake inputs";
            icon = "system-software-update";
            terminal = true;
          }
        ];
      };
      "secrets edit" = {
        exec = script "secrets-edit" [ ] ''
          cd ${lib.escapeShellArg flake}
          # The admin key if this machine has it (it lives on the DB flash drive, not on
          # either laptop), otherwise this host's SSH key, which is a recipient too and needs
          # sudo to read -- the same fallback as scripts/set-backup-password.sh.
          keyfile=''${SOPS_AGE_KEY_FILE:-''${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}
          if [[ -f $keyfile ]]; then
            export SOPS_AGE_KEY_FILE=$keyfile
          else
            # shellcheck disable=SC2016 # expanded by the inner bash, inside the dev shell
            exec nix develop --command bash -c \
              'SOPS_AGE_KEY=$(sudo "$(command -v ssh-to-age)" -private-key -i /etc/ssh/ssh_host_ed25519_key) exec sops secrets/common.yaml'
          fi
          exec nix develop --command sops secrets/common.yaml
        '';
        summary = "Open secrets/common.yaml in sops";
        group = "system";
      };
      "secrets password" = {
        exec = "${flake}/scripts/set-password.sh";
        args = "[user]";
        summary = "Set a login password in the secrets";
        group = "system";
      };

      version = {
        exec = script "version" [ pkgs.git ] ''
          ${revisionCheck}
          generation=$(readlink /nix/var/nix/profiles/system)
          generation=''${generation#system-}
          printf '%-10s %s\n' \
            host "$(hostname)" \
            nixos "$(nixos-version)" \
            kernel "$(uname -r)" \
            generation "''${generation%-link}''${trial:+ (boot default; not what is running)}" \
            built "''${built:-unknown}" \
            checkout "''${head:-unknown}''${dirty:+ (dirty)}"
          echo
          echo "$drift"
          [[ -z $trial ]] || echo "$trial"
        '';
        summary = "What is running, and whether the checkout has moved since";
        group = "system";
        launch = [
          {
            label = "What's running";
            icon = "dialog-information";
            terminal = true;
          }
        ];
      };

      doctor = {
        exec =
          script "doctor"
            [
              pkgs.git
              pkgs.gawk
              pkgs.jq
              pkgs.btrfs-progs
              pkgs.util-linux
            ]
            ''
              problems=0
              if [[ -t 1 ]]; then
                section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
              else
                section() { printf '\n%s\n' "$1"; }
              fi

              section "Failed units"
              system=$(systemctl --failed --no-legend --plain | awk '{ print "  system  " $1 }')
              user=$(systemctl --user --failed --no-legend --plain | awk '{ print "  user    " $1 }')
              # Daemons that died with an error but are no longer marked failed. A reset-failed
              # clears the failed state, as happened to lattice-network-notify at login on
              # 2026-10-04, but ExecMainStatus keeps the exit status, so they are still listed.
              # Only units with a Restart= policy, which are meant to stay up. A oneshot such as
              # a lattice-notify-failure@ instance keeps its last status until it runs again,
              # and would stay listed for the rest of the boot.
              # Records from `systemctl show` come in its own property order, not the order
              # asked for, so each one is read in full before it is judged.
              exited() {
                systemctl "$1" list-units --type=service --all --state=inactive --no-legend --plain \
                  | awk '{ print $1 }' \
                  | xargs -r systemctl "$1" show -p Id -p ExecMainStatus -p Restart 2>/dev/null \
                  | awk -v scope="$2" '
                      function judge() { if (id != "" && status != 0 && restart != "no") printf "  %-7s %s (exited %s, not running)\n", scope, id, status; id = status = restart = "" }
                      /^$/ { judge(); next }
                      /^Id=/ { id = substr($0, 4) }
                      /^ExecMainStatus=/ { status = substr($0, 16) }
                      /^Restart=/ { restart = substr($0, 9) }
                      END { judge() }'
              }
              system+=$'\n'$(exited --system system)
              user+=$'\n'$(exited --user user)
              if [[ -n ''${system//$'\n'/}''${user//$'\n'/} ]]; then
                printf '%s\n' "$system" "$user" | grep . || true
                echo "  systemctl [--user] status <unit> for why; lattice-notify-failure has already said so on screen"
                problems=1
              else
                echo "  none"
              fi

              section "Crashes this boot"
              # Core dumps, grouped by program. Informational, not a problem: Hyprland 0.56.2
              # segfaults in aquamarine's teardown on every clean exit, and takes its clients
              # down with it, so each logout leaves a handful here.
              booted=$(awk '/^btime/ { print $2 }' /proc/stat)
              crashes=$(coredumpctl list --since "@$booted" --json=short --no-pager 2>/dev/null \
                | jq -r '.[] | "\(.exe | split("/") | last | ltrimstr(".") | rtrimstr("-wrapped"))\t\(.sig)"' \
                | sort | uniq -c | sort -rn || true)
              # The kernel's OOM killer and systemd-oomd both end a process without a core.
              ooms=$(journalctl -b -k -q --no-pager -o cat --grep 'Out of memory: Killed process' 2>/dev/null | wc -l || true)
              oomd=$(journalctl -b -q --no-pager -o cat -u systemd-oomd --grep 'Killed' 2>/dev/null | wc -l || true)
              if [[ -n $crashes ]]; then
                while read -r n exe sig; do
                  printf '  %6dx %s (SIG%s)\n' "$n" "$exe" "$(kill -l "$sig" 2>/dev/null || echo "$sig")"
                done <<< "$crashes"
                echo "  coredumpctl info <program> for the backtrace"
              fi
              if (( ooms + oomd > 0 )); then
                echo "  $ooms killed by the kernel OOM killer, $oomd by systemd-oomd"
              fi
              if [[ -z $crashes ]] && (( ooms + oomd == 0 )); then
                echo "  none"
              fi

              section "Previous boot"
              # A boot whose journal stops without systemd reaching its shutdown ended in a
              # hang, a panic or a power cut, and the cause is usually only in that journal.
              if ! last=$(journalctl -b -1 -q --no-pager -o cat -n 50 2>/dev/null) || [[ -z $last ]]; then
                echo "  no journal for it"
              elif grep -qE '^(Shutting down|Journal stopped)' <<< "$last"; then
                echo "  shut down cleanly"
              else
                echo "  ended without a clean shutdown; journalctl -b -1 -e for its last words"
                problems=1
              fi

              section "Configuration"
              ${revisionCheck}
              echo "  $drift"
              [[ -z $trial ]] || echo "  $trial"
              # A switch can change the kernel, initrd or modules without them taking effect, and
              # the system then runs one generation's userland on another's kernel.
              stale=()
              for part in kernel initrd kernel-modules; do
                if [[ $(readlink -f /run/booted-system/$part) != $(readlink -f /run/current-system/$part) ]]; then
                  stale+=("$part")
                fi
              done
              if (( ''${#stale[@]} > 0 )); then
                echo "  reboot to load the new ''${stale[*]}"
              fi
              ahead=$(git -C ${lib.escapeShellArg flake} rev-list --count '@{u}..HEAD' 2>/dev/null || true)
              if [[ -n $ahead && $ahead != 0 ]]; then
                echo "  $ahead commit(s) not pushed"
              fi
              # How far the running system's nixpkgs trails today. This matters most for Firefox,
              # whose media decoder runs unsandboxed on Apple Silicon (hardware/apple-silicon.nix):
              # what protects it is mostly how soon a fixed release arrives. nixpkgs-unstable picks
              # those up within a day or two, so anything past a week means `lattice update` is
              # overdue.
              nixpkgsDate=$(nixos-version | sed -nE 's/^[0-9]+\.[0-9]+\.([0-9]{8})\..*/\1/p')
              if [[ -n $nixpkgsDate ]]; then
                age=$(( ($(date +%s) - $(date -d "$nixpkgsDate" +%s)) / 86400 ))
                echo "  nixpkgs is $age day(s) old"
                if (( age > 7 )); then
                  echo "  Firefox is probably missing security fixes; lattice update"
                  problems=1
                fi
              fi

              section "Persistence"
              # Where code running as the user would hide to survive a reboot, which matters
              # because Firefox's media decoder runs unsandboxed on Apple Silicon
              # (hardware/apple-silicon.nix). Every unit comes from the flake, and any config that
              # runs code at login is either absent or a symlink into a git repo (a dotfiles
              # repo), so anything else is worth looking at. Detection, not prevention: it only shows up here.
              clean=1
              extra=$(find "$HOME/.config/systemd" "$HOME/.config/environment.d" -mindepth 1 \( -type f -o -type l \) 2>/dev/null || true)
              if [[ -n $extra ]]; then
                echo "  user units or environment from outside the flake:"
                awk '{ print "    " $0 }' <<< "$extra"
                problems=1 clean=0
              fi
              # Bitwarden writes its own entry, with a store path that changes on every
              # update, so it is matched by shape.
              for entry in "$HOME"/.config/autostart/*.desktop; do
                [[ -e $entry ]] || continue
                exec=$(grep -m1 '^Exec=' "$entry" || true)
                case "''${entry##*/} $exec" in
                  "bitwarden.desktop Exec=/nix/store/"*"-bitwarden-desktop-"*"/bin/bitwarden --autostart") ;;
                  *)
                    echo "  autostart ''${entry##*/}: ''${exec#Exec=}"
                    problems=1 clean=0
                    ;;
                esac
              done
              # Shell startup files and the user's Hyprland Lua run at every login. Each one
              # must be a symlink into a git repo, whose hooks and uncommitted changes are then
              # checked below.
              declare -A repos=()
              [[ -d $HOME/.dotfiles/.git ]] && repos[$HOME/.dotfiles]=1
              for rc in .zshrc .zshenv .zprofile .zlogin .zlogout .profile .bashrc .bash_profile .bash_login .pam_environment \
                .config/hypr/hyprland.lua .config/hypr/local.lua; do
                f="$HOME/$rc"
                [[ -e $f || -L $f ]] || continue
                target=$(readlink -f "$f")
                if [[ -L $f ]] && repo=$(git -C "''${target%/*}" rev-parse --show-toplevel 2>/dev/null); then
                  repos[$repo]=1
                else
                  echo "  ~/$rc is not from a git repo"
                  problems=1 clean=0
                fi
              done
              # This one is a choice rather than a threat, but it replaces the whole of
              # /etc/xdg/hypr/hyprland.lua, so lattice's binds and rules no longer apply.
              if [[ -e $HOME/.config/hypr/hyprland.lua ]]; then
                echo "  ~/.config/hypr/hyprland.lua replaces lattice's Hyprland config"
                clean=0
              fi
              # A git hook runs on the next commit in that repo.
              for repo in ${lib.escapeShellArg flake} "''${!repos[@]}"; do
                hooks=$(find "$repo/.git/hooks" -type f ! -name '*.sample' 2>/dev/null || true)
                if [[ -n $hooks ]]; then
                  echo "  git hooks in ''${repo/#$HOME/\~}:"
                  awk '{ print "    " $0 }' <<< "$hooks"
                  problems=1 clean=0
                fi
              done
              # Every config in those repos can run code (zshrc, gitconfig and so on), so
              # uncommitted changes are listed for review. They don't count as a problem on
              # their own, since they are usually just work in progress.
              for repo in "''${!repos[@]}"; do
                changes=$(git -C "$repo" status --porcelain 2>/dev/null || true)
                if [[ -n $changes ]]; then
                  echo "  uncommitted in ''${repo/#$HOME/\~} (review anything you didn't change yourself):"
                  head -n 10 <<< "$changes" | sed 's/^/    /'
                  clean=0
                fi
              done
              if (( clean )); then
                echo "  nothing from outside the flake and your git repos"
              fi

              section "Errors this boot"
              # Counted by message rather than listed in order: one chatty daemon repeating
              # itself every minute would otherwise be all the tail ever shows.
              #
              # Less the lines that turn up on every healthy boot, which otherwise took all five
              # slots and pushed anything new off the list (all checked on 2026-10-06):
              # dbus-broker's duplicate-name lines, which NixOS's merged service directories cause
              # on every host; and on the Mac, the Bluetooth codec query and BAP probe the bcm4377
              # firmware refuses, the brcmfmac join-pref/roam/P2P setup calls its firmware does not
              # implement (-52), the three speaker amps the devicetree leaves unconfigured, and
              # cpufreq_schedutil, which the Asahi module asks modules-load for although this
              # kernel has the governor built in. Also udev's mtd_probe callout, which this systemd
              # no longer ships, and bluetoothd's wake flag the controller rejects.
              journalctl -b -p err -q --no-pager -o short 2>/dev/null \
                | grep -vE 'Ignoring duplicate name|Failed to read codec capabilities|BAP requires ISO Socket|bap: Operation not supported|error \(-52\)|err=-52|ret -52|p2p-dev-wld0|brcmf_p2p_create_p2pdev|tas2764_i2c_probe: Failed to parse devicetree|cpufreq_schedutil|mtd_probe|set_wake_allowed_complete' \
                | awk '{ $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); sub(/\[[0-9]+\]/, ""); print }' \
                | sort | uniq -c | sort -rn | head -n 5 \
                | awk 'NF > 1 { n = $1; $1 = ""; printf "  %6dx %s\n", n, substr($0, 2, 110) }' || true

              section "Backups"
              # backup.nix: a failed run, a week without a backup, a nested subvolume left out
              # or a check that found damage.
              if ! backups=$(${lib.getExe config.lattice.backup.internal.cli} status); then
                problems=1
              fi
              awk '{ print "  " $0 }' <<< "$backups"

              section "Disk"
              df -h --output=target,avail,pcent / /nix 2>/dev/null | awk 'NR > 1 && !seen[$1]++ { print "  " $1 "  " $2 " free, " $3 " used" }'
              if df --output=pcent / /nix 2>/dev/null | awk 'NR > 1 && $1 + 0 >= 90 { found = 1 } END { exit !found }'; then
                echo "  under 10% free; nh clean all frees old generations"
                problems=1
              fi
              # Every btrfs filesystem, once each however many subvolumes it is mounted as.
              # Device stats are cumulative across boots and readable without root; nonzero
              # means the disk has actually returned a bad read, write or checksum.
              for fs in $(findmnt -t btrfs -no UUID,TARGET | awk '!seen[$1]++ { print $2 }'); do
                errors=$(btrfs device stats -c "$fs" 2>/dev/null | awk '$2 != 0 { print "    " $0 }' || true)
                if [[ -n $errors ]]; then
                  echo "  btrfs on $fs has recorded device errors:"
                  echo "$errors"
                  problems=1
                else
                  echo "  btrfs on $fs: no device errors"
                fi
              done
              # The last scrub's summary, from the journal. `btrfs scrub status` needs root to
              # read the result file and prints nothing useful without it. The monthly
              # btrfs-scrub@ timer logs the same summary there. One line for every filesystem,
              # because each host has a single btrfs filesystem.
              scrub=$(journalctl -q --no-pager -o cat -t btrfs --grep '^(Scrub started|Error summary):' -n 2 2>/dev/null \
                | awk '{ value = $0; sub(/^[^:]*: */, "", value) }
                    /^Scrub started/ { started = value } /^Error summary/ { summary = value }
                    END { if (started != "") print "last scrub " started ": " summary }' || true)
              if [[ -n $scrub ]]; then
                echo "  $scrub"
                if [[ $scrub != *"no errors found" ]]; then problems=1; fi
              elif [[ -n $(findmnt -t btrfs -no TARGET) ]]; then
                echo "  no scrub on record"
              fi

              exit "$problems"
            '';
        summary = "Health check: units, crashes, last shutdown, drift, persistence, boot errors, backups, disk";
        group = "system";
        launch = [
          {
            label = "Health check";
            icon = "utilities-system-monitor";
            terminal = true;
          }
        ];
      };
    };
  };
}
