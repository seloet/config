{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/base.nix
    ../../modules/core/services.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/themes/stylix.nix
    ../../modules/google-colab-cli.nix
  ];

  modules.desktop.hyprland.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix = {
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  networking.hostName = "laptop";

  users.users.severin.extraGroups = [ "docker" ];
  environment.systemPackages = with pkgs; [
    curl
    wget
    docker-compose
    (python3.withPackages (ps: [ ps.requests ]))
    ntfs3g
    usbutils
    pciutils
    foot
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; }; # forwards flake inputs (Noctalia) to user leaves
    users.severin = {
      imports = [
        ../../users/sevi/sevi.nix
        # Defines programs.noctalia; without it the bar never applies.
        inputs.noctalia.homeModules.default
      ];
      home.homeDirectory = "/home/severin";
      home.username = "severin";
    };
  };
  system.stateVersion = "23.11";
}
