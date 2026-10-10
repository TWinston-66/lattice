{ lib, pkgs, ... }:
let
  # SIGRTMIN+8, the signal the bar pill below listens for (waybar.nix checks that no two pills share one).
  barSignal = 8;

  # The desktop app is what lets the Firefox extension unlock with polkit instead of the
  # master password: the extension talks to desktop_proxy over native messaging, the proxy
  # talks to the running app, and the app asks polkit. Passkeys themselves need none of
  # this -- the extension stores and fills them on its own. Linux has no OS passkey-provider
  # API for the app to plug into the way it does on Windows and macOS.
  bitwarden = pkgs.bitwarden-desktop;

  # The package ships no manifest, and the app's own "Allow browser integration" toggle
  # writes one into the profile that names a /nix/store path, which goes stale on the
  # next update. This one is rebuilt with the package, and programs.firefox links it in
  # through the wrapper's MOZ_SYSTEM_DIR. The id is the AMO extension's, read off
  # extensions.json in the profile.
  firefoxManifest = pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/com.8bit.bitwarden.json" (
    builtins.toJSON {
      name = "com.8bit.bitwarden";
      description = "Bitwarden desktop <-> browser bridge";
      path = "${bitwarden}/libexec/desktop_proxy";
      type = "stdio";
      allowed_extensions = [ "{446900e4-71c2-419f-a6a7-df9c091e268b}" ];
    }
  );

  unit = "app-bitwarden@autostart.service";

  # The bar's Bitwarden pill, which replaced the app's tray icon so it no longer shares the
  # tray with blueman. Waybar's tray module draws every StatusNotifierItem in one box and
  # cannot be told to leave one out, so the icon is off in the app (Settings > Enable tray
  # icon) and this stands in for it.
  #
  # Without a tray the app's window is its only presence, and closing it quits the app. So
  # the window lives on the special:bitwarden workspace (a window rule in hyprland.lua),
  # where it opens silently at login and again whenever the unit below restarts it; a click
  # here shows or hides that workspace.
  #
  # The lock state is read off the SSH agent: an unlocked vault serves its keys, a locked
  # one lists none.
  pill = pkgs.writeShellApplication {
    name = "lattice-bitwarden";
    runtimeInputs = [
      pkgs.systemd
      pkgs.openssh
      pkgs.jq
      pkgs.procps
      pkgs.coreutils
      pkgs.util-linux
      pkgs.hyprland
      bitwarden
    ];
    text = ''
      unit=${unit}

      shown() {
        hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name == "special:bitwarden")' >/dev/null
      }

      status() {
        local text class tip
        if ! systemctl --user is-active --quiet "$unit"; then
          text=󰌾
          class=stopped
          tip="Bitwarden is not running: no SSH agent, no browser unlock"$'\n'"Click to start it"
        else
          local keys rc=0
          keys=$(timeout 3 ssh-add -l 2>/dev/null | wc -l) || rc=$?
          if ((rc == 0 && keys > 0)); then
            text=󰿆
            class=unlocked
            tip="Bitwarden is unlocked, SSH agent serving $keys key$( ((keys == 1)) || echo s)"
          else
            text=󰌾
            class=locked
            tip="Bitwarden is locked, SSH agent has no keys"
          fi
          tip+=$'\n'"Click to show or hide the window"
        fi
        if shown; then
          class+=" shown"
        fi
        jq -nc --arg text "$text" --arg tip "$tip" --arg class "$class" \
          '{text: $text, tooltip: $tip, class: ($class | split(" "))}'
      }

      toggle() {
        if ! systemctl --user is-active --quiet "$unit"; then
          systemctl --user start "$unit"
        elif ! hyprctl clients -j | jq -e 'any(.[]; .class | test("^[Bb]itwarden$"))' >/dev/null; then
          # Running with no window: a second launch hands over to the running app, which
          # opens its window -- onto the scratchpad, by the rule, so show that too.
          setsid -f bitwarden >/dev/null 2>&1 </dev/null
          sleep 1
          shown || hyprctl dispatch 'hl.dsp.workspace.toggle_special("bitwarden")' >/dev/null
        else
          hyprctl dispatch 'hl.dsp.workspace.toggle_special("bitwarden")' >/dev/null
        fi
        pkill -RTMIN+${toString barSignal} waybar || true
      }

      case ''${1:-status} in
      status) status ;;
      toggle) toggle ;;
      *)
        echo "usage: lattice-bitwarden [status|toggle]" >&2
        exit 2
        ;;
      esac
    '';
  };
in
{
  # The pill: the lock state as a glyph, and a click that shows or hides the app's window.
  # A minute, not ten seconds: every poll is an `ssh-add -l` that wakes the Electron app and
  # logs a line, times two bars when docked. A click repaints it at once through the
  # signal, so only a lock or unlock done in the app itself waits for the next tick.
  lattice.bar.modules."custom/bitwarden" = {
    section = "group/toggles";
    order = 80;
    settings = {
      exec = "lattice-bitwarden status";
      return-type = "json";
      signal = barSignal;
      interval = 60;
      on-click = "lattice-bitwarden toggle";
    };
  };

  # On systemPackages rather than a bare reference so its share/polkit-1 lands in
  # /run/current-system/sw, where polkit looks for com.bitwarden.Bitwarden.unlock. The
  # app's own "set up" button wants to write it under /usr/share, which does not exist here.
  environment.systemPackages = [ bitwarden ];

  programs.firefox.nativeMessagingHosts.packages = [ firefoxManifest ];

  # SSH keys are served by the desktop app's agent, so the private key lives in the vault
  # and not in ~/.ssh. Code running as the user can still ask an unlocked agent to sign, and
  # Bitwarden prompts for each use, but there is no key file left to copy. This is one of
  # the mitigations for the Mac's Firefox running its media decoder unsandboxed
  # (hosts/mac). The app autostarts from its own XDG entry, so the socket is there from
  # login, and only while the app runs.
  #
  # Two app-side steps go with this: Settings > SSH agent on, and the key imported as an
  # SSH key item. With the private half gone, ~/.ssh/config names ~/.ssh/id_ed25519.pub as
  # the IdentityFile (a Match on the key file, so macOS keeps loading its own); OpenSSH
  # offers it and has the agent sign. Naming the missing private file instead works too,
  # but warns "not accessible" on every connection.
  programs.ssh.startAgent = false;
  environment.sessionVariables.SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";

  # The app's own XDG entry stays the launcher (the doctor's persistence check expects it);
  # this is a drop-in on the unit systemd generates from it. It comes back if it exits,
  # because the SSH agent and the browser unlock both die with it -- and with the tray icon
  # off, closing the window is an exit. The restart reopens the window on the scratchpad,
  # out of the way. (It used to wait for waybar's StatusNotifierWatcher, which Electron
  # needs at startup to register a tray icon; there is no icon to register now.)
  systemd.user.services."app-bitwarden@autostart" = {
    overrideStrategy = "asDropin";
    serviceConfig = {
      Restart = "always";
      RestartSec = 2;
    };
  };

  # The pill's exec and click; see the note on it above.
  systemd.user.services.waybar.path = [ pill ];

  lattice.cli.commands.bitwarden = {
    exec = lib.getExe pill;
    args = "[status|toggle]";
    summary = "Bitwarden's lock state, or show and hide its window";
    group = "session";
    launch = [
      {
        label = "Bitwarden: show or hide";
        args = "toggle";
        icon = "bitwarden";
      }
    ];
  };
}
