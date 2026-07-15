{ pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    settings.manager.show_hidden = true;
  };

  # Open PDFs in Zathura (the system default for yazi). The Home Manager
  # yazi module only generates yazi.toml from `settings`; openers live in a
  # separate opener.toml, so we ship it directly via xdg.configFile.
  xdg.configFile."yazi/opener.toml".text = ''
    [opener]
    mime = [
      { match = "application/pdf", use = "zathura" },
    ]

    [zathura]
    run = 'zathura "$@"'
  '';
}
