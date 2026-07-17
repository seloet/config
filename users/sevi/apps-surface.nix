{ pkgs, ... }:

{
  home.packages = with pkgs; [
    brave
    mpv
    micro

    # Keep Tuxedo as it currently exists in the configuration.
    tuxedo

    # Required by the existing Google Drive setup.
    rclone

    brightnessctl
    playerctl
    pavucontrol
    wl-clipboard

    # Useful for checking video acceleration.
    libva-utils
  ];
}
