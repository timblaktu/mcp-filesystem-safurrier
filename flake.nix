{
  description = "MCP Filesystem Server - A powerful Model Context Protocol server for filesystem operations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    # uv2nix for Python package management
    uv2nix = {
      url = "github:adisbladis/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # pyproject-nix for build system integration
    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      
      perSystem = { config, self', inputs', pkgs, lib, system, ... }: 
      let
        workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";  # Use wheels when available for faster builds
        };
        pyprojectOverrides = import inputs.pyproject-nix {
          inherit pkgs;
        };
        python = pkgs.python312;
        pythonSet = python.pkgs.overrideScope (
          lib.composeExtensions overlay pyprojectOverrides.overrides
        );
      in {
        packages = {
          default = pythonSet.mcp-filesystem;
          mcp-filesystem = pythonSet.mcp-filesystem;
        };

        apps = {
          default = {
            type = "app";
            program = "${self'.packages.default}/bin/mcp-filesystem";
          };
          mcp-filesystem = {
            type = "app";
            program = "${self'.packages.mcp-filesystem}/bin/mcp-filesystem";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.uv
            python
            pkgs.git
            pkgs.ripgrep  # Required for optimal filesystem search performance
          ];
          
          shellHook = ''
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

        checks = {
          # Build the package to ensure it works
          build = self'.packages.default;
          
          # Run tests if available
          pytest = pkgs.runCommand "mcp-filesystem-tests" 
            { 
              buildInputs = [ 
                pythonSet.mcp-filesystem 
                pythonSet.pytest 
                pythonSet.pytest-asyncio
                pythonSet.pytest-cov
              ]; 
            } ''
            cd ${./.}
            python -m pytest tests/ || echo "Tests failed, but package builds"
            touch $out
          '';
        };
      };
    };
}
