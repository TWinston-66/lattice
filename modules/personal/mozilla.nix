{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Neither the NixOS firefox nor the thunderbird module has a userChrome option and there is
  # no home-manager here, so the stylesheets are linked into the profiles directly. Both
  # profile directory names are generated at first run and are derivable from nothing in this
  # file: a new profile means the path has to be updated, and until it is the stylesheet
  # stops applying silently. Per-user for the same reason as the graphical profile's: the
  # greeter's user manager would otherwise try these under its own /var/empty home.
  systemd.user.tmpfiles.users.winston.rules =
    let
      linkChrome = profile: css: [
        "d ${profile}/chrome 0755 - - -"
        "L+ ${profile}/chrome/userChrome.css - - - - ${css}"
      ];

      firefoxProfile = "%h/.config/mozilla/firefox/uk8qrdih.default";
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
           a half tile on this panel (653 logical at 2.25), so Hyprland tiled the window
           narrower than Firefox would draw it and cropped the right side off, page and
           window controls alike. Back to the normal window's 500px floor, with the
           address bar's own minimum (275px for these windows) cut so the toolbar still
           fits at that width. */
        :root[taskbartab]:not([popup-window]) {
          min-width: 500px !important;
          --urlbar-container-min-width: 160px !important;
        }
      '';

      thunderbirdProfile = "%h/.config/thunderbird/7uftjt3v.default";
      thunderbirdUserChrome = pkgs.writeText "lattice-thunderbird-userChrome.css" ''
        /* Chrome font. messenger.css sets no font-size of its own, so the whole window
           inherits `font: message-box` from global-shared.css's :root -- the GTK font again
           (Noto Sans 9 -> 12px), and again a shorthand that resets font-size, so :root is
           where it has to be overridden rather than somewhere further down. Compact
           uidensity above only rewrites --space-base (6px -> 3px in spacings.css), which is
           padding and nothing else; the type stays 12px until this rule lands.

           This reaches every chrome document in the window -- the 3-pane, the spaces
           toolbar, dialogs -- which is the point. Message bodies are content documents and
           are untouched by userChrome.css, so reading size is still Ctrl+= / View > Zoom. */
        :root {
          font-size: 11px !important;
        }
      '';
    in
    linkChrome firefoxProfile firefoxUserChrome
    ++ linkChrome thunderbirdProfile thunderbirdUserChrome
    ++ [
      "L+ ${thunderbirdProfile}/user.js - - - - ${config.lattice.theme.runtimeTheme}/thunderbird-user.js"
    ];

  # The profile's user.js, as a runtime kit file so the calendar colours follow lattice-theme.
  # Thunderbird reads it at every startup and applies it to the user branch, so a switch lands
  # at the next launch, and a colour changed in the calendar's properties dialog lasts only
  # until then. Its other job is the pref the policy allowlist refuses for Thunderbird (see
  # programs.thunderbird above); anything settable through the module belongs there instead.
  #
  # The calendars are keyed by the UUID Thunderbird generated when each was added, which is
  # in nothing but this profile's prefs.js: a calendar removed and added again comes back
  # under a new one, and its line here stops applying silently. Palette slots rather than the
  # accent, since the accent moves with the wallpaper and a calendar's colour should not.
  lattice.theme.extraKitFiles."thunderbird-user.js" =
    { palette, ... }:
    let
      calendars = {
        "262193a3-8f90-4cc1-a7af-ad483a5c01bc" = palette.blue; # Gmail
        "bf0f94d8-2ec2-4e58-aae8-51872d804284" = palette.lavender; # Personal
        "53d36323-e22a-4766-bf98-ca03ed141c5f" = palette.yellow; # Work
        "5dd1668b-1a09-4ea4-b1a8-a92deda57d8c" = palette.teal; # School
        "a005c774-a761-4e47-947d-400e057738a4" = palette.green; # Tasks (local)
        "611a68b4-b613-4e04-8e8b-c1540f22923f" = palette.overlay1; # Holidays in United States
      };
    in
    ''
      user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (id: hex: ''
        user_pref("calendar.registry.${id}.color", "${hex}");
      '') calendars
    );
}
