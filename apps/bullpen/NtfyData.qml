// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import Quickshell
import Quickshell.Io

// Messages from an ntfy server (https://ntfy.sh, or a self-hosted one),
// shared by every bar's ntfy indicator. Keeps one streaming subscription to
// `topics` open with curl while `running`, sends each message on as a
// desktop notification, and counts the ones not yet seen. A dropped
// connection reconnects on its own and asks for what it missed.
Scope {
    id: root

    property bool running: true
    property string server: "https://ntfy.sh"
    property var topics: []
    // A file holding an ntfy access token (tk_...), for protected topics.
    property string tokenFile: ""
    property bool notifications: true
    // A shell command; clicking the indicator runs it. Empty opens the
    // server's web app.
    property string openCommand: ""

    readonly property string baseUrl: server.replace(/\/+$/, "")
    readonly property bool configured: topics.length > 0
    property string token: ""
    property bool tokenLoaded: tokenFile === ""

    // "off", "connecting", "ok", "offline", "unauthorized" or "error".
    property string status: configured ? "connecting" : "off"
    property string lastError: ""
    // Messages since the indicator was last clicked.
    property int unseen: 0
    // The newest message: {topic, title, message, priority, time}.
    property var latest: null
    // Id of the newest message, so a reconnect picks up from there.
    property string lastId: ""
    // Seconds before the next reconnect; doubles on each failure.
    property int backoff: 5
    // Set while bullpen stops curl itself, so the exit isn't an error.
    property bool quitting: false
    // Set when the watchdog dropped a silent connection.
    property bool stalled: false

    // Marks every message seen.
    function clear() {
        root.unseen = 0;
    }

    // Opens the web app (or the configured command) and marks every message seen.
    function open() {
        root.clear();
        const command = root.openCommand !== "" ? root.openCommand : "xdg-open \"$0\"";
        opener.command = ["sh", "-c", command, root.baseUrl];
        opener.startDetached();
    }

    // Handles one line of ntfy's JSON stream.
    function handle(line) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            console.warn("bullpen: ntfy: unexpected line:", line);
            return;
        }
        watchdog.restart();
        if (event.event === "open") {
            root.status = "ok";
            root.lastError = "";
            root.backoff = 5;
        } else if (event.event === "message") {
            root.lastId = event.id;
            root.unseen += 1;
            root.latest = {
                topic: event.topic,
                title: event.title || event.topic,
                message: event.message || "",
                priority: event.priority || 3,
                time: event.time
            };
            root.notify(root.latest);
        }
    }

    function notify(message) {
        if (!root.notifications)
            return;
        // ntfy priorities: 1 min, 2 low, 3 default, 4 high, 5 max.
        const urgency = message.priority >= 5 ? "critical" : message.priority <= 2 ? "low" : "normal";
        const args = ["notify-send", "--app-name=ntfy", "--urgency=" + urgency];
        if (message.priority >= 4)
            args.push("--icon=dialog-warning");
        args.push(message.title, message.message);
        notifier.command = args;
        notifier.startDetached();
    }

    function connect() {
        if (!root.running || !root.configured || !root.tokenLoaded || stream.running)
            return;
        root.quitting = false;
        const query = root.lastId !== "" ? "?since=" + encodeURIComponent(root.lastId) : "";
        stream.url = root.baseUrl + "/" + root.topics.map(encodeURIComponent).join(",") + "/json" + query;
        stream.running = true;
    }

    // Drops the connection on purpose; the exit handler opens a new one
    // straight away unless `running` is off.
    function reconnect() {
        if (stream.running) {
            root.quitting = true;
            stream.running = false;
        } else {
            retry.interval = 0;
            retry.restart();
        }
    }

    onRunningChanged: {
        if (running) {
            connect();
        } else if (stream.running) {
            quitting = true;
            stream.running = false;
        }
    }
    onTopicsChanged: reconnect()
    onServerChanged: reconnect()
    onTokenChanged: reconnect()
    Component.onCompleted: connect()

    // The token goes to curl through its environment and a config on stdin,
    // never its command line, which any user can read.
    Process {
        id: stream

        property string url

        command: ["sh", "-c", "if [ -n \"$NTFY_TOKEN\" ]; then printf 'header = \"Authorization: Bearer %s\"\\n' \"$NTFY_TOKEN\"; fi | exec curl --silent --show-error --no-buffer --fail --config - -- \"$0\"", stream.url]
        // Quickshell takes a JS object here; qmllint wants a QVariantHash,
        // which QML can't write as a literal.
        // qmllint disable incompatible-type
        environment: ({
                NTFY_TOKEN: root.token
            })
        // qmllint enable incompatible-type

        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: StdioCollector {
            id: streamErrors
        }

        onStarted: watchdog.restart()
        onExited: code => {
            watchdog.stop();
            if (root.quitting) {
                root.quitting = false;
                retry.interval = 0;
                if (root.running && root.configured)
                    retry.restart();
                return;
            }
            const error = streamErrors.text.trim();
            const http = /error:? (\d{3})/.exec(error);
            if (http && (http[1] === "401" || http[1] === "403")) {
                root.status = "unauthorized";
                root.lastError = root.token === "" ? root.topics.join(", ") + " needs an access token (ntfy.tokenFile)" : "the server rejected the token for " + root.topics.join(", ");
            } else if (http) {
                root.status = "error";
                root.lastError = "server returned " + http[1];
            } else if (root.stalled) {
                root.status = "offline";
                root.lastError = "the connection to " + root.baseUrl + " went quiet";
            } else if ([6, 7, 28, 35, 52, 56].includes(code)) {
                root.status = "offline";
                root.lastError = "cannot reach " + root.baseUrl;
            } else if (code !== 0) {
                root.status = "error";
                root.lastError = error || "curl exited with " + code;
            }
            root.stalled = false;
            if (root.status !== "ok" && root.lastError !== "")
                console.warn("bullpen: ntfy:", root.lastError);
            if (root.running && root.configured) {
                retry.interval = root.backoff * 1000;
                root.backoff = Math.min(300, root.backoff * 2);
                retry.restart();
            }
        }
    }

    // ntfy sends a keepalive every 45 seconds. Without one for two minutes
    // (after a suspend, or a network change) the connection is dead: drop it,
    // and the exit handler reconnects.
    Timer {
        id: watchdog

        interval: 120000
        onTriggered: {
            root.stalled = true;
            stream.running = false;
        }
    }

    Timer {
        id: retry

        interval: 5000
        onTriggered: root.connect()
    }

    Process {
        id: notifier
    }

    Process {
        id: opener
    }

    FileView {
        path: root.tokenFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.token = text().trim();
            root.tokenLoaded = true;
            root.connect();
        }
        onLoadFailed: {
            if (root.tokenFile !== "")
                console.warn("bullpen: ntfy: cannot read", root.tokenFile);
            root.token = "";
            root.tokenLoaded = true;
            root.connect();
        }
    }
}
