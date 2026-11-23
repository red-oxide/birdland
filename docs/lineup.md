<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: GPL-3.0-only
-->

## Lineup dock

Lineup is a dock on every monitor, attached to the middle of one screen edge
(`position`, the bottom by default). Your `favorites` come first, in the order
you list them, then a divider and any other apps with open windows.

```nix
programs.birdland.lineup = {
  enable = true;
  position = "left";
  iconSize = 48;
  favorites = [
    "firefox"
    "foot"
    "org.gnome.Nautilus"
  ];
};
```

`favorites` are desktop entry IDs: the `.desktop` file's name without the
extension (`org.gnome.Nautilus` for `org.gnome.Nautilus.desktop`). An ID that
matches no installed app is skipped, so a list shared between machines can name
apps only some of them have.

A line beside an icon, on the side facing the screen edge, shows the app has a
window open; it is longer when one of them has focus.

- **Left click** starts the app, or focuses its window if it's running. Click
  again to move through its windows.
- **Middle click** always starts a new instance.

A window's app ID doesn't always match its desktop entry (Firefox's is
`firefox`, its entry `org.mozilla.firefox`), so Lineup tries a few ways of
matching them. A window it can't match to any entry still gets an icon, named by
its app ID.

`iconSize` takes the sizes icon themes ship (16, 22, 24, 32, 48, 64, 96 or 128),
so icons stay sharp. The dock is the icon plus 12 pixels thick, for the hover
highlight and the running indicator. When nothing is pinned or running, the dock
is hidden.

Apps are started through Niri, so each runs in its own systemd scope and stays
open when Lineup's service restarts.
