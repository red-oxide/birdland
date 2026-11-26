<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: GPL-3.0-only
-->

## Bullpen layout

`bullpen.layout` sets what goes in the left, center and right parts of the bar,
and in what order. On side bars, left is the top and right the bottom. Any
module can go in any part, a part can be empty (`[ ]`), and a module left out of
all three isn't shown.

The bar has no background: each entry is an island, a pill floating just off the
screen edge. An entry is one module, or a list of modules that share a pill:

```nix
right = [ "media" [ "cpu" "memory" "temperature" ] "weather" [ "network" "volume" "battery" ] "tray" [ "clock" "date" ] ];
```

An island whose modules all have nothing to show hides. The workspaces dots are
a pill of their own, so on their own they get no island around them.

The center stays centered on the bar. A long window title is shortened with "…"
to fit; outside the center it is capped at a quarter of the bar.

| Module | Shows | Needs |
| :--------------- | :----------------------------------------------------------------------------- | :-------------------------------------------------------------------------- |
| `workspaces` | Niri workspaces; click one to switch | Niri |
| `title` | Focused window title, on its monitor's bar (top/bottom bars only) | Niri |
| `clock` | Time | Nothing |
| `date` | Date | Nothing |
| `cpu`, `memory` | Usage | Nothing (`/proc`) |
| `gpu` | Usage, and temperature when available | AMD, Intel (`i915`, `xe`): nothing (sysfs). NVIDIA: `nvidia-smi` |
| `temperature` | CPU temperature | A hwmon sensor: `k10temp`, `zenpower`, `coretemp`... |
| `weather` | Current conditions from Open-Meteo | Internet access and `weather.latitude`/`longitude` |
| `network` | Wired, or Wi-Fi signal strength | NetworkManager, or systemd-networkd (`networkctl`; no captive-portal check) |
| `volume` | Default output; click mutes, scroll changes it | PipeWire with WirePlumber |
| `microphone` | Default input; click mutes, scroll changes it | PipeWire with WirePlumber |
| `battery` | Charge and charging state | UPower: `services.upower.enable = true` in your NixOS config |
| `media` | The playing track; click plays/pauses, right click next, middle click previous | A player with MPRIS (most do) |
| `tray` | Tray icons; click activates, right click opens the menu | Apps with StatusNotifierItem icons |
| `feeds` | Unread items; click opens the reader, right click refreshes the feeds | A paired [pressbox](https://github.com/red-oxide/pressbox) client |
| `ntfy` | Unseen ntfy messages; click opens the web app, right click marks them seen | `ntfy.topics` on an [ntfy](https://ntfy.sh) server |
| `dnd` | Announcer's do not disturb; click turns it on or off | [Announcer](./announcer.md) |
| `idle-inhibitor` | Whether idle is inhibited; click keeps the session awake, or lets it idle | A compositor with idle-inhibit (Niri has it) |

Modules with nothing to show (no battery, no GPU sensor, no weather location, no
media player, no tray icons, no paired pressbox, no ntfy topics) hide themselves. Icons come
from the Symbols Nerd Font, which the Home Manager module installs.

The `feeds` indicator shows unread items on a
[pressbox](https://github.com/red-oxide/pressbox) server. It reads the server
and token from pressbox's own client files, `~/.config/pressbox/client.json`
(written by pressbox's Home Manager module) and the token saved by
`pressbox pair`, so there is nothing to set up in Birdland beyond adding
`"feeds"` to a layout. It stays hidden until the machine is paired, shows a dim
icon when everything is read, and a red `!` when the server can't be reached or
rejects the token. With `feeds.notifications`, new items also send a
notification (shown by Announcer, if you use it).

Bullpen can subscribe to topics on an [ntfy](https://ntfy.sh) server, ntfy.sh or
your own, and send each message on as a notification (shown by Announcer, if you
use it). Set `ntfy.server` and `ntfy.topics`, and `ntfy.tokenFile` for topics
that need an access token:

```nix
programs.birdland.bullpen.ntfy = {
  server = "https://ntfy.example.org";
  topics = [ "alerts" ];
  tokenFile = "/run/secrets/ntfy-token";   # a file holding tk_...
};
```

The subscription runs whenever topics are set, whether or not the `ntfy`
indicator is in the layout. It is one streaming connection: messages show up as
soon as they are published, and after a dropped connection (a suspend, a network
change) Bullpen reconnects and asks for what it missed. Messages sent while
Bullpen isn't running are not fetched when it starts. Priority 5 ("max")
messages are critical notifications, which stay until dismissed and get through
do not disturb; priority 1 and 2 are low.

The `ntfy` indicator shows a dim speech bubble while nothing is new, a bright one
with the number of messages since you last clicked it, and a red `!` while the
server can't be reached or rejects the token. Click opens the server's web app
(or runs `ntfy.command`); right click just marks everything seen. The token is
handed to curl through its environment, never its command line.

The `dnd` indicator shows a dim bell while notifications show and a bright
crossed-out bell while Announcer holds them back; click to switch. It is the
same setting as `birdland-announcer ipc call announcer toggleDnd`, so a keybind
and the bar stay in step. It stays hidden until Announcer has started in this
session.

The `idle-inhibitor` indicator is a coffee cup: dim while the session idles
normally, bright while it is kept awake. While it is on, idle timeouts don't
fire, so Tarp neither locks nor turns the monitors off on idle (locking before
sleep and on `loginctl lock-session` still works). It starts off each time
Bullpen starts. A keybind can switch it too, whether or not the indicator is in
the layout:

```sh
birdland-bullpen ipc call bullpen toggleIdleInhibitor    # prints the new state
birdland-bullpen ipc call bullpen setIdleInhibitor true
birdland-bullpen ipc call bullpen isIdleInhibited
```

The `gpu` indicator uses the first GPU it can read: AMD (`gpu_busy_percent`),
then Intel, then NVIDIA. Intel usage is the share of time the render engine is
out of its idle state (RC6 on `i915`, gt-c6 on `xe`). The engine stays awake
briefly after each burst of work, so this can read higher than `intel_gpu_top`
at light load. Integrated Intel GPUs have no temperature sensor of their own;
their heat shows in the CPU temperature.

Reading usage wakes a sleeping GPU. That doesn't matter for the GPU driving your
screen, which is awake anyway. NVIDIA is only polled when there is no AMD or
Intel GPU, so Intel + NVIDIA laptops leave the NVIDIA GPU asleep. On a machine
whose only readable GPU is a discrete one that sleeps, leave `gpu` out of the
layout to save power.

The clock and date use Qt's date format, set with `clock.format` and
`date.format`. The defaults, `hh:mm` and `dd MMM, yyyy`, show "17:24" and "01
Nov, 2026"; `h:mm AP` shows "5:24 PM", and `yyyy-MM-dd` shows "2026-11-01". A
clock format with seconds (`ss`) updates every second. The tray hides icons
their apps mark as idle ("passive"), as Waybar does.

The weather request sends only the configured coordinates to
[Open-Meteo](https://open-meteo.com), every 15 minutes (a minute after a failed
request); click the weather to refresh it.
