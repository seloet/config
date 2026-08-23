{ lib, ... }:

{
  # TEMPLATE ONLY: replace both UUIDs with nixos-generate-config output and
  # add the real CPU/GPU modules before attempting to activate this host.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-EFI-UUID";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  warnings = [
    "The desktop hardware configuration is a non-deployable template; replace disk UUIDs and configure its CPU/GPU first."
  ];

  # Keep evaluation and builds useful while making an accidental `switch`
  # fail before it can activate placeholder hardware settings.
  system.activationScripts.desktop-hardware-template.text = ''
    echo "Refusing to activate the desktop hardware template." >&2
    echo "Generate real hardware configuration and remove this guard first." >&2
    exit 1
  '';
}
