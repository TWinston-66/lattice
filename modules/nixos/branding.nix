{
  config,
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

  # The same hexagonal lattice as .github/assets/logo.svg, drawn for a terminal: twelve
  # accent nodes on the outer ring, six accentAlt inside, one text node at the centre.
  # A/B/C are the only Latin letters in the template, so they double as the substitutions.
  logo =
    let
      node = colour: "${fg colour}●${fg palette.overlay0}";
      art =
        builtins.replaceStrings
          [ "A" "B" "C" ]
          [
            (node theme.accentHex)
            (node theme.accentAltHex)
            (node palette.text)
          ]
          ''
                A───A───A
               ╱ ╲ ╱ ╲ ╱ ╲
              A───B───B───A
             ╱ ╲ ╱ ╲ ╱ ╲ ╱ ╲
            A───B───C───B───A
             ╲ ╱ ╲ ╱ ╲ ╱ ╲ ╱
              A───B───B───A
               ╲ ╱ ╲ ╱ ╲ ╱
                A───A───A
          '';
      # Each row opens with the edge colour and closes with a reset, so a row is legible
      # on its own and nothing bleeds into the module output beside it.
      row = l: "${fg palette.overlay0}${l}${reset}";
    in
    lib.concatMapStringsSep "\n" row (lib.init (lib.splitString "\n" art)) + "\n";

  key = "38;2;${theme.accentRgb}";

  info = type: name: {
    inherit type;
    key = name;
    keyColor = key;
  };
in
{
  imports = [ ./theme.nix ];

  ### OS IDENTITY ###
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
    "xdg/fastfetch/lattice.txt".text = logo;

    "xdg/fastfetch/config.jsonc".source = json.generate "fastfetch-config.jsonc" {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";

      logo = {
        type = "file-raw";
        source = "/etc/xdg/fastfetch/lattice.txt";
        width = 17;
        height = 9;
        padding = {
          top = 1;
          left = 2;
          right = 3;
        };
      };

      display = {
        separator = "  ";
        # Pads the key column so the values line up; "packages" is the longest key.
        key.width = 8;
      };

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
        (info "os" "os")
        (info "kernel" "kernel")
        (info "uptime" "uptime")
        (info "packages" "packages")
        (info "shell" "shell")
        (info "wm" "wm")
        (info "terminal" "term")
        (info "cpu" "cpu")
        (info "gpu" "gpu")
        (info "memory" "memory")
        (info "disk" "disk")
        "break"
        {
          type = "colors";
          symbol = "circle";
        }
      ];
    };
  };

  # console.colors comes from ./theme.nix.
}
