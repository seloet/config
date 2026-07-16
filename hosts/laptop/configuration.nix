{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/services.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/themes/stylix.nix
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

  # Zurich; drives Noctalia's clock widget
  time.timeZone = "Europe/Zurich";

  boot.consoleLogLevel = 0;
  boot.kernelParams = [ "quiet" "systemd.show_status=false" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # FUSE helper for rclone/GDrive FUSE mount
  programs.fuse.enable = true;

  users.users.severin = {
    isNormalUser = true;
    description = "Severin";
    group = "severin";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "docker" ];
    shell = pkgs.zsh;
  };
  users.groups.severin = {};

  programs.zsh.enable = true;
  environment.systemPackages = with pkgs; [
    curl
    wget
    docker
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
    users.severin ={
    imports = [
      ../../users/sevi/sevi.nix
      # Defines programs.noctalia; without it the bar never applies.
      inputs.noctalia.homeModules.default
    ];
    home.homeDirectory = "/home/severin";
      home.username = "severin";
  };
};
  console.keyMap = "sg";

  system.stateVersion = "23.11";
}
