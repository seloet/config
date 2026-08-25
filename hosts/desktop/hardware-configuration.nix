# Real hardware configuration for the desktop host (generated 2026-08-25
# against the running Omarchy install, which this NixOS flake replaces).
#
# Disk layout (kept intact across the reinstall — /home data survives):
#   sda: 447G SSD
#     ├─ sda1  vfat        EFI system partition          -> /boot
#     └─ sda2  crypto_LUKS "root"                         -> unlocked as /dev/mapper/root
#        └─ btrfs with subvolumes @, @home, @log, @pkg
#   sdb1/sdc1/sdd1: ext4 data disks mounted under /mnt/storage*
#
# Swap is zram-only (zramSwap configured in profiles/workstation.nix).
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
    # Ask for the passphrase once; systemd stage handles it.
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

  # Intel i7-10700KF + NVIDIA RTX 2060 (Turing). The NVIDIA driver is required
  # for Hyprland and for the CUDA LLM backend selected in the workstation profile.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    # Turing consumer GPUs are supported by the open kernel module.
    open = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    nvidiaSettings = true;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # NOTE: verify these UUIDs against the actual disk before installing:
  #   lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS
}
