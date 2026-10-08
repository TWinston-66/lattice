{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) appWindow;

  # The guides, in the order the page lists them. The text is docs/<id>.md -- the same files
  # the README links to on GitHub -- so a guide is written once and read either way. That
  # matters most for install and recovery, which are needed on a machine with no lattice
  # running.
  guides = [
    "using"
    "install"
    "backups"
    "recovery"
    "configuring"
  ];

  # guides.html with every guide rendered by cmark-gfm and inlined, plus the theme table it
  # shares with the cheatsheet, so the page opens from file:// with nothing to fetch. The
  # live values go in at @LIVE@ when `lattice guide` writes it out. "</" is escaped so a
  # </code> in a guide can't close the script element early.
  page =
    pkgs.runCommand "lattice-guides.html"
      {
        nativeBuildInputs = [
          pkgs.cmark-gfm
          pkgs.jq
          pkgs.gawk
          pkgs.gnused
        ];
      }
      ''
        for id in ${lib.escapeShellArgs guides}; do
          cmark-gfm -e table -e autolink -e strikethrough --unsafe ${../../../docs}/$id.md \
            | jq -R -s --arg id "$id" '{id: $id, html: .}'
        done | jq -c -s . | sed 's#</#<\\/#g' > guides.json
        awk -v f=guides.json -v t=${./page-themes.json} '
          $0 == "@GUIDES@" { while ((getline l < f) > 0) print l; next }
          $0 == "@THEMES@" { while ((getline l < t) > 0) print l; next }
          { print }
        ' ${./guides/guides.html} > $out
      '';

  guide = pkgs.writeShellApplication {
    name = "lattice-guide";
    runtimeInputs = [
      appWindow
      pkgs.jq
      pkgs.coreutils
      pkgs.gawk
      pkgs.hostname
      pkgs.util-linux
    ];
    text = ''
      # `keys` is the keybinding cheatsheet, which stays its own page: it is regenerated
      # from the running configs on every open and laid out as a grid, not a column of
      # prose. This only makes `lattice guide` the one command to remember. `--write`
      # writes the page without opening it, for the cheatsheet's link back here.
      write=false
      case ''${1-} in
        keys)
          shift
          exec ${config.lattice.cli.commands.cheatsheet.exec} "$@"
          ;;
        --write)
          write=true
          shift
          ;;
        "" | ${lib.concatStringsSep " | " guides}) ;;
        *)
          echo "lattice guide: no guide called '$1' (${lib.concatStringsSep ", " guides}, keys)" >&2
          exit 2
          ;;
      esac
      out="''${XDG_CACHE_HOME:-$HOME/.cache}/lattice/guides.html"
      theme=$(lattice theme current 2>/dev/null) || theme=""
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      jq -n -c --arg theme "$theme" --arg hostname "$(hostname)" --arg generated "$(date '+%Y-%m-%d %H:%M')" \
        --argjson zoom ${toString config.lattice.display.webZoom} \
        '{theme: $theme, hostname: $hostname, generated: $generated, zoom: $zoom}' > "$tmp/live.json"
      awk -v f="$tmp/live.json" '$0 == "@LIVE@" { while ((getline l < f) > 0) print l; next } { print }' \
        ${page} > "$tmp/guides.html"
      mkdir -p "$(dirname "$out")"
      cp "$tmp/guides.html" "$out"
      $write && exit 0
      lattice-app-window "$out" "''${1-}"

      # The sidebar links to the cheatsheet, so write a fresh one behind the window. Detached:
      # reading the live configs takes a few seconds, and the guides shouldn't wait on it.
      setsid -f ${config.lattice.cli.commands.keys.exec} page >/dev/null 2>&1 </dev/null || true
    '';
  };

  guidesItem = pkgs.makeDesktopItem {
    name = "lattice-guides";
    desktopName = "Lattice Guides";
    genericName = "Install, backup and recovery guides";
    exec = lib.getExe guide;
    icon = "help-contents";
    categories = [ "Utility" ];
    keywords = [
      "help"
      "docs"
      "manual"
      "guide"
      "install"
      "backup"
      "restore"
      "recovery"
    ];
  };
in
{
  environment.systemPackages = [
    guide
    guidesItem
  ];

  lattice.cli.commands.guide = {
    exec = lib.getExe guide;
    args = "[${lib.concatStringsSep "|" (guides ++ [ "keys" ])}]";
    summary = "Open the lattice guides; `keys` opens the keybinding cheatsheet";
    group = "session";
    launch = [
      {
        label = "Lattice guides";
        icon = "help-contents";
      }
    ];
  };
}
