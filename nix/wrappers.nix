# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
# Wrapper modules (nix-wrapper-modules) for each app: the same options as the
# Home Manager module, under `settings`, baked into the app's environment.
{
  self,
  inputs,
  lib,
  ...
}:
let
  appNames = [
    "announcer"
    "bullpen"
    "dugout"
    "jumbotron"
    "lineup"
    "outfield"
    "tarp"
  ];

  mkWrapperModule =
    name:
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      b = import ./_apps.nix {
        inherit lib pkgs;
        cfg = config.settings;
        base24 = inputs.base24-themes.lib.base24;
        birdlandPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      };
    in
    {
      imports = [ wlib.modules.default ];

      options.settings = lib.mkOption {
        type = lib.types.submodule { options = b.options; };
        default = { };
        description = ''
          Birdland settings, the same as the Home Manager module's
          programs.birdland. Every app reads the parts it uses (tarp also reads
          outfield's wallpaper), so pass the same settings to each wrapper.
        '';
      };

      config = {
        package = b.appPackage name;
        env = b.apps.${name}.sessionVariables;
      };
    };
in
{
  flake = {
    wrapperModules = lib.genAttrs appNames mkWrapperModule;
    wrappers = lib.mapAttrs (
      _: module: (inputs.nix-wrapper-modules.lib.evalModule module).config
    ) self.wrapperModules;
  };

  perSystem =
    { pkgs, ... }:
    {
      # Every app wrapped with settings away from their defaults.
      checks = lib.mapAttrs' (
        name: wrapper:
        lib.nameValuePair "wrapper-${name}" (
          wrapper.wrap {
            inherit pkgs;
            settings = {
              theme.scheme = "birdland";
              bullpen = {
                position = "left";
                units = "imperial";
                layout.right = [
                  "network"
                  [
                    "volume"
                    "microphone"
                  ]
                ];
              };
              lineup.favorites = [ "foot" ];
              outfield.wallpaper = ../docs/assets/birdland-mark.svg;
              tarp.lockAfter = 5;
            };
          }
        )
      ) self.wrappers;
    };
}
