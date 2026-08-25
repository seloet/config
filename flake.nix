{
  nixConfig = {
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
    # numtide's binary cache for llm-agents.nix packages (avoids building from source)
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
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
    herdr = {
      url = "github:ogulcancelik/herdr/v0.7.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    beellama = {
      url = "github:Anbeeld/beellama.cpp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      stylix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkBeeLlama =
        backend:
        let
          upstream = inputs.beellama.packages.${system}.${if backend == "cuda" then "cuda" else "default"};
        in
        pkgs.runCommand "beellama-renamed-${backend}" { } ''
          mkdir -p "$out/bin"
          for executable in ${upstream}/bin/llama-*; do
            name="$(basename "$executable")"
            ln -s "$executable" "$out/bin/bee-''${name#llama-}"
          done
        '';
      mkNixosHost =
        { modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            home-manager.nixosModules.home-manager
            stylix.nixosModules.stylix
          ]
          ++ modules;
        };
    in
    {
      lib.mkNixosHost = mkNixosHost;

      packages.${system} = {
        beellama-cpu = mkBeeLlama "cpu";
        beellama-cuda = mkBeeLlama "cuda";
      };

      nixosConfigurations = {
        laptop = mkNixosHost {
          modules = [ ./hosts/laptop/configuration.nix ];
        };

        desktop = mkNixosHost {
          modules = [ ./hosts/desktop/configuration.nix ];
        };

        surface = mkNixosHost {
          modules = [
            ./hosts/surface/configuration.nix
            inputs.nixos-hardware.nixosModules.microsoft-surface-pro-intel
          ];
        };
      };
    };
}
