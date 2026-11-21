## Tarp lock screen

Tarp runs in the background as a user service and locks every monitor when
asked; your password unlocks it. With `tarp.swayidle` (the default) it locks
after `lockAfter` minutes without input, before the machine sleeps, and on
`loginctl lock-session`. Before sleep, the lock command waits until Niri
confirms every monitor is covered, so the desktop never shows on resume. To lock
from a Niri keybind:

```kdl
Mod+Alt+L { spawn "birdland-tarp" "ipc" "call" "tarp" "lock"; }
```

The password is checked by PAM's `login` service, which exists on every NixOS
system and includes fingerprint login if you've enabled it there. To use a
dedicated service, add `security.pam.services.birdland-tarp = { };` to your
NixOS configuration and set `tarp.pamService = "birdland-tarp";`.

### Unlocking with a YubiKey

Tarp can also unlock with a touch of a security key, beside the password. It
uses a second PAM service with only [pam_u2f](https://developers.yubico.com/pam-u2f/)
in it, and keeps it waiting for a touch the whole time the screen is locked. In
your NixOS configuration:

```nix
security.pam.u2f.settings.cue = true;  # shows "Please touch the device."
security.pam.services.birdland-tarp-key = {
  u2fAuth = true;
  unixAuth = false;  # the key only; the password stays with pamService
};
```

Register the key once, as yourself (`pamu2fcfg` is in `pkgs.pam_u2f`), adding
`-n` for each extra key:

```sh
mkdir -p ~/.config/Yubico
pamu2fcfg > ~/.config/Yubico/u2f_keys
```

and in Home Manager:

```nix
programs.birdland.tarp.keyPamService = "birdland-tarp-key";
```

The key service must not ask for anything typed (so no `pinverification`); if
it does, Tarp stops using it and logs a warning. Don't turn on
`security.pam.u2f.enable` for the whole system unless you want the key in every
service, `login` included: Tarp's password check would then wait for a touch
before it takes the password. A fingerprint reader works the same way, with a
service that has `fprintAuth = true; unixAuth = false;`.

With `screenOffAfter` (15 minutes by default) the monitors also turn off when
idle; any input turns them back on. This uses swayidle too, so it needs
`tarp.swayidle`.

If Tarp crashes while locked, Niri keeps the screens locked (a solid color).
systemd restarts Tarp, which notices and locks again, so you can unlock as
usual. If it doesn't come back, switch to a text console (Ctrl+Alt+F2), log in,
and run `systemctl --user restart tarp`.
