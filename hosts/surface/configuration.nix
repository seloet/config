{ pkgs, inputs, ... }:

# Surface host: lean Hyprland profile reusing the laptop's shared modules but
# with the Surface Home Manager leaf (surface.nix) and Surface-specific
# resource settings (zram, oomd, thermald, trimmed journald, single-job builds).
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/base.nix

    # Shared system modules reused from the laptop layout.
    # desktop/hyprland provides the greetd login, xdg-portal, brightnessctl
    # (Noctalia brightness widget) and the Hyprland system binary.
    ../../modules/desktop/hyprland.nix
    # stylix is required: zathura.nix + Noctalia theming read config.lib.stylix.colors.
    ../../modules/themes/stylix.nix

    # NOTE: modules/core/services.nix is intentionally NOT imported here. Its
    # pipewire/printing/tailscale/docker/bluetooth settings are either inlined
    # leaner below or disabled. Keep the Tuxedo package (apps-surface.nix) as-is.
  ];

  # Apply the shared Hyprland desktop module.
  modules.desktop.hyprland.enable = true;

  networking.hostName = "surface";
  networking.networkmanager.enable = true;

  boot.loader.systemd-boot.configurationLimit = 5;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    extraSpecialArgs = {
      inherit inputs;
    };

    users.severin = import ../../users/sevi/surface.nix;
  };

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
  };

  # Surface Pro 1796 = Surface Pro (2017) = Kaby Lake (Gen 7.5).
  # Use the i965/intel-vaapi-driver, NOT intel-media-driver (that targets
  # Gen 8+/newer). Re-evaluate only if the exact CPU generation differs.
  hardware.graphics.extraPackages = with pkgs; [
    intel-vaapi-driver
  ];

  # Noctalia's bluetooth widget needs the bluetooth backend (core/services.nix
  # is intentionally not imported on the Surface, so enable it here).
  hardware.bluetooth.enable = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  systemd.oomd.enable = true;

  services.fstrim.enable = true;
  services.thermald.enable = true;

  # Noctalia's battery widget reads UPower over DBus.
  services.upower.enable = true;

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
    MaxRetentionSec=7day
  '';

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    max-jobs = 1;
    cores = 2;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.printing.enable = false;
  services.avahi.enable = false;
  services.openssh.enable = false;

  system.stateVersion = "26.11";
}
