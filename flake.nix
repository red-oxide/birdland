# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
{
  description = "Quickshell desktop shell for Niri";

  # Builds from this flake's CI. Used by `nix build`/`nix run` on this flake
  # (after accepting the prompt); a flake that takes this one as an input
  # must add the cache to its own nix.settings instead.
  nixConfig = {
    extra-substituters = [ "https://red-oxide.cachix.org" ];
    extra-trusted-public-keys = [
      "red-oxide.cachix.org-1:kX7CnXH4XIGlSiCojVBNK3zcka8p2po2PnfNToDYauI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    base24-themes = {
      url = "github:red-oxide/base24-themes";
      inputs = {
        devfmt.follows = "devfmt";
        nixpkgs.follows = "nixpkgs";
      };
    };
    devfmt = {
      url = "github:red-oxide/devfmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    qml-niri = {
      url = "github:imiric/qml-niri/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        quickshell.follows = "quickshell";
        # Share devfmt's copies instead of locking a second set.
        flake-parts.follows = "devfmt/flake-parts";
        treefmt-nix.follows = "devfmt/treefmt-nix";
      };
    };
  };

  outputs =
    inputs:
    inputs.devfmt.lib.mkFlake { inherit inputs; } {
      imports = [
        (inputs.devfmt.lib.importTree ./nix)
      ];
    };
}
