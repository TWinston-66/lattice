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
      nixosConfigurations.dell = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/dell
        ];
      };

      nixosConfigurations.mac = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/mac
        ];
      };

      # Tools for scripts/, pinned by flake.lock. The scripts enter it themselves.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
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
