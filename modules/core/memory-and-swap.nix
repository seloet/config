{ config, lib, ... }:

let
  cfg = config.seloet.memory;
in
{
  options.seloet.memory = {
    enable = lib.mkEnableOption "the shared memory and swap policy";

    zramPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 50;
      description = "Percentage of physical memory available as compressed zram swap.";
    };

    swapfilePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/swapfile";
      description = "Disk swapfile path, or null to use only hardware-defined swap partitions.";
    };

    swapfileSizeMb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16384;
      description = "Size in MiB of the disk swapfile; unused when swapfilePath is null.";
    };
  };

  options.swapDevices = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      config = lib.mkIf cfg.enable {
        priority = lib.mkDefault 10;
      };
    });
  };

  config = lib.mkIf cfg.enable {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = cfg.zramPercent;
      priority = 100;
    };

    swapDevices = lib.optional (cfg.swapfilePath != null) {
      device = cfg.swapfilePath;
      size = cfg.swapfileSizeMb;
    };

    boot.kernel.sysctl = {
      "vm.swappiness" = 100;
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.dirty_bytes" = 268435456;
      "vm.dirty_background_bytes" = 67108864;
    };

    systemd.oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
    };

    services.ananicy.enable = lib.mkDefault false;

    nix = {
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
    };

    systemd.services.nix-daemon.serviceConfig = {
      MemoryHigh = "75%";
      MemoryMax = "85%";
      OOMScoreAdjust = 500;
      CPUWeight = 20;
      IOWeight = 20;
    };
  };
}
