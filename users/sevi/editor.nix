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
      # Nix-built tree-sitter CLI so nvim-treesitter can compile parsers
      # natively. The prebuilt binary it tries to download is a generic
      # glibc ELF that NixOS refuses to execute ("Could not start
      # dynamically linked executable"), which is what caused the
      # treesitter errors on every startup.
      tree-sitter
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