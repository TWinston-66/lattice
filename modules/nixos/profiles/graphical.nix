{
  # Everything below reads config.lattice.theme, so don't rely on branding.nix pulling it in.
  imports = [
    ../artwork.nix
    ../theme.nix
    ../plymouth.nix
    ../display.nix
    ../weather.nix
    ../streamdeck.nix
    ../webapps.nix
    ../widevine.nix
    ../phone.nix
    ../bitwarden.nix
    ../desktop/session.nix
    ../desktop/apps.nix
    ../desktop/theming.nix
    ../desktop/bar.nix
    ../desktop/backup.nix
    ../desktop/menus.nix
    ../desktop/notifications.nix
    ../desktop/lock.nix
    ../desktop/screenshot.nix
    ../desktop/greeter.nix
  ];
}
