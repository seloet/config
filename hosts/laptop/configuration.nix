{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/profiles/workstation.nix
  ];

  networking.hostName = "laptop";

  profiles.workstation = {
    enable = true;
    portableWidgets = true;
    automaticSuspend = true;
    llmBackend = "cpu";
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

  system.stateVersion = "23.11";
}
