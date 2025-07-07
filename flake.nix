{
  description = "MCP Filesystem Server - A powerful Model Context Protocol server for filesystem operations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    ...
  }: let
    inherit (nixpkgs) lib;

    # Load a uv workspace from a workspace root.
    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

    # Create package overlay from workspace.
    overlay = workspace.mkPyprojectOverlay {
      sourcePreference = "wheel"; # Prefer prebuilt binary wheels
    };

    # Extend generated overlay with build fixups
    pyprojectOverrides = _final: _prev: {
      # Build fixups for mcp-filesystem if needed
    };

    # Support multiple systems
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = lib.genAttrs systems;

  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python312;

      # Construct package set
      pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
        inherit python;
      }).overrideScope (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
          pyprojectOverrides
        ]
      );
    in {
      default = pythonSet.mkVirtualEnv "mcp-filesystem-env" workspace.deps.default;
      mcp-filesystem = pythonSet.mkVirtualEnv "mcp-filesystem-env" workspace.deps.default;
    });

    apps = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/mcp-filesystem";
      };
      mcp-filesystem = {
        type = "app";
        program = "${self.packages.${system}.mcp-filesystem}/bin/mcp-filesystem";
      };
      # Alternative entry point using run_server.py  
      run-server = {
        type = "app";
        program = "${pkgs.writeShellScript "mcp-filesystem-run-server" ''
          exec ${self.packages.${system}.default}/bin/python ${./.}/run_server.py "$@"
        ''}";
      };
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python312;
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          python
          uv
          git
          ripgrep  # Required for optimal filesystem search performance
        ];
        
        env = {
          UV_PYTHON_DOWNLOADS = "never";
          UV_PYTHON = python.interpreter;
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
        };
        
        shellHook = ''
          unset PYTHONPATH
          echo "=== MCP Filesystem Server Development Environment ==="
          echo "Python: $(python --version)"
          echo "UV: $(uv --version)"
          echo "Ripgrep: $(rg --version | head -1)"
          echo
          echo "Development commands:"
          echo "  uv sync              # Install dependencies"
          echo "  uv run run_server.py # Run the MCP server"
          echo "  uv run -m pytest    # Run tests"
          echo "  uv run -m ruff check # Lint code"
          echo
          echo "MCP Server ready for development!"
        '';
      };
    });

    checks = forAllSystems (system: {
      # Build the package to ensure it works
      build = self.packages.${system}.default;
    });
  };
}
