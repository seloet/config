{
  nixConfig = {
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  description = "Dendritic Multi-Host System Layout";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-kernel.url = "github:nixos/nixpkgs/nixos-unstable";
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
    local-assistant = {
      url = "path:./vendor/local-assistant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.9.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };
    beellama = {
      url = "github:Anbeeld/beellama.cpp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llama-mach1 = {
      url = "github:SyzygyResearch/llama.cpp-mach1";
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
      mkMach1 =
        backend:
        let
          upstream = inputs.llama-mach1.packages.${system}.${backend};
        in
        pkgs.runCommand "mach1-renamed-${backend}" { } ''
          mkdir -p "$out/bin"
          for executable in ${upstream}/bin/llama-*; do
            name="$(basename "$executable")"
            ln -s "$executable" "$out/bin/mach1-''${name#llama-}"
          done
        '';
      baseSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
          ./modules/core/base.nix
          ./modules/core/memory-and-swap.nix
          ./modules/core/boot-choreography.nix
          ./modules/desktop/hyprland.nix
          ./modules/themes/stylix.nix
          {
            seloet.memory.enable = true;
            seloet.bootChoreography.enable = true;
          }
        ];
      };
    in
    {
      packages.${system} = {
        beellama-cpu = mkBeeLlama "cpu";
        beellama-cuda = mkBeeLlama "cuda";
        mach1-cuda = mkMach1 "cuda";
        mach1-vulkan = mkMach1 "vulkan";
        installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;
      };

      nixosConfigurations = {
        laptop = baseSystem.extendModules {
          modules = [ ./hosts/laptop/configuration.nix ];
        };

        desktop = baseSystem.extendModules {
          modules = [ ./hosts/desktop/configuration.nix ];
        };

        surface = baseSystem.extendModules {
          modules = [
            ./hosts/surface/configuration.nix
            inputs.nixos-hardware.nixosModules.microsoft-surface-pro-intel
          ];
        };

        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/installer/configuration.nix ];
        };
      };
    };
}
