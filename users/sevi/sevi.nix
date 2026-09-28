{
  config,
  lib,
  ...
}:

{
  imports = [
    ./common.nix
    ./apps.nix
    ./gdrive.nix
    ./calendar.nix
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
    mach1Backend = lib.mkOption {
      description = "Acceleration backend for the Mach-1 llama.cpp fork.";
      type = lib.types.enum [
        "cpu"
        "cuda"
        "vulkan"
      ];
    };
    keyboard = lib.mkOption {
      description = "Hyprland keyboard layout for this host.";
      type = lib.types.str;
    };
    localAssistant = lib.mkOption {
      description = "Whether LocalAssistant and its Noctalia widget are enabled.";
      type = lib.types.bool;
    };
  };

  config = {
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
