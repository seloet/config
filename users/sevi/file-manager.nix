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
          run = "zathura %s1";
          desc = "Zathura";
          for = "linux";
          orphan = true;
        }
      ];
      opener.glow = [
        {
          run = "glow %s1";
          desc = "Glow";
          for = "linux";
          block = true;
        }
      ];
      opener.nvim = [
        {
          run = "nvim %s1";
          desc = "Neovim";
          for = "linux";
          block = true;
        }
      ];
      open.prepend_rules = [
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
          url = "*.md";
          use = "glow";
        }
        {
          url = "*.nix";
          use = "nvim";
        }
      ];
    };
  };

  # Glow is a terminal application and does not ship a desktop entry.
  xdg.desktopEntries.glow = {
    name = "Glow";
    genericName = "Markdown Viewer";
    comment = "Render Markdown in a terminal";
    exec = "${pkgs.glow}/bin/glow %f";
    terminal = true;
    type = "Application";
    mimeType = [ "text/markdown" ];
    categories = [ "Utility" ];
  };

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
