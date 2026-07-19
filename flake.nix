{
  nixConfig = {
    extra-experimental-features = [ "nix-command" "flakes" ];
  };

  description = "Dendritic Multi-Host System Layout";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, home-manager, stylix, ... }@inputs: {
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/laptop/configuration.nix
        home-manager.nixosModules.home-manager
        stylix.nixosModules.stylix
      ];
    };

    nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/surface/configuration.nix
        home-manager.nixosModules.home-manager
        stylix.nixosModules.stylix
        inputs.nixos-hardware.nixosModules.microsoft-surface-pro-intel
      ];
    };
  };
}
