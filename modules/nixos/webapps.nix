{ pkgs, ... }:
let
  # Firefox's own "Taskbar Tabs": a chromeless window onto one site, sharing the default
  # profile. That sharing is the point -- a firefoxpwa install would have given each app an
  # isolated profile, so every login would have to happen again on each host, and the
  # profile itself is imperative state no flake can carry. Here the logins, extensions and
  # Firefox Sync that the browser already has are simply the ones the web apps get.
  #
  # `-taskbar-tab <id>` is looked up in [Profile]/taskbartabs/taskbartabs.json, which
  # Firefox writes itself and warns against editing. Nothing here touches it: when the id
  # is absent the command-line handler reconstructs the entry from `-new-window` and
  # `-container` instead of failing (TaskbarTabsCmd.sys.mjs, "doesn't exist, reconstructing
  # it"). So the id only has to be stable, not pre-registered -- which is what lets the
  # same desktop entry land on both hosts and have each build its own registry on first
  # launch. Generate a fresh one with `uuidgen`; never reuse one across two apps.
  #
  # The argv mirrors what Firefox generates when you pin a tab by hand, minus `-profile`:
  # its own shortcuts hardcode the absolute profile path of whichever profile did the
  # pinning, and that path is random per machine. Leaving it off takes the default profile,
  # which is both portable and the one already signed in.
  webApp =
    {
      id,
      name,
      url,
      icon,
      categories,
    }:
    pkgs.makeDesktopItem {
      inherit icon categories;
      name = "lattice-webapp-${id}";
      desktopName = name;
      exec = "firefox -taskbar-tab ${id} -new-window ${url} -container 0";
      # Firefox names its own entries firefox.webapp-<uuid> and takes the Wayland app_id
      # from the glib prgname, so these windows most likely report app_id "firefox" like
      # any other. Check with `hyprctl clients` before writing a windowrule against them.
    };
in
{
  # Off by default on Linux as of Firefox 155 -- `pref("browser.taskbarTabs.enabled",
  # false)` in the shipped firefox.js. Status stays whatever the host set for its other
  # Firefox prefs ("default" on both), so this is still reachable from about:config.
  programs.firefox.preferences."browser.taskbarTabs.enabled" = true;

  environment.systemPackages = map webApp [
    # No Gemini mark in Papirus -- its gemini.svg is Calligra Gemini, a KDE office app.
    # This is a stand-in until a real one is vendored into assets/.
    {
      id = "fe0b1e57-cca8-48be-bd34-df63fa837afc";
      name = "Gemini";
      url = "https://gemini.google.com/app";
      icon = "accessories-text-editor";
      categories = [ "Network" ];
    }
    # Papirus ships one icloud.svg and no per-app variants, so both iCloud apps would wear
    # the same mark. Generic-but-distinct reads better in rofi than correct-but-identical.
    #
    # Note the two iCloud hostnames, and don't collapse them. A reconstructed entry is
    # looked up by exact hostname plus container, so a second app on www.icloud.com under
    # container 0 matches the first one's scope and opens *its* start URL instead -- launch
    # Reminders once and Calendar would only ever reopen Reminders. Navigation scope is the
    # looser of the two checks: it compares base domains, so the 301 from icloud.com to
    # www.icloud.com stays inside the window rather than spilling into a normal tab.
    # Separate containers would also split them, at the price of a second iCloud login;
    # distinct hostnames keep the single sign-on that made this approach worth having.
    {
      id = "7645277b-e07d-4154-9702-429745e77965";
      name = "Reminders";
      url = "https://www.icloud.com/reminders";
      icon = "gnome-todo";
      categories = [ "Office" ];
    }
    {
      id = "2ba60649-bb0b-4a45-9c82-7645a2a69578";
      name = "Calendar";
      url = "https://icloud.com/calendar";
      icon = "office-calendar";
      categories = [ "Office" ];
    }
  ];
}
