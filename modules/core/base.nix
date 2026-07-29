{ pkgs, ... }:

{
  time.timeZone = "Europe/Zurich";
  console.keyMap = "sg";

  boot = {
    consoleLogLevel = 0;
    kernelParams = [ "quiet" "systemd.show_status=false" ];
    loader = {
      systemd-boot.enable = true;
      timeout = 1;
      efi.canTouchEfiVariables = true;
    };
  };

  # Network-aware services retry on their own; do not hold up the login screen
  # while NetworkManager waits for Wi-Fi to finish associating.
  systemd.services.NetworkManager-wait-online.enable = false;

  # FUSE helper for user-level rclone mounts.
  programs.fuse.enable = true;
  programs.zsh.enable = true;

  users.users.severin = {
    isNormalUser = true;
    description = "Severin";
    group = "severin";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    shell = pkgs.zsh;
  };
  users.groups.severin = { };
}
