{
  description = "lattice - daily driver NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # A prebuilt nix-index database, rebuilt weekly. Without it nix-index is useless until
    # someone spends several minutes running the indexer by hand.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Asahi kernel, m1n1/U-Boot and audio for the Apple Silicon MacBook. It has no binary
    # cache, so the kernel is built on the Mac itself.
    apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The screenshot overlay, used from the launcher entry in desktop/screenshot.nix.
    # Carried as an input rather than a fetchFromGitHub because upstream already ships a
    # flake whose package does the quickshell wrapping and covers aarch64; the derivation
    # is only the QML tree, and quickshell itself comes from nixpkgs.
    hyprquickframe = {
      url = "github:Ronin-CK/HyprQuickFrame";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Every folder in hosts/ is a machine: hosts/mac is the author's, and hosts/macbook a
      # clean install with nothing personal in it, which lattice-install copies for each new
      # one. Read from the directory so that copy is all a new host takes.
      nixosConfigurations = nixpkgs.lib.mapAttrs (
        name: _:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/${name} ];
        }
      ) (nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));

      # Both hosts as CI sees them. The Apple firmware only exists on a Mac that ran the
      # Asahi installer, so it is left out; everything else is the host as it ships.
      ci = nixpkgs.lib.mapAttrs (
        _: host:
        host.extendModules {
          modules = [ ({ lib, ... }: { lattice.asahi.firmwareHash = lib.mkForce null; }) ];
        }
      ) inputs.self.nixosConfigurations;

      # The installer ISO; see installer/ and docs/install.md. Built on the Mac rather than in
      # CI, since it boots the patched Asahi kernel, which CI never builds.
      packages.aarch64-linux.installer = inputs.apple-silicon.lib.mkInstallerBootstrapCustom {
        system = "aarch64-linux";
        extraModules = [
          ./installer
          { _module.args.inputs = inputs; }
        ];
      };

      # Tools for scripts/, pinned by flake.lock. The scripts enter it themselves.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            jq
            mkpasswd
            sops
            ssh-to-age
          ];
          LATTICE_DEV_SHELL = "1";
        };
      });

      # Generated hardware configs stay as nixos-generate-config wrote them.
      formatter = forAllSystems (
        pkgs:
        pkgs.nixfmt-tree.override {
          settings.formatter.nixfmt.excludes = [ "hosts/*/hardware-configuration.nix" ];
        }
      );
    };
}
