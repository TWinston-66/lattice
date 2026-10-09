{
  config,
  lib,
  ...
}:
{
  # The calendars' colours, linked into the one Thunderbird profile they belong to. Its
  # directory name was generated at first run and is derivable from nothing in this file: a
  # new profile means the path has to be updated, and until it is the colours stop applying
  # silently. Per-user because the greeter's user manager would otherwise try this under its
  # own /var/empty home. The stylesheets are the distro's (desktop/mozilla.nix).
  systemd.user.tmpfiles.users.winston.rules = [
    "L+ %h/.config/thunderbird/7uftjt3v.default/user.js - - - - ${config.lattice.theme.runtimeTheme}/thunderbird-user.js"
  ];

  # The profile's user.js, as a runtime kit file so the calendar colours follow lattice-theme.
  # Thunderbird reads it at every startup and applies it to the user branch, so a switch lands
  # at the next launch, and a colour changed in the calendar's properties dialog lasts only
  # until then.
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
    lib.concatStrings (
      lib.mapAttrsToList (id: hex: ''
        user_pref("calendar.registry.${id}.color", "${hex}");
      '') calendars
    );
}
