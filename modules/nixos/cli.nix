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
    elif [[ ''${built%-dirty} != "$head" ]]; then
      drift="the checkout is at ''${head:0:7}, ahead of or apart from the running system"
    elif [[ $built == *-dirty || -n $dirty ]]; then
      drift="same commit, but one side was built or is sitting dirty"
    else
      drift="the running system is the checkout's HEAD"
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
        args = "[host]";
        summary = "Build this machine from the checkout and switch to it";
        group = "system";
      };
      deploy = {
        exec = "${flake}/scripts/deploy.sh";
        args = "[host] [address]";
        summary = "Build and switch another host over SSH";
        group = "system";
      };
      update = {
        exec = "${flake}/scripts/update.sh";
        args = "[input...]";
        summary = "Move flake.lock forward, then offer a rebuild";
        group = "system";
      };
      "secrets edit" = {
        exec = script "secrets-edit" [ ] ''
          cd ${lib.escapeShellArg flake}
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
            generation "''${generation%-link}" \
            built "''${built:-unknown}" \
            checkout "''${head:-unknown}''${dirty:+ (dirty)}"
          echo
          echo "$drift"
        '';
        summary = "What is running, and whether the checkout has moved since";
        group = "system";
      };

      doctor = {
        exec = script "doctor" [ pkgs.git pkgs.gawk ] ''
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

          section "Configuration"
          ${revisionCheck}
          echo "  $drift"

          section "Errors this boot"
          # Counted by message rather than listed in order: one chatty daemon repeating
          # itself every minute would otherwise be all the tail ever shows.
          journalctl -b -p err -q --no-pager -o short 2>/dev/null \
            | awk '{ $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); sub(/\[[0-9]+\]/, ""); print }' \
            | sort | uniq -c | sort -rn | head -n 5 \
            | awk 'NF > 1 { n = $1; $1 = ""; printf "  %6dx %s\n", n, substr($0, 2, 110) }' || true

          section "Space"
          df -h --output=target,avail,pcent / /nix 2>/dev/null | awk 'NR > 1 && !seen[$1]++ { print "  " $1 "  " $2 " free, " $3 " used" }'

          exit "$problems"
        '';
        summary = "Health check: failed units, config drift, boot errors, disk";
        group = "system";
      };
    };
  };
}
