{ pkgs, ... }:

{
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;

  # local multi-service stacks (e.g. GroktoCrawl)
  virtualisation.docker.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  services.printing.enable = true;

  # battery metrics for Noctalia bar
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
