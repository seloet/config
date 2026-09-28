{ pkgs, lib, config, ... }:

{
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

    systemd.services.NetworkManager-wait-online.enable = false;

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
