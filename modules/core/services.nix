{ pkgs, ... }:

{
  # Core Network Orchestration
  networking.networkmanager.enable = true;

  # Sound architecture (PipeWire ecosystem)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Hardware interface services
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  services.printing.enable = true;

  # Power & Battery reporting infrastructure (Mandatory for Noctalia status metrics)
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
