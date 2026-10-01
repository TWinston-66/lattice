{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = config.lattice.theme;
  inherit (theme) palette;

  json = pkgs.formats.json { };

  # Nix has no escape for ESC and nixfmt rewrites an indented-string \u001b into a raw
  # control byte, so the one form that survives a format is a double-quoted JSON escape.
  esc = builtins.fromJSON "\"\\u001b\"";
  fg = colour: "${esc}[38;2;${theme.rgbOf colour}m";
  reset = "${esc}[0m";

  # The same hexagonal lattice as .github/assets/logo.svg, drawn for a terminal. The SVG's
  # five node rows carry 3/4/5/4/3 nodes, and its edges come in two opacities -- 0.75 for the
  # inner hexagon, 0.32 for the outer ring -- so both the shape and that fade are reproduced
  # here rather than flattened onto a single edge colour.
  #
  # Generated rather than written out as a template, because the fade makes the colour of a
  # cell depend on which nodes its edge joins: a hand-drawn version would need a letter per
  # glyph-and-colour pair and stop reading as art in the source.
  lattice =
    let
      rows = [
        3
        4
        5
        4
        3
      ];
      last = lib.length rows - 1;
      widest = lib.foldl' lib.max 0 rows;
      middle = last / 2;

      # Rows a diagonal edge is drawn over. A diagonal advances one column per row, so it
      # spans `diagonals + 1` columns and the node columns have to sit twice that apart for
      # the slope to stay clean. 1 gives the original 17x9 art, 2 the 25x13 one, 3 a 33x17
      # one -- which is as far as this goes before the longest module line passes 80 columns.
      diagonals = 2;
      gap = diagonals + 1;
      step = 2 * gap;

      width = (widest - 1) * step + 1;
      height = lib.length rows + last * diagonals;

      # Node columns for a row of n nodes, centred in the field.
      colsOf = n: lib.genList (i: (widest - n) * step / 2 + i * step) n;
      indices = xs: lib.genList (i: i) (lib.length xs);

      # Which of the three node colours a node takes: the outer ring is every node on the
      # first or last row or at either end of its own row, the centre is the middle node of
      # the middle row, and the six that are neither make up the inner hexagon.
      kindOf =
        r: c:
        let
          n = lib.elemAt rows r;
        in
        if r == middle && c == n / 2 then
          "centre"
        else if r == 0 || r == last || c == 0 || c == n - 1 then
          "outer"
        else
          "inner";

      # An edge is part of the inner hexagon only if neither end is on the outer ring, which
      # is exactly the 0.75-opacity set in the SVG.
      edgeColour = a: b: if a == "outer" || b == "outer" then palette.surface1 else palette.overlay1;

      cell =
        y: x: ch: colour:
        lib.nameValuePair "${toString y},${toString x}" { inherit ch colour; };

      horizontals = lib.concatMap (
        r:
        let
          cols = colsOf (lib.elemAt rows r);
          y = r * gap;
        in
        lib.concatMap (
          c:
          let
            from = lib.elemAt cols c;
            to = lib.elemAt cols (c + 1);
          in
          lib.genList (i: cell y (from + 1 + i) "─" (edgeColour (kindOf r c) (kindOf r (c + 1)))) (
            to - from - 1
          )
        ) (lib.genList (c: c) (lib.length cols - 1))
      ) (indices rows);

      # Only the pairs one half-step apart are joined, which is what keeps this a triangular
      # lattice rather than every node on one row reaching every node on the next.
      diagonalEdges = lib.concatMap (
        r:
        let
          top = colsOf (lib.elemAt rows r);
          bottom = colsOf (lib.elemAt rows (r + 1));
        in
        lib.concatMap (
          t:
          lib.concatMap (
            b:
            let
              from = lib.elemAt top t;
              to = lib.elemAt bottom b;
              leans = if to > from then 1 else -1;
            in
            lib.optionals (to - from == gap || from - to == gap) (
              lib.genList (
                s:
                cell (r * gap + s + 1) (from + leans * (s + 1)) (if leans == 1 then "╲" else "╱") (
                  edgeColour (kindOf r t) (kindOf (r + 1) b)
                )
              ) diagonals
            )
          ) (indices bottom)
        ) (indices top)
      ) (lib.genList (r: r) last);

      nodes = lib.concatMap (
        r:
        let
          cols = colsOf (lib.elemAt rows r);
        in
        lib.genList (
          c:
          cell (r * gap) (lib.elemAt cols c) "●"
            {
              outer = theme.accentHex;
              inner = theme.accentAltHex;
              centre = palette.text;
            }
            .${kindOf r c}
        ) (lib.length cols)
      ) (indices rows);

      # Nodes merge last, so a node wins the cell the edges meeting it also want.
      cells = lib.listToAttrs (horizontals ++ diagonalEdges) // lib.listToAttrs nodes;

      # A glyph carries its colour only when it differs from the one before it on the row, and
      # a gap does not end the run: nothing here paints a background, so the colour survives
      # the spaces between two edges of the same tier. Each row closes with a reset, so it is
      # legible on its own and nothing bleeds into the module output beside it.
      row =
        y:
        (lib.foldl'
          (
            acc: x:
            let
              at = cells."${toString y},${toString x}" or null;
            in
            if at == null then
              acc // { out = acc.out + " "; }
            else
              acc
              // {
                out = acc.out + (if acc.colour == at.colour then "" else fg at.colour) + at.ch;
                colour = at.colour;
              }
          )
          {
            out = "";
            colour = null;
          }
          (lib.genList (x: x) width)
        ).out
        + reset;
    in
    {
      inherit width height;
      art = lib.concatMapStringsSep "\n" row (lib.genList (y: y) height) + "\n";
    };

  # The commit this system was built from, shortened for the fetch and marked with a `+` when
  # the tree it came out of was dirty. flake.nix has no `self.rev` for a dirty tree, so
  # dirtyRev -- the same hash with a `-dirty` suffix -- is what carries it in that case.
  revision =
    let
      rev = config.system.configurationRevision;
    in
    lib.optionalString (rev != null) (
      " · ${lib.substring 0 7 rev}${lib.optionalString (lib.hasSuffix "-dirty" rev) "+"}"
    );

  key = "38;2;${theme.accentRgb}";

  info = type: name: {
    inherit type;
    key = name;
    keyColor = key;
  };

  # A module that leads with a percentage bar and then says the same thing in numbers. The
  # bar's format variable is named after the module's own quantity rather than being common
  # across them, so it is passed in.
  gauge =
    type: name: format:
    (info type name) // { inherit format; };

  modules = [
    "break"
    {
      type = "title";
      keyColor = key;
    }
    {
      type = "separator";
      string = "─";
    }
    ((info "os" "os") // { format = "{name} {version-id} {arch}"; })
    (info "kernel" "kernel")
    (info "uptime" "uptime")
    (info "packages" "pkgs")
    (
      (info "command" "gen")
      // {
        # The generation the running system is, which is the number `nixos-rebuild` prints that
        # is worth keeping in sight. Read with shell parameter expansion rather than sed, so the
        # line does not depend on anything being on fastfetch's PATH.
        text = "p=$(readlink /nix/var/nix/profiles/system); p=\${p#system-}; echo \${p%-link}";
        format = "{result}${revision}";
      }
    )
    (info "shell" "shell")
    (info "terminal" "term")
    ((info "wm" "wm") // { format = "{pretty-name} ({protocol-name})"; })
    # Stated from the theme options rather than read back at runtime: the `theme` module
    # reports the GTK theme with a "[GTK2/3/4]" suffix baked into its one format variable,
    # and this is the setting that produced that name in the first place.
    {
      type = "custom";
      key = "theme";
      keyColor = key;
      format = "${theme.flavor} · ${theme.accent}";
    }
    (info "cpu" "cpu")
    ((info "gpu" "gpu") // { format = "{name}"; })
    (gauge "memory" "memory" "{percentage-bar} {percentage} {used} / {total}")
    # btrfs rather than disk: it is the filesystem on both hosts, and it is the only one of
    # the two that can report allocated space, which is the number that actually runs out.
    (gauge "btrfs" "disk" "{used-percentage-bar} {used-percentage} {used} / {total}")
    (gauge "battery" "battery" "{capacity-bar} {capacity} {status}")
    # One line per output, so this is two lines while docked.
    ((info "display" "screen") // { format = "{scaled-width}x{scaled-height} @ {refresh-rate} Hz"; })
    "break"
    {
      type = "colors";
      symbol = "block";
    }
  ];

  # What the logo is centred against. One line per module, plus one for the second row the
  # colours block prints.
  infoLines = lib.length modules + 1;
in
{
  imports = [ ./theme.nix ];

  ### OS IDENTITY ###
  # What `nixos-version --configuration-revision` reports, and what the fetch's `gen` line
  # shows beside the generation number. `self.rev` is unset whenever the tree is dirty, which
  # for a config that is edited and rebuilt in place is most of the time, so dirtyRev is the
  # one that usually answers.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  system.nixos = {
    distroId = "lattice";
    distroName = "lattice";
    vendorId = "lattice";
    vendorName = "lattice";
    extraOSReleaseArgs = {
      PRETTY_NAME = "lattice ${config.system.nixos.release}";
      HOME_URL = "https://github.com/TWinston-66/lattice";
      LOGO = "lattice";
      ANSI_COLOR = "38;2;${theme.accentRgb}";
    };
  };

  # The hicolor icon every LOGO= consumer picks up, recoloured to the live accent.
  environment.systemPackages = [
    pkgs.fastfetch
    (pkgs.runCommand "lattice-logo" { } ''
      install -Dm644 ${
        theme.recolourSvg {
          name = "lattice-logo.svg";
          src = ../../.github/assets/logo.svg;
        }
      } $out/share/icons/hicolor/scalable/apps/lattice.svg
    '')
  ];

  ### FASTFETCH ###
  # /etc/xdg is on fastfetch's search path, so this is the system-wide default and a
  # ~/.config/fastfetch still wins. The art arrives pre-coloured, hence file-raw and an
  # explicit width/height: fastfetch would otherwise count the escape bytes as columns.
  environment.etc = {
    "xdg/fastfetch/lattice.txt".text = lattice.art;

    "xdg/fastfetch/config.jsonc".source = json.generate "fastfetch-config.jsonc" {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";

      logo = {
        type = "file-raw";
        source = "/etc/xdg/fastfetch/lattice.txt";
        inherit (lattice) width height;
        padding = {
          # The one thing that moves the art relative to the modules: padding.top pushes the
          # logo down while the modules stay at the top of the output, so this is what centres
          # the hexagon against the taller info column instead of leaving it top-aligned. A
          # second monitor adds a display line and puts it half a row out, which is not worth
          # making dynamic.
          top = (infoLines - lattice.height) / 2;
          left = 2;
          right = 3;
        };
      };

      display = {
        separator = "  ";
        # Pads the key column so the values line up; "battery" is the longest key.
        key.width = 8;

        # A monochrome accent bar, because bar.color.elapsed overrides the green/yellow/red
        # the bar would otherwise take from the thresholds below -- those stay on the number
        # beside it, where a colour change reads as a warning rather than as decoration.
        bar = {
          char = {
            elapsed = "━";
            total = "━";
          };
          width = 10;
          border = {
            left = "";
            right = "";
          };
          color = {
            elapsed = key;
            total = "38;2;${theme.rgbOf palette.surface1}";
          };
        };

        # 11 is number-and-bar with the number coloured. Every lower value silently drops one
        # half of that: 1 and 9 render no bar, 6 and 10 render no number.
        percent = {
          type = 11;
          ndigits = 0;
          color = {
            green = "38;2;${theme.rgbOf palette.green}";
            yellow = "38;2;${theme.rgbOf palette.yellow}";
            red = "38;2;${theme.rgbOf palette.red}";
          };
        };
      };

      inherit modules;
    };
  };

  # console.colors comes from ./theme.nix.
}
