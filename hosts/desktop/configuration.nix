{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/profiles/workstation.nix
  ];

  networking.hostName = "desktop";

  profiles.workstation = {
    enable = true;
    user = "sevi";
    keyboard = "us";
    portableWidgets = false;
    automaticSuspend = false;
    llmBackend = "cuda";
    monitors = [
      {
        output = "DP-1";
        mode = "1920x1080@240";
        position = "0x0";
        scale = 1;
      }
      {
        output = "HDMI-A-1";
        mode = "1920x1080@60";
        position = "auto-right";
        scale = 1;
        transform = 3;
      }
    ];
  };

  system.stateVersion = "26.05";
  console.keyMap = "us";
}
