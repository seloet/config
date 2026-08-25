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
    ../core/base.nix
    ../core/services.nix
    ../desktop/hyprland.nix
    ../themes/stylix.nix
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
    nixpkgs.config = {
      allowUnfree = true;
      cudaSupport = cfg.llmBackend == "cuda";
    };

    nix = {
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
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
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };

    services.power-profiles-daemon.enable = cfg.portableWidgets;
    services.upower.enable = cfg.portableWidgets;

    users.users."${cfg.user}".extraGroups = [ "docker" ];
    environment.systemPackages = with pkgs; [
      curl
      wget
      docker-compose
      (python3.withPackages (ps: [ ps.requests ]))
      modal
      ntfs3g
      usbutils
      pciutils
      foot
      mosh
      kdePackages.kdeconnect-kde
      inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; inherit (cfg) user; };
      users."${cfg.user}" = {
        imports = [
          ../../users/sevi/sevi.nix
          ../../users/sevi/moshi.nix
          inputs.noctalia.homeModules.default
        ];
        workstation = {
          inherit (cfg)
            monitors
            portableWidgets
            automaticSuspend
            llmBackend
            keyboard
            ;
        };
      };
    };
  };
}
