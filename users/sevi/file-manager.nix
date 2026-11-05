{ pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "yy";
    settings = {
      manager.show_hidden = true;
      opener.zathura = [
        {
          run = "zathura %s";
          desc = "Zathura";
          for = "linux";
          orphan = true;
        }
      ];
      opener.glow = [
        {
          run = "glow --tui %s1";
          desc = "Glow";
          for = "linux";
          block = true;
        }
      ];
      opener.nvim = [
        {
          run = "nvim %s";
          desc = "Neovim";
          for = "linux";
          block = true;
        }
      ];
      open.prepend_rules = [
        {
          url = "*.ipynb";
          use = "nvim";
        }
        {
          url = "*.md";
          use = "glow";
        }
        {
          mime = "application/pdf";
          use = "zathura";
        }
        {
          mime = "text/markdown";
          use = "glow";
        }
        {
          mime = "text/plain";
          use = "nvim";
        }
        {
          url = "*.nix";
          use = "nvim";
        }
      ];
    };
  };

  xdg.desktopEntries.glow = {
    name = "Glow";
    genericName = "Markdown Viewer";
    comment = "Render Markdown in a terminal";
    exec = "${pkgs.ghostty}/bin/ghostty -o background-opacity=1 -e ${pkgs.glow}/bin/glow --tui %f";
    terminal = false;
    type = "Application";
    mimeType = [ "text/markdown" ];
    categories = [ "Utility" ];
  };

  xdg.configFile."fsel/config.toml".text = ''
    terminal_launcher = "ghostty -e"
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications."application/pdf" = [
      "org.pwmt.zathura-pdf-mupdf.desktop"
    ];
    defaultApplications."text/markdown" = [
      "glow.desktop"
    ];
    defaultApplications."text/plain" = [
      "nvim.desktop"
    ];
  };
}
