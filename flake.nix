{
  description = "lattice - daily driver NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
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
