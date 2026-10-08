{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Opens the NuPhy Halo65 V2's raw-HID node to whoever holds the seat, so the keyboard can
  # be remapped from nuphy.io in the Chromium below. The board is QMK underneath: its
  # interface 1 reports usage page 0xFF60, QMK's raw-HID endpoint and the transport both
  # NuPhy Console and VIA speak. That node is root-only by default, and the resulting
  # failure is badly disguised -- the WebHID chooser comes up empty and reads as "no
  # compatible devices found", which looks like the site not supporting the keyboard
  # rather than like a permission problem.
  #
  # This is a udev *package* rather than services.udev.extraRules, and that is the whole
  # point of it. uaccess is not applied by the rule that sets the tag; systemd's
  # 73-seat-late.rules is what turns TAG+="uaccess" into an ACL. extraRules is hardcoded
  # into 99-local.rules, which udev reaches long after 73, so the tag is set after the
  # only rule that would consume it and nothing happens -- silently, with the rule
  # present and correct in the file. Numbering this below 73 is what makes it fire, and
  # is why the MX Master's own rule ships at 42. udev.packages takes the filename from
  # the destination, so the 60- prefix here is load-bearing.
  #
  # pkgs.qmk-udev-rules is no substitute: all 89 of its lines are bootloader VID/PIDs for
  # flashing, and none touch hidraw on a running board.
  #
  # Scoped to the one product and to hidraw only. The evdev nodes stay shut -- remapping
  # happens in the keyboard's own firmware, so nothing here needs to read keystrokes.
  nuphyHidAccess = pkgs.writeTextFile {
    name = "nuphy-halo65-udev-rules";
    destination = "/lib/udev/rules.d/60-nuphy-halo65.rules";
    text = ''
      KERNEL=="hidraw*", ATTRS{idVendor}=="19f5", ATTRS{idProduct}=="3315", TAG+="uaccess"
    '';
  };

  # Vesktop passes itself off as desktop Chrome, and on Linux it hardcodes the x86_64
  # string whatever the arch. Discord's edge 403s exactly that string (2026-10-04, Vesktop
  # 1.6.7): the window shows a "Temporary Network Error" page with a Request ID that
  # reload never clears, while discordstatus.com reports everything up. The same UA with
  # "Linux aarch64" loads fine, so this sends the machine's real arch. The Chrome major
  # tracks the Electron Vesktop runs on, like Vesktop's own string does.
  #
  # Not seen on the Dell, where the substitution is a no-op: if Discord blocks the x86_64
  # string there too, --user-agent-os=windows is Vesktop's own escape hatch.
  vesktop = pkgs.symlinkJoin {
    name = "vesktop-${pkgs.vesktop.version}";
    paths = [ pkgs.vesktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/vesktop --add-flag ${lib.escapeShellArg "--user-agent=Mozilla/5.0 (X11; Linux ${pkgs.stdenv.hostPlatform.uname.processor}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${lib.versions.major pkgs.electron.unwrapped.info.chrome}.0.0.0 Safari/537.36"}
    '';
  };

  # Stremio's streaming server (server.js) looks for ffmpeg and ffprobe in Debian/Flatpak
  # paths, finds neither, and spawns `undefined` for every probe: a TypeError per stream
  # in the log, and no HLS transcoding for codecs the player can't take or for casting.
  # The nixpkgs package only wraps node in. Playback itself is libmpv, which already
  # decodes on the Mac's AVD through libva-v4l2-request (HEVC seen 2026-10-07).
  stremio = pkgs.symlinkJoin {
    name = "stremio-${pkgs.stremio-linux-shell.version}";
    paths = [ pkgs.stremio-linux-shell ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/stremio \
        --set FFMPEG_BIN ${lib.getExe' pkgs.ffmpeg "ffmpeg"} \
        --set FFPROBE_BIN ${lib.getExe' pkgs.ffmpeg "ffprobe"}
      # The D-Bus activation file names the unwrapped binary by store path.
      svc=share/dbus-1/services/com.stremio.Stremio.service
      sed "s|${pkgs.stremio-linux-shell}/bin/stremio|$out/bin/stremio|" \
        "$(readlink -f $out/$svc)" > $out/$svc.new
      rm $out/$svc && mv $out/$svc.new $out/$svc
    '';
  };

  # caligula ships no desktop entry, and `caligula burn` won't start without an image, so
  # the launcher row is a foot window that picks one first: disk images under ~, newest
  # first, in fzf. Escape closes the window. caligula finds the removable disks and asks
  # for sudo itself once a target is chosen.
  #
  # --size skips the empty file Firefox leaves under the final name while the download
  # goes to .part. It is the newest file, so it tops the list, and caligula 0.5.0 panics
  # on a zero-byte input: its progress gauge gets 0/0 (seen 2026-10-08).
  flash = pkgs.writeShellApplication {
    name = "lattice-flash";
    runtimeInputs = [
      pkgs.caligula
      pkgs.fd
      pkgs.fzf
    ];
    text = ''
      if (( $# )); then exec caligula burn "$@"; fi
      cd ~
      image=$(fd -t f --max-depth 4 --size +1m '\.(iso|img|raw)(\.(gz|bz2|xz|lz4|zst))?$' \
        --exec-batch ls -1t -- | fzf --prompt 'Image to flash> ' --no-sort) || exit 0
      exec caligula burn "$image"
    '';
  };
  flashItem = pkgs.makeDesktopItem {
    name = "lattice-flash";
    desktopName = "USB Flasher";
    comment = "Write a disk image to a USB drive";
    exec = "foot --app-id lattice-flash ${flash}/bin/lattice-flash";
    icon = "media-removable";
    categories = [ "System" ];
    keywords = [
      "usb"
      "flash"
      "burn"
      "iso"
      "image"
      "caligula"
      "etcher"
      "impression"
    ];
  };
in
{
  ### APPS ###
  environment.systemPackages = with pkgs; [
    # The terminal: a window for tmux, which does the tabs, splits and scrollback, so it
    # only has to draw. foot does that at about a fifth of the memory Ghostty took (25 MB
    # against 127 MB a window, measured). Its terminfo is a separate output, for TERM=foot.
    foot
    foot.terminfo
    # The same libqalculate engine at its other two surfaces: `qalc` in a terminal, and a
    # real window for the times a calculation is worth keeping on screen and editing --
    # qalculate-gtk carries the history, stored variables, user functions and the plot
    # button that a one-line launcher prompt has nowhere to put. It is GTK3, so the
    # run-time GTK theme (gtkUserTheme) dresses it; it lands in `rofi -show drun` as "Qalculate!".
    # libqalculate is free here (rofi-calc already put it in the closure) and qalculate-gtk
    # adds ~8 MiB on top of it.
    libqalculate
    qalculate-gtk

    mpv
    imv
    xarchiver
    hunspellDicts.en_US
    drawio
    telegram-desktop
    zathura
    bitwarden-desktop
    wf-recorder

    # Not a browser: Firefox keeps http/https under DEFAULT APPS below, and nothing here
    # changes that. This is on the machine for WebHID (navigator.hid) alone, which is the
    # only way to reach the NuPhy Halo65 V2's QMK raw-HID interface from this host. The
    # native clients cannot: pkgs.via and pkgs.vial are both x86_64-only AppImages in
    # nixpkgs, so on aarch64 the configurator is nuphy.io (or usevia.app) in a Chromium
    # tab. Firefox is not an option either -- Mozilla lists WebHID as harmful and ships no
    # implementation -- which is the whole reason a second browser exists here.
    #
    # Ungoogled rather than pkgs.chromium, and it costs nothing to prefer: both are cached
    # for aarch64 at ~200 MiB, and NIXOS_OZONE_WL (session.nix) already makes either a native
    # Wayland client. The keyboard's hidraw node still needs the udev rule above before
    # the page can open the device.
    ungoogled-chromium

    # Everything below was once picked per host, because the obvious client is x86-only
    # in nixpkgs and the Mac needed a stand-in. Running the stand-in on both is simpler
    # than keeping two app sets: each is cross-arch, cached for aarch64, and close
    # enough to what it replaces that having one of them in muscle memory is worth more
    # than the nicer x86 build.
    #
    # Vesktop, for Discord: an Electron shell around the web client, so it is the same
    # app the official build wraps, plus Vencord and working Wayland screen share.
    #
    # cryptomator-cli, for Cryptomator: same vaults, same format -- `cryptomator-cli
    # unlock` mounts one over FUSE and it is a normal directory from there. The GUI is
    # x86-only because nixpkgs pins `platforms = [ "x86_64-linux" ]`; that looks like an
    # untested restriction rather than a real one (zulu25 has an aarch64 JDK with
    # JavaFX, and the derivation evaluates fine on aarch64 with the meta relaxed), so an
    # overlay is the way back to the GUI on both if the CLI ever grates.
    #
    # caligula, for Impression: Impression is not merely unbuilt on ARM, it depends on
    # syslinux, which is genuinely x86-only, so this one has no way back. Popsicle sat
    # here first and listed no drives on the Mac: its dbus-udisks2 unwraps a partition
    # on every non-table block of a drive, and the Apple SSD's extra NVMe namespaces
    # (nvme0n2/n3) have neither, so the refresh thread panics. caligula walks the
    # removable disks itself and does a hash check and readback verify as well.
    vesktop # the wrapped one from the let above
    stremio # likewise
    cryptomator-cli
    caligula
    flash
    flashItem

    # Tor Browser used to sit here, on the Dell alone. It is dropped rather than gated:
    # the Tor Project ships no ARM Linux build (only tor-browser-linux-x86_64), and
    # Mullvad Browser is x86-only for the same reason, so there is nothing to make the
    # two hosts agree on. `nix run nixpkgs#tor-browser` on the Dell for the rare need.
  ];

  programs = {
    # No nativeMessagingHosts: firefoxpwa was the one entry here, and its host is only
    # reachable by the PWAsForFirefox extension, which isn't installed. Web apps are
    # Firefox's own Taskbar Tabs instead -- see modules/nixos/webapps.nix for why.
    firefox.enable = true;
    # Microsoft Graph accounts, hidden behind these prefs as of 156. The university's Microsoft
    # 365 tenant 403s every EWS request ("EWS is blocked by policy") since Exchange Online's
    # EWS retirement began on 2026-10-01, so that mailbox is a Graph account now. Both
    # prefixes pass the policy allowlist, so they ride the module rather than the Mac's
    # user.js.
    thunderbird = {
      enable = true;
      preferences = {
        "mail.graph.enabled" = true;
        "calendar.graph.enabled" = true;
      };
    };
    thunar = {
      enable = true;
      plugins = [
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
      ];
    };

    # Logitech HID++ control, for the MX Master 3. Its sensor ships at 4000 DPI, which is
    # what makes the pointer read as fast however far down Hyprland's per-device
    # `sensitivity` goes -- libinput can only discard motion counts after the fact, so it
    # buys slowness at the cost of precision. `solaar config <device> dpi <n>` moves it at
    # the source instead, which is why the device block in ~/.dotfiles/hypr/.config/hypr/
    # hyprland.lua now sits at sensitivity 0 with accel_profile flat: DPI is the only
    # speed knob, and pointer travel is proportional to hand travel so it means one thing.
    #
    # DPI is volatile: the mouse forgets it whenever it power-cycles or the Bluetooth link
    # drops, which on the Dell includes every hibernate -- see the btintel_pcie unload
    # in hosts/dell. The CLI alone would hold only until the next reconnect; the
    # user service is what makes it stick, reapplying ~/.config/solaar/config.yaml each
    # time the device comes back. It runs with no window and no tray icon at all -- see
    # the note on the package override below.
    #
    # That config.yaml is a symlink into the dotfiles repo (the solaar stow package), so
    # the DPI is shared rather than re-set per machine. Solaar rewrites it with a plain
    # open(path, "w"), which writes through the symlink instead of replacing it.
    #
    # enable also turns on hardware.logitech.wireless, which is what installs the udev
    # rules that let a non-root user talk to the device at all.
    #
    # The buttons are mapped in ~/.config/solaar/rules.yaml, the other half of the same
    # stow package: config.yaml diverts Back, Forward, Smart Shift and the gesture button
    # away from their built-in meanings, and rules.yaml says what they do instead (volume
    # on back/forward, the launcher on Smart Shift, and Hyprland navigation on the gesture
    # button). Rules are read once at start-up, so editing that file means
    # `systemctl --user restart solaar`.
    #
    # Most of those rules run commands rather than synthesising keystrokes. Execute needs
    # no privilege, and the uwsm-populated user environment already carries
    # HYPRLAND_INSTANCE_SIGNATURE into the service, which is what makes hyprctl work from
    # there. Its PATH does not carry /run/current-system/sw/bin, though, so the rules name
    # every binary absolutely.
    #
    # The exception is the gesture button, which holds SUPER down for as long as it is
    # held. That one needs KeyPress, which writes to /dev/uinput -- hence the
    # hardware.uinput block below. It buys the thing Solaar cannot do on its own: its
    # mouse-gesture mode only reports the direction once the button is released (the
    # notification is pushed from release_action, with no mid-gesture hook), so a gesture
    # can move one workspace per press and no more. Held as a modifier instead, the button
    # feeds the SUPER+scroll and SUPER+drag binds already in hyprland.lua, and workspaces
    # cycle continuously under the wheel. The cost is that a button is diverted as Mouse
    # Gestures or as a plain key, never both, so the four directional gestures are gone.
    #
    # The tray icon is built out rather than hidden. Solaar draws the mouse's battery
    # level into it, which put a second battery readout on the bar next to blueman's
    # bluetooth icon -- both live in waybar's one `tray` pill, and waybar's tray has no
    # per-item filter to drop one of them with. Solaar's own `--window only` switches the
    # icon off but also makes closing the window quit the process, which is the one thing
    # this service must not do: it is what reapplies the DPI and serves rules.yaml.
    #
    # So the indicator is removed at the source. Solaar asks gobject-introspection for
    # AyatanaAppIndicator3, then AppIndicator3, and falls back to Gtk.StatusIcon when
    # neither typelib is on GI_TYPELIB_PATH -- and GtkStatusIcon is X11 XEmbed, so under
    # Wayland it registers nothing. Dropping libappindicator from buildInputs is what
    # takes the typelib out of the wrapper; the fallback is upstream's own code path, and
    # it costs five Gtk-CRITICAL lines in the journal at start-up and nothing after.
    #
    # The window is still reachable -- solaar.desktop is still installed, and Solaar is a
    # single-instance GApplication, so launching it again pops the running process's
    # window rather than starting a second one.
    solaar = {
      enable = true;
      userService.enable = true;
      package = pkgs.solaar.overrideAttrs (old: {
        buildInputs = lib.filter (p: p != pkgs.libappindicator) old.buildInputs;
      });
    };

    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  services = {
    gvfs.enable = true;
    tumbler.enable = true;
    blueman.enable = config.hardware.bluetooth.enable;
    flatpak.enable = true;

    # swayosd writes backlight brightness through sysfs, which its udev rule opens to the video group.
    #
    # nuphyHidAccess opens the Halo65 V2's raw-HID node so the configurator can reach it;
    # see the note on the package itself for why it is a package here and not extraRules.
    udev.packages = [
      pkgs.swayosd
      nuphyHidAccess
    ];
  };
  # /dev/uinput, for the Solaar rule that holds SUPER while the mouse's gesture button is
  # down. The NixOS module loads the module, makes the group and writes the udev rule; the
  # group membership is what the solaar user service actually needs. Supplementary groups
  # are fixed when the session starts, so this only reaches a running Solaar after a
  # re-login -- until then KeyPress fails silently, which is its only failure mode.
  hardware.uinput.enable = true;

  # The module's unit is WantedBy graphical-session.target but not ordered after it, so it
  # started with the rest of the login transaction, before Hyprland had a display to hand
  # it: "cannot open display" and a failed start on every boot, rescued only by the restart
  # five seconds later.
  systemd.user.services.solaar.after = [ "graphical-session.target" ];

  users.users.winston.extraGroups = [
    "video"
    "uinput"
  ];

  systemd.user.services = {
    # Collabora Office replaces LibreOffice: the same engine under Collabora Online's
    # interface, which nixpkgs only packages as the server. Flathub builds the desktop app
    # for both arches, so it lands as a per-user Flatpak at session start -- installed when
    # missing and never updated here, so a login doesn't turn into a 400 MiB download;
    # `flatpak update` is the upgrade.
    #
    # Its Qt UI comes out a size too big on both screens; QT_SCALE_FACTOR multiplies each
    # output's own scale, so one factor shrinks it on the 2.25x panel and the 1.5x Samsung
    # alike. Re-applied every run so the value here stays the source of truth.
    lattice-flatpaks = {
      description = "Install lattice's Flatpak apps";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      # Fails when the session starts offline before the first install; say so rather than
      # leave Collabora quietly missing from rofi.
      onFailure = [ "lattice-notify-failure@%n.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "lattice-flatpaks";
            runtimeInputs = [
              config.services.flatpak.package
              pkgs.gnugrep
            ];
            text = ''
              app=com.collaboraoffice.Office
              # --if-not-exists still fetches the .flatpakrepo before checking, so an
              # offline login failed even with everything already installed.
              flatpak remotes --user --columns=name | grep -qx flathub \
                || flatpak remote-add --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
              flatpak info --user "$app" >/dev/null 2>&1 \
                || flatpak install --user --noninteractive flathub "$app"
              flatpak override --user --env=QT_SCALE_FACTOR=0.8 "$app"
            '';
          }
        );
      };
    };
  };

  ### DEFAULT APPS ###
  #
  # Only the exact type is ever consulted. xdg-open's open_generic asks `xdg-mime query
  # default` for the detected type and does not walk the subclass chain, so a type absent
  # here does not fall back to its parent -- it falls off the end of the script into the
  # hardcoded browser list, which is why an unassigned .md, .py or .json opened as a
  # Firefox tab rather than failing. Silent and wrong, so anything worth opening needs its
  # own line.
  #
  # What is left out is decided by mimeinfo.cache order, which is arbitrary and moves when
  # a package does. So the rule for being on this list is: either two installed apps claim
  # the type, or nothing claimed it at all.
  xdg.mime.defaultApplications =
    let
      assign = app: types: lib.genAttrs types (_: app);
    in
    assign "firefox.desktop" [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      # Both of these resolved to ungoogled-chromium, which is on the machine for the
      # Halo65's WebHID configurator alone -- see the note on the package above. Firefox
      # renders XML and XHTML perfectly well, and nothing should reach the other browser
      # by accident.
      "application/xml"
      "application/xhtml+xml"
    ]
    // assign "thunderbird.desktop" [
      "x-scheme-handler/mailto"
      "x-scheme-handler/mid"
      "message/rfc822"
      "text/calendar"
      # Thunderbird registers these itself, by writing a userapp-Thunderbird-*.desktop
      # into ~/.local/share/applications and pointing ~/.config/mimeapps.list at it. That
      # is also how it broke them: three of those generated files are gone and the entries
      # naming them are still there, so webcal had no working handler at all. A system
      # assignment to the real thunderbird.desktop is the stable spelling -- but the user
      # list still outranks /etc/xdg, so these only take effect once its stale entries are
      # cleared.
      "x-scheme-handler/webcal"
      "x-scheme-handler/webcals"
      # What Firefox hands off when a calendar invite is downloaded rather than followed as
      # a link, so it needs naming separately from text/calendar above.
      "application/x-extension-ics"
    ]
    # Also claimed by org.pwmt.zathura-cb.desktop, which declares inode/directory,
    # application/zip, x-tar and x-7z-compressed on its way to the comic formats. Pinning
    # the file manager and the archiver is what keeps a folder or a .zip from opening in a
    # comic reader.
    // assign "thunar.desktop" [ "inode/directory" ]
    // assign "org.pwmt.zathura.desktop" [ "application/pdf" ]
    # The Flatpak's export, installed by lattice-flatpaks. CSV is left out on purpose: it is
    # as often something to read in a terminal as a spreadsheet.
    // assign "com.collaboraoffice.Office.desktop" [
      "application/vnd.oasis.opendocument.text"
      "application/vnd.oasis.opendocument.spreadsheet"
      "application/vnd.oasis.opendocument.presentation"
      "application/vnd.oasis.opendocument.graphics"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      "application/msword"
      "application/vnd.ms-excel"
      "application/vnd.ms-powerpoint"
      "application/rtf"
      "text/rtf"
    ]
    # .cbz is detected as application/vnd.comicbook+zip; zathura-cb only declares the
    # older application/x-cbz, so every real comic went to xarchiver instead -- the reader
    # was installed and unreachable.
    // assign "org.pwmt.zathura-cb.desktop" [
      "application/vnd.comicbook+zip"
      "application/x-cbz"
    ]
    # imv.desktop and imv-dir.desktop declare an identical MimeType list, and imv-dir
    # opens the whole containing directory as a playlist. Whichever of the two the cache
    # happens to return first is not a choice, so every type imv declares and we care
    # about is named here. image/x-icon deliberately is not: imv has no .ico loader, and
    # an assignment to an app that cannot open the file is worse than none.
    // assign "imv.desktop" [
      "image/png"
      "image/jpeg"
      "image/gif"
      "image/webp"
      "image/avif"
      "image/bmp"
      "image/tiff"
      "image/svg+xml"
      "image/heif"
      "image/jxl"
    ]
    # The editor for everything that is text and had no handler. vim, gvim and neovim all
    # ship entries claiming text/plain as well, and gvim -- X11 only, so XWayland and
    # blurry -- was the one winning application/x-shellscript. The two Terminal=true
    # entries among them could not have worked from xdg-open anyway: nothing here provides
    # a terminal for them to open in.
    // assign "dev.zed.Zed.desktop" [
      "text/plain"
      "text/markdown"
      "application/json"
      "text/x-python"
      "text/x-nix"
      "application/x-shellscript"
      "text/x-shellscript"
    ]
    // assign "mpv.desktop" [
      "video/mp4"
      "video/webm"
      "video/x-matroska"
      "video/quicktime"
      "video/x-msvideo"
      "audio/mpeg"
      "audio/flac"
      "audio/ogg"
      "audio/wav"
      "audio/mp4"
      "audio/aac"
      "audio/x-m4a"
      "audio/opus"
    ]
    # The compound types are the ones a .tar.gz or .tar.zst actually detects as -- the
    # plain application/gzip below only matches a bare .gz. They already resolved here,
    # but by cache order rather than by decision.
    // assign "xarchiver.desktop" [
      "application/zip"
      "application/x-tar"
      "application/gzip"
      "application/x-xz"
      "application/zstd"
      "application/x-7z-compressed"
      "application/vnd.rar"
      "application/x-compressed-tar"
      "application/x-xz-compressed-tar"
      "application/x-bzip-compressed-tar"
      "application/x-zstd-compressed-tar"
      "application/x-bzip2"
    ];
}
