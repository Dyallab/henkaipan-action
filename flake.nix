{
  description = "HenKaiPan GitHub Action — security scan orchestration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              bash
              shellcheck
              curl
              jq
              docker
              git
            ];

          shellHook = ''
            echo "━━━ HenKaiPan Action Dev Shell ━━━"
            echo "  bash:       $(bash --version | head -n 1)"
            echo "  curl:       $(curl --version | head -n 1)"
            echo "  jq:         $(jq --version)"
            echo "  docker:     $(docker --version 2>/dev/null || echo 'not available')"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };
      }
    );
}
