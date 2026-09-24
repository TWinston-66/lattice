{ lib, ... }:
{
  options.lattice.weather = {
    latitude = lib.mkOption {
      type = lib.types.str;
      default = "40.015";
      example = "39.7392";
      description = ''
        Latitude lattice-weather reports for, in decimal degrees.

        A string rather than a float for the reason the monitor scales in
        modules/nixos/display.nix are: Nix renders `40.015` as `40.015000`. Six decimal
        places is harmless in a query string -- it is still the same point, to within a
        tenth of a millimetre -- but the option is written straight into a URL and is
        easier to read back as what was typed.

        Fixed coordinates, rather than the IP geolocation a wttr.in-style widget would do,
        because this tailnet has the Mullvad exit nodes on: see lattice-tailscale in
        profiles/graphical.nix. With an exit node up, every IP lookup places the machine
        wherever that endpoint is, so the pill would quietly report the weather in another
        country. The cost is that this is wrong while travelling, which is the rarer case
        and the obvious one when it happens.
      '';
    };

    longitude = lib.mkOption {
      type = lib.types.str;
      default = "-105.2705";
      example = "-104.9903";
      description = "Longitude, in decimal degrees. A string for the same reason as `latitude`.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "Boulder, CO";
      example = "Denver, CO";
      description = ''
        Place name for the first line of the tooltip. Open-Meteo takes coordinates and
        hands back coordinates -- it does no reverse geocoding -- so the name is not
        derivable from the numbers above and is simply stated here.
      '';
    };
  };
}
