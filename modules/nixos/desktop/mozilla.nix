{
  lib,
  pkgs,
  ...
}:
let
  # The chrome stylesheets that finish what compact uidensity leaves alone on the Mac's
  # panel (see the FIREFOX block in hardware/apple-silicon.nix for the scaling they go with).
  firefoxUserChrome = pkgs.writeText "lattice-firefox-userChrome.css" ''
    /* Chrome font. Much of the chrome -- the vertical tab strip among it -- draws with
       `font: menu`, which resolves to the GTK font (gtk-font-name, Noto Sans 9 -> 12px)
       and resets font-size as part of the shorthand, so a smaller size inherited from
       :root never reaches it; setting the resolved size directly is what bites. These
       stay CSS pixels, which devPixelsPerPx goes on scaling per monitor. */
    #navigator-toolbox,
    #sidebar-main,
    #vertical-tabs {
      font-size: 10px !important;
    }

    /* Vertical tab rows. Under the sidebar.verticalTabs pref tabs.css sizes these as
       max(32px, line-height * 1em), so the 32px floor has to come down explicitly --
       the horizontal strip's own --tab-min-height never applies in this mode. */
    :root {
      --tab-min-height: 24px !important;
    }

    /* Web-app (Taskbar Tab) windows. browser-shared.css floors them at 804px wide
       because their toolbar has no overflow menu to shed buttons into -- wider than
       a half tile on a MacBook panel (653 logical at 2.25), so Hyprland tiled the window
       narrower than Firefox would draw it and cropped the right side off, page and
       window controls alike. Back to the normal window's 500px floor, with the
       address bar's own minimum (275px for these windows) cut so the toolbar still
       fits at that width. */
    :root[taskbartab]:not([popup-window]) {
      min-width: 500px !important;
      --urlbar-container-min-width: 160px !important;
    }
  '';

  thunderbirdUserChrome = pkgs.writeText "lattice-thunderbird-userChrome.css" ''
    /* Chrome font. messenger.css sets no font-size of its own, so the whole window
       inherits `font: message-box` from global-shared.css's :root -- the GTK font again
       (Noto Sans 9 -> 12px), and again a shorthand that resets font-size, so :root is
       where it has to be overridden rather than somewhere further down. Compact
       uidensity only rewrites --space-base (6px -> 3px in spacings.css), which is
       padding and nothing else; the type stays 12px until this rule lands.

       This reaches every chrome document in the window -- the 3-pane, the spaces
       toolbar, dialogs -- which is the point. Message bodies are content documents and
       are untouched by userChrome.css, so reading size is still Ctrl+= / View > Zoom. */
    :root {
      font-size: 11px !important;
    }
  '';

  # Profile directory names are random per profile, so rather than naming one, every
  # profile in each app's profiles.ini gets the stylesheet. A userChrome.css of the user's
  # own -- anything but a link into the store -- is left alone.
  linkChrome = pkgs.writeShellApplication {
    name = "lattice-mozilla-chrome";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      link() {
        local root=$1 css=$2 profile target
        [[ -f $root/profiles.ini ]] || return 0
        awk -F= -v root="$root" '
          /^\[/ { sec = $0; next }
          sec ~ /^\[Profile/ && $1 == "Path"       { p[sec] = substr($0, 6) }
          sec ~ /^\[Profile/ && $1 == "IsRelative" { r[sec] = $2 }
          END { for (s in p) print (r[s] == "0" ? "" : root "/") p[s] }
        ' "$root/profiles.ini" | while IFS= read -r profile; do
          [[ -d $profile ]] || continue
          target=$profile/chrome/userChrome.css
          if [[ -e $target || -L $target ]] && [[ $(readlink "$target") != /nix/store/* ]]; then
            echo "$target is the user's own; leaving it"
            continue
          fi
          mkdir -p "$profile/chrome"
          ln -sfn "$css" "$target"
        done
      }

      config=''${XDG_CONFIG_HOME:-$HOME/.config}
      link "$config/mozilla/firefox" ${firefoxUserChrome}
      link "$config/thunderbird" ${thunderbirdUserChrome}
    '';
  };
in
{
  # Thunderbird's module funnels `preferences` through the enterprise policy allowlist,
  # which has no `toolkit.` entry, so the pref that lets it read userChrome.css at all is
  # set in the wrapper's autoconfig instead. Firefox's allowlist carries it, so Firefox's
  # rides programs.firefox.preferences (hardware/apple-silicon.nix).
  programs.thunderbird.package = pkgs.wrapThunderbird pkgs.thunderbird-unwrapped {
    extraPrefs = ''
      pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    '';
  };

  # At every login, so a rebuild's new stylesheet lands, and whenever either app writes its
  # profiles.ini, which is how a first launch or a new profile shows up. The apps read
  # userChrome.css at startup, so a new profile takes it from its second launch.
  systemd.user.services.lattice-mozilla-chrome = {
    description = "Link lattice's userChrome.css into every Firefox and Thunderbird profile";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    onFailure = [ "lattice-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe linkChrome;
    };
  };
  systemd.user.paths.lattice-mozilla-chrome = {
    wantedBy = [ "graphical-session.target" ];
    pathConfig.PathChanged = [
      "%h/.config/mozilla/firefox/profiles.ini"
      "%h/.config/thunderbird/profiles.ini"
    ];
  };
}
