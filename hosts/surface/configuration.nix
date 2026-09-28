{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/base.nix
    ../../modules/desktop/hyprland.nix
    ../../modules/themes/stylix.nix
  ];

  modules.desktop.hyprland.enable = true;

  networking.hostName = "surface";
  networking.networkmanager.enable = true;

  boot.loader.systemd-boot.configurationLimit = 5;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    extraSpecialArgs = {
      inherit inputs;
      user = "severin";
    };

    users.severin = import ../../users/sevi/surface.nix;
  };

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
  };

  hardware.graphics.extraPackages = with pkgs; [
    intel-vaapi-driver
  ];

  hardware.bluetooth.enable = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  systemd.oomd.enable = true;

  services.fstrim.enable = true;
  services.thermald.enable = true;

  services.upower.enable = true;

  services.journald.settings.Journal = {
    SystemMaxUse = "100M";
    RuntimeMaxUse = "50M";
    MaxRetentionSec = "7day";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    max-jobs = 1;
    cores = 2;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.printing.enable = false;
  services.avahi.enable = false;
  services.openssh.enable = false;

  environment.systemPackages = with pkgs; [
    mosh
  ];

  system.stateVersion = "26.11";
}
