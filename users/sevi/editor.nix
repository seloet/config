{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;

    # toolchains for nvim plugins / LSP
    extraPackages = with pkgs; [
      gnumake
      gcc
      nodejs

      python3
      pyright
      ruff

      marksman
      markdownlint-cli2
      prettier
      harper

      texlab
      texliveSmall

      (rWrapper.override { packages = with rPackages; [ languageserver ]; })
    ];
  };

  # atomically mounts ./nvim over ~/.config/nvim
  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}