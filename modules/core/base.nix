{ pkgs, lib, config, ... }:

{
  # Primary user account; hosts may override (desktop uses "sevi").
  options.modules.core.user = lib.mkOption {
    description = "Primary user account name created by the core module.";
    type = lib.types.str;
    default = "severin";
  };

  config = {
    time.timeZone = "Europe/Zurich";
    console.keyMap = lib.mkDefault "sg";

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

    users.users."${config.modules.core.user}" = {
      isNormalUser = true;
      description = "Severin";
      group = config.modules.core.user;
      extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
      shell = pkgs.zsh;
    };
    users.groups."${config.modules.core.user}" = { };
  };
}
