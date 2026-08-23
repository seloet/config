{
  config,
  lib,
  inputs,
  ...
}:

{
  imports = [
    ./common.nix
    inputs.local-assistant.homeManagerModules.default
    ./apps.nix
    ./gdrive.nix
    ./editor.nix
    ./noctalia.nix
    ./hyprland.nix
    ./wallpaper.nix
    ./cliphist.nix
  ];

  options.workstation = {
    monitors = lib.mkOption {
      description = "Hyprland monitor definitions for this workstation.";
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            output = lib.mkOption { type = lib.types.str; };
            mode = lib.mkOption { type = lib.types.str; };
            position = lib.mkOption { type = lib.types.str; };
            scale = lib.mkOption { type = lib.types.number; };
            transform = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
            };
          };
        }
      );
    };
    portableWidgets = lib.mkOption {
      description = "Whether portable-only applications and battery/brightness widgets are enabled.";
      type = lib.types.bool;
    };
    automaticSuspend = lib.mkOption {
      description = "Whether idle sessions suspend after 30 minutes.";
      type = lib.types.bool;
    };
    llmBackend = lib.mkOption {
      description = "Acceleration backend for local LLM tools.";
      type = lib.types.enum [
        "cpu"
        "cuda"
      ];
    };
  };

  config = {
    services.local-assistant = {
      enable = true;
      speechConfig = "/home/severin/LocalAssistant/config/speech.yaml";
      playChime = true;
      notifications = true;
    };

    home.file.".local/bin/keep-awake" = {
      source = ./scripts/keep-awake;
      executable = true;
      force = true;
    };

    assertions = [
      {
        assertion = config.workstation.monitors != [ ];
        message = "A workstation must define at least one monitor.";
      }
    ];
  };
}
