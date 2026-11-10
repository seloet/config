{ lib, ... }:

{
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        onnxruntime = prev.onnxruntime.override { cudaSupport = false; };
      })
    ];
  };

  nix.settings = {
    max-jobs = 2;
    cores = 4;
    http-connections = 50;
    builders-use-substitutes = true;
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  documentation = {
    # Installation media otherwise force-enable the NixOS manual.
    nixos.enable = lib.mkForce false;
    doc.enable = false;
    info.enable = false;
  };
}
