{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lattice.homeassistant;

  # An entity id, as one of the seven the Stream Deck's home page presses. The default is a
  # guess at the usual naming and is meant to be corrected: `lattice-ha entities` prints
  # what this instance actually calls things, and the id is the first column.
  entity =
    default: description:
    lib.mkOption {
      type = lib.types.str;
      inherit default description;
    };

  ha = pkgs.writeShellApplication {
    name = "lattice-ha";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.libnotify
      pkgs.coreutils
    ];
    text = ''
      url=${lib.escapeShellArg cfg.url}
      token_file=${lib.escapeShellArg (toString cfg.tokenFile)}
      # Short on purpose: every verb here is behind a key press, and a house that is not
      # answering should say so rather than hold the key down.
      timeout=4

      # The token never reaches a command line. curl reads the Authorization header from a
      # config file handed to it on stdin, so it is not in /proc/<pid>/cmdline for the
      # length of the call, and nothing that lists processes can pick it up. A long-lived
      # access token is a JWT -- base64url and dots -- so no character in one needs escaping
      # inside curl's quoted config syntax.
      api() {
        local method="$1" path="$2" token
        shift 2
        token="$(cat "$token_file")"
        printf 'header = "Authorization: Bearer %s"\n' "$token" |
          curl --silent --show-error --fail --max-time "$timeout" \
            --request "$method" --header "Content-Type: application/json" \
            --config - "$@" "$url/api/$path"
      }

      fail() {
        notify-send -a lattice-ha -i dialog-error "Home Assistant" "$1"
        exit 1
      }

      # Read the deck's device keys back after something that moved the house.
      #
      # Twice, because a service call returning is not the same as the house reporting: a
      # bulb told to come on is not yet saying that it has, and a scene that ramps or a
      # device answering over the radio can still be reporting its old state a moment later.
      # The first pass is what makes the press feel answered; the second, in the background,
      # catches whatever was still in flight. Three GETs each, so neither is worth economising.
      #
      # `&` rather than anything cleverer for the same reason `lattice-deck arm` uses one:
      # the deck runs these with no one waiting on them, so a backgrounded child outlives
      # the press without holding it up.
      resync() {
        sleep 0.3
        lattice-deck sync home || true
        (
          sleep 4
          lattice-deck sync home || true
        ) &
      }

      # One service call, with the entity as its only target. The service is written the way
      # Home Assistant writes it -- domain.service -- and the path wants a slash.
      call() {
        local service="$1" entity="$2"
        api POST "services/''${service/./\/}" \
          --data "$(jq -nc --arg e "$entity" '{entity_id: $e}')" >/dev/null
      }

      # What "press this" means depends on the domain, and the domain is the half of the
      # entity id before the dot -- so a key does not have to say whether the thing behind
      # it ended up a scene or a script. Anything else is a device, and turning it on is
      # the closest thing to activating it.
      service_for() {
        case "''${1%%.*}" in
        scene) echo scene.turn_on ;;
        script) echo script.turn_on ;;
        automation) echo automation.trigger ;;
        *) echo homeassistant.turn_on ;;
        esac
      }

      friendly() {
        api GET "states/$1" 2>/dev/null | jq -r '.attributes.friendly_name // .entity_id' \
          || printf '%s' "$1"
      }

      case "''${1:-}" in
      state)
        # Deliberately not an error when the read fails: the caller is a key being
        # repainted, and "I could not tell" is a third answer it has to be able to act on.
        # See sync_home in modules/nixos/streamdeck.nix, which leaves the face alone for it.
        entity="''${2:?usage: lattice-ha state <entity>}"
        if raw="$(api GET "states/$entity" 2>/dev/null)"; then
          printf '%s\n' "$raw" | jq -r '.state // "unknown"'
        else
          echo unknown
        fi
        ;;

      toggle | on | off)
        entity="''${2:?usage: lattice-ha ''${1} <entity>}"
        case "$1" in
        toggle) service=homeassistant.toggle ;;
        on) service=homeassistant.turn_on ;;
        off) service=homeassistant.turn_off ;;
        esac
        call "$service" "$entity" || fail "Could not reach $entity"
        resync
        ;;

      activate)
        # A scene or a script has no face of its own to flip -- the banner is what says the
        # press landed -- but it is very much allowed to move the devices that *do*. Bed
        # time turns the fan on, so the fan's key has to be read back here exactly as it is
        # after a toggle; without this it sits wrong until the five-minute timer comes
        # round. resync before the banner, so the keys settle while notify-send is busy
        # looking the friendly name up.
        entity="''${2:?usage: lattice-ha activate <entity>}"
        call "$(service_for "$entity")" "$entity" || fail "Could not run $entity"
        resync
        notify-send -a lattice-ha -i dialog-information "Home Assistant" "$(friendly "$entity")"
        ;;

      call)
        # The escape hatch, for anything the three verbs above do not shape: a fan speed, a
        # light's colour, a media player. Same argument order as the service itself reads.
        service="''${2:?usage: lattice-ha call <domain.service> <entity>}"
        entity="''${3:?usage: lattice-ha call <domain.service> <entity>}"
        call "$service" "$entity" || fail "Could not call $service"
        ;;

      entities)
        # What the entity ids below are set from. The optional argument is a plain substring
        # match over both columns, so `lattice-ha entities bedroom` is the usual way in.
        api GET states |
          jq -r --arg want "''${2:-}" '
            .[]
            | [.entity_id, (.attributes.friendly_name // "")]
            | select(any(.[]; ascii_downcase | contains($want | ascii_downcase)))
            | @tsv
          ' | sort
        ;;

      *)
        cat >&2 <<USAGE
      usage: lattice-ha <verb>

        state <entity>               on, off, or unknown if the house cannot be reached
        toggle | on | off <entity>   a device, with the deck's key repainted after
        activate <entity>            a scene, script or automation, with a banner
        call <domain.service> <e>    any other service, targeting one entity
        entities [substring]         every entity id and friendly name, for setting the above
      USAGE
        exit 2
        ;;
      esac
    '';
  };
