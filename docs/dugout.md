<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: GPL-3.0-only
-->

## Dugout app launcher

Dugout is an app launcher. It runs in the background, starts hidden, and opens
on the monitor with Niri's focused workspace when you toggle it. It has no
options besides `dugout.enable`, so bind a key to it in your Niri config:

```kdl
Mod+D { spawn "birdland-dugout" "ipc" "call" "dugout" "toggle"; }
```

`show` and `hide` are there too, for scripts that need to open or close it
rather than flip it.

Type to search the installed apps. A match on the start of the name comes first,
then a match anywhere in the name, then letters in order ("ffx" finds Firefox),
then the app's generic name, description and keywords. With nothing typed it
lists every app alphabetically. Apps that hide themselves from menus
(`NoDisplay=true`) are left out.

| Key | Action |
| ---------------------------------- | ----------------------- |
| Enter | Start the selected app |
| Down, Tab, Ctrl+N, Ctrl+J | Select the next app |
| Up, Shift+Tab, Ctrl+P, Ctrl+K | Select the previous app |
| Escape, or a click outside the box | Close |

Apps are started through Niri, so each runs in its own systemd scope and stays
open when Dugout's service restarts. Dugout forgets what you typed each time it
closes.
