_: {
  ### AIRPLAY ###
  # The HomePod as an ordinary output. raop-discover browses for AirPlay receivers and makes
  # each one a sink, so it shows up next to the speakers and headphones with nothing else
  # running. It finds them through avahi -- resolved's mDNS only resolves names, it has no
  # service browsing for the module to use.
  #
  # Video stays in sync without help: the sink reports the receiver's buffer (~1.75s) as its
  # latency, and Firefox holds frames back by that much, the same way it does for Bluetooth.
  # What remains is the delay itself, felt as slow play/pause/seek. If lip sync does drift,
  # raop.latency.ms in the discover module's stream rules moves both the buffer and the
  # reported latency together.
  services.pipewire = {
    raopOpenFirewall = true;
    extraConfig.pipewire."60-airplay" = {
      "context.modules" = [ { name = "libpipewire-module-raop-discover"; } ];
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Two mDNS responders on one link answer every query twice and fight over the host name.
  # avahi has to be one of them, and nssmdns4 takes over .local lookups, so resolved stops.
  services.resolved.settings.Resolve.MulticastDNS = false;
}
