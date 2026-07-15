{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    # External toolchains required by Neovim to parse tree-sitter or compile runtimes
    extraPackages = with pkgs; [
      ripgrep
      fd
      gnumake
      gcc
      git
      tree-sitter
    ];
  };

  # Instantly mounts the local nvim/ directory over ~/.config/nvim atomically
  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}