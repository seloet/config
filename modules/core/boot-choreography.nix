{ config, lib, pkgs, ... }:

let
  cfg = config.seloet.bootChoreography;
  kmsModules = {
    nvidia = [ "nvidia" "nvidia_modeset" "nvidia_drm" ];
    amdgpu = [ "amdgpu" ];
    i915 = [ "i915" ];
    none = [ ];
  };
  greeterCommand = lib.escapeShellArgs [
    "${pkgs.tuigreet}/bin/tuigreet"
    "--time"
    "--remember"
    "--remember-user-session"
    "--asterisks"
    "--window-padding" "2"
    "--container-padding" "2"
    "--prompt-padding" "1"
    "--theme" "border=darkgray;text=white;prompt=cyan;time=darkgray;action=darkgray;button=cyan;container=black;input=white"
    "--greeting" "seloet // workstation"
    "--cmd" "start-hyprland"
  ];
in
{
  options.seloet.bootChoreography = {
    enable = lib.mkEnableOption "quiet Plymouth boot and a VT2 login greeter";

    gpuDriver = lib.mkOption {
      type = lib.types.enum [ "nvidia" "amdgpu" "i915" "none" ];
      default = "none";
      description = "Existing GPU driver to load in the initrd for early modesetting.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      consoleLogLevel = 0;
      kernelParams = [
        "quiet"
        "systemd.show_status=false"
        "rd.systemd.show_status=false"
        "udev.log_level=3"
        "rd.udev.log_level=3"
        "vt.global_cursor_default=0"
      ];
      initrd = {
        kernelModules = kmsModules.${cfg.gpuDriver};
      };
      plymouth = {
        enable = true;
        extraConfig = ''
          DeviceScale=1
        '';
      };
    };

    console = {
      earlySetup = true;
      font = lib.mkDefault "ter-v24n";
      packages = [ pkgs.terminus_font ];
    };

    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings = {
        terminal.vt = lib.mkForce 2;
        default_session = {
          command = greeterCommand;
          user = "greeter";
        };
      };
    };

    systemd.services = {
      "autovt@tty1" = {
        enable = lib.mkForce true;
        overrideStrategy = "asDropin";
      };
      "autovt@tty2".enable = false;
      greetd = {
        wants = [ "plymouth-quit.service" "plymouth-quit-wait.service" ];
        unitConfig = {
          After = lib.mkForce [
            "systemd-user-sessions.service"
            "getty@tty2.service"
            "plymouth-quit.service"
            "plymouth-quit-wait.service"
          ];
          Conflicts = lib.mkForce [ "getty@tty2.service" ];
        };
        serviceConfig.TTYPath = lib.mkForce "/dev/tty2";
      };
    };
  };
}