in
{
  options.lattice.homeassistant = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "http://ha.home.lan:8123";
      description = ''
        Where Home Assistant answers, with no trailing slash. Plain HTTP on the LAN name
        rather than a tailnet address: the deck's keys are pressed at the desk, and the
        token that authenticates them never leaves the wire between here and the house.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = config.sops.secrets.ha-token.path;
      description = ''
        A file holding one Home Assistant long-lived access token and nothing else. The
        default is the sops secret this module declares, which has to exist in
        secrets/common.yaml as `ha-token` before a rebuild will activate.

        Mint one from the Security tab of your Home Assistant profile page -- the bottom of
        `/profile/security` on the `url` above -- and paste it in with
        `sops secrets/common.yaml`.
        The token does not expire and is shown once, so it is worth naming it "lattice" at
        the prompt to know which one to revoke later.
      '';
    };

    entities = {
      # The two light groups rather than any of the bulbs inside them: `light.bedroom` is
      # ceiling + lamp + hex panel, `light.bathroom_lights` is the four over the mirror. A
      # group reports `on` when any member is, which is the reading the key wants -- one
      # bulb left on is not a key that should be showing off.
      bedroomLights = entity "light.bedroom" "The bedroom's lights, as a toggle key.";
      bathroomLights = entity "light.bathroom_lights" "The bathroom's lights, as a toggle key.";

      # The same physical fan is on the bus twice -- `fan.fan` and `switch.fan`, one device
      # named Fan in the Bedroom area. The fan domain is the honest one of the two, and it
      # is what a speed would hang off if this ever grows one; `switch.fan` is the outlet
      # underneath it.
      bedroomFan = entity "fan.fan" "The bedroom fan, as a toggle key.";

      # All four are scenes today. They are pressed through `activate`, which reads the
      # domain and picks the service -- so one that later becomes a script, or an
      # automation, is a changed id here and nothing else.
      bedTime = entity "scene.bed_time" "Bed time: the whole house, set for sleep.";
      calm = entity "scene.calm_work" "Calm.";
      focus = entity "scene.focus" "Focus.";
      windDown = entity "scene.wind_down" "Wind down: the hour before bed time.";
    };
  };

  config = {
    # Owned by winston rather than root: lattice-ha runs as the session, both from the deck's
    # user unit and from a shell. 0400 is sops-nix's default and is what is wanted.
    sops.secrets.ha-token.owner = "winston";

    # On the PATH rather than named by store path in the deck's button commands, which is
    # what lets lattice-deck call it and it call lattice-deck back without a cycle between
    # the two derivations. See sessionPath in modules/nixos/streamdeck.nix.
    environment.systemPackages = [ ha ];
  };
}
