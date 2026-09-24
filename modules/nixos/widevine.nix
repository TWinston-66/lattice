{ lib, pkgs, ... }:
let
  # The DRM module every subscription service decrypts with -- Apple Music, Spotify,
  # Netflix. Firefox normally installs it itself, as a Gecko Media Plugin pulled from
  # Mozilla's update service at first use, so on x86_64 there is nothing to configure.
  # aarch64 Linux is the gap: asking aus5.mozilla.org for GMPs as this machine does
  # (Linux_aarch64-gcc3) returns openh264 and nothing else, and Firefox's own
  # toolkit/content/gmp-sources/widevinecdm.json lists Windows and macOS on ARM64 but no
  # Linux entry to serve. So Firefox here asks, is told there is no such plugin, and
  # reports DRM content as unplayable -- silently, since the page just never starts.
  #
  # Google does build one for ARM64 Linux; it ships inside ChromeOS. pkgs.widevine-cdm on
  # this platform is that build, lifted out of a chromeos-lacros image and run through
  # Asahi's widevine_fixup.py, which pads its LOAD segments out to the page size ChromeOS
  # did not anticipate (4K there, 16K on an Asahi kernel -- `getconf PAGESIZE`), injects
  # the two outline-atomic helpers libgcc does not export, and adds the GLIBC_ABI_DT_RELR
  # tag current glibc wants. Unpatched it would not map at all.
  #
  # The padding is not free: its own docs are explicit that on a >4K page system it costs
  # RELRO and leaves an RWX mapping *inside the CDM's process*. That process is the
  # sandboxed GMP child, not the browser, and the alternative is no DRM at all on this
  # machine -- but it is the reason this module is scoped to Firefox's plugin directory
  # and not a system-wide install.
  #
  # It also reads the *builder's* page size, so the result is only correct for a machine
  # whose pages are that size or smaller. Building here, natively, that is this one; a
  # remote aarch64 builder on a 4K kernel would hand back something that will not load.
  #
  # It is the older 4.10.2662.3 and declares CDM interface version 10 in its manifest,
  # where Firefox 155 prefers 11. That is a negotiation, not a floor: the adapter tries 11,
  # logs "FAILED to create cdm version 11", and comes back at 10, which is also the
  # interface version of the 4.10.3050.0 CDM Mozilla serves to x86_64 -- 10 is simply what
  # Widevine still speaks. Both cenc and cbcs come back supported.
  #
  # The library needs libnspr4.so, which is not in the plugin directory and does not have
  # to be: the CDM is dlopened by a plugin-container that has already loaded libxul, and
  # libxul links libnspr4 itself, so the soname is resolved from what is in the process.
  #
  # Files are copied rather than symlinked into one directory. The GMP process is sandboxed
  # around its plugin path, and a link out to a second store path is a read it would have to
  # be granted; there is no reason to find out whether it is.
  gmpWidevine = pkgs.runCommand "firefox-gmp-widevinecdm" { } ''
    cdm=${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm
    install -Dm444 "$cdm/manifest.json" \
      $out/gmp-widevinecdm/system-installed/manifest.json
    install -Dm555 "$cdm/_platform_specific/linux_arm64/libwidevinecdm.so" \
      $out/gmp-widevinecdm/system-installed/libwidevinecdm.so
  '';
in
# x86_64 is left alone deliberately: there Mozilla serves the CDM, Firefox keeps it current
# on its own, and pinning a hand-placed one would replace a maintained plugin with a
# frozen one.
lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 {
  # Each entry of MOZ_GMP_PATH is a plugin *version* directory, not a search root: Firefox
  # reads the plugin name and version off its last two path components, which is why the
  # variable points all the way down to .../gmp-widevinecdm/system-installed and why the
  # version pref below has to be that same directory name. "system-installed" is what
  # Asahi's installer calls it; keeping the name means anything written for that setup
  # (and the rest of the web's advice for ARM Linux) describes this one too.
  environment.sessionVariables.MOZ_GMP_PATH = "${gmpWidevine}/gmp-widevinecdm/system-installed";

  programs.firefox.preferences = {
    "media.gmp-widevinecdm.version" = "system-installed";
    "media.gmp-widevinecdm.enabled" = true;
    # Listed in about:addons under Plugins, where its absence is the one visible sign of
    # this having gone wrong.
    "media.gmp-widevinecdm.visible" = true;
    # There is no update channel behind this plugin -- the version above is a directory
    # name, and the service has nothing to offer aarch64 anyway. Left on, the GMP manager
    # would check on a timer and log a failure each time.
    "media.gmp-widevinecdm.autoupdate" = false;
    # The "Play DRM-controlled content" checkbox. On by default, but a profile that was
    # once told otherwise keeps the answer, and the plugin is unreachable while it is off.
    "media.eme.enabled" = true;
  };
}
