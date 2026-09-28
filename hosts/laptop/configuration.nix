{ inputs, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/profiles/workstation.nix
  ];

  networking.hostName = "laptop";

  boot.crashDump = {
    enable = true;
    reservedMemory = "256M";
  };
  services.fwupd.enable = true;

  boot.kernelPackages = lib.mkForce
    inputs.nixpkgs-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_zen;

  profiles.workstation = {
    enable = true;
    user = "severin";
    keyboard = "ch";
    localAssistant = true;
    nasMount = false;
    portableWidgets = true;
    automaticSuspend = true;
    llmBackend = "cpu";
    mach1Backend = "vulkan";
    monitors = [
      {
        output = "eDP-1";
        mode = "preferred";
        position = "auto";
        scale = 1.5;
      }
      {
        output = "HDMI-A-1";
        mode = "1920x1080";
        position = "-1080x0";
        scale = 1;
        transform = 1;
      }
    ];
  };

  virtualisation.docker.enable = lib.mkForce false;

  boot.loader.systemd-boot.memtest86.enable = true;
  hardware.rasdaemon.enable = true;
  hardware.rasdaemon.extraModules = [ "amd64_edac" ];

  system.stateVersion = "23.11";
}
