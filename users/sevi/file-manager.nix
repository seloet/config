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
      open.prepend_rules = [
        {
          mime = "application/pdf";
          use = "zathura";
        }
      ];
    };
  };

  # Zathura is Yazi's fallback when xdg-open is used
  xdg.mimeApps = {
    enable = true;
    defaultApplications."application/pdf" = [
      "org.pwmt.zathura-pdf-mupdf.desktop"
    ];
  };
}
