# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
{ self, inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      home =
        birdland:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home = {
                username = "birdland";
                homeDirectory = "/home/birdland";
                stateVersion = "26.05";
              };
              programs.birdland = birdland;
            }
          ];
        };

      # Every app, with the options that change what the module writes set
      # away from their defaults.
      everything = home {
        enable = true;
        systemd.enable = true;
        bullpen = {
          enable = true;
          position = "left";
          layout.right = [
            "network"
            [
              "volume"
              "microphone"
            ]
            "feeds"
            "ntfy"
          ];
          ntfy = {
            server = "https://ntfy.example.org";
            topics = [
              "alerts"
              "backups"
            ];
            tokenFile = "~/.config/ntfy/token";
            command = "foot";
          };
          units = "imperial";
          weather = {
            latitude = 39.28;
            longitude = -76.62;
          };
        };
        dugout.enable = true;
        lineup = {
          enable = true;
          favorites = [
            "firefox"
            "foot"
          ];
          iconSize = 48;
        };
        outfield = {
          enable = true;
          wallpaper = "~/Pictures/Wallpapers";
          outputs.DP-1 = ../docs/assets/birdland-mark.svg;
        };
        announcer.enable = true;
        jumbotron.enable = true;
        tarp = {
          enable = true;
          pamService = "birdland-tarp";
          wallpaper = ../docs/assets/birdland-mark.svg;
        };
      };

      # A custom theme attrset and font instead of a bundled theme name.
      customTheme = home {
        enable = true;
        theme.scheme = inputs.base24-themes.lib.base24.themes.birdland;
        font = {
          family = "Sans";
          package = null;
        };
        bullpen.enable = true;
      };

      # Evaluating the activation package's derivation runs the whole module
      # (and its assertions) without building anything; the app-* checks build
      # the apps.
      evaluate =
        name: hm:
        assert lib.assertMsg (
          hm.config.warnings == [ ]
        ) "${name}: unexpected warnings:\n${lib.concatStringsSep "\n" hm.config.warnings}";
        builtins.unsafeDiscardStringContext hm.activationPackage.drvPath;
    in
    {
      # The Home Manager module is otherwise never evaluated by
      # `nix flake check`, so broken option wiring would only show on a switch.
      checks.home-manager-module =
        pkgs.runCommand "birdland-home-manager-module"
          {
            everything = evaluate "everything" everything;
            customTheme = evaluate "customTheme" customTheme;
          }
          ''
            echo "$everything" "$customTheme" > $out
          '';
    };
}
