{ pkgs, ... }:

let
  notebookKernel = pkgs.writeTextDir "share/jupyter/kernels/nix-python3/kernel.json" (
    builtins.toJSON {
      argv = [
        "${pkgs.python3.withPackages (ps: [ ps.ipykernel ])}/bin/python3"
        "-m"
        "ipykernel_launcher"
        "-f"
        "{connection_file}"
      ];
      display_name = "Python 3 (Nix)";
      language = "python";
    }
  );
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = true;
    sideloadInitLua = true;

    extraWrapperArgs = [
      "--prefix"
      "LD_LIBRARY_PATH"
      ":"
      "${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc ]}"
      "--prefix"
      "JUPYTER_PATH"
      ":"
      "${notebookKernel}/share/jupyter"
    ];

    extraPython3Packages = ps: with ps; [
      pynvim
      jupyter-client
      nbformat
    ];

    extraPackages = with pkgs; [
      gnumake
      gcc
      tree-sitter
      nodejs
      lua5_1
      lua51Packages.luarocks

      python3
      python3Packages.jupytext
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

  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };
}
