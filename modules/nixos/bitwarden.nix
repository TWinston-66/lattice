{ pkgs, ... }:
let
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
in
{
  # On systemPackages rather than a bare reference so its share/polkit-1 lands in
  # /run/current-system/sw, where polkit looks for com.bitwarden.Bitwarden.unlock. The
  # app's own "set up" button wants to write it under /usr/share, which does not exist here.
  environment.systemPackages = [ bitwarden ];

  programs.firefox.nativeMessagingHosts.packages = [ firefoxManifest ];

  # SSH keys are served by the desktop app's agent, so the private key lives in the vault
  # and not in ~/.ssh. Code running as winston can still ask an unlocked agent to sign, and
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
  # this is a drop-in on the unit systemd generates from it. Electron registers its tray
  # icon once, at startup, and gives up for good if no StatusNotifierWatcher is on the bus
  # yet -- and at login it raced waybar and lost, leaving the app running with no window
  # and no icon (2026-10-04). So it waits for waybar's tray, and comes back if it exits,
  # because the SSH agent and the browser unlock both die with it.
  systemd.user.services."app-bitwarden@autostart" = {
    overrideStrategy = "asDropin";
    after = [ "waybar.service" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.writeShellScript "bitwarden-wait-for-tray" ''
        for _ in $(seq 100); do
          ${pkgs.systemd}/bin/busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && exit 0
          sleep 0.1
        done
      ''}";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
