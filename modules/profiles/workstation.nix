{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.profiles.workstation;
in
{
  imports = [
    ../core/services.nix
    ../google-colab-cli.nix
  ];

  options.profiles.workstation = {
    enable = lib.mkEnableOption "full workstation profile";
    user = lib.mkOption {
      description = "Primary user account name (forwarded from modules.core.user).";
      type = lib.types.str;
      default = "severin";
    };
    keyboard = lib.mkOption {
      description = "Hyprland keyboard layout for this host.";
      type = lib.types.str;
      default = "ch";
    };
    localAssistant = lib.mkEnableOption "the LocalAssistant service and Noctalia widget";
    nasMount = lib.mkEnableOption "the Synology NAS user mount";
    monitors = lib.mkOption {
      description = "Monitor definitions forwarded to the user's Hyprland configuration.";
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
      description = "Enable laptop-only widgets, applications, and power services.";
      type = lib.types.bool;
      default = false;
    };
    automaticSuspend = lib.mkOption {
      description = "Suspend the workstation after 30 minutes idle.";
      type = lib.types.bool;
      default = false;
    };
    llmBackend = lib.mkOption {
      description = "Acceleration backend used to build local LLM tools.";
      type = lib.types.enum [
        "cpu"
        "cuda"
      ];
      default = "cpu";
    };
    mach1Backend = lib.mkOption {
      description = ''
        Acceleration backend for the Mach-1 llama.cpp fork. Mach-1
        checkpoints only load in that fork, so it is built independently of
        the upstream llama.cpp / beellama packages above.
      '';
      type = lib.types.enum [
        "cpu"
        "cuda"
        "vulkan"
      ];
      default = "cpu";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.monitors != [ ];
        message = "profiles.workstation.monitors must contain at least one monitor.";
      }
    ];

    modules.core.user = cfg.user;

    modules.desktop.hyprland.enable = true;
    boot.kernelPackages = pkgs.linuxPackages_zen;

    nix = {
      optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    virtualisation.docker.enableOnBoot = false;

    services.power-profiles-daemon.enable = cfg.portableWidgets;
    services.upower.enable = cfg.portableWidgets;

    users.users."${cfg.user}".extraGroups =
      lib.optionals config.virtualisation.docker.enable [ "docker" ];
    environment.systemPackages = with pkgs; [
      curl
      wget
      (python3.withPackages (ps: [ ps.requests ]))
      modal
      ntfs3g
      usbutils
      pciutils
      foot
      mosh
      kdePackages.kdeconnect-kde
      inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals config.virtualisation.docker.enable [ pkgs.docker-compose ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; inherit (cfg) user; };
      users."${cfg.user}" = {
        imports = [
          ../../users/sevi/sevi.nix
          ../../users/sevi/moshi.nix
          inputs.noctalia.homeModules.default
        ]
        ++ lib.optionals cfg.localAssistant [
          inputs.local-assistant.homeManagerModules.default
          ../../users/sevi/local-assistant.nix
        ]
        ++ lib.optionals cfg.nasMount [
          ../../users/sevi/nas-mount.nix
        ];
        workstation = {
          inherit (cfg)
            monitors
            portableWidgets
            automaticSuspend
            llmBackend
            mach1Backend
            keyboard
            localAssistant
            ;
        };
      };
    };
  };
}
