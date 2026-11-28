# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
{
  self,
  inputs,
  config,
  ...
}:
{
  flake = {
    # The same module under the name older flakes and docs use.
    homeManagerModules = config.flake.homeModules;

    homeModules.default =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.programs.birdland;
        b = import ./_apps.nix {
          inherit lib pkgs cfg;
          base24 = inputs.base24-themes.lib.base24;
          birdlandPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
        };
        inherit (b)
          appPackage
          enabledApps
          serviceEnvironment
          tarpLock
          ;

        # Another notification daemon would hold the D-Bus name announcer needs.
        otherNotifier = config.services.mako.enable || config.services.dunst.enable;
      in
      {
        options.programs.birdland = b.options;

        config = lib.mkIf cfg.enable {
          warnings =
            lib.optional (cfg.tarp.enable && !cfg.systemd.enable) ''
              programs.birdland.tarp locks the screen only while it is running. Enable
              programs.birdland.systemd.enable, or start birdland-tarp with your session.
            ''
            ++ lib.optional (cfg.announcer.enable && otherNotifier) ''
              programs.birdland.announcer and services.mako or services.dunst are both
              notification servers, and only one can run; disable one of them.
            '';

          # Lock after inactivity, before sleep and on `loginctl lock-session`.
          services.swayidle = lib.mkIf (cfg.tarp.enable && cfg.tarp.swayidle) {
            enable = true;
            events = {
              before-sleep = lib.mkDefault "${tarpLock}";
              lock = lib.mkDefault "${tarpLock}";
            };
            timeouts =
              lib.optional (cfg.tarp.lockAfter != null) {
                timeout = cfg.tarp.lockAfter * 60;
                command = "${tarpLock}";
              }
              ++ lib.optional (cfg.tarp.screenOffAfter != null) {
                timeout = cfg.tarp.screenOffAfter * 60;
                command = "${lib.getExe (appPackage "tarp")} ipc call tarp screenOff";
              };
          };

          home = {
            packages =
              (map appPackage (lib.attrNames enabledApps))
              # Icon glyphs: bullpen's indicators, and tarp's and the shared
              # controls' buttons.
              ++ [ pkgs.nerd-fonts.symbols-only ]
              ++ (lib.optional (cfg.font.package != null) cfg.font.package)
              # The feeds indicator's default click opens the default terminal.
              ++ (lib.optional (
                cfg.bullpen.enable
                && lib.elem "feeds" (lib.flatten (with cfg.bullpen.layout; left ++ center ++ right))
                && lib.hasPrefix "xdg-terminal-exec " cfg.bullpen.feeds.command
              ) pkgs.xdg-terminal-exec);

            sessionVariables = lib.foldl' (acc: app: acc // app.sessionVariables) { } (
              lib.attrValues enabledApps
            );
          };

          fonts.fontconfig.enable = true;

          systemd.user.services = lib.mkIf cfg.systemd.enable (
            lib.mapAttrs' (
              name: app:
              lib.nameValuePair name {
                Unit = {
                  Description = app.description;
                  PartOf = [ "graphical-session.target" ];
                  After = [ "graphical-session.target" ];
                  # Wayland apps; skip them outside a Wayland session.
                  ConditionEnvironment = "WAYLAND_DISPLAY";
                }
                // app.unit or { };
                Service = {
                  ExecStart = lib.getExe (appPackage name);
                  Environment = serviceEnvironment app.sessionVariables;
                  Restart = "always";
                  # systemd gives up after 5 starts in 10 s. Waiting 3 s between
                  # tries stays under that, so an app that starts before the
                  # compositor is ready keeps retrying instead of staying down.
                  RestartSec = 3;
                }
                // app.service or { };
                Install.WantedBy = [ "graphical-session.target" ];
              }
            ) enabledApps
          );
        };
      };
  };
}
