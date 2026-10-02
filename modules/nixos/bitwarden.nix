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
}
