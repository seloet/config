{ pkgs, ... }:

{
  # Keep normal clipboard history. GTK primary-selection paste is configured
  # directly in common.nix and does not need a second persistent watcher.
  services.cliphist = {
    enable = true;
    package = pkgs.cliphist;
  };
}
