{ lib, ... }:

{
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."root" = {
    device = "/dev/disk/by-uuid/0b75c7f8-d5bd-4025-b7a5-1a76c24b3f1f";
    bypassWorkqueues = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = [ "subvol=@log" "compress=zstd" ];
  };

  fileSystems."/var/cache/pacman/pkg" = {
    device = "/dev/mapper/root";
    fsType = "btrfs";
    options = [ "subvol=@pkg" "compress=zstd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/18AD-C962";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  fileSystems."/mnt/storage-120gb" = {
    device = "/dev/disk/by-uuid/6d1d90a4-0490-42f7-b592-8ab3fae5eba9";
    fsType = "ext4";
  };

  fileSystems."/mnt/storage-2tb" = {
    device = "/dev/disk/by-uuid/eea48b21-40d4-4acd-aeaa-03e2f08673fc";
    fsType = "ext4";
  };

  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/efbf29df-e907-411f-9743-fecbed8492e7";
    fsType = "ext4";
  };

  swapDevices = [ ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    nvidiaSettings = true;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
