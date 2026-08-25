{
  description = "LocalAssistant package, Home Manager service, and dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      makePackage = pkgs:
        pkgs.python312Packages.buildPythonApplication {
          pname = "local-assistant";
          version = "0.1.0";
          pyproject = true;
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./pyproject.toml
              ./app.py
              ./audio
              ./config
              ./data
              ./output
              ./parser
              ./safety
              ./speech
              ./tools
            ];
          };

          build-system = with pkgs.python312Packages; [ setuptools ];
          dependencies = with pkgs.python312Packages; [
            numpy
            pillow
            pydantic
            pyparsing
            pystray
            pyyaml
            sherpa-onnx
            sounddevice
          ];

          # nixpkgs' sherpa-onnx exposes the importable `sherpa_onnx` module but
          # does not expose matching Python distribution metadata to the
          # runtime dependency checker. Keep it in `dependencies`, remove only
          # the unsatisfiable wheel-metadata edge, and verify the import below.
          pythonRemoveDeps = [ "sherpa-onnx" ];
          pythonImportsCheck = [
            "app"
            "sherpa_onnx"
          ];

          nativeBuildInputs = [ pkgs.makeWrapper ];
          doCheck = false;

          postFixup = ''
            wrapProgram "$out/bin/local-assistant" \
              --prefix PATH : ${nixpkgs.lib.makeBinPath [
                pkgs.libnotify
                pkgs.playerctl
                pkgs.util-linux
                pkgs.wireplumber
              ]}
          '';

          meta = {
            description = "Always-on fully local Linux voice assistant";
            mainProgram = "local-assistant";
            platforms = nixpkgs.lib.platforms.linux;
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        localAssistant = makePackage pkgs;
        python = pkgs.python312.withPackages (ps: with ps; [
          sherpa-onnx
          pydantic
          pyyaml
          numpy
          pyparsing
          pytest
          scipy
          sounddevice
          soundfile
          pystray
          pillow
        ]);
      in
      {
        packages = {
          default = localAssistant;
          local-assistant = localAssistant;
        };

        apps.default = {
          type = "app";
          program = "${localAssistant}/bin/local-assistant";
          meta = localAssistant.meta;
        };

        checks = {
          package = localAssistant;
          home-manager-module = import ./nix/test-home-manager-module.nix {
            inherit pkgs self;
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            python
            pkgs.portaudio        # libportaudio.so for sounddevice
            pkgs.wireplumber      # wpctl
            pkgs.playerctl
            pkgs.libnotify        # notify-send
            pkgs.util-linux       # loginctl
            pkgs.stdenv.cc.cc.lib # libstdc++.so.6 for the venv's sherpa-onnx wheel
          ];
          shellHook = ''
            echo "LocalAssistant dev shell ready"
            # The .venv sherpa-onnx wheel links libstdc++.so.6; expose it so
            # `python -c "import sherpa_onnx"` works with no manual LD_LIBRARY_PATH.
            export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH
          '';
        };
      }
    )
    // {
      homeManagerModules.default = import ./nix/home-manager-module.nix {
        inherit self;
      };
    };
}
