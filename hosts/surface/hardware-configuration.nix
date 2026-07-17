# Hardware config for the Microsoft Surface host.
#
# !!! REQUIRED BEFORE FIRST BOOT !!!
# The fileSystems UUIDs below are PLACEHOLDERS. On the real Surface, after
# installing NixOS (or booting this config from installation media), run:
#     nixos-generate-config --show-hardware-config
# and paste the generated block over this file. The disk UUIDs MUST match the
# actual partitions or the system will not boot.
#
# Surface-specific support is already enabled in flake.nix through the
# `nixos-hardware` Surface Pro Intel module. It supplies the linux-surface
# kernel and vendor-specific modules for touch, pen, and camera support.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "usb_storage" "sd_mod" "sdhci_pci"
    "iwlwifi" "btusb"            # wifi + bluetooth on most Surface models
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # --- PLACEHOLDER: replace with real UUIDs from `blkid` / lsblk ---
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/REPLACE-ROOT-UUID";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/REPLACE-EFI-UUID";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/REPLACE-SWAP-UUID"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
