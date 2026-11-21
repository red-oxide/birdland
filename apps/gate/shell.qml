// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import modules.theme
import modules.util

// Gate: the greeter. Runs under greetd inside cage (one window, so one
// monitor), logs a user in and starts their chosen Wayland session.
//
// Logging in starts as soon as a user is selected, before anything is typed,
// so PAM can wait for a security key touch or a fingerprint; a password typed
// meanwhile is handed over when PAM asks for it.
//
// Settings come from GATE_CONFIG, a JSON file the NixOS module writes:
//
//   users           [{ name, realName }] to choose from
//   sessionsDir     folder of Wayland session .desktop files
//   defaultSession  session id (file name without .desktop) used first
//   statePath       file remembering the last user and session
//   power           show restart and shut down buttons (default true)
//   wallpaper, fill background image or folder, and how it fits
ShellRoot {
    id: root

    JsonSettings {
        id: settings

        variable: "GATE_CONFIG"
    }

    readonly property var config: settings.values

    readonly property var users: config.users ?? []
    readonly property bool power: config.power ?? true
    readonly property string wallpaper: String(config.wallpaper ?? "")
    readonly property string fill: String(config.fill ?? "fill")

    // The last user and session, kept across logins.
    FileView {
        id: stateFile

        path: String(root.config.statePath ?? "")
        blockLoading: true
        blockWrites: true
        printErrors: false
    }

    readonly property var saved: {
        try {
            return JSON.parse(stateFile.text());
        } catch (e) {
            return {};
        }
    }

    property int userIndex: Math.max(0, users.findIndex(u => u.name === saved.user))
    readonly property var user: users[userIndex] ?? null

    Sessions {
        id: sessionList

        dir: String(root.config.sessionsDir ?? "")
    }

    readonly property var sessions: sessionList.sessions
    property string sessionId: ""
    readonly property int sessionIndex: {
        const wanted = [sessionId, saved.session, config.defaultSession];
        for (const id of wanted) {
            const index = sessions.findIndex(s => s.id === id);
            if (index >= 0)
                return index;
        }
        return 0;
    }
    readonly property var session: sessions[sessionIndex] ?? null

    // Authentication state.
    property string prompt: "Password"
    property bool promptEchoes: false
    property bool awaitingInput: false
    property string message: ""
    property bool messageIsError: false
    // Information from PAM, such as "Please touch the device."; shown while
    // there is no message.
    property string hint: ""
    // Something was entered for this login attempt, so the field waits.
    property bool submitted: false
    // PAM showed a hint during this attempt (likely a key or fingerprint).
    property bool hadHint: false
    readonly property bool busy: submitted && Greetd.state !== GreetdState.Inactive && !awaitingInput
    // Typed before greetd asked for it; handed over at its first question.
    property var pendingResponse: null

    signal failed

    function selectUser(index) {
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        reset();
        message = "";
        userIndex = index;
        startSession();
    }

    // Enter with nothing typed: start over, for a key or fingerprint check
    // that gave up waiting and moved on to the password.
    function retry() {
        if (submitted || pendingResponse !== null)
            return;
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        reset();
        message = "";
        startSession();
    }

    // Start logging in the selected user, without waiting for a password.
    function startSession() {
        if (!Greetd.available || !user || Greetd.state !== GreetdState.Inactive)
            return;
        Greetd.createSession(user.name);
    }

    function selectSession(index) {
        sessionId = sessions[index]?.id ?? "";
    }

    function submit(text) {
        message = "";
        if (!Greetd.available) {
            showError("greetd is not running");
            return;
        }
        if (!user || !session) {
            showError(!user ? "No users to log in as" : "No sessions found");
            return;
        }
        if (awaitingInput) {
            awaitingInput = false;
            submitted = true;
            Greetd.respond(text);
            return;
        }
        if (Greetd.state === GreetdState.Authenticating) {
            // PAM hasn't asked yet (it may be waiting for a key touch).
            if (pendingResponse === null) {
                pendingResponse = text;
                submitted = true;
            }
            return;
        }
        if (Greetd.state !== GreetdState.Inactive)
            return;
        pendingResponse = text;
        submitted = true;
        Greetd.createSession(user.name);
    }

    function reset() {
        pendingResponse = null;
        submitted = false;
        awaitingInput = false;
        hint = "";
        hadHint = false;
        prompt = "Password";
        promptEchoes = false;
    }

    function showError(text) {
        reset();
        message = text;
        messageIsError = true;
        failed();
    }

    function launch() {
        stateFile.setText(JSON.stringify({
            user: user.name,
            session: session.id
        }) + "\n");
        const environment = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + session.id];
        if (session.desktopNames !== "")
            environment.push("XDG_CURRENT_DESKTOP=" + session.desktopNames);
        // Exec lines may carry arguments and quoting; let the shell read them.
        Greetd.launch(["sh", "-c", session.exec], environment);
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (root.pendingResponse !== null) {
                    const response = root.pendingResponse;
                    root.pendingResponse = null;
                    Greetd.respond(response);
                } else {
                    // The password, or a further question such as a
                    // one-time code.
                    root.prompt = message.replace(/:\s*$/, "");
                    root.promptEchoes = echoResponse;
                    root.awaitingInput = true;
                    root.hint = root.hadHint ? "Or press Enter to try your key again" : "";
                }
            } else if (error) {
                root.message = message;
                root.messageIsError = true;
            } else if (message !== "") {
                root.hint = message;
                root.hadHint = true;
            }
        }

        function onAuthFailure(message) {
            const tried = root.submitted;
            root.showError(message || "Incorrect password");
            // Ready for the next try. A failure with nothing entered (a key
            // check that timed out, with no password to fall back to) waits
            // for Enter instead, so it doesn't repeat on its own.
            if (tried)
                restartSession.restart();
        }

        function onReadyToLaunch() {
            root.reset();
            root.launch();
        }

        function onError(error) {
            root.showError(error);
        }
    }

    // After a failure, once greetd has closed the attempt.
    Timer {
        id: restartSession

        interval: 500
        onTriggered: root.startSession()
    }

    Process {
        id: reboot

        command: ["systemctl", "reboot"]
    }

    Process {
        id: poweroff

        command: ["systemctl", "poweroff"]
    }

    function powerAction(action) {
        if (!power)
            return;
        if (action === "reboot")
            reboot.running = true;
        else if (action === "poweroff")
            poweroff.running = true;
    }

    FloatingWindow {
        title: "Birdland"
        color: Theme.background

        GateView {
            anchors.fill: parent
            gate: root
        }
    }

    Component.onCompleted: {
        if (!Greetd.available)
            console.warn("gate: greetd is not available (GREETD_SOCK is unset); logging in will not work");
        else
            startSession();
    }
}
