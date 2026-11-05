{ pkgs, ... }:

{
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;

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
  services.printing = {
    enable = true;
    drivers = [ (pkgs.hplipWithPlugin.override { withQt5 = false; }) ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
