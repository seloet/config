{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.local-assistant;
  command = lib.escapeShellArgs (
    [
      "${cfg.package}/bin/local-assistant"
      "--mic"
      "--config"
      (if cfg.speechConfig == null then "<unset>" else cfg.speechConfig)
    ]
    ++ lib.optional cfg.playChime "--play-chime"
    ++ lib.optional (!cfg.notifications) "--no-notifications"
    ++ cfg.extraArgs
  );
in
{
  options.services.local-assistant = {
    enable = lib.mkEnableOption "the LocalAssistant local voice service";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.local-assistant.packages.\${pkgs.system}.default";
      description = "LocalAssistant package to run.";
    };

    speechConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/severin/.config/local-assistant/speech.yaml";
      description = ''
        Absolute path to speech.yaml. Model paths may be absolute or relative
        to this file. The service refuses evaluation when this is unset.
      '';
    };

    playChime = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Play the local activation chime after wake detection.";
    };

    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show local desktop notifications for prompts and results.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--no-notifications" ];
      description = "Additional arguments passed verbatim to LocalAssistant.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.speechConfig != null;
        message = "services.local-assistant.speechConfig must be set";
      }
      {
        assertion = cfg.speechConfig == null || lib.hasPrefix "/" cfg.speechConfig;
        message = "services.local-assistant.speechConfig must be an absolute path";
      }
    ];

    home.packages = [ cfg.package ];

    systemd.user.services.local-assistant = {
      Unit = {
        Description = "LocalAssistant local voice assistant";
        Documentation = "https://github.com/seloet/local-assistant";
        After = [
          "graphical-session.target"
          "pipewire.service"
        ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = lib.escapeShellArgs [
          "${pkgs.coreutils}/bin/test"
          "-r"
          (if cfg.speechConfig == null then "<unset>" else cfg.speechConfig)
        ];
        ExecStart = command;
        WorkingDirectory = config.home.homeDirectory;
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
