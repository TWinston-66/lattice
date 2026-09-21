{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailnet = config.services.tailscale;

  downloads = "%h/Downloads";

  # `tailscale file get` moves whatever is sitting in the inbox and exits; nothing on the
  # receiving end is automatic. --loop exists and would be the obvious answer, but it only
  # streams names to stdout, and parsing that to raise a notification means depending on a
  # human-readable format with no stability promise. --wait blocks on an empty inbox and
  # returns once it has drained it, which is a contract rather than a format: loop around
  # that instead and the exit is the event worth announcing.
  taildrop = pkgs.writeShellApplication {
    name = "lattice-taildrop";
    runtimeInputs = [
      pkgs.tailscale
      pkgs.libnotify
    ];
    text = ''
      dir="''${1:-$HOME/Downloads}"
      mkdir -p "$dir"

      while :; do
        # --conflict=rename rather than the default skip: a skipped file stays in the
        # inbox, so the next --wait returns immediately on the same stuck file and this
        # turns into a hot loop that re-reports it forever.
        if received="$(tailscale file get --wait --verbose --conflict=rename "$dir" 2>&1)"; then
          # `|| true` is load-bearing twice over, under errexit and pipefail: grep exits
          # 1 when the capture is empty, and head closing the pipe early can SIGPIPE it.
          # Either would kill the loop here instead of falling through to the default
          # below, which is exactly the case the default was written for.
          body="$(printf '%s\n' "$received" | grep -v '^$' | head -5 || true)"
          notify-send --app-name=Taildrop --icon=phone \
            "Files received" "''${body:-Saved to $dir}"
        else
          # tailscaled down, signed out, or this user is not its operator. Backing off
          # keeps a restart loop off the journal until the tunnel is back.
          sleep 30
        fi
      done
    '';
  };
in
{
  ### IPHONE OVER USB ###
  # usbmuxd is the multiplexer every libimobiledevice tool speaks through -- the iPhone
  # exposes its services over USB as a single muxed channel, not as anything the kernel can
  # mount on its own, so without this daemon the phone is an unreadable device.
  #
  # gvfs is already on (profiles/graphical.nix) and nixpkgs builds it against
  # libimobiledevice, so its afc:// backend comes for free: with usbmuxd running, a trusted
  # iPhone appears in Thunar's sidebar and the camera roll is browsable with no mount step.
  # That covers the actual use, and is why there is no fstab entry or mount unit here.
  services.usbmuxd.enable = true;

  environment.systemPackages = [
    # The CLI path, for when Thunar's isn't enough: `idevicepair pair` to re-run the trust
    # handshake when the phone stops recognising this machine, `ideviceinfo` to see whether
    # it is talking at all, and `ifuse ~/mnt` to mount the same filesystem somewhere a
    # script can reach. Pairing is per-host and the phone must be unlocked for it: the
    # "Trust This Computer" prompt only appears on an unlocked screen.
    pkgs.libimobiledevice
    pkgs.ifuse
  ];

  ### TAILDROP ###
  # File transfer to and from the phone, over the tailnet rather than the LAN. This is the
  # one channel iOS does not get in the way of -- the share sheet hands a file to the
  # Tailscale app, which is a foreground action, so none of the background-execution limits
  # that make the various KDE-Connect-style tools unreliable on an iPhone apply.
  #
  # It costs nothing here that isn't already paid for: tailscaled is running, firewall.nix
  # already trusts the tailnet interface, and there is no LAN discovery to fail on a
  # network that blocks client isolation.
  systemd.user.services.taildrop = lib.mkIf tailnet.enable {
    description = "Receive Taildrop files";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    # Bound to the graphical session and not to default.target because the only thing it
    # does on arrival is raise a notification, which needs a session to raise it into.
    #
    # Reaching the inbox at all needs LocalAPI access, which is root or the operator. The
    # tailscale-operator unit in the host config hands winston that; without it every
    # iteration fails on permissions and this sits in the 30s backoff.
    serviceConfig = {
      ExecStart = "${taildrop}/bin/lattice-taildrop ${downloads}";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
