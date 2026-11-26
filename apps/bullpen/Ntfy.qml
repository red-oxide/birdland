// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import modules.theme

// Messages from ntfy, from the shared NtfyData: a dim bubble while there is
// nothing new, a bright one with the count of unseen messages, and a red `!`
// while the server can't be reached or rejects the token. Click opens the
// web app; right click marks everything seen.
Indicator {
    id: root

    required property NtfyData ntfy

    readonly property bool problem: ["offline", "unauthorized", "error"].includes(ntfy.status)

    // Hidden when no topics are set.
    available: ntfy.configured
    interactive: true
    icon: ntfy.unseen > 0 ? "\u{F0362}" : "\u{F0365}" // message-alert / message-outline
    label: problem ? "!" : ntfy.unseen > 0 ? (ntfy.unseen > 99 ? "99+" : String(ntfy.unseen)) : ""
    color: problem ? Theme.primary : ntfy.unseen > 0 ? Theme.textBright : Theme.textMuted

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            ntfy.clear();
        else
            ntfy.open();
    }
}
