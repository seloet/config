{ pkgs, ... }:

# google-colab-cli is not in nixpkgs. It depends on two small packages that are
# also missing from nixpkgs (jupyter-kernel-client, jupyter-mimetypes). We define
# them locally as buildPythonPackage derivations and wrap google-colab-cli as a
# buildPythonApplication so it lands in the system profile.
#
# Note: jupyter-kernel-client and jupyter-mimetypes only publish wheels (no sdist),
# so they are fetched as wheels and built with format = "wheel".

let
  python = pkgs.python3;

  jupyter-mimetypes = python.pkgs.buildPythonPackage rec {
    pname = "jupyter-mimetypes";
    version = "0.2.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/72/45/cb4671e13fed39f721066ad1a00714d4b607982b8d3e97a25f836198d1df/jupyter_mimetypes-0.2.0-py3-none-any.whl";
      hash = "sha256-5tzZiSWOP8lENltlbZFzGRUX4OOTvYeOl85QDls4hSc=";
    };
    # pyarrow is only needed for parquet support, which colab does not use.
    # The runtime-deps check would require it; disable that check for this pkg.
    dontCheckRuntimeDeps = true;
    propagatedBuildInputs = [ python.pkgs.typing-extensions ];
    doCheck = false;
    pythonImportsCheck = [ "jupyter_mimetypes" ];
  };

  jupyter-kernel-client = python.pkgs.buildPythonPackage rec {
    pname = "jupyter-kernel-client";
    version = "0.9.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/7a/68/287315ba355aa93bda2e344de5febc45e6de1b47d8f4a5b69400b24cfdfd/jupyter_kernel_client-0.9.0-py3-none-any.whl";
      hash = "sha256-d6y48vc42XYl1r0B7ozyHE1ZeQt7pGQQhxLbOHBBbyA=";
    };
    propagatedBuildInputs = [
      python.pkgs.jupyter-client
      python.pkgs.jupyter-core
      jupyter-mimetypes
      python.pkgs.requests
      python.pkgs.traitlets
      python.pkgs.typing-extensions
      python.pkgs.websocket-client
    ];
    doCheck = false;
    pythonImportsCheck = [ "jupyter_kernel_client" ];
  };

  google-colab-cli = python.pkgs.buildPythonApplication rec {
    pname = "google-colab-cli";
    version = "0.6.0";
    pyproject = true;
    nativeBuildInputs = [ python.pkgs.hatchling python.pkgs.hatch-vcs ];
    # filelock in nixpkgs is 3.29.0 vs the >=3.29.2 pin; functionally fine.
    dontCheckRuntimeDeps = true;
    src = pkgs.fetchPypi {
      pname = "google_colab_cli";
      inherit version;
      hash = "sha256-mK3C4gDfQhoM27TYW8cF7U5djBaJK1hJkt3+rHRiWso=";
    };
    propagatedBuildInputs = [
      python.pkgs.click
      python.pkgs.filelock
      python.pkgs.google-auth-oauthlib
      python.pkgs.google-auth
      python.pkgs.html2text
      jupyter-kernel-client
      python.pkgs.nbformat
      python.pkgs.packaging
      python.pkgs.prompt-toolkit
      python.pkgs.pydantic
      python.pkgs.pygments
      python.pkgs.requests
      python.pkgs.rich
      python.pkgs.typer
      python.pkgs.typing-extensions
      python.pkgs.websocket-client
    ];
    doCheck = false;
    pythonImportsCheck = [ "colab_cli" ];
  };

in
{
  environment.systemPackages = [ google-colab-cli ];
}
