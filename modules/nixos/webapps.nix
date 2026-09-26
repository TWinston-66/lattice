{ pkgs, lib, ... }:
let
  # Firefox's own "Taskbar Tabs": a chromeless window onto one site, sharing the default
  # profile. That sharing is the point -- a firefoxpwa install would have given each app an
  # isolated profile, so every login would have to happen again on each host, and the
  # profile itself is imperative state no flake can carry. Here the logins, extensions and
  # Firefox Sync that the browser already has are simply the ones the web apps get.
  #
  # `-taskbar-tab <id>` is looked up in [Profile]/taskbartabs/taskbartabs.json. An id that
  # isn't in there does NOT fail, but it does not survive either: TaskbarTabsCmd.sys.mjs
  # catches the miss, logs "doesn't exist, reconstructing it", and calls
  # findOrCreateTaskbarTab(url, userContextId) -- *without* forwarding the id it was given.
  # Firefox mints a fresh uuid, and because that counts as `created` it also pins a new
  # shortcut, which on Linux means a second .desktop written into
  # ~/.local/share/applications. So an unregistered id costs a permanent duplicate launcher
  # entry on first launch, named from the page title and pointing at the scope root rather
  # than the deep URL asked for. Measured on Firefox 155: launching Gemini this way left a
  # twin called "Google Gemini" on https://gemini.google.com, minus the /app.
  #
  # Hence seedRegistry below: the declared ids are written into the registry before first
  # launch, so the lookup hits and the reconstruction path never runs. Generate a fresh id
  # with `uuidgen`; never reuse one across two apps.
  #
  # The argv mirrors what Firefox generates when you pin a tab by hand, minus `-profile`:
  # its own shortcuts hardcode the absolute profile path of whichever profile did the
  # pinning, and that path is random per machine. Leaving it off takes the default profile,
  # which is both portable and the one already signed in.
  apps = [
    # Neither of these has a usable mark in Papirus -- its gemini.svg is Calligra Gemini,
    # a KDE office app, and there is no claude.svg at all -- so webAppIcons below installs
    # both into hicolor. The files are stand-ins drawn for this, not the vendors' assets;
    # .github/assets/gemini.svg and claude.svg each say what to do about that.
    {
      id = "fe0b1e57-cca8-48be-bd34-df63fa837afc";
      name = "Gemini";
      url = "https://gemini.google.com/app";
      hostname = "gemini.google.com";
      icon = "lattice-gemini";
      categories = [ "Network" ];
    }
    {
      id = "a7c62fd4-e771-4988-8efa-c046dd773719";
      name = "Claude";
      url = "https://claude.ai/new";
      hostname = "claude.ai";
      icon = "lattice-claude";
      categories = [ "Network" ];
    }
    # Papirus does have an apple-music mark, so this one needs no stand-in.
    #
    # Everything here plays through Widevine, which Firefox installs itself on x86_64 and
    # cannot on aarch64 -- modules/nixos/widevine.nix is what makes this app more than a
    # window on the Mac. Sign-in is an overlay served from music.apple.com rather than a
    # navigation to an Apple ID domain, so it stays inside the scope below.
    {
      id = "7112a47e-a16c-4a6a-a025-02a8366d7c3d";
      name = "Apple Music";
      url = "https://music.apple.com/us/home";
      hostname = "music.apple.com";
      icon = "apple-music";
      categories = [
        "AudioVideo"
        "Audio"
      ];
    }
    # Papirus ships one icloud.svg and no per-app variants, so both iCloud apps would wear
    # the same mark. Generic-but-distinct reads better in rofi than correct-but-identical.
    #
    # Note the two iCloud hostnames, and don't collapse them. A registered entry is matched
    # by exact hostname plus container, so a second app on www.icloud.com under container 0
    # matches the first one's scope and opens *its* start URL instead -- launch Reminders
    # once and Calendar would only ever reopen Reminders. Navigation scope is the looser of
    # the two checks: it compares base domains, so the 301 from icloud.com to
    # www.icloud.com stays inside the window rather than spilling into a normal tab.
    # Separate containers would also split them, at the price of a second iCloud login;
    # distinct hostnames keep the single sign-on that made this approach worth having.
    {
      id = "7645277b-e07d-4154-9702-429745e77965";
      name = "Reminders";
      url = "https://www.icloud.com/reminders";
      hostname = "www.icloud.com";
      icon = "gnome-todo";
      categories = [ "Office" ];
    }
    {
      id = "2ba60649-bb0b-4a45-9c82-7645a2a69578";
      name = "Calendar";
      url = "https://icloud.com/calendar";
      hostname = "icloud.com";
      icon = "office-calendar";
      categories = [ "Office" ];
    }
  ];

  webApp =
    {
      id,
      name,
      url,
      icon,
      categories,
      ...
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

  # Icons for the web apps that no installed theme has a mark for. Papirus-Dark falls
  # through to hicolor, so installing here is enough to be found by name -- no icon-theme
  # change, and `gtk-update-icon-cache` is not needed for an uncached hicolor lookup.
  # Same shape as the lattice logo in modules/nixos/branding.nix.
  webAppIcons = pkgs.runCommand "lattice-webapp-icons" { } ''
    install -Dm644 ${../../.github/assets/gemini.svg} \
      $out/share/icons/hicolor/scalable/apps/lattice-gemini.svg
    install -Dm644 ${../../.github/assets/claude.svg} \
      $out/share/icons/hicolor/scalable/apps/lattice-claude.svg
  '';

  # The declared half of the registry, in the shape TaskbarTabs.1.schema.json asks for.
  # Only id, scopes, userContextId and startUrl are required; `name` is carried anyway
  # because it titles the window. shortcutRelativePath is deliberately absent -- it is
  # what ties a registry entry to a Firefox-written .desktop, and these entries are backed
  # by makeDesktopItem instead.
  declared = pkgs.writeText "lattice-taskbartabs.json" (
    builtins.toJSON {
      version = 1;
      taskbarTabs = map (a: {
        inherit (a) id name;
        scopes = [ { inherit (a) hostname; } ];
        userContextId = 0;
        startUrl = a.url;
      }) apps;
    }
  );

  # Merges the declared entries into the profile's registry, adding only ids that aren't
  # there yet. It never edits or removes an entry Firefox wrote: a tab pinned by hand is
  # the user's, and the only thing this needs is for its own ids to resolve.
  seedRegistry = pkgs.writeShellApplication {
    name = "lattice-webapp-seed";
    runtimeInputs = [
      pkgs.jq
      pkgs.procps
    ];
    text = ''
      # Firefox keeps the registry in memory and rewrites the whole file on exit, so a
      # merge landed underneath a running browser is simply discarded. Skipping is right
      # rather than fatal: the unit runs at every session start, and by the next one the
      # browser will have been closed at least once.
      if pgrep -x firefox >/dev/null 2>&1; then
        echo "firefox is running; leaving the Taskbar Tabs registry alone"
        exit 0
      fi

      root="''${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
      ini="$root/profiles.ini"
      if [ ! -f "$ini" ]; then
        echo "no profiles.ini at $ini; nothing to seed"
        exit 0
      fi

      # The default profile's directory name is random per machine, so it has to be read
      # rather than hardcoded. Only [Profile*] sections are considered: an [Install*]
      # section also carries a Default= key, but its value is a path, not a flag.
      read -r relative path <<< "$(awk -F'\n' '
        /^\[/  { sec = $0; next }
        sec ~ /^\[Profile/ && /^Path=/        { p[sec] = substr($0, 6) }
        sec ~ /^\[Profile/ && /^IsRelative=/  { r[sec] = substr($0, 12) }
        sec ~ /^\[Profile/ && /^Default=1$/   { d[sec] = 1 }
        END {
          for (s in d)     { print (r[s] == "0" ? "abs" : "rel"), p[s]; exit }
          for (s in p)     { print (r[s] == "0" ? "abs" : "rel"), p[s]; exit }
        }
      ' "$ini")"

      if [ -z "''${path:-}" ]; then
        echo "no profile with a Path in $ini; nothing to seed"
        exit 0
      fi
      if [ "$relative" = rel ]; then profile="$root/$path"; else profile="$path"; fi

      reg="$profile/taskbartabs/taskbartabs.json"
      mkdir -p "$(dirname "$reg")"
      [ -f "$reg" ] || printf '{"version":1,"taskbarTabs":[]}' > "$reg"

      # An unreadable or future-versioned registry is left alone rather than rewritten:
      # the schema is Firefox's, and guessing at version 2 would lose whatever it holds.
      if ! jq -e '.version == 1' "$reg" >/dev/null 2>&1; then
        echo "$reg is not a version 1 registry; leaving it alone" >&2
        exit 0
      fi

      # Written to a temporary file and moved into place, so a jq failure leaves the
      # existing registry untouched rather than truncated.
      tmp="$(mktemp "$reg.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      jq -s '
        (.[0].taskbarTabs) as $declared
        | (.[1].taskbarTabs // []) as $live
        | ($live | map(.id)) as $known
        | { version: 1,
            taskbarTabs: ($live + ($declared | map(select(.id as $i | $known | index($i) | not)))) }
      ' "${declared}" "$reg" > "$tmp"

      added="$(( $(jq '.taskbarTabs | length' "$tmp") - $(jq '.taskbarTabs | length' "$reg") ))"
      mv "$tmp" "$reg"
      trap - EXIT
      echo "seeded $added web app(s) into $reg"
    '';
  };
in
{
  # Off by default on Linux as of Firefox 155 -- `pref("browser.taskbarTabs.enabled",
  # false)` in the shipped firefox.js. Status stays whatever the host set for its other
  # Firefox prefs ("default" on both), so this is still reachable from about:config.
  programs.firefox.preferences."browser.taskbarTabs.enabled" = true;

  environment.systemPackages = [
    webAppIcons
    # On PATH too, so the merge can be re-run by hand after editing `apps` without
    # waiting for the next session.
    seedRegistry
  ]
  ++ map webApp apps;

  # At session start rather than at activation: the registry lives in the user's home, and
  # this is the moment the browser is reliably not running. It is a oneshot with no
  # ordering against anything but the target -- nothing else reads the file, and Firefox
  # cannot have opened it yet.
  systemd.user.services.lattice-webapp-seed = {
    description = "Seed Firefox's Taskbar Tabs registry with lattice's web apps";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    # A oneshot that failed leaves no trace in the UI except web apps that are missing from
    # rofi, which is easy to read as never having added them.
    onFailure = [ "lattice-notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe seedRegistry;
    };
  };
}
