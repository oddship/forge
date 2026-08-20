{
  description = "Development environment for Forge infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    "logchef-nix".url = "github:oddship/logchef-nix";
    "sops-nix" = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      logchef = inputs."logchef-nix";
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);

      devShells = forEachSystem (system: {
        default = import ./devshell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
      });

      nixosConfigurations.local-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs."sops-nix".nixosModules.sops
          ./hosts/local-vm.nix
          ./modules/local-secrets.nix
          ./modules/secrets.nix
        ];
      };

      nixosConfigurations.hetzner-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs."sops-nix".nixosModules.sops
          ./hosts/hetzner-vm.nix
          ./modules/secrets.nix
        ];
      };

      nixosConfigurations.local-observability = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit logchef;
        };
        modules = [ ./hosts/observability.nix ];
      };

      checks.x86_64-linux = import ./tests {
        inherit logchef nixpkgs;
        sopsNix = inputs."sops-nix";
      };
    };
}
