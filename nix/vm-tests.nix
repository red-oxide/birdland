# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: GPL-3.0-only
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      self',
      ...
    }:
    let
      quickshell = lib.getExe inputs.quickshell.packages.${system}.default;

      # Python for the test scripts: wait until the Quickshell instance of a
      # user has loaded its config (its log says so), and print what there is
      # to know when a step fails.
      helpers = ''
        from datetime import timedelta

        def qs_logs(uid):
            return machine.execute(
                f"for f in $(find /run/user/{uid}/quickshell -name '*.qslog' 2>/dev/null); do "
                f"${quickshell} log \"$f\"; done"
            )[1]

        def wait_for_quickshell(uid):
            retry(lambda _: "Configuration Loaded" in qs_logs(uid), timeout=timedelta(minutes=3))

        def diagnose(uid, extra=[]):
            for cmd in [
                "ps -eo user,pid,args | grep -iE 'cage|sway|quickshell|greet' | grep -v grep",
                f"ls -lR /run/user/{uid}/quickshell",
            ] + extra:
                print(f"$ {cmd}")
                print(machine.execute(cmd)[1])
            print(qs_logs(uid))
      '';

      password = "correct horse";

      user = {
        isNormalUser = true;
        description = "Alice";
        inherit password;
        uid = 1000;
      };

      # What every test machine needs to draw: a GPU that wlroots and Mesa's
      # software renderer can use (the default -vga std isn't one).
      graphical = {
        hardware.graphics.enable = true;
        virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      };

      # A Wayland session that only records who started it, for Gate to log
      # in to.
      testSession =
        (pkgs.writeTextDir "share/wayland-sessions/test.desktop" ''
          [Desktop Entry]
          Name=Test session
          Exec=${pkgs.writeShellScript "birdland-test-session" ''
            id -un > /tmp/session-user
            exec sleep infinity
          ''}
        '').overrideAttrs
          { passthru.providedSessions = [ "test" ]; };
    in
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        # Log in through Gate, run by greetd in cage as the NixOS module sets
        # it up: a wrong password is refused, the right one starts the session.
        vm-gate = pkgs.testers.runNixOSTest {
          name = "birdland-gate";
          nodes.machine = {
            imports = [
              self.nixosModules.default
              graphical
            ];
            users.users.alice = user;
            programs.birdland.gate.enable = true;
            services.displayManager = {
              sessionPackages = [ testSession ];
              defaultSession = "test";
            };
          };
          testScript = ''
            ${helpers}
            greeter = machine.succeed("id -u greeter").strip()
            machine.wait_for_unit("greetd.service")
            try:
                wait_for_quickshell(greeter)
            except Exception:
                diagnose(greeter, ["journalctl -b -u greetd.service --no-pager | tail -40"])
                raise
            machine.sleep(5)
            machine.screenshot("gate")

            with subtest("A wrong password is refused"):
                machine.send_chars("wrong password\n")
                machine.sleep(10)
                machine.fail("test -e /tmp/session-user")

            with subtest("The right password starts the session"):
                machine.send_chars("${password}\n")
                try:
                    machine.wait_for_file("/tmp/session-user", timeout=timedelta(minutes=1))
                except Exception:
                    machine.screenshot("gate-failed")
                    diagnose(greeter, ["journalctl -b -u greetd.service --no-pager | tail -40"])
                    raise
                machine.succeed("grep -x alice /tmp/session-user")
          '';
        };

        # Lock and unlock with Tarp in a Wayland session. Tarp needs only the
        # session-lock protocol (Niri is just for turning monitors off), so
        # this uses sway, which runs here with wlroots' software renderer.
        vm-tarp = pkgs.testers.runNixOSTest {
          name = "birdland-tarp";
          nodes.machine = {
            imports = [ graphical ];
            users.users.alice = user;
            services.getty.autologinUser = "alice";
            environment.loginShellInit = ''
              [ "$(tty)" = /dev/tty1 ] && exec sway
            '';
            programs.sway.enable = true;
            environment.etc."sway/config".source = lib.mkForce (
              pkgs.writeText "sway-config" ''
                exec sh -c '${lib.getExe self'.packages.tarp} > /tmp/tarp.log 2>&1'
              ''
            );
            environment.variables.WLR_RENDERER = "pixman";
            environment.systemPackages = [ self'.packages.tarp ];
          };
          testScript = ''
            ${helpers}
            # Tarp's IPC, as Alice in her sway session.
            def ipc(call):
                return f"su alice -c 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 birdland-tarp ipc call tarp {call}'"

            def tarp(call):
                return machine.succeed(ipc(call)).strip()

            machine.wait_for_file("/run/user/1000/wayland-1")
            try:
                wait_for_quickshell(1000)
            except Exception:
                diagnose(1000, ["cat /tmp/tarp.log"])
                raise
            assert tarp("isLocked") == "false"

            with subtest("Locking covers the screen"):
                tarp("lock")
                machine.wait_until_succeeds(
                    ipc("isSecure") + " | grep -x true",
                    timeout=timedelta(minutes=1),
                )
                machine.sleep(3)
                machine.screenshot("tarp")

            with subtest("A wrong password keeps it locked"):
                machine.send_chars("wrong password\n")
                machine.sleep(10)
                assert tarp("isLocked") == "true"

            with subtest("The right password unlocks"):
                machine.send_chars("${password}\n")
                machine.wait_until_succeeds(
                    ipc("isLocked") + " | grep -x false",
                    timeout=timedelta(minutes=1),
                )
          '';
        };
      };
    };
}
