{ pkgs, ... }:

{
  home.packages = with pkgs; [
    brave
    micro

    # Keep Tuxedo as it currently exists in the configuration.
    tuxedo

    # Required by the existing Google Drive setup.
    rclone

    playerctl
    pavucontrol

    # Useful for checking video acceleration.
    libva-utils
  ];
}
